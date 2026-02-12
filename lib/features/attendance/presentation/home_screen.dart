import 'dart:async';
import 'dart:io';
import 'package:analog_clock/analog_clock.dart';
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/attendance/data/attendance_repository.dart';
import 'package:app_asistencias_pauser/features/requests/data/requests_repository.dart';
import 'package:app_asistencias_pauser/features/requests/presentation/notifications_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

// Provider for unread count
final unreadNotificationCountProvider = StreamProvider.family
    .autoDispose<int, String>((ref, employeeId) {
      return ref
          .watch(requestsRepositoryProvider)
          .watchNotifications(employeeId)
          .map((list) => list.where((n) => n['is_read'] == false).length);
    });

// 1. Provider para obtener el estado completo (Asistencia + Vacaciones)
final employeeStatusProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>?, String?>((ref, employeeId) async {
      if (employeeId == null) return null;
      return ref
          .watch(attendanceRepositoryProvider)
          .getEmployeeDayStatus(employeeId);
    });

// 2. Provider para el estado de carga de la acción (WRITE State)
final actionLoadingNotifierProvider = Provider.autoDispose<ValueNotifier<bool>>(
  (ref) {
    final notifier = ValueNotifier<bool>(false);
    // Aseguramos que se limpie cuando el provider se destruya
    ref.onDispose(notifier.dispose);
    return notifier;
  },
);

// 3. Clase lógica para acciones
class AttendanceLogic {
  final WidgetRef ref;

  AttendanceLogic(this.ref);

  Future<void> reportAbsence(BuildContext context, String employeeId) async {
    // 0. Check permissions & Get Location (Obligatorio ahora)
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permisos de ubicación denegados')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permisos de ubicación denegados permanentemente'),
          ),
        );
      }
      return;
    }

    // 1. Mostrar diálogo de justificación con tipos dinámicos
    // Pasamos la referencia al repositorio para cargar motivos
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => JustificationDialog(
        title: 'Reportar Novedad / Inasistencia',
        message: 'Seleccione el motivo y describa los detalles.',
        repositoryRef: ref.read(attendanceRepositoryProvider), // Pasar repo
      ),
    );

    if (result == null) return; // Cancelado

    final reason = result['reason'];
    final recordType = result['recordType'];
    final evidenceFile = result['file'];

    // 2. Proceder a reportar
    if (context.mounted) {
      ref.read(actionLoadingNotifierProvider).value = true;
      try {
        // Obtener ubicación actual
        final position = await Geolocator.getCurrentPosition();

        await ref
            .read(attendanceRepositoryProvider)
            .reportAbsence(
              employeeId: employeeId,
              reason: reason,
              recordType: recordType,
              evidenceFile: evidenceFile,
              lat: position.latitude,
              lng: position.longitude,
            );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Inasistencia reportada correctamente'),
            ),
          );
        }
        // Refrescar estado
        ref.invalidate(employeeStatusProvider(employeeId));
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        ref.read(actionLoadingNotifierProvider).value = false;
      }
    }
  }

  Future<void> markAttendance(BuildContext context, String employeeId) async {
    // Check location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permisos de ubicación denegados')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permisos de ubicación denegados permanentemente'),
          ),
        );
      }
      return;
    }

    // Set loading
    ref.read(actionLoadingNotifierProvider).value = true;

    try {
      // Get location
      final position = await Geolocator.getCurrentPosition();

      // Refresh data local to be sure logic is correct
      final lastAttendance = await ref
          .read(attendanceRepositoryProvider)
          .getTodayAttendance(employeeId);

      // VALIDACIÓN DE FECHA: Asegurar que el registro sea de HOY
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final recordDate = lastAttendance?['work_date'] as String?;
      final isRecordFromToday = recordDate == todayStr;

      // Solo consideramos check-in activo si es de hoy y no tiene salida
      final isCheckedIn =
          isRecordFromToday &&
          lastAttendance != null &&
          lastAttendance['check_out'] == null;

      if (isCheckedIn) {
        // YA NO HACEMOS CHECK OUT.
        // Si el usuario ya marcó entrada hoy, simplemente le informamos.
        // Opcionalmente podríamos permitir actualizar la "salida" si fuera necesario,
        // pero según requerimiento: "solo se debe de registrar el ingreso".

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ya has registrado tu asistencia hoy'),
            ),
          );
        }
        return;
      } else {
        // Validación extra: Si ya existe un registro HOY que no sea CheckIn activo
        // (ej. ya completó el día), attendanceRepository.checkIn podría fallar o crear duplicado si no hay unique constraint.
        // Pero aquí confiamos en que isCheckedIn es false.

        // Check In logic (UPDATED - Simplified Flow)
        // Ya no solicitamos motivo ni evidencia para tardanzas o inasistencias.
        // El sistema captura automáticamente la hora y ubicación.

        String? lateReason;
        File? evidenceFile;

        // Procedemos directamente al check-in
        if (context.mounted) {
          ref.read(actionLoadingNotifierProvider).value = true;
        }

        await ref
            .read(attendanceRepositoryProvider)
            .checkIn(
              employeeId: employeeId,
              lat: position.latitude,
              lng: position.longitude,
              lateReason: lateReason, // null
              evidenceFile: evidenceFile, // null
            );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Entrada registrada exitosamente!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      // Refresh provider
      ref.invalidate(employeeStatusProvider(employeeId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      // Stop loading
      ref.read(actionLoadingNotifierProvider).value = false;
    }
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    final employeeId = storage.employeeId;
    // Nuevo: Obtener Rol (mapped from employeeType)
    // final userRole = storage.employeeType;
    final fullName = storage.fullName ?? 'Usuario';

    // Lista de cargos con privilegios de gestión
    // Solo Analistas de Gente y Gestión (o RRHH) tienen permisos
    final userPosition = (storage.position ?? '').trim().toUpperCase();
    final isSupervisor =
        userPosition.contains('GENTE Y GESTION') ||
        userPosition.contains('RRHH') ||
        userPosition.contains('GENTE & GESTION');

    // Watch data
    // Use select to watch only specific parts if needed, or watch the whole provider
    // IMPORTANT: invalidate this provider on logout to prevent stale data
    final employeeStatusAsync = ref.watch(employeeStatusProvider(employeeId));
    final loadingNotifier = ref.watch(actionLoadingNotifierProvider);

    final positionTitle = storage.position ?? 'Empleado';
    final profilePic = storage.profilePicture;
    final canMarkAttendance = storage.canMarkAttendance;
    final restrictionMessage = storage.restrictionMessage;

    return Scaffold(
      body: employeeStatusAsync.when(
        data: (statusData) {
          // Extraer datos del nuevo formato
          final attendance = statusData?['attendance'] as Map<String, dynamic>?;
          final vacation = statusData?['vacation'] as Map<String, dynamic>?;
          final isOnVacation = statusData?['is_on_vacation'] as bool? ?? false;

          // Lógica de Horario Estricto
          final now = DateTime.now();
          // Usamos la misma cadena de fecha que se usa en la query del repositorio
          final todayStr =
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

          // Validar si el registro recuperado es de hoy
          // La query ya filtra por fecha exacta, así que si attendance != null, ES de hoy.
          // Pero mantenemos la verificación por seguridad.
          final recordDate = attendance?['work_date'] as String?;
          final isRecordFromToday = recordDate == todayStr;

          // Filtrar asistencia efectiva
          // Si el repositorio devuelve null, effectiveAttendance es null.
          // Si devuelve algo, confiamos en que es de hoy gracias al filtro del repo.
          final effectiveAttendance = attendance;

          // Solo consideramos check-in activo si es de hoy, no tiene salida Y es de tipo ASISTENCIA o IN
          // O cualquier tipo que NO sea ausencia
          final isCheckedIn =
              effectiveAttendance != null &&
              effectiveAttendance['check_out'] == null &&
              effectiveAttendance['record_type'] != 'AUSENCIA' &&
              effectiveAttendance['record_type'] != 'INASISTENCIA' &&
              effectiveAttendance['record_type'] != 'FALTA_INJUSTIFICADA';

          final lastCheckIn = effectiveAttendance != null
              ? effectiveAttendance['check_in']
              : null;

          // Si ya marcó salida hoy O si es una INASISTENCIA registrada (cualquier tipo que no sea asistencia)
          final isDayComplete =
              effectiveAttendance != null &&
              (effectiveAttendance['check_out'] != null ||
                  effectiveAttendance['record_type'] != 'ASISTENCIA');

          final isAbsence =
              effectiveAttendance != null &&
              effectiveAttendance['record_type'] != 'ASISTENCIA';

          // Hora límite para TARDANZA: 07:00 (7 AM)
          final tardanzaLimit = DateTime(now.year, now.month, now.day, 7, 0);

          // Hora límite para CIERRE/INASISTENCIA: 18:00 (6 PM)
          final absenceLimit = DateTime(now.year, now.month, now.day, 18, 0);

          final isTardanza = now.isAfter(tardanzaLimit);
          final isPastAbsenceLimit = now.isAfter(absenceLimit);

          // Lógica de Falta Injustificada
          // 1. Si ya viene del backend con ese estado
          final isMarkedFalta =
              effectiveAttendance != null &&
              (effectiveAttendance['status'] == 'FALTA_INJUSTIFICADA' ||
                  effectiveAttendance['absence_reason'] ==
                      'FALTA INJUSTIFICADA');

          // 2. Si no hay registro y ya pasó la hora límite (Simulación cliente + Persistencia)
          final shouldRegisterFalta =
              effectiveAttendance == null && isPastAbsenceLimit;
          final isFaltaInjustificada = isMarkedFalta || shouldRegisterFalta;

          // AUTO-REGISTRO DE FALTA:
          // Si detectamos que debería ser falta pero no está en BD (effectiveAttendance == null),
          // disparamos el registro silencioso para que la Web lo vea.
          if (shouldRegisterFalta) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Usamos un provider/flag o simplemente llamamos al repo.
              // Para evitar spam, el repositorio maneja 'duplicate key' exception.
              // Además, al invalidar el provider, la UI se actualizará y esta condición será falsa.
              ref
                  .read(attendanceRepositoryProvider)
                  .registerUnjustifiedAbsence(employeeId!)
                  .then((_) {
                    // Refrescar para traer el nuevo registro de la BD
                    ref.invalidate(employeeStatusProvider(employeeId));
                  });
            });
          }

          return Stack(
            children: [
              // Background Gradient Header
              Container(
                height: 220,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
              ),

              // Main Content with RefreshIndicator
              SafeArea(
                child: RefreshIndicator(
                  onRefresh: () async {
                    if (employeeId != null) {
                      // Invalidar provider para recargar datos
                      ref.invalidate(employeeStatusProvider(employeeId));
                      // Esperar a que se complete la recarga para detener el indicador
                      try {
                        await ref.read(
                          employeeStatusProvider(employeeId).future,
                        );
                      } catch (_) {
                        // Ignorar errores en el refresh visual
                      }
                    }
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // Top Bar: Welcome & Profile
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                          child: Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Colors.white,
                                  backgroundImage: profilePic != null
                                      ? NetworkImage(profilePic)
                                      : null,
                                  child: profilePic == null
                                      ? const Icon(
                                          Icons.person,
                                          color: Color(0xFF2563EB),
                                          size: 30,
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hola,',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      fullName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              // Botón de Notificaciones
                              Consumer(
                                builder: (context, ref, _) {
                                  final unreadCountAsync = employeeId != null
                                      ? ref.watch(
                                          unreadNotificationCountProvider(
                                            employeeId,
                                          ),
                                        )
                                      : const AsyncValue.data(0);

                                  return unreadCountAsync.when(
                                    data: (count) {
                                      return Stack(
                                        children: [
                                          IconButton(
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const NotificationsScreen(),
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.notifications_outlined,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                          ),
                                          if (count > 0)
                                            Positioned(
                                              right: 8,
                                              top: 8,
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 16,
                                                      minHeight: 16,
                                                    ),
                                                child: Text(
                                                  '$count',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                    loading: () => const IconButton(
                                      onPressed: null,
                                      icon: Icon(
                                        Icons.notifications_outlined,
                                        color: Colors.white54,
                                        size: 28,
                                      ),
                                    ),
                                    error: (_, __) => const IconButton(
                                      onPressed: null,
                                      icon: Icon(
                                        Icons.notifications_off_outlined,
                                        color: Colors.white54,
                                        size: 28,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      SliverToBoxAdapter(child: const SizedBox(height: 30)),

                      // Clock & Date Card
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat(
                                          'EEEE',
                                          'es',
                                        ).format(now).toUpperCase(),
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('d MMMM', 'es').format(now),
                                        style: const TextStyle(
                                          color: Color(0xFF1E293B),
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          positionTitle.toUpperCase(),
                                          style: const TextStyle(
                                            color: Color(0xFF2563EB),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: SizedBox(
                                    width: 60,
                                    height: 60,
                                    child: AnalogClock(
                                      decoration: const BoxDecoration(
                                        color: Colors.transparent,
                                        shape: BoxShape.circle,
                                      ),
                                      width: 60.0,
                                      isLive: true,
                                      hourHandColor: const Color(0xFF1E293B),
                                      minuteHandColor: const Color(0xFF1E293B),
                                      showSecondHand: true,
                                      secondHandColor: const Color(0xFFEF4444),
                                      numberColor: Colors
                                          .transparent, // Minimalist: no numbers
                                      showNumbers: false,
                                      showTicks: true,
                                      tickColor: Colors.grey.shade400,
                                      datetime: DateTime.now(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SliverToBoxAdapter(child: const SizedBox(height: 24)),

                      // Status & Action Area
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isOnVacation) ...[
                                // VACATION STATE (Priority High)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF0EA5E9),
                                        Color(0xFF0284C7),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(32),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.3),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.beach_access,
                                        size: 64,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        '¡MODO VACACIONES!',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      if (vacation != null) ...[
                                        Text(
                                          'Del ${DateFormat('d MMM').format(DateTime.parse(vacation['start_date']))} al ${DateFormat('d MMM').format(DateTime.parse(vacation['end_date']))}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Disfruta tu descanso. No necesitas registrar asistencia.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ).animate().scale(
                                  curve: Curves.elasticOut,
                                  duration: 800.ms,
                                ),
                              ] else if (!canMarkAttendance) ...[
                                // RESTRICTED STATE (Policy)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF64748B),
                                        Color(0xFF475569),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(32),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.lock_clock,
                                        size: 64,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'REGISTRO RESTRINGIDO',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        restrictionMessage ??
                                            'Su ubicación requiere registro en Reloj Biométrico.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ).animate().scale(
                                  curve: Curves.elasticOut,
                                  duration: 800.ms,
                                ),
                              ] else if (isFaltaInjustificada ||
                                  isDayComplete ||
                                  isCheckedIn) ...[
                                // COMPLETED STATE
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    color: isFaltaInjustificada
                                        ? Colors.red.shade50
                                        : (isAbsence
                                              ? Colors.orange.shade50
                                              : Colors.green.shade50),
                                    borderRadius: BorderRadius.circular(32),
                                    border: Border.all(
                                      color: isFaltaInjustificada
                                          ? Colors.red.shade200
                                          : (isAbsence
                                                ? Colors.orange.shade200
                                                : Colors.green.shade200),
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        isFaltaInjustificada
                                            ? Icons.block
                                            : (isAbsence
                                                  ? Icons.assignment_late
                                                  : Icons.check_circle),
                                        size: 64,
                                        color: isFaltaInjustificada
                                            ? Colors.red
                                            : (isAbsence
                                                  ? Colors.orange
                                                  : Colors.green),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        isFaltaInjustificada
                                            ? 'FALTA INJUSTIFICADA'
                                            : (isAbsence
                                                  ? (effectiveAttendance['record_type'])
                                                  : '¡Jornada Iniciada!'),
                                        style: TextStyle(
                                          color: isFaltaInjustificada
                                              ? Colors.red.shade800
                                              : (isAbsence
                                                    ? Colors.orange.shade800
                                                    : Colors.green.shade800),
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        isFaltaInjustificada
                                            ? 'No registraste asistencia antes de las 6:00 PM.'
                                            : (isAbsence
                                                  ? 'Tu reporte ha sido enviado.'
                                                  : 'Entrada: ${lastCheckIn != null ? DateFormat('hh:mm a').format(DateTime.parse(lastCheckIn).toLocal()) : '--:--'}'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: isFaltaInjustificada
                                              ? Colors.red.shade700
                                              : (isAbsence
                                                    ? Colors.orange.shade700
                                                    : Colors.green.shade700),
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ).animate().scale(
                                  curve: Curves.elasticOut,
                                  duration: 800.ms,
                                ),
                              ] else ...[
                                // ACTION STATE

                                // Main Check-In Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 200,
                                  child: ValueListenableBuilder<bool>(
                                    valueListenable: loadingNotifier,
                                    builder: (context, isActionLoading, child) {
                                      return ElevatedButton(
                                        onPressed: (isActionLoading)
                                            ? null
                                            : () {
                                                if (employeeId != null) {
                                                  AttendanceLogic(
                                                    ref,
                                                  ).markAttendance(
                                                    context,
                                                    employeeId,
                                                  );
                                                }
                                              },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isTardanza
                                              ? const Color(0xFFEA580C)
                                              : const Color(0xFF2563EB),
                                          foregroundColor: Colors.white,
                                          elevation: 10,
                                          shadowColor:
                                              (isTardanza
                                                      ? Colors.orange
                                                      : Colors.blue)
                                                  .withValues(alpha: 0.5),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              32,
                                            ),
                                          ),
                                        ),
                                        child: isActionLoading
                                            ? const CircularProgressIndicator(
                                                color: Colors.white,
                                              )
                                            : Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    isTardanza
                                                        ? Icons.timer_off
                                                        : Icons.touch_app,
                                                    size: 56,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    'MARCAR ENTRADA',
                                                    style: const TextStyle(
                                                      fontSize: 24,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 1,
                                                    ),
                                                  ),
                                                  if (isTardanza)
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                        top: 8,
                                                      ),
                                                      child: Text(
                                                        'Registrando con TARDANZA',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                      );
                                    },
                                  ),
                                ).animate().shimmer(
                                  delay: 1000.ms,
                                  duration: 1500.ms,
                                ),

                                const SizedBox(height: 24),

                                // Absence Button (Secondary)
                                if (!isSupervisor) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        if (employeeId != null) {
                                          AttendanceLogic(
                                            ref,
                                          ).reportAbsence(context, employeeId);
                                        }
                                      },
                                      icon: const Icon(Icons.sick_outlined),
                                      label: const Text(
                                        'REPORTAR INASISTENCIA',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade600,
                                        side: BorderSide(
                                          color: Colors.red.shade200,
                                          width: 1.5,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        textStyle: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error: $error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  if (employeeId != null) {
                    // Invalidate provider to force refresh
                    ref.invalidate(employeeStatusProvider(employeeId));
                  }
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JustificationDialog extends StatefulWidget {
  final String title;
  final String message;
  final bool isEvidenceRequired; // Legacy support
  final dynamic repositoryRef; // Para cargar motivos

  const JustificationDialog({
    super.key,
    required this.title,
    required this.message,
    this.isEvidenceRequired = false,
    this.repositoryRef,
  });

  @override
  State<JustificationDialog> createState() => _JustificationDialogState();
}

class _JustificationDialogState extends State<JustificationDialog> {
  final _reasonController = TextEditingController();
  File? _evidenceFile;

  // Logic for dynamic reasons
  List<Map<String, dynamic>> _absenceReasons = [];
  String? _selectedReasonType;
  bool _isLoadingReasons = false;
  bool _dynamicEvidenceRequired = false;

  @override
  void initState() {
    super.initState();
    if (widget.repositoryRef != null) {
      _loadReasons();
    } else {
      // Fallback or legacy mode
      _dynamicEvidenceRequired = widget.isEvidenceRequired;
    }
  }

  Future<void> _loadReasons() async {
    setState(() => _isLoadingReasons = true);
    try {
      final reasons = await widget.repositoryRef.getAbsenceReasons();
      if (mounted) {
        setState(() {
          _absenceReasons = reasons;
          _isLoadingReasons = false;
          if (reasons.isNotEmpty) {
            // Default to first one or specific one
            _selectedReasonType = reasons.first['name'];
            _dynamicEvidenceRequired =
                reasons.first['requires_evidence'] ?? false;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingReasons = false);
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _evidenceFile = File(result.files.single.path!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Selector de Motivo (Si hay repositorio)
            if (widget.repositoryRef != null) ...[
              if (_isLoadingReasons)
                const Center(child: CircularProgressIndicator())
              else if (_absenceReasons.isNotEmpty)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedReasonType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Motivo',
                    border: OutlineInputBorder(),
                  ),
                  items: _absenceReasons.map<DropdownMenuItem<String>>((r) {
                    return DropdownMenuItem(
                      value: r['name'],
                      child: Text(r['name'], overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedReasonType = val;
                      final r = _absenceReasons.firstWhere(
                        (e) => e['name'] == val,
                      );
                      _dynamicEvidenceRequired =
                          r['requires_evidence'] ?? false;
                    });
                  },
                ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Comentarios / Detalles',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Text(
              'Adjuntar evidencia${_dynamicEvidenceRequired ? ' (Obligatorio)' : ''}:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _dynamicEvidenceRequired ? Colors.red : null,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickFile,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.attach_file,
                      color: _evidenceFile != null ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _evidenceFile != null
                            ? _evidenceFile!.path.split('/').last
                            : 'Toca para adjuntar archivo',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              (_dynamicEvidenceRequired &&
                                  _evidenceFile == null)
                              ? Colors.red
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            // Validaciones
            if (widget.repositoryRef != null && _selectedReasonType == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Seleccione un tipo de motivo')),
              );
              return;
            }

            if (_reasonController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Debes ingresar un comentario o detalle'),
                ),
              );
              return;
            }
            if (_dynamicEvidenceRequired && _evidenceFile == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Es obligatorio adjuntar evidencia para este motivo',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            Navigator.of(context).pop({
              'reason': _reasonController.text,
              'file': _evidenceFile,
              'recordType':
                  _selectedReasonType ?? 'AUSENCIA', // Fallback legacy
            });
          },
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

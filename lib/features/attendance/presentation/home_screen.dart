import 'dart:async';
import 'dart:io';

import 'package:analog_clock/analog_clock.dart';
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/attendance/data/attendance_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

// 1. Provider para obtener los datos de asistencia (READ-ONLY State)
final attendanceDataProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>?, String?>((ref, employeeId) async {
      if (employeeId == null) return null;
      // Pequeño delay artificial para asegurar que la UI responda bien a cambios rápidos
      // await Future.delayed(Duration.zero);
      return ref
          .watch(attendanceRepositoryProvider)
          .getTodayAttendance(employeeId);
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

    // 1. Mostrar diálogo de justificación
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const JustificationDialog(
        title: 'Reportar Inasistencia',
        message:
            'Describe el motivo de tu falta. Si tienes certificado médico u otra evidencia, adjúntala.',
        isEvidenceRequired:
            false, // Opcional o obligatorio según regla de negocio
      ),
    );

    if (result == null) return; // Cancelado

    final reason = result['reason'];
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
        ref.invalidate(attendanceDataProvider(employeeId));
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

        // Check In logic (UPDATED)
        final now = DateTime.now();
        // Hora límite para TARDANZA: 07:00 (7 AM)
        final tardanzaLimit = DateTime(now.year, now.month, now.day, 7, 0);

        // Hora límite para CIERRE/INASISTENCIA: 18:00 (6 PM)
        final absenceLimit = DateTime(now.year, now.month, now.day, 18, 0);

        final isLate = now.isAfter(tardanzaLimit);
        final isAbsenceTime = now.isAfter(absenceLimit);

        String? lateReason;
        File? evidenceFile;

        if (isLate || isAbsenceTime) {
          if (context.mounted) {
            ref.read(actionLoadingNotifierProvider).value = false;

            final title = isAbsenceTime
                ? 'Justificar Inasistencia'
                : 'Ingreso Tardío';
            final message = isAbsenceTime
                ? 'Ha pasado el límite de registro (6:00 PM). Debes justificar tu inasistencia.'
                : 'Estás marcando después de las 7:00 AM. Se registrará como TARDANZA.';

            final result = await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (context) => JustificationDialog(
                title: title,
                message: message,
                isEvidenceRequired: true,
              ),
            );

            if (result == null) {
              return; // Cancelled
            }

            lateReason = result['reason'];
            evidenceFile = result['file'];

            ref.read(actionLoadingNotifierProvider).value = true;
          }
        }

        await ref
            .read(attendanceRepositoryProvider)
            .checkIn(
              employeeId: employeeId,
              lat: position.latitude,
              lng: position.longitude,
              lateReason: lateReason,
              evidenceFile: evidenceFile,
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
      ref.invalidate(attendanceDataProvider(employeeId));
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

    // Lista de roles con privilegios de gestión (no bloqueados por horario)
    // final isSupervisor = [
    //   'SUPERVISOR',
    //   'JEFE_VENTAS',
    //   'SUPERVISOR_VENTAS',
    //   'SUPERVISOR_OPERACIONES',
    //   'COORDINADOR_OPERACIONES',
    // ].contains(userRole);

    // Watch data
    // Use select to watch only specific parts if needed, or watch the whole provider
    // IMPORTANT: invalidate this provider on logout to prevent stale data
    final attendanceAsync = ref.watch(attendanceDataProvider(employeeId));
    final loadingNotifier = ref.watch(actionLoadingNotifierProvider);

    final positionTitle = storage.position ?? 'Empleado';
    final profilePic = storage.profilePicture;

    return Scaffold(
      body: attendanceAsync.when(
        data: (attendance) {
          // Lógica de Horario Estricto
          final now = DateTime.now();
          final todayStr = DateFormat('yyyy-MM-dd').format(now);

          // Validar si el registro recuperado es de hoy
          final recordDate = attendance?['work_date'] as String?;
          final isRecordFromToday = recordDate == todayStr;

          // Filtrar asistencia efectiva (si no es de hoy, es como si no hubiera registro hoy)
          final effectiveAttendance = isRecordFromToday ? attendance : null;

          final isCheckedIn =
              effectiveAttendance != null &&
              effectiveAttendance['check_out'] == null;

          final lastCheckIn = effectiveAttendance != null
              ? effectiveAttendance['check_in']
              : null;

          // Si ya marcó salida hoy O si es una INASISTENCIA registrada
          final isDayComplete =
              effectiveAttendance != null &&
              (effectiveAttendance['check_out'] != null ||
                  effectiveAttendance['record_type'] == 'INASISTENCIA' ||
                  effectiveAttendance['record_type'] == 'AUSENCIA');

          final isAbsence =
              effectiveAttendance != null &&
              (effectiveAttendance['record_type'] == 'INASISTENCIA' ||
                  effectiveAttendance['record_type'] == 'AUSENCIA');

          // Hora límite para TARDANZA: 07:00 (7 AM)
          final tardanzaLimit = DateTime(now.year, now.month, now.day, 7, 0);

          // Hora límite para CIERRE/INASISTENCIA: 18:00 (6 PM)
          // final absenceLimit = DateTime(now.year, now.month, now.day, 18, 0);

          final isTardanza = now.isAfter(tardanzaLimit);
          // final isPastAbsenceLimit = now.isAfter(absenceLimit);

          // Si pasó las 18:00 y no marcó, es "Inasistencia por justificar"
          // Habilitamos el botón pero cambiamos su función visualmente
          // final isAbsenceJustificationMode =
          //    !isCheckedIn && !isDayComplete && isPastAbsenceLimit;

          // final canMark =
          //    !isDayComplete && !isCheckedIn; // Solo puede marcar si NO ha completado Y NO está en jornada

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

              // Main Content
              SafeArea(
                child: Column(
                  children: [
                    // Top Bar: Welcome & Profile
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
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
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  fullName.split(
                                    ' ',
                                  )[0], // First name only for cleaner look
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // Optional: Notification or Settings Icon
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.notifications_outlined,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Clock & Date Card
                    Padding(
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                      borderRadius: BorderRadius.circular(8),
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

                    const SizedBox(height: 24),

                    // Status & Action Area
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isDayComplete || isCheckedIn) ...[
                              // COMPLETED STATE
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  color: isAbsence
                                      ? Colors.orange.shade50
                                      : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(32),
                                  border: Border.all(
                                    color: isAbsence
                                        ? Colors.orange.shade200
                                        : Colors.green.shade200,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      isAbsence
                                          ? Icons.assignment_late
                                          : Icons.check_circle,
                                      size: 64,
                                      color: isAbsence
                                          ? Colors.orange
                                          : Colors.green,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      isAbsence
                                          ? 'Inasistencia Registrada'
                                          : '¡Jornada Iniciada!',
                                      style: TextStyle(
                                        color: isAbsence
                                            ? Colors.orange.shade800
                                            : Colors.green.shade800,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      isAbsence
                                          ? 'Tu reporte ha sido enviado.'
                                          : 'Entrada: ${lastCheckIn != null ? DateFormat('hh:mm a').format(DateTime.parse(lastCheckIn).toLocal()) : '--:--'}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isAbsence
                                            ? Colors.orange.shade700
                                            : Colors.green.shade700,
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
                                                    fontWeight: FontWeight.w800,
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
                                  label: const Text('REPORTAR INASISTENCIA'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade600,
                                    side: BorderSide(
                                      color: Colors.red.shade200,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
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
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
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
                    ref.invalidate(attendanceDataProvider(employeeId));
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
  final bool isEvidenceRequired;

  const JustificationDialog({
    super.key,
    required this.title,
    required this.message,
    this.isEvidenceRequired = false,
  });

  @override
  State<JustificationDialog> createState() => _JustificationDialogState();
}

class _JustificationDialogState extends State<JustificationDialog> {
  final _reasonController = TextEditingController();
  File? _evidenceFile;

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
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo / Justificación',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Text(
              'Adjuntar evidencia${widget.isEvidenceRequired ? ' (Obligatorio)' : ''}:',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _evidenceFile != null
                        ? _evidenceFile!.path.split('/').last
                        : 'Ningún archivo seleccionado',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          (widget.isEvidenceRequired && _evidenceFile == null)
                          ? Colors.red
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.attach_file),
                ),
              ],
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
            if (_reasonController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Debes ingresar un motivo')),
              );
              return;
            }
            if (widget.isEvidenceRequired && _evidenceFile == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Es obligatorio adjuntar evidencia'),
                ),
              );
              return;
            }
            Navigator.of(
              context,
            ).pop({'reason': _reasonController.text, 'file': _evidenceFile});
          },
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

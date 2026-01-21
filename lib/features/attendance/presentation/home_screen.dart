import 'dart:async';
import 'dart:io';

import 'package:analog_clock/analog_clock.dart';
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/attendance/data/attendance_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
    ref.onDispose(notifier.dispose);
    return notifier;
  },
);

// 3. Clase lógica para acciones
class AttendanceLogic {
  final WidgetRef ref;

  AttendanceLogic(this.ref);

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
      final currentAttendance = await ref
          .read(attendanceRepositoryProvider)
          .getTodayAttendance(employeeId);
      final isCheckedIn =
          currentAttendance != null && currentAttendance['check_out'] == null;

      if (isCheckedIn) {
        // Check Out
        await ref
            .read(attendanceRepositoryProvider)
            .checkOut(
              employeeId: employeeId,
              lat: position.latitude,
              lng: position.longitude,
            );
      } else {
        // Check In logic
        String? lateReason;
        File? evidenceFile;

        // Check if late (Strict schedule logic moved here or reused)
        final now = DateTime.now();
        // Usamos una hora límite estándar para considerar "tardanza" y pedir justificación
        // Por ejemplo, 8:10 AM. Si es después de esto, se pide foto.
        final lateLimit = DateTime(
          now.year,
          now.month,
          now.day,
          8,
          10,
        ); // 8:10 AM

        // Si es después de las 8:10 AM, es tarde.
        final isLate = now.isAfter(lateLimit);

        if (isLate) {
          // Stop loading to show dialog
          ref.read(actionLoadingNotifierProvider).value = false;

          if (!context.mounted) return;

          final result = await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            isScrollControlled: true,
            builder: (context) => const LateCheckInModal(),
          );

          if (result == null) {
            return; // Cancelled
          }

          lateReason = result['reason'];
          evidenceFile = result['file'];

          // Resume loading
          ref.read(actionLoadingNotifierProvider).value = true;
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

class LateCheckInModal extends StatefulWidget {
  const LateCheckInModal({super.key});

  @override
  State<LateCheckInModal> createState() => _LateCheckInModalState();
}

class _LateCheckInModalState extends State<LateCheckInModal> {
  final _reasonController = TextEditingController();
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 50,
    );
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Justificación de Tardanza',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(
              labelText: 'Motivo de la tardanza',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          const Text(
            'Evidencia (Opcional)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cámara'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galería'),
                ),
              ),
            ],
          ),
          if (_selectedImage != null) ...[
            const SizedBox(height: 8),
            Container(
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(_selectedImage!, fit: BoxFit.cover),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _selectedImage = null),
              icon: const Icon(Icons.delete, color: Colors.red),
              label: const Text(
                'Eliminar foto',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (_reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor ingrese un motivo')),
                );
                return;
              }
              Navigator.pop(context, {
                'reason': _reasonController.text.trim(),
                'file': _selectedImage,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('REGISTRAR ENTRADA'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    final employeeId = storage.employeeId;
    final userRole = storage.role;
    final fullName = storage.userName ?? 'Usuario'; // Added fallback

    // Lista de roles con privilegios de gestión (no bloqueados por horario)
    final isSupervisor = [
      'SUPERVISOR',
      'JEFE_VENTAS',
      'SUPERVISOR_VENTAS',
      'SUPERVISOR_OPERACIONES',
      'COORDINADOR_OPERACIONES',
    ].contains(userRole);

    // Watch data
    final attendanceState = ref.watch(attendanceDataProvider(employeeId));
    final loadingNotifier = ref.watch(actionLoadingNotifierProvider);

    final position = storage.position ?? 'Empleado';
    final sede = storage.sede ?? 'Sin Sede';
    final businessUnit = storage.businessUnit;
    final profilePic = storage.profilePicture;

    return Scaffold(
      body: attendanceState.when(
        data: (attendance) {
          final isCheckedIn =
              attendance != null && attendance['check_out'] == null;

          final lastCheckIn = attendance != null
              ? attendance['check_in']
              : null;

          // Si ya marcó salida hoy O si es una INASISTENCIA registrada
          final isDayComplete =
              attendance != null &&
              (attendance['check_out'] != null ||
                  attendance['record_type'] == 'INASISTENCIA');

          final isAbsence =
              attendance != null && attendance['record_type'] == 'INASISTENCIA';

          // Lógica de Horario Estricto
          // Si son las 06:01 PM o más y NO ha marcado entrada -> Se bloquea Check-In (Para Operarios)
          final now = DateTime.now();

          // Hora límite visual: 18:00 (6 PM) - Solo para mostrar advertencia visual, NO BLOQUEAR
          final lateLimit = DateTime(now.year, now.month, now.day, 18, 0);

          final isPastLimit = now.isAfter(lateLimit);

          // Variable solo para visualización, ya NO bloquea la acción
          final isTooLateToMark =
              !isCheckedIn && !isDayComplete && isPastLimit && !isSupervisor;

          if (isDayComplete) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: isAbsence
                                ? Colors.orange
                                : Colors.green,
                            child: Icon(
                              isAbsence ? Icons.warning : Icons.check,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Hola, $fullName',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isAbsence
                                ? 'Inasistencia Registrada'
                                : 'Jornada Completada',
                            style: TextStyle(
                              color: isAbsence ? Colors.orange : Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAbsence
                                ? 'Se ha registrado tu reporte de inasistencia.'
                                : 'Has registrado tu salida exitosamente.',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ).animate().slideY(begin: -0.1, duration: 400.ms).fadeIn(),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 48,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '¡Hasta mañana!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ya no puedes registrar más asistencias por hoy.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              SizedBox(
                height:
                    MediaQuery.of(context).size.height -
                    kToolbarHeight -
                    48, // Fill screen
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      color: Colors.white,
                      surfaceTintColor: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Left: Profile Picture
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.grey.shade100,
                                    border: Border.all(
                                      color: Colors.blue.shade100,
                                      width: 2,
                                    ),
                                    image: profilePic != null
                                        ? DecorationImage(
                                            image: NetworkImage(profilePic),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: profilePic == null
                                      ? Icon(
                                          Icons.person,
                                          size: 40,
                                          color: Colors.blue.shade300,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                // Right: User Data
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fullName.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1E293B),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          position.toUpperCase(),
                                          style: TextStyle(
                                            color: const Color(0xFF2563EB),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        businessUnit != null
                                            ? '$sede - $businessUnit'
                                            : sede,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(height: 1),
                            const SizedBox(height: 16),
                            // Bottom: Date and Analog Clock
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat(
                                        'EEEE',
                                        'es',
                                      ).format(DateTime.now()).toUpperCase(),
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    Text(
                                      DateFormat(
                                        'd MMMM yyyy',
                                        'es',
                                      ).format(DateTime.now()),
                                      style: const TextStyle(
                                        color: Color(0xFF1E293B),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: AnalogClock(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        width: 2.0,
                                        color: Colors.black,
                                      ),
                                      color: Colors.transparent,
                                      shape: BoxShape.circle,
                                    ),
                                    width: 50.0,
                                    isLive: true,
                                    hourHandColor: Colors.black,
                                    minuteHandColor: Colors.black,
                                    showSecondHand: true,
                                    secondHandColor: Colors.red,
                                    numberColor: Colors.black87,
                                    datetime: DateTime.now(),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ).animate().slideY(begin: -0.1, duration: 400.ms).fadeIn(),

                    const Spacer(),

                    // Status Indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isCheckedIn
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isTooLateToMark
                              ? Colors.red.shade200
                              : (isCheckedIn
                                    ? Colors.green.shade200
                                    : Colors.orange.shade200),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isTooLateToMark
                                ? Icons.lock_clock
                                : (isCheckedIn
                                      ? Icons.check_circle_outline
                                      : Icons.access_time),
                            color: isTooLateToMark
                                ? Colors.red
                                : (isCheckedIn ? Colors.green : Colors.orange),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isTooLateToMark
                                    ? 'Ingreso Bloqueado'
                                    : (isCheckedIn
                                          ? 'En Jornada'
                                          : 'Fuera de Jornada'),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isTooLateToMark
                                      ? Colors.red
                                      : (isCheckedIn
                                            ? Colors.green.shade700
                                            : Colors.orange.shade800),
                                ),
                              ),
                              if (isCheckedIn && lastCheckIn != null)
                                Text(
                                  'Entrada: $lastCheckIn',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms),

                    const SizedBox(height: 24),

                    // Main Action Button
                    SizedBox(
                      height: 180,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: loadingNotifier,
                        builder: (context, isActionLoading, child) {
                          return ElevatedButton(
                            onPressed: isActionLoading
                                ? null
                                : () {
                                    if (employeeId != null) {
                                      AttendanceLogic(
                                        ref,
                                      ).markAttendance(context, employeeId);
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isCheckedIn
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF2563EB),
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 8,
                              shadowColor:
                                  (isCheckedIn ? Colors.red : Colors.blue)
                                      .withValues(alpha: 0.4),
                            ),
                            child: isActionLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isCheckedIn
                                            ? Icons.exit_to_app
                                            : Icons.login,
                                        size: 48,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        isCheckedIn
                                            ? 'MARCAR SALIDA'
                                            : 'MARCAR ENTRADA',
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Toque para registrar',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
                    ).animate().scale(
                      delay: 300.ms,
                      duration: 400.ms,
                      curve: Curves.easeOut,
                    ),

                    const SizedBox(height: 24),

                    // Absence Button (Secondary)
                    if (!isCheckedIn)
                      SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (employeeId != null) {
                              context.push('/absence', extra: employeeId);
                            }
                          },
                          icon: const Icon(Icons.assignment_late_outlined),
                          label: const Text('REPORTAR INASISTENCIA'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ).animate().fadeIn(delay: 400.ms),

                    const Spacer(),
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

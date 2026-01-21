import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/attendance/data/attendance_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

final attendanceHistoryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final storage = ref.watch(storageServiceProvider);
      final employeeId = storage.employeeId;
      if (employeeId == null) return [];

      return ref
          .watch(attendanceRepositoryProvider)
          .getAttendanceHistory(employeeId);
    });

class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Manejar error silenciosamente o mostrar snackbar si se tuviera contexto
      debugPrint('No se pudo abrir $url');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(attendanceHistoryProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Historial de Asistencias'),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(attendanceHistoryProvider),
          ),
        ],
      ),
      body: historyAsync.when(
        data: (history) {
          if (history.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No hay historial de asistencias'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final record = history[index];
              final date = DateTime.parse(
                record['work_date'] ?? record['created_at'],
              );
              final checkIn = record['check_in'] != null
                  ? DateTime.parse(record['check_in']).toLocal()
                  : null;
              // final checkOut = record['check_out'] != null
              //    ? DateTime.parse(record['check_out']).toLocal()
              //    : null;

              final isLate = record['is_late'] == true;
              final hasBonus = record['has_bonus'] == true;
              final recordType = record['record_type'];
              final isAbsence = recordType == 'INASISTENCIA';

              final notes = record['notes'];
              final absenceReason = record['absence_reason'];
              final evidenceUrl = record['evidence_url'];

              // Determinar textos a mostrar
              final displayNotes = isAbsence ? (absenceReason ?? notes) : notes;

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat(
                              'EEEE, d MMMM',
                              'es',
                            ).format(date).toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          if (isAbsence)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'INASISTENCIA',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else if (isLate)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'TARDE',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else if (hasBonus)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'BONO',
                                style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Divider(),
                      if (!isAbsence) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Entrada',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.login,
                                        size: 16,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        checkIn != null
                                            ? DateFormat(
                                                'hh:mm a',
                                              ).format(checkIn)
                                            : '--:--',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Motivo',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  GestureDetector(
                                    onTap:
                                        (displayNotes != null ||
                                            evidenceUrl != null)
                                        ? () {
                                            showDialog(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text(
                                                  'Detalle de Justificación',
                                                ),
                                                content: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (displayNotes !=
                                                        null) ...[
                                                      const Text(
                                                        'Motivo:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(displayNotes),
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
                                                    ],
                                                    if (evidenceUrl != null)
                                                      ElevatedButton.icon(
                                                        onPressed: () =>
                                                            _launchUrl(
                                                              evidenceUrl,
                                                            ),
                                                        icon: const Icon(
                                                          Icons.attach_file,
                                                        ),
                                                        label: const Text(
                                                          'Ver Evidencia',
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    child: const Text('Cerrar'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        : null,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          size: 16,
                                          color:
                                              (displayNotes != null ||
                                                  evidenceUrl != null)
                                              ? Colors.blue
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          (displayNotes != null ||
                                                  evidenceUrl != null)
                                              ? 'Ver Detalle'
                                              : 'Sin motivo',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color:
                                                (displayNotes != null ||
                                                    evidenceUrl != null)
                                                ? Colors.blue
                                                : Colors.grey,
                                            decoration:
                                                (displayNotes != null ||
                                                    evidenceUrl != null)
                                                ? TextDecoration.underline
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Eliminamos la sección de detalles expandida ya que ahora es modal
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

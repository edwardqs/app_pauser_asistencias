import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/attendance/data/attendance_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// State Class para manejar la lista y el estado de paginación
class AttendanceHistoryState {
  final List<Map<String, dynamic>> records;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String filter; // Nuevo campo para el filtro actual
  final Object? error;

  AttendanceHistoryState({
    required this.records,
    this.isLoading = false,
    this.hasMore = true,
    this.page = 0,
    this.filter = 'all',
    this.error,
  });

  AttendanceHistoryState copyWith({
    List<Map<String, dynamic>>? records,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? filter,
    Object? error,
  }) {
    return AttendanceHistoryState(
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      filter: filter ?? this.filter,
      error: error,
    );
  }
}

// Notifier para la lógica de paginación
class AttendanceHistoryNotifier
    extends AutoDisposeNotifier<AttendanceHistoryState> {
  static const int _pageSize = 15;

  @override
  AttendanceHistoryState build() {
    // Carga inicial
    Future.microtask(() => loadInitial());
    return AttendanceHistoryState(records: [], isLoading: true);
  }

  Future<void> loadInitial() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final storage = ref.read(storageServiceProvider);
      final employeeId = storage.employeeId;
      if (employeeId == null) {
        state = state.copyWith(
          isLoading: false,
          hasMore: false,
          records: [],
          error: 'No se encontró ID de empleado',
        );
        return;
      }

      final newRecords = await ref
          .read(attendanceRepositoryProvider)
          .getAttendanceHistory(
            employeeId,
            page: 0,
            pageSize: _pageSize,
            filter: state.filter,
          );

      state = state.copyWith(
        records: newRecords,
        isLoading: false,
        page: 1,
        hasMore: newRecords.length >= _pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  Future<void> setFilter(String newFilter) async {
    if (state.filter == newFilter) return;

    // Resetear lista y cambiar filtro
    state = AttendanceHistoryState(
      records: [],
      isLoading: true,
      filter: newFilter,
    );

    await loadInitial();
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final storage = ref.read(storageServiceProvider);
      final employeeId = storage.employeeId;
      if (employeeId == null) return;

      final newRecords = await ref
          .read(attendanceRepositoryProvider)
          .getAttendanceHistory(
            employeeId,
            page: state.page,
            pageSize: _pageSize,
            filter: state.filter,
          );

      state = state.copyWith(
        records: [...state.records, ...newRecords],
        isLoading: false,
        page: state.page + 1,
        hasMore: newRecords.length >= _pageSize,
      );
    } catch (e) {
      // En error de "cargar más", solo quitamos loading, mantenemos los datos viejos
      state = state.copyWith(isLoading: false);
      // Podríamos guardar el error en una variable temporal para mostrar snackbar
    }
  }

  void refresh() {
    // Mantener filtro actual al refrescar
    final currentFilter = state.filter;
    state = AttendanceHistoryState(
      records: [],
      isLoading: true,
      filter: currentFilter,
    );
    loadInitial();
  }
}

final attendanceHistoryProvider =
    NotifierProvider.autoDispose<
      AttendanceHistoryNotifier,
      AttendanceHistoryState
    >(AttendanceHistoryNotifier.new);

class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState
    extends ConsumerState<AttendanceHistoryScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(attendanceHistoryProvider.notifier).loadMore();
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('No se pudo abrir $url');
    }
  }

  Widget _buildFilterChip(String label, String value, String currentFilter) {
    final isSelected = currentFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          ref.read(attendanceHistoryProvider.notifier).setFilter(value);
        }
      },
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFEFF6FF), // Azul muy claro
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
        ),
      ),
      showCheckmark: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final historyState = ref.watch(attendanceHistoryProvider);
    final history = historyState.records;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Historial de Asistencias'),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(attendanceHistoryProvider.notifier).refresh(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildFilterChip('Todos', 'all', historyState.filter),
                const SizedBox(width: 8),
                _buildFilterChip('Puntuales', 'on_time', historyState.filter),
                const SizedBox(width: 8),
                _buildFilterChip('Tardanzas', 'late', historyState.filter),
                const SizedBox(width: 8),
                _buildFilterChip('Ausencias', 'absent', historyState.filter),
              ],
            ),
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          if (historyState.isLoading && history.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (historyState.error != null && history.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${historyState.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        ref.read(attendanceHistoryProvider.notifier).refresh(),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

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
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: history.length + (historyState.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == history.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final record = history[index];
              final date = DateTime.parse(
                record['work_date'] ?? record['created_at'],
              );
              final checkIn = record['check_in'] != null
                  ? DateTime.parse(record['check_in']).toLocal()
                  : null;

              final isLate = record['is_late'] == true;
              final hasBonus = record['has_bonus'] == true;
              final recordType = record['record_type'];
              final isAbsence =
                  recordType == 'INASISTENCIA' || recordType == 'AUSENCIA';
              final isValidated = record['validated'] == true;
              final locationIn = record['location_in'];

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
                          Expanded(
                            child: Text(
                              DateFormat(
                                'EEEE, d MMMM',
                                'es',
                              ).format(date).toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
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
                                'AUSENCIA',
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
                          // Indicador de Validación
                          if (isValidated)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Icon(
                                Icons.verified,
                                size: 16,
                                color: Colors.blue.shade600,
                              ),
                            ),
                        ],
                      ),
                      const Divider(),
                      // Bloque de información (Siempre visible, tanto para asistencias como ausencias)
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Hora Registro',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      isAbsence
                                          ? Icons.report_problem_outlined
                                          : Icons.login,
                                      size: 16,
                                      color: isAbsence
                                          ? Colors.orange
                                          : Colors.green,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      // Para ausencias usamos created_at si no hay check_in
                                      isAbsence
                                          ? (record['created_at'] != null
                                                ? DateFormat('hh:mm a').format(
                                                    DateTime.parse(
                                                      record['created_at'],
                                                    ).toLocal(),
                                                  )
                                                : '--:--')
                                          : (checkIn != null
                                                ? DateFormat(
                                                    'hh:mm a',
                                                  ).format(checkIn)
                                                : '--:--'),
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
                                  'Motivo / Ubicación',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    // Botón de Detalle
                                    GestureDetector(
                                      onTap:
                                          (displayNotes != null ||
                                              evidenceUrl != null)
                                          ? () {
                                              showDialog(
                                                context: context,
                                                builder: (context) =>
                                                    AlertDialog(
                                                      title: const Text(
                                                        'Detalle de Registro',
                                                      ),
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          if (displayNotes !=
                                                              null) ...[
                                                            const Text(
                                                              'Motivo/Notas:',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            Text(displayNotes),
                                                            const SizedBox(
                                                              height: 16,
                                                            ),
                                                          ],
                                                          if (evidenceUrl !=
                                                              null)
                                                            ElevatedButton.icon(
                                                              onPressed: () =>
                                                                  _launchUrl(
                                                                    evidenceUrl,
                                                                  ),
                                                              icon: const Icon(
                                                                Icons
                                                                    .attach_file,
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
                                                              Navigator.pop(
                                                                context,
                                                              ),
                                                          child: const Text(
                                                            'Cerrar',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                              );
                                            }
                                          : null,
                                      child: Icon(
                                        Icons.info_outline,
                                        size: 18,
                                        color:
                                            (displayNotes != null ||
                                                evidenceUrl != null)
                                            ? Colors.blue
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Botón de Mapa
                                    if (locationIn != null)
                                      GestureDetector(
                                        onTap: () {
                                          try {
                                            final lat = locationIn['lat'];
                                            final lng = locationIn['lng'];
                                            if (lat != null && lng != null) {
                                              _launchUrl(
                                                'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                                              );
                                            }
                                          } catch (e) {
                                            debugPrint(
                                              'Error parsing location: $e',
                                            );
                                          }
                                        },
                                        child: const Icon(
                                          Icons.map_outlined,
                                          size: 18,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

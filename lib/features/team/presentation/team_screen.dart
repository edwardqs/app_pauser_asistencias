import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/team/data/team_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final teamAttendanceProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final storage = ref.watch(storageServiceProvider);
      final supervisorId = storage.employeeId;

      if (supervisorId == null) return [];

      return ref.watch(teamRepositoryProvider).getTeamAttendance(supervisorId);
    });

// Provider para el filtro seleccionado (Notifier)
class TeamFilterNotifier extends Notifier<String> {
  @override
  String build() => 'todos';

  void setFilter(String filter) => state = filter;
}

final teamFilterProvider = NotifierProvider<TeamFilterNotifier, String>(
  TeamFilterNotifier.new,
);

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamAttendanceProvider);
    final currentFilter = ref.watch(teamFilterProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Mi Equipo'),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(teamAttendanceProvider),
          ),
        ],
      ),
      body: teamAsync.when(
        data: (team) {
          if (team.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No tienes empleados asignados o no hay datos.'),
                ],
              ),
            );
          }

          // Lógica de filtrado
          final filteredTeam = team.where((member) {
            final isLate = member['is_late'] == true;
            final isAbsent = member['record_type'] == 'INASISTENCIA';
            final hasCheckIn = member['check_in'] != null;

            // Puntual: Tiene check-in y NO es tarde
            final isPuntual = hasCheckIn && !isLate;

            // Tardanza: Es tarde (con o sin check-in, aunque usualmente con check-in)
            final isTardanza = isLate;

            switch (currentFilter) {
              case 'puntuales':
                return isPuntual;
              case 'tardanzas':
                return isTardanza;
              case 'inasistencias':
                return isAbsent;
              default:
                return true;
            }
          }).toList();

          // Resumen de contadores (Globales, sin filtrar)
          final total = team.length;
          final presentes = team
              .where((e) => e['check_in'] != null && e['check_out'] == null)
              .length;
          final pendientes = team
              .where(
                (e) =>
                    e['check_in'] == null && e['record_type'] != 'INASISTENCIA',
              )
              .length;
          final ausentes = team
              .where((e) => e['record_type'] == 'INASISTENCIA')
              .length;

          return Column(
            children: [
              // Header con métricas
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey.shade50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('Total', total.toString(), Colors.blue),
                    _buildStat('Presentes', presentes.toString(), Colors.green),
                    _buildStat(
                      'Pendientes',
                      pendientes.toString(),
                      Colors.orange,
                    ),
                    _buildStat('Ausentes', ausentes.toString(), Colors.red),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Filtros
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Todos',
                      value: 'todos',
                      groupValue: currentFilter,
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Puntuales',
                      value: 'puntuales',
                      groupValue: currentFilter,
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Tardanzas',
                      value: 'tardanzas',
                      groupValue: currentFilter,
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Inasistencias',
                      value: 'inasistencias',
                      groupValue: currentFilter,
                    ),
                  ],
                ),
              ),

              // Lista de empleados filtrada
              Expanded(
                child: filteredTeam.isEmpty
                    ? const Center(
                        child: Text('No hay registros con este filtro'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredTeam.length,
                        itemBuilder: (context, index) {
                          final member = filteredTeam[index];
                          return _buildMemberCard(context, member);
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildMemberCard(BuildContext context, Map<String, dynamic> member) {
    final fullName = member['full_name'] ?? 'Sin Nombre';
    final position = member['position'] ?? 'Cargo no definido';
    final profilePic = member['profile_picture_url'];
    final checkIn = member['check_in'];
    final checkOut = member['check_out'];
    final isLate = member['is_late'] == true;
    final notes = member['notes'];
    final recordType = member['record_type'];

    Color statusColor;
    String statusText;

    if (recordType == 'INASISTENCIA') {
      statusColor = Colors.red;
      statusText = 'Ausente';
    } else if (checkOut != null) {
      statusColor = Colors.grey;
      statusText = 'Salida';
    } else if (checkIn != null) {
      statusColor = Colors.green;
      statusText = 'En Jornada';
    } else {
      statusColor = Colors.orange;
      statusText = 'Pendiente';
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: profilePic != null
                      ? NetworkImage(profilePic)
                      : null,
                  child: profilePic == null
                      ? Icon(Icons.person, color: Colors.grey.shade400)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        position,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (checkIn != null ||
                notes != null ||
                recordType == 'INASISTENCIA') ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (checkIn != null)
                    Row(
                      children: [
                        const Icon(Icons.login, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat(
                            'HH:mm',
                          ).format(DateTime.parse(checkIn).toLocal()),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (isLate)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'TARDE',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (checkOut != null)
                    Row(
                      children: [
                        const Icon(Icons.logout, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat(
                            'HH:mm',
                          ).format(DateTime.parse(checkOut).toLocal()),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                ],
              ),
              if (notes != null && notes.toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.note, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          notes,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends ConsumerWidget {
  final String label;
  final String value;
  final String groupValue;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.groupValue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = value == groupValue;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          ref.read(teamFilterProvider.notifier).setFilter(value);
        }
      },
      selectedColor: Colors.blue.shade100,
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue.shade900 : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

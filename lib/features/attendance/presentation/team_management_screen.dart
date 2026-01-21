import 'package:app_asistencias_pauser/features/attendance/data/attendance_repository.dart';
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final teamProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final storage = ref.watch(storageServiceProvider);
  final supervisorId = storage.employeeId;
  if (supervisorId == null) return [];
  
  return ref.read(attendanceRepositoryProvider).getMyTeam(supervisorId);
});

class TeamManagementScreen extends ConsumerWidget {
  const TeamManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Equipo'),
        centerTitle: true,
      ),
      body: teamAsync.when(
        data: (team) {
          if (team.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No tienes personal asignado',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: team.length,
            itemBuilder: (context, index) {
              final employee = team[index];
              final name = '${employee['first_name']} ${employee['last_name']}';
              final position = employee['position'] ?? 'Sin cargo';
              
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      name.substring(0, 1).toUpperCase(),
                      style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(position),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Futuro: Ver detalle de asistencia del empleado
                  },
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

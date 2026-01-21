import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return TeamRepository(Supabase.instance.client);
});

class TeamRepository {
  final SupabaseClient _supabase;

  TeamRepository(this._supabase);

  Future<List<Map<String, dynamic>>> getTeamAttendance(String supervisorId) async {
    try {
      final response = await _supabase.rpc(
        'get_team_attendance',
        params: {
          'p_supervisor_id': supervisorId,
        },
      );

      if (response == null) {
        return [];
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // print('Error fetching team attendance: $e');
      throw Exception('Error cargando equipo: $e');
    }
  }
}

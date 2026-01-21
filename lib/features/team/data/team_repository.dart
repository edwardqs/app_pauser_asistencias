import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return TeamRepository(Supabase.instance.client);
});

class TeamRepository {
  final SupabaseClient _supabase;

  TeamRepository(this._supabase);

  Future<List<Map<String, dynamic>>> getTeamAttendance(
    String supervisorId,
  ) async {
    try {
      final response = await _supabase.rpc(
        'get_team_attendance',
        params: {'p_supervisor_id': supervisorId},
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

  /// Valida o rechaza una asistencia
  Future<void> validateAttendance({
    required String attendanceId,
    required String supervisorId,
    required bool approved,
    String? notes,
  }) async {
    try {
      final response = await _supabase.rpc(
        'supervisor_validate_attendance',
        params: {
          'p_attendance_id': attendanceId,
          'p_supervisor_id': supervisorId,
          'p_validated': approved,
          'p_notes': notes,
        },
      );

      if (response['success'] == false) {
        throw Exception(response['message']);
      }
    } catch (e) {
      throw Exception('Error validando asistencia: $e');
    }
  }

  /// Registra una asistencia manualmente
  Future<void> registerManualAttendance({
    required String employeeId,
    required String supervisorId,
    required DateTime workDate,
    required DateTime checkIn,
    DateTime? checkOut,
    required String recordType,
    String? notes,
    String? evidenceUrl,
    bool isLate = false,
    Map<String, dynamic>? location,
  }) async {
    try {
      final response = await _supabase.rpc(
        'register_manual_attendance',
        params: {
          'p_employee_id': employeeId,
          'p_supervisor_id': supervisorId,
          'p_work_date': workDate.toIso8601String().split('T')[0],
          'p_check_in': checkIn.toUtc().toIso8601String(),
          // 'p_check_out': checkOut?.toIso8601String(), // Eliminado
          'p_record_type': recordType,
          'p_notes': notes,
          'p_evidence_url': evidenceUrl,
          'p_is_late': isLate,
          'p_location': location,
        },
      );

      if (response['success'] == false) {
        throw Exception(response['message']);
      }
    } catch (e) {
      throw Exception('Error registrando asistencia manual: $e');
    }
  }

  /// Obtiene asistencias pendientes de validación
  Future<List<Map<String, dynamic>>> getPendingValidations(
    String supervisorId,
  ) async {
    try {
      final response = await _supabase.rpc(
        'get_pending_validations',
        params: {'p_supervisor_id': supervisorId, 'p_days_back': 7},
      );

      if (response == null) {
        return [];
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Error cargando validaciones pendientes: $e');
    }
  }
}

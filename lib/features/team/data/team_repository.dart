import 'dart:io' as java_io;
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
    String? subcategory, // NUEVO
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
          'p_record_type': recordType,
          'p_subcategory': subcategory, // Enviamos subcategoría
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

  /// Crea una solicitud de vacaciones
  Future<void> createVacationRequest({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
    required int totalDays,
    String? notes,
  }) async {
    try {
      await _supabase.from('vacation_requests').insert({
        'employee_id': employeeId,
        'start_date': startDate.toIso8601String().split('T')[0],
        'end_date': endDate.toIso8601String().split('T')[0],
        'total_days': totalDays,
        'notes': notes,
        'status': 'PENDIENTE',
      });
    } catch (e) {
      throw Exception('Error creando solicitud de vacaciones: $e');
    }
  }

  /// Obtiene solicitudes de vacaciones (para supervisor)
  Future<List<Map<String, dynamic>>> getVacationRequests() async {
    try {
      // Esto requeriría una vista o join si queremos nombre del empleado,
      // o usar un RPC. Por ahora hacemos select simple asumiendo RLS.
      final response = await _supabase
          .from('vacation_requests')
          .select('*, employees:employee_id(full_name, position)')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Error obteniendo solicitudes: $e');
    }
  }

  /// Obtiene los tipos de motivos configurados
  Future<List<Map<String, dynamic>>> getAbsenceReasons() async {
    try {
      // print('Cargando motivos desde DB...');
      final response = await _supabase
          .from('absence_reasons')
          .select()
          .eq('is_active', true)
          .order('name');

      // print('Motivos cargados: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // print('ERROR CRÍTICO cargando motivos: $e');
      // Fallback de emergencia para que no salga vacío
      return [
        {'name': 'ENFERMEDAD COMUN', 'requires_evidence': true},
        {'name': 'MOTIVOS DE SALUD', 'requires_evidence': true},
        {'name': 'MOTIVOS FAMILIARES', 'requires_evidence': false},
        {'name': 'PERMISO', 'requires_evidence': false},
        {'name': 'VACACIONES', 'requires_evidence': false},
      ];
    }
  }

  /// Sube un archivo de evidencia
  Future<String> uploadEvidence(String filePath, String fileName) async {
    try {
      // Usar storage_service.dart idealmente, pero aquí acceso directo para rapidez
      // Asumiendo que existe bucket 'evidence'
      final file = java_io.File(filePath); // Necesitaremos importar dart:io
      final path = 'evidence/$fileName';

      await _supabase.storage
          .from('evidence')
          .upload(path, file, fileOptions: const FileOptions(upsert: true));

      return _supabase.storage.from('evidence').getPublicUrl(path);
    } catch (e) {
      throw Exception('Error subiendo evidencia: $e');
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

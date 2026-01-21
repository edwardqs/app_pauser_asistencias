import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(Supabase.instance.client);
});

class AttendanceRepository {
  final SupabaseClient _supabase;

  AttendanceRepository(this._supabase);

  Future<Map<String, dynamic>?> getTodayAttendance(String employeeId) async {
    // CAMBIO: Obtenemos el ÚLTIMO registro de asistencia, sin filtrar por fecha estricta en la query.
    // La validación de si es "de hoy" se hará en la capa de lógica/UI.
    // Esto previene problemas de zona horaria donde la app cree que es hoy pero la DB lo guardó diferente, o viceversa.

    final response = await _supabase
        .from('attendance')
        .select()
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return response;
  }

  Future<List<Map<String, dynamic>>> getAttendanceHistory(
    String employeeId,
  ) async {
    final response = await _supabase
        .from('attendance')
        .select()
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false)
        .limit(30);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> checkIn({
    required String employeeId,
    required double lat,
    required double lng,
    String? lateReason,
    File? evidenceFile,
  }) async {
    String? evidenceUrl;

    // 1. Upload evidence if exists
    if (evidenceFile != null) {
      try {
        final fileExt = evidenceFile.path.split('.').last;
        final fileName =
            'evidence/$employeeId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        await _supabase.storage
            .from('attendance_evidence')
            .upload(fileName, evidenceFile);

        evidenceUrl = _supabase.storage
            .from('attendance_evidence')
            .getPublicUrl(fileName);
      } catch (e) {
        throw Exception('Error subiendo evidencia: $e');
      }
    }

    // 2. Call RPC to register attendance with all data
    final response = await _supabase.rpc(
      'register_attendance',
      params: {
        'p_employee_id': employeeId,
        'p_lat': lat,
        'p_lng': lng,
        'p_type': 'IN',
        'p_notes': lateReason,
        'p_evidence_url': evidenceUrl,
      },
    );

    if (response['success'] == false) {
      throw Exception(response['message']);
    }
  }

  Future<void> reportAbsence({
    required String employeeId,
    required String reason,
    File? evidenceFile,
  }) async {
    String? evidenceUrl;

    // 1. Upload evidence if exists
    if (evidenceFile != null) {
      try {
        final fileExt = evidenceFile.path.split('.').last;
        final fileName =
            'evidence/$employeeId/absence_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        await _supabase.storage
            .from('attendance_evidence')
            .upload(fileName, evidenceFile);

        evidenceUrl = _supabase.storage
            .from('attendance_evidence')
            .getPublicUrl(fileName);
      } catch (e) {
        throw Exception('Error subiendo evidencia: $e');
      }
    }

    // 2. Call RPC to register absence
    // We send dummy lat/lng because the RPC expects them, but for absence they might be irrelevant or 0.0
    final response = await _supabase.rpc(
      'register_attendance',
      params: {
        'p_employee_id': employeeId,
        'p_lat': 0.0,
        'p_lng': 0.0,
        'p_type': 'ABSENCE',
        'p_notes': reason,
        'p_evidence_url': evidenceUrl,
      },
    );

    if (response['success'] == false) {
      throw Exception(response['message']);
    }
  }

  Future<void> checkOut({
    required String employeeId,
    required double lat,
    required double lng,
  }) async {
    await _supabase.rpc(
      'register_attendance',
      params: {
        'p_employee_id': employeeId,
        'p_lat': lat,
        'p_lng': lng,
        'p_type': 'OUT',
      },
    );
  }
}

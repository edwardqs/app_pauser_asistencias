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
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final endOfDay = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
    ).toIso8601String();

    final response = await _supabase
        .from('attendance')
        .select()
        .eq('employee_id', employeeId)
        .gte('created_at', startOfDay)
        .lte('created_at', endOfDay)
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
    // 1. Call RPC to register attendance
    await _supabase.rpc(
      'register_attendance',
      params: {
        'p_employee_id': employeeId,
        'p_lat': lat,
        'p_lng': lng,
        'p_type': 'IN',
      },
    );

    // 2. If there is extra data (reason/evidence), update the record
    if (lateReason != null || evidenceFile != null) {
      try {
        // Find the record we just created
        final now = DateTime.now();
        final startOfDay = DateTime(
          now.year,
          now.month,
          now.day,
        ).toIso8601String();

        final record = await _supabase
            .from('attendance')
            .select('id')
            .eq('employee_id', employeeId)
            .gte('created_at', startOfDay)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (record != null) {
          final String recordId = record['id'];
          final Map<String, dynamic> updates = {};

          if (lateReason != null) {
            updates['notes'] = lateReason; // Appending to notes
          }

          if (evidenceFile != null) {
            final fileExt = evidenceFile.path.split('.').last;
            final fileName =
                'evidence/$employeeId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';
            await _supabase.storage
                .from('attendance_evidence')
                .upload(fileName, evidenceFile);
            final evidenceUrl = _supabase.storage
                .from('attendance_evidence')
                .getPublicUrl(fileName);
            updates['evidence_url'] =
                evidenceUrl; // Assuming this column exists or we add it to notes
            // If evidence_url column doesn't exist, we might fail.
            // Safer to put it in a JSON column or notes if we aren't sure.
            // But let's assume 'evidence_url' for now, or 'notes'
            if (updates['notes'] != null) {
              updates['notes'] = '${updates['notes']}\nEvidence: $evidenceUrl';
            } else {
              updates['notes'] = 'Evidence: $evidenceUrl';
            }
          }

          if (updates.isNotEmpty) {
            await _supabase
                .from('attendance')
                .update(updates)
                .eq('id', recordId);
          }
        }
      } catch (e) {
        // print('Error updating late reason/evidence: $e');
        // Don't fail the whole check-in if just updating metadata fails
      }
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

  Future<void> reportAbsence({
    required String employeeId,
    required String reason,
    File? evidenceFile,
  }) async {
    String? evidenceUrl;
    if (evidenceFile != null) {
      final fileExt = evidenceFile.path.split('.').last;
      final fileName =
          'evidence/$employeeId/absence_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      await _supabase.storage
          .from('attendance_evidence')
          .upload(fileName, evidenceFile);
      evidenceUrl = _supabase.storage
          .from('attendance_evidence')
          .getPublicUrl(fileName);
    }

    await _supabase.from('attendance').insert({
      'employee_id': employeeId,
      'record_type': 'INASISTENCIA',
      'notes': reason + (evidenceUrl != null ? '\nEvidence: $evidenceUrl' : ''),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Nuevo método para que los jefes vean a su equipo
  Future<List<Map<String, dynamic>>> getMyTeam(String supervisorId) async {
    // Esta lógica asume que hay una relación o tabla que vincula supervisor con empleados.
    // Como no tenemos el esquema completo, asumiremos una consulta basada en 'reports_to' o similar,
    // o filtrando por la misma sede/unidad si es una regla de negocio simple.
    //
    // Opción A: Usar RPC 'get_my_team' si existe (Recomendado para lógica compleja)
    // Opción B: Consultar tabla 'employees' filtrando donde supervisor_id = supervisorId

    try {
      // Intentamos primero por columna supervisor_id
      final response = await _supabase
          .from('employees')
          .select()
          .eq('supervisor_id', supervisorId);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // Si falla, retornamos lista vacía para no romper la UI
      return [];
    }
  }
}

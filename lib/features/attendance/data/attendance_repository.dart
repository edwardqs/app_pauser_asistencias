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
    String employeeId, {
    int page = 0,
    int pageSize = 20,
    String filter = 'all', // 'all', 'on_time', 'late', 'absent'
  }) async {
    final start = page * pageSize;
    final end = start + pageSize - 1;

    // IMPORTANTE: Definir 'query' explícitamente como PostgrestFilterBuilder
    // para poder encadenar filtros (eq, neq, not, inFilter) ANTES de transformaciones (order, range).
    // El error anterior ocurría porque 'order' devuelve un PostgrestTransformBuilder que ya no acepta filtros WHERE.

    var query = _supabase
        .from('attendance')
        .select() // Esto devuelve PostgrestFilterBuilder
        .eq('employee_id', employeeId);

    // Aplicar filtros ANTES de ordenar/paginar
    if (filter == 'on_time') {
      // Puntuales: tienen check_in, no son tarde, y no son ausencias
      query = query
          .not('check_in', 'is', null)
          .eq('is_late', false)
          .neq('record_type', 'AUSENCIA')
          .neq('record_type', 'INASISTENCIA');
    } else if (filter == 'late') {
      // Tardanzas: is_late = true
      query = query.eq('is_late', true);
    } else if (filter == 'absent') {
      // Ausencias: record_type es AUSENCIA o INASISTENCIA
      query = query.inFilter('record_type', ['AUSENCIA', 'INASISTENCIA']);
    }

    // Finalmente aplicamos orden y rango
    final response = await query
        .order('created_at', ascending: false)
        .range(start, end);

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
    required double lat,
    required double lng,
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
    final response = await _supabase.rpc(
      'register_attendance',
      params: {
        'p_employee_id': employeeId,
        'p_lat': lat,
        'p_lng': lng,
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

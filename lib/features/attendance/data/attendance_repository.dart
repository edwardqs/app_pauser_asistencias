import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(Supabase.instance.client);
});

class AttendanceRepository {
  final SupabaseClient _supabase;

  AttendanceRepository(this._supabase);

  // Método actualizado para usar el nuevo RPC que devuelve estado completo (Asistencia + Vacaciones)
  Future<Map<String, dynamic>> getEmployeeDayStatus(String employeeId) async {
    Map<String, dynamic> statusData;
    
    try {
      final response = await _supabase.rpc(
        'get_employee_day_status',
        params: {'p_employee_id': employeeId},
      );
      statusData = Map<String, dynamic>.from(response);
    } catch (e) {
      print('Error en getEmployeeDayStatus RPC: $e');
      // Inicializar con valores por defecto si falla el RPC
      statusData = {
        'date': DateTime.now().toIso8601String(),
        'attendance': null,
        'vacation': null,
        'is_on_vacation': false
      };
    }

    // FALLBACK HÍBRIDO ROBUSTO:
    // Si el RPC no devolvió asistencia (null), intentamos buscarla directamente 
    // usando la fecha local del cliente. Esto corrige desfases de zona horaria o fallos del RPC.
    if (statusData['attendance'] == null) {
      try {
        final localAttendance = await getTodayAttendance(employeeId);
        if (localAttendance != null) {
          print('Attendance found locally (RPC missed it): ${localAttendance['id']}');
          statusData['attendance'] = localAttendance;
        }
      } catch (e) {
        print('Error en fallback local: $e');
      }
    }

    return statusData;
  }

  Future<Map<String, dynamic>?> getTodayAttendance(String employeeId) async {
    // CAMBIO: Obtenemos el registro que coincida explícitamente con la fecha actual de Perú
    // Esto asegura que la app móvil sepa si "hoy" ya marcó o no, independientemente de la hora UTC.
    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    final response = await _supabase
        .from('attendance')
        .select()
        .eq('employee_id', employeeId)
        .eq('work_date', todayStr) // Filtro explícito por fecha
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
            'evidence/$employeeId/checkin_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        await _supabase.storage.from('evidence').upload(fileName, evidenceFile);

        evidenceUrl = _supabase.storage.from('evidence').getPublicUrl(fileName);
      } catch (e) {
        print('Error uploading evidence: $e');
        // Continue without evidence or throw? Let's continue.
      }
    }

    // 2. Call RPC to register attendance
    // We pass 'IN' as type.
    // If lateReason is provided, we pass it as notes.

    final response = await _supabase.rpc(
      'register_attendance',
      params: {
        'p_employee_id': employeeId,
        'p_lat': lat,
        'p_lng': lng,
        'p_type': 'IN',
        if (lateReason != null) 'p_notes': lateReason,
        if (evidenceUrl != null) 'p_evidence_url': evidenceUrl,
      },
    );

    if (response is Map && response['success'] == false) {
      throw Exception(response['message']);
    }
  }

  Future<void> reportAbsence({
    required String employeeId,
    required String reason,
    required String recordType,
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
        // Fallback to 'evidence' bucket
        try {
          final fileExt = evidenceFile.path.split('.').last;
          final fileName =
              'evidence/$employeeId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';
          await _supabase.storage
              .from('evidence')
              .upload(fileName, evidenceFile);
          evidenceUrl = _supabase.storage
              .from('evidence')
              .getPublicUrl(fileName);
        } catch (e2) {
          throw Exception('Error subiendo evidencia: $e');
        }
      }
    }

    // 2. Call RPC to register absence
    final response = await _supabase.rpc(
      'register_attendance',
      params: {
        'p_employee_id': employeeId,
        'p_lat': lat,
        'p_lng': lng,
        'p_type': recordType,
        'p_notes': reason,
        'p_evidence_url': evidenceUrl,
      },
    );

    if (response is Map && response['success'] == false) {
      throw Exception(response['message']);
    }
  }

  Future<List<Map<String, dynamic>>> getAbsenceReasons() async {
    try {
      final response = await _supabase
          .from('absence_reasons')
          .select()
          .eq('is_active', true)
          .order('name');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // Fallback
      return [
        {'name': 'ENFERMEDAD COMUN', 'requires_evidence': true},
        {'name': 'MOTIVOS DE SALUD', 'requires_evidence': true},
        {'name': 'MOTIVOS FAMILIARES', 'requires_evidence': false},
        {'name': 'PERMISO', 'requires_evidence': false},
        {'name': 'VACACIONES', 'requires_evidence': false},
      ];
    }
  }

  // NUEVO: Registrar falta injustificada automática (Triggered by Client)
  Future<void> registerUnjustifiedAbsence(String employeeId) async {
    try {
      // Usamos RPC segura en lugar de insert directo para evitar problemas de RLS
      await _supabase.rpc(
        'register_auto_absence',
        params: {'p_employee_id': employeeId},
      );
    } catch (e) {
      // Ignorar errores, es un proceso background best-effort
      print('Error auto-registering absence: $e');
    }
  }
}

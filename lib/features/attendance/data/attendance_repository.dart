import 'dart:io';
import 'package:flutter/foundation.dart';
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
      if (kDebugMode) print('Error en getEmployeeDayStatus RPC: $e');
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
          if (kDebugMode) print('Attendance found locally (RPC missed it): ${localAttendance['id']}');
          statusData['attendance'] = localAttendance;
        }
      } catch (e) {
        if (kDebugMode) print('Error en fallback local: $e');
      }
    }

    return statusData;
  }

  Future<Map<String, dynamic>?> getTodayAttendance(String employeeId) async {
    // Usa RPC SECURITY DEFINER para bypassear RLS (app no usa Supabase Auth)
    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    final response = await _supabase.rpc(
      'get_employee_attendance_history',
      params: {
        'p_employee_id': employeeId,
        'p_page': 0,
        'p_page_size': 1,
        'p_filter': 'all',
      },
    );

    final list = response as List?;
    if (list == null || list.isEmpty) return null;

    final record = Map<String, dynamic>.from(list.first as Map);
    // Solo retornar si el registro más reciente es de hoy
    if (record['work_date'].toString().startsWith(todayStr)) {
      return record;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getAttendanceHistory(
    String employeeId, {
    int page = 0,
    int pageSize = 20,
    String filter = 'all', // 'all', 'on_time', 'late', 'absent', 'vacation'
  }) async {
    // Usa RPC SECURITY DEFINER para bypassear RLS (app no usa Supabase Auth)
    final response = await _supabase.rpc(
      'get_employee_attendance_history',
      params: {
        'p_employee_id': employeeId,
        'p_page': page,
        'p_page_size': pageSize,
        'p_filter': filter,
      },
    );
    return List<Map<String, dynamic>>.from(response as List);
  }

Future<void> checkIn({
    required String employeeId,
    required double lat,
    required double lng,
    String? lateReason,
    File? evidenceFile,
    String? shift,
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
        if (kDebugMode) print('Error uploading evidence: $e');
      }
    }

    // 2. Call RPC to register attendance with shift parameter
    final response = await _supabase.rpc(
      'register_attendance',
      params: {
        'p_employee_id': employeeId,
        'p_lat': lat,
        'p_lng': lng,
        'p_type': 'IN',
        if (lateReason != null) 'p_notes': lateReason,
        if (evidenceUrl != null) 'p_evidence_url': evidenceUrl,
        if (shift != null) 'p_shift': shift,
      },
    );

    if (response is Map && response['success'] == false) {
      throw Exception(response['message']);
    }
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

  static const _dowNames = {
    1: 'LUNES', 2: 'MARTES', 3: 'MIÉRCOLES',
    4: 'JUEVES', 5: 'VIERNES', 6: 'SÁBADO', 7: 'DOMINGO',
  };

  String _nextWorkDayName(int currentDow, List workDays) {
    final days = workDays.map((d) => d as int).toList()..sort();
    for (final d in days) {
      if (d > currentDow) return _dowNames[d] ?? '';
    }
    return _dowNames[days.first] ?? '';
  }

  /// Obtiene todos los horarios activos asignados al empleado para hoy.
  /// Retorna:
  ///   []                             → sin asignaciones
  ///   [{'is_work_day': false, ...}]  → tiene horarios pero hoy no es día laboral (retorna info del siguiente)
  ///   [schedule1, schedule2, ...]    → uno o más horarios válidos para hoy
  Future<List<Map<String, dynamic>>> getActiveSchedules(String employeeId) async {
    try {
      final today = DateTime.now();
      final todayStr =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      final isodow = today.weekday;

      final response = await _supabase
          .from('employee_schedule_assignments')
          .select('valid_from, valid_to, schedule:schedule_id(id, name, check_in_time, check_out_time, bonus_start, bonus_end, tolerance_minutes, work_days, schedule_type, shift)')
          .eq('employee_id', employeeId)
          .lte('valid_from', todayStr)
          .or('valid_to.is.null,valid_to.gte.$todayStr')
          .order('valid_from', ascending: false);

      if ((response as List).isEmpty) return [];

      // Excluir asignaciones REGULAR cerradas hoy (valid_to = hoy)
      final List<Map<String, dynamic>> all = List<Map<String, dynamic>>.from(response)
          .where((a) {
            final validTo = a['valid_to'] as String?;
            if (validTo == null) return true;
            final scheduleType = (a['schedule'] as Map<String, dynamic>?)?['schedule_type'] as String? ?? 'REGULAR';
            if (scheduleType != 'REGULAR') return true;
            return false;
          })
          .toList();

      final matching = all.where((a) {
        final s = a['schedule'] as Map<String, dynamic>?;
        if (s == null) return false;
        final workDays = s['work_days'] as List?;
        if (workDays == null || workDays.isEmpty) return true;
        return workDays.contains(isodow);
      }).toList();

      // Ordenar: especiales primero, luego por shift
      matching.sort((a, b) {
        final aType = (a['schedule']?['schedule_type'] ?? 'REGULAR') as String;
        final bType = (b['schedule']?['schedule_type'] ?? 'REGULAR') as String;
        if (aType != 'REGULAR' && bType == 'REGULAR') return -1;
        if (aType == 'REGULAR' && bType != 'REGULAR') return 1;
        return 0;
      });

      // Hoy no está en los días laborales → retornar con is_work_day: false
      if (matching.isEmpty) {
        final anySchedule = all.isNotEmpty ? all.first['schedule'] as Map<String, dynamic>? : null;
        final workDays = anySchedule?['work_days'] as List? ?? [];
        final todayName = _dowNames[isodow] ?? '';
        final nextDay = workDays.isNotEmpty
            ? _nextWorkDayName(isodow, workDays)
            : '';
        return [{
          'is_work_day': false,
          'today_name': todayName,
          'next_work_day': nextDay,
          'schedule_name': anySchedule?['name'] ?? '',
        }];
      }

      return matching.map((a) {
        final schedule = Map<String, dynamic>.from(
            a['schedule'] as Map<String, dynamic>);
        schedule['is_work_day'] = true;
        return schedule;
      }).toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching active schedules: $e');
      return [];
    }
  }

  /// Obtiene el horario activo (retorno de compatibilidad - solo primer horario)
  @Deprecated('Usar getActiveSchedules para soportar múltiples turnos')
  Future<Map<String, dynamic>?> getActiveSchedule(String employeeId) async {
    final schedules = await getActiveSchedules(employeeId);
    if (schedules.isEmpty) return null;
    return schedules.firstWhere(
      (s) => s['is_work_day'] == true,
      orElse: () => schedules.first,
    );
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
      if (kDebugMode) print('Error auto-registering absence: $e');
    }
  }
}

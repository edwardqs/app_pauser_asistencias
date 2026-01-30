import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

final requestsRepositoryProvider = Provider<RequestsRepository>((ref) {
  return RequestsRepository(Supabase.instance.client);
});

class RequestsRepository {
  final SupabaseClient _supabase;

  RequestsRepository(this._supabase);

  /// Obtiene las solicitudes del empleado
  Future<List<Map<String, dynamic>>> getMyRequests(String employeeId) async {
    try {
      final response = await _supabase
          .from('vacation_requests')
          .select()
          .eq('employee_id', employeeId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Error al cargar solicitudes: $e');
    }
  }

  /// Escucha las solicitudes del empleado en tiempo real
  Stream<List<Map<String, dynamic>>> watchMyRequests(String employeeId) {
    return _supabase
        .from('vacation_requests')
        .stream(primaryKey: ['id'])
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false)
        .map((list) => List<Map<String, dynamic>>.from(list));
  }

  /// Crea una nueva solicitud (Vacaciones, Permisos, Licencias)
  Future<void> createRequest({
    required String employeeId,
    required String requestType, // 'VACACIONES', 'PERMISO', 'SALUD', etc.
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    File? evidenceFile,
  }) async {
    try {
      // 0. Validar superposición antes de cualquier cosa
      final validation = await _supabase.rpc(
        'check_vacation_overlap',
        params: {
          'p_employee_id': employeeId,
          'p_start_date': startDate.toIso8601String().split('T')[0],
          'p_end_date': endDate.toIso8601String().split('T')[0],
        },
      );

      if (validation != null && validation['allowed'] == false) {
        throw Exception(
          validation['reason'] ??
              'No se permite registrar la solicitud en estas fechas.',
        );
      }

      String? evidenceUrl;

      // 1. Subir evidencia si existe
      if (evidenceFile != null) {
        final fileExt = evidenceFile.path.split('.').last;
        final fileName =
            'requests/$employeeId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        // Intentar subir a bucket 'evidence'
        await _supabase.storage.from('evidence').upload(fileName, evidenceFile);

        evidenceUrl = _supabase.storage.from('evidence').getPublicUrl(fileName);
      }

      // 2. Calcular días (simple por ahora, luego se puede refinar con lógica de negocio)
      final totalDays = endDate.difference(startDate).inDays + 1;

      // 3. Guardar en BD
      final data = {
        'employee_id': employeeId,
        'start_date': startDate.toIso8601String().split('T')[0],
        'end_date': endDate.toIso8601String().split('T')[0],
        'total_days': totalDays,
        'notes': reason,
        'request_type': requestType,
        'status': 'PENDIENTE',
      };

      if (evidenceUrl != null) {
        data['evidence_url'] = evidenceUrl;
      }

      await _supabase.from('vacation_requests').insert(data);
    } catch (e) {
      // Si es una excepción nuestra, la relanzamos tal cual
      if (e.toString().contains('No se permite')) rethrow;
      throw Exception('Error al crear solicitud: $e');
    }
  }

  /// Cancelar una solicitud (Solo si está PENDIENTE)
  Future<void> cancelRequest(String requestId) async {
    try {
      // 1. Verificar estado actual
      final request = await _supabase
          .from('vacation_requests')
          .select('status')
          .eq('id', requestId)
          .single();

      if (request['status'] != 'PENDIENTE') {
        throw Exception('Solo se pueden cancelar solicitudes pendientes.');
      }

      // 2. Actualizar a CANCELADO
      await _supabase
          .from('vacation_requests')
          .update({'status': 'CANCELADO'})
          .eq('id', requestId);
    } catch (e) {
      throw Exception('Error al cancelar solicitud: $e');
    }
  }

  /// Obtener notificaciones del empleado
  Stream<List<Map<String, dynamic>>> watchNotifications(String employeeId) {
    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false)
        .limit(50) // Limitar para rendimiento
        .map((list) => List<Map<String, dynamic>>.from(list));
  }

  /// Marcar notificaciones como leídas
  Future<void> markNotificationsAsRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _supabase.rpc(
      'mark_notifications_read',
      params: {'p_notification_ids': ids},
    );
  }

  /// Obtener conteo de no leídas (para el badge)
  Future<int> getUnreadCount(String employeeId) async {
    final count = await _supabase
        .from('notifications')
        .count(CountOption.exact)
        .eq('employee_id', employeeId)
        .eq('is_read', false);
    return count;
  }

  /// Obtener preferencias de notificación
  Future<Map<String, dynamic>> getNotificationPreferences(
    String employeeId,
  ) async {
    final response = await _supabase
        .from('notification_preferences')
        .select()
        .eq('employee_id', employeeId)
        .maybeSingle();

    // Si no existe, devolver valores por defecto (todo true)
    if (response == null) {
      return {'push_enabled': true, 'email_enabled': true};
    }
    return response;
  }

  /// Actualizar preferencias de notificación
  Future<void> updateNotificationPreferences(
    String employeeId,
    bool push,
    bool email,
  ) async {
    await _supabase.from('notification_preferences').upsert({
      'employee_id': employeeId,
      'push_enabled': push,
      'email_enabled': email,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}

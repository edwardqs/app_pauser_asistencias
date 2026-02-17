import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:typed_data';

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

  /// Crea una nueva solicitud y retorna su ID
  Future<String> createRequest({
    required String employeeId,
    required String requestType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    File? evidenceFile,
  }) async {
    try {
      // 0. Validar superposición
      final validation = await _supabase.rpc(
        'check_vacation_overlap',
        params: {
          'p_employee_id': employeeId,
          'p_start_date': startDate.toIso8601String().split('T')[0],
          'p_end_date': endDate.toIso8601String().split('T')[0],
          'p_exclude_request_id': null,
        },
      );

      if (validation != null && validation['allowed'] == false) {
        throw Exception(
          validation['reason'] ??
              'No se permite registrar la solicitud en estas fechas.',
        );
      }

      String? evidenceUrl;

      // 1. Subir evidencia inicial si existe (ej. certificado médico)
      if (evidenceFile != null) {
        final fileExt = evidenceFile.path.split('.').last;
        final fileName =
            'requests/$employeeId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        // Usamos bucket 'evidence' o el que tengas configurado
        await _supabase.storage.from('evidence').upload(fileName, evidenceFile);
        evidenceUrl = _supabase.storage.from('evidence').getPublicUrl(fileName);
      }

      final totalDays = endDate.difference(startDate).inDays + 1;

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

      final res = await _supabase
          .from('vacation_requests')
          .insert(data)
          .select()
          .single();

      return res['id'] as String;
    } catch (e) {
      if (e.toString().contains('No se permite') ||
          e.toString().contains('superponen'))
        rethrow;
      if (e.toString().contains('P0001')) {
        final msg = e.toString().split('message:').last.trim();
        throw Exception(msg);
      }
      throw Exception('Error al crear solicitud: $e');
    }
  }

  /// Cancelar una solicitud (Solo si está PENDIENTE)
  Future<void> cancelRequest(String requestId) async {
    try {
      final request = await _supabase
          .from('vacation_requests')
          .select('status')
          .eq('id', requestId)
          .single();

      if (request['status'] != 'PENDIENTE') {
        throw Exception('Solo se pueden cancelar solicitudes pendientes.');
      }

      await _supabase
          .from('vacation_requests')
          .update({'status': 'CANCELADO'})
          .eq('id', requestId);
    } catch (e) {
      throw Exception('Error al cancelar solicitud: $e');
    }
  }

  /// --- NUEVO: SUBIR DOCUMENTO GENERADO (Papeleta) ---
  Future<String> uploadGeneratedPdf({
    required String requestId,
    required String employeeDni,
    required Uint8List pdfBytes,
  }) async {
    try {
      final fileName =
          'papeletas/${employeeDni}_${requestId}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      // 1. Subir archivo
      await _supabase.storage
          .from('papeletas')
          .uploadBinary(
            fileName,
            pdfBytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          );

      // 2. Obtener URL Pública
      final publicUrl = _supabase.storage
          .from('papeletas')
          .getPublicUrl(fileName);

      // 3. Actualizar la solicitud
      await _supabase
          .from('vacation_requests')
          .update({'pdf_url': publicUrl})
          .eq('id', requestId);

      return publicUrl;
    } catch (e) {
      throw Exception('Error al subir PDF generado: $e');
    }
  }

  /// --- NUEVO: SUBIR DOCUMENTO FIRMADO ---
  Future<void> uploadSignedDocument({
    required String requestId,
    required String employeeId,
    required File file,
  }) async {
    try {
      final fileExt = file.path.split('.').last;
      // Guardamos en carpeta 'signed' dentro del bucket 'papeletas'
      final fileName = 'signed/${employeeId}_${requestId}_firmado.$fileExt';

      // 1. Subir archivo (con upsert true para reemplazar si se equivocó)
      await _supabase.storage
          .from('papeletas')
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

      // 2. Obtener URL Pública
      final signedUrl = _supabase.storage
          .from('papeletas')
          .getPublicUrl(fileName);

      // 3. Actualizar la solicitud con la URL del firmado
      await _supabase
          .from('vacation_requests')
          .update({
            'signed_file_url': signedUrl,
            'signed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', requestId);
    } catch (e) {
      throw Exception('Error al subir documento: $e');
    }
  }

  // ... (Resto de métodos de notificaciones igual) ...
  Stream<List<Map<String, dynamic>>> watchNotifications(String employeeId) {
    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false)
        .limit(50)
        .map((list) => List<Map<String, dynamic>>.from(list));
  }

  Future<void> markNotificationsAsRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _supabase.rpc(
      'mark_notifications_read',
      params: {'p_notification_ids': ids},
    );
  }

  Future<int> getUnreadCount(String employeeId) async {
    final count = await _supabase
        .from('notifications')
        .count(CountOption.exact)
        .eq('employee_id', employeeId)
        .eq('is_read', false);
    return count;
  }
}

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
      throw Exception('Error al crear solicitud: $e');
    }
  }
}

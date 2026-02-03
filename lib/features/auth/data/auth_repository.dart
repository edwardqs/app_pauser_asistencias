import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(Supabase.instance.client);
});

class AuthRepository {
  final SupabaseClient _supabase;

  AuthRepository(this._supabase);

  /// Realiza el login usando la función RPC 'mobile_login'
  Future<Map<String, dynamic>> loginRPC({
    required String dni,
    required String password,
  }) async {
    try {
      final response = await _supabase.rpc(
        'mobile_login',
        params: {'dni_input': dni, 'password_input': password},
      );

      // La respuesta es un Map<String, dynamic> o similar
      if (response is Map<String, dynamic>) {
        return response;
      } else {
        throw Exception('Formato de respuesta inválido del servidor');
      }
    } catch (e) {
      throw Exception('Error de conexión o credenciales: $e');
    }
  }

  Future<void> signOut() async {
    // Si usáramos Auth de Supabase, sería: await _supabase.auth.signOut();
    // Como usamos RPC y shared preferences, la limpieza se hace en StorageService/Controller
  }

  /// Cambia la contraseña del empleado
  Future<void> changePassword({
    required String employeeId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _supabase.rpc(
        'change_employee_password',
        params: {
          'p_employee_id': employeeId,
          'p_current_password': currentPassword,
          'p_new_password': newPassword,
        },
      );

      if (response['success'] == false) {
        throw Exception(response['message']);
      }
    } catch (e) {
      throw Exception('Error cambiando contraseña: $e');
    }
  }

  /// Restablece la contraseña verificando identidad (DNI + Fecha Nacimiento)
  Future<void> resetPasswordWithIdentity({
    required String dni,
    required DateTime birthDate,
    required String newPassword,
  }) async {
    try {
      // Formato YYYY-MM-DD para Supabase date
      final birthDateStr =
          "${birthDate.year}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}";

      final response = await _supabase.rpc(
        'reset_password_identity',
        params: {
          'p_dni': dni,
          'p_birth_date': birthDateStr,
          'p_new_password': newPassword,
        },
      );

      if (response['success'] == false) {
        throw Exception(response['message']);
      }
    } catch (e) {
      throw Exception('Error al restablecer: $e');
    }
  }
}

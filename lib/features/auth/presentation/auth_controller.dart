import 'dart:async';
import 'package:app_asistencias_pauser/core/services/auth_notifier.dart';
import 'package:app_asistencias_pauser/features/attendance/presentation/home_screen.dart';
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/auth/data/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    return null;
  }

  Future<bool> signIn({required String dni, required String password}) async {
    state = const AsyncValue.loading();
    try {
      final response = await ref
          .read(authRepositoryProvider)
          .loginRPC(dni: dni, password: password);

      final success = response['success'] == true;
      if (success) {
        final employeeType = response['employee_type'] as String?;
        final position = response['position'] as String?;
        final userRole = response['role'] as String?; // Nuevo campo de DB

        // Validación de Rol: Analista de Gente solo Web
        if (position?.toLowerCase().trim() == 'analista de gente' ||
            employeeType?.toLowerCase().trim() == 'analista de gente' ||
            userRole?.toLowerCase().trim() == 'analista_gente') {
          state = AsyncValue.error(
            'Este usuario solo tiene acceso a la plataforma Web',
            StackTrace.current,
          );
          return false;
        }

        final employeeId = response['employee_id'] as String;
        final fullName = response['full_name'] as String;
        final dni = response['dni'] as String;
        final sede = response['sede'] as String?;
        final businessUnit = response['business_unit'] as String?;
        final profilePicture = response['profile_picture_url'] as String?;

        // Save to Storage
        final storage = ref.read(storageServiceProvider);
        await storage.saveUserSession(
          employeeId: employeeId,
          fullName: fullName,
          dni: dni,
          sede: sede,
          businessUnit: businessUnit,
          // Guardamos 'role' en employeeType para compatibilidad o creamos nuevo campo
          // Usaremos 'role' de la DB como prioridad, si no existe usamos employee_type
          employeeType: userRole ?? employeeType,
          position: position,
          profilePicture: profilePicture,
        );

        // Notificar al AuthNotifier que el usuario se ha autenticado correctamente
        ref.read(authNotifierProvider.notifier).setAuthenticated(true);

        state = const AsyncValue.data(null);
        return true;
      } else {
        final msg = response['message'] ?? 'Error desconocido';
        state = AsyncValue.error(msg, StackTrace.current);
        return false;
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    final storage = ref.read(storageServiceProvider);

    // Invalidate all providers that might hold user-specific state
    // This is crucial to prevent "phantom" data when switching users
    ref.invalidate(
      employeeStatusProvider,
    ); // Actualizado para usar el nuevo provider
    // Add other providers here if necessary (e.g. teamAttendanceProvider)

    await storage.clearSession();
    state = const AsyncValue.data(null);
  }
}

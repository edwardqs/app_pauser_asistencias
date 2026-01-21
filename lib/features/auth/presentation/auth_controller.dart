import 'dart:async';
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
        final employeeId = response['employee_id'] as String;
        final fullName = response['full_name'] as String;
        final dni = response['dni'] as String;
        final sede = response['sede'] as String?;
        final businessUnit = response['business_unit'] as String?;
        final employeeType = response['employee_type'] as String?;
        final position = response['position'] as String?;
        final profilePicture = response['profile_picture_url'] as String?;

        // Save to Storage
        final storage = ref.read(storageServiceProvider);
        await storage.saveUserSession(
          employeeId: employeeId,
          fullName: fullName,
          dni: dni,
          sede: sede,
          businessUnit: businessUnit,
          employeeType: employeeType,
          position: position,
          profilePicture: profilePicture,
        );

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
    await storage.clearSession();
    state = const AsyncValue.data(null);
  }
}

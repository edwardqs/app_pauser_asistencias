import 'dart:io';
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/auth/data/profile_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final profileControllerProvider = AsyncNotifierProvider<ProfileController, void>(
  ProfileController.new,
);

class ProfileController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // nothing to init
  }

  Future<bool> updateProfilePicture(File imageFile) async {
    state = const AsyncValue.loading();
    try {
      final storage = ref.read(storageServiceProvider);
      final employeeId = storage.employeeId;
      
      if (employeeId == null) {
        throw Exception('No hay sesión activa');
      }

      final repository = ref.read(profileRepositoryProvider);
      final imageUrl = await repository.uploadProfilePicture(employeeId, imageFile);

      // Update local storage
      await storage.updateProfilePicture(imageUrl);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

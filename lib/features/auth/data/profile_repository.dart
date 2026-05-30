import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(Supabase.instance.client);
});

class ProfileRepository {
  final SupabaseClient _supabase;

  ProfileRepository(this._supabase);

  Future<String> uploadProfilePicture(
    String employeeId,
    Uint8List imageBytes,
    String extension,
  ) async {
    final fileName =
        '$employeeId/${DateTime.now().millisecondsSinceEpoch}.$extension';

    await _supabase.storage.from('avatars').uploadBinary(
          fileName,
          imageBytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final imageUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);

    await _supabase.rpc('update_employee_profile_picture', params: {
      'p_employee_id': employeeId,
      'p_image_url': imageUrl,
    });

    return imageUrl;
  }
}

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(Supabase.instance.client);
});

class ProfileRepository {
  final SupabaseClient _supabase;

  ProfileRepository(this._supabase);

  Future<String> uploadProfilePicture(String employeeId, File imageFile) async {
    final fileExt = imageFile.path.split('.').last;
    final fileName =
        'profiles/$employeeId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    // Upload file
    await _supabase.storage
        .from('profiles')
        .upload(
          fileName,
          imageFile,
          fileOptions: const FileOptions(upsert: true),
        );

    // Get public URL
    final imageUrl = _supabase.storage.from('profiles').getPublicUrl(fileName);

    // Update user profile in database
    await _supabase
        .from('employees')
        .update({'profile_picture': imageUrl})
        .eq('id', employeeId);

    return imageUrl;
  }
}

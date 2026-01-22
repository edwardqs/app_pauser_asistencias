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
    final fileName = '$employeeId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    
    // Upload image to 'avatars' bucket (as defined in SUPABASE_PROFILE_PICTURE.sql)
    await _supabase.storage.from('avatars').upload(
          fileName,
          imageFile,
          fileOptions: const FileOptions(upsert: true),
        );

    final imageUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
    
    // Update user profile in database using RPC
    // RPC name matches SUPABASE_UPDATE_PROFILE_RPC.sql
    await _supabase.rpc('update_employee_profile_picture', params: {
      'p_employee_id': employeeId,
      'p_image_url': imageUrl,
    });
    
    return imageUrl;
  }
}

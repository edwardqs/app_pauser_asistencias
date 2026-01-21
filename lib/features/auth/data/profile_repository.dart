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
    
    // Upload image to 'profiles' bucket
    await _supabase.storage.from('profiles').upload(
          fileName,
          imageFile,
          fileOptions: const FileOptions(upsert: true),
        );

    final imageUrl = _supabase.storage.from('profiles').getPublicUrl(fileName);
    
    // Update user profile in database using RPC
    // Assuming there is an RPC for this, or we can update the employees table directly if RLS allows
    // Based on file list SUPABASE_UPDATE_PROFILE_RPC.sql exists
    await _supabase.rpc('update_profile_picture', params: {
      'p_employee_id': employeeId,
      'p_image_url': imageUrl,
    });
    
    return imageUrl;
  }
}

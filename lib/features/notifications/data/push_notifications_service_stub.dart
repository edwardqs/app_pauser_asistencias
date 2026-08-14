import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stub para web: no hay FCM web configurado. No-op para que la web arranque
/// sin depender de Firebase.
class PushNotificationsService {
  final SupabaseClient _supabase;
  final StorageService _storage;

  PushNotificationsService({
    SupabaseClient? supabase,
    StorageService? storage,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _storage = storage ?? _uninitializedStorage();

  static StorageService _uninitializedStorage() {
    throw StateError('StorageService no fue inyectado');
  }

  Future<void> init() async {}

  Future<bool> requestPermission() async => false;

  Future<String?> getToken() async => null;

  Future<void> registerDevice() async {}

  void onMessageReceived(void Function(Object message) handler) {}

  void onMessageOpened(void Function(Object message) handler) {}
}

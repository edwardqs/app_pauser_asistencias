import 'dart:io';

import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    debugPrint('Mensaje FCM en segundo plano: ${message.messageId}');
  }
}

class PushNotificationsService {
  final FirebaseMessaging _messaging;
  final SupabaseClient _supabase;
  final StorageService _storage;

  PushNotificationsService({
    FirebaseMessaging? messaging,
    SupabaseClient? supabase,
    StorageService? storage,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _supabase = supabase ?? Supabase.instance.client,
        _storage = storage ?? _uninitializedStorage();

  static StorageService _uninitializedStorage() {
    throw StateError('StorageService no fue inyectado');
  }

  Future<void> init() async {
    if (kIsWeb) return;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      if (kDebugMode) debugPrint('Error pidiendo permiso FCM: $e');
      return false;
    }
  }

  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      if (kDebugMode) debugPrint('Error obteniendo token FCM: $e');
      return null;
    }
  }

  Future<void> registerDevice() async {
    if (kIsWeb) return;
    final employeeId = _storage.employeeId;
    if (employeeId == null) return;

    final granted = await requestPermission();
    if (!granted) return;

    final token = await getToken();
    if (token == null) return;

    try {
      await _supabase.rpc('upsert_push_device', params: {
        'p_token': token,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
        'p_app_version': _storage.appVersion,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error registrando token FCM: $e');
    }

    _messaging.onTokenRefresh.listen((newToken) async {
      try {
        await _supabase.rpc('upsert_push_device', params: {
          'p_token': newToken,
          'p_platform': Platform.isIOS ? 'ios' : 'android',
          'p_app_version': _storage.appVersion,
        });
      } catch (e) {
        if (kDebugMode) debugPrint('Error renovando token FCM: $e');
      }
    });
  }

  void onMessageReceived(void Function(RemoteMessage) handler) {
    FirebaseMessaging.onMessage.listen(handler);
  }

  void onMessageOpened(void Function(RemoteMessage) handler) {
    FirebaseMessaging.onMessageOpenedApp.listen(handler);
  }
}

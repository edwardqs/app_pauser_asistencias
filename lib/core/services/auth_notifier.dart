import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;

  const AuthState({this.isAuthenticated = false, this.isLoading = false});
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final storage = ref.watch(storageServiceProvider);
    
    // Escuchar cambios en la sesión de Supabase
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      
      if (event == AuthChangeEvent.signedOut || 
          event == AuthChangeEvent.userDeleted ||
          event == AuthChangeEvent.tokenRefreshed) { // Check token refresh failures internally handled by client but good to monitor
         // La lógica principal se basa en el storage local por ahora, 
         // pero podríamos reaccionar aquí si el token expira irremediablemente.
      }
    });

    return AuthState(isAuthenticated: storage.isAuthenticated);
  }

  Future<void> login(String email, String password) async {
    state = const AuthState(isAuthenticated: false, isLoading: true);
    // La lógica real de login está en LoginScreen/Repository, 
    // pero aquí actualizamos el estado global al finalizar.
    // Idealmente moveríamos la lógica de AuthRepository aquí o la coordinaríamos.
  }

  void setAuthenticated(bool value) {
    state = AuthState(isAuthenticated: value, isLoading: false);
  }

  Future<void> logout() async {
    state = const AuthState(isAuthenticated: true, isLoading: true);
    try {
      await Supabase.instance.client.auth.signOut();
      await ref.read(storageServiceProvider).clearSession();
      state = const AuthState(isAuthenticated: false, isLoading: false);
    } catch (e) {
      // Forzar salida local incluso si falla red
      await ref.read(storageServiceProvider).clearSession();
      state = const AuthState(isAuthenticated: false, isLoading: false);
    }
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
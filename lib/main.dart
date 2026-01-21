import 'package:app_asistencias_pauser/core/services/auth_notifier.dart';
import 'package:app_asistencias_pauser/core/constants/supabase_constants.dart';
import 'package:app_asistencias_pauser/core/presentation/main_layout.dart';
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/core/theme/app_theme.dart';
import 'package:app_asistencias_pauser/features/attendance/presentation/attendance_history_screen.dart';
import 'package:app_asistencias_pauser/features/attendance/presentation/home_screen.dart';
import 'package:app_asistencias_pauser/features/auth/presentation/login_screen.dart';
import 'package:app_asistencias_pauser/features/auth/presentation/profile_screen.dart';
import 'package:app_asistencias_pauser/features/team/presentation/manual_attendance_screen.dart';
import 'package:app_asistencias_pauser/features/team/presentation/team_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConstants.url,
    anonKey: SupabaseConstants.anonKey,
  );

  // Initialize Storage
  final storageService = await StorageService.init();

  runApp(
    ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storageService)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Escuchar el estado de autenticación para redirecciones
    final authState = ref.watch(authNotifierProvider);

    // Configurar GoRouter con refreshListenable para reaccionar a cambios
    // NOTA: Como usamos Riverpod, podemos reconstruir el router si cambia el authState
    // O usar un enfoque más estático si no queremos reconstruir todo el árbol.
    // Aquí simplificamos reconstruyendo el router, lo cual es aceptable para cambios de auth.
    final router = GoRouter(
      initialLocation: authState.isAuthenticated ? '/home' : '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) {
            return MainLayout(child: child);
          },
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
            GoRoute(
              path: '/history',
              builder: (context, state) => const AttendanceHistoryScreen(),
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
            GoRoute(
              path: '/team',
              builder: (context, state) => const TeamScreen(),
            ),
            GoRoute(
              path: '/manual-attendance',
              builder: (context, state) => const ManualAttendanceScreen(),
            ),
          ],
        ),
      ],
      redirect: (context, state) {
        final isLoggedIn = authState.isAuthenticated;
        final isLoginRoute = state.uri.path == '/login';

        if (!isLoggedIn && !isLoginRoute) {
          return '/login';
        }

        if (isLoggedIn && isLoginRoute) {
          return '/home';
        }

        return null;
      },
    );

    return MaterialApp.router(
      title: 'App Asistencias',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

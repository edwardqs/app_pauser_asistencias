import 'package:app_asistencias_pauser/core/presentation/main_layout.dart';
import 'package:app_asistencias_pauser/core/services/auth_notifier.dart';
import 'package:app_asistencias_pauser/features/attendance/presentation/attendance_history_screen.dart';
import 'package:app_asistencias_pauser/features/attendance/presentation/home_screen.dart';
import 'package:app_asistencias_pauser/features/auth/presentation/login_screen.dart';
import 'package:app_asistencias_pauser/features/auth/presentation/forgot_password_screen.dart';
import 'package:app_asistencias_pauser/features/auth/presentation/splash_screen.dart';
import 'package:app_asistencias_pauser/features/auth/presentation/profile_screen.dart';
import 'package:app_asistencias_pauser/features/team/presentation/manual_attendance_screen.dart';
import 'package:app_asistencias_pauser/features/team/presentation/team_screen.dart';
import 'package:app_asistencias_pauser/features/requests/presentation/my_requests_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Observamos el estado de autenticación
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
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
          GoRoute(
            path: '/requests',
            builder: (context, state) => const MyRequestsScreen(),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final path = state.uri.path;
      final isLoginRoute = path == '/login';
      final isForgotRoute = path == '/forgot-password';
      final isSplashRoute = path == '/splash';

      if (isSplashRoute) return null;

      if (!isLoggedIn && !isLoginRoute && !isForgotRoute) {
        return '/login';
      }

      if (isLoggedIn && (isLoginRoute || isForgotRoute)) {
        return '/home';
      }

      return null;
    },
  );
});

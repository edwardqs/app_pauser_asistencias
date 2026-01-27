import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MainLayout extends ConsumerWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);

    // Usamos 'position' (cargo) en lugar de 'employeeType' (rol) porque ahí es donde está "ANALISTA DE GENTE Y GESTION"
    // Si 'position' es nulo, fallbback a 'employeeType'
    final userRole = storage.position ?? storage.employeeType;

    final hasTeamAccess = _checkTeamAccess(userRole);

    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_filled),
        label: 'Inicio',
      ),
      if (hasTeamAccess)
        NavigationDestination(
          icon: const Icon(Icons.people_outline),
          selectedIcon: const Icon(Icons.people),
          label: 'Equipo',
        ),
      NavigationDestination(
        icon: const Icon(Icons.history_outlined),
        selectedIcon: const Icon(Icons.history),
        label: 'Historial',
      ),
      NavigationDestination(
        icon: const Icon(Icons.description_outlined),
        selectedIcon: const Icon(Icons.description),
        label: 'Solicitudes',
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: 'Perfil',
      ),
    ];

    const primaryColor = Color(0xFF2563EB);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            indicatorColor: primaryColor.withOpacity(0.1),
            labelTextStyle: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) {
                return const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                );
              }
              return TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              );
            }),
            iconTheme: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) {
                return const IconThemeData(color: primaryColor);
              }
              return IconThemeData(color: Colors.grey.shade600);
            }),
          ),
          child: NavigationBar(
            height: 70,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            selectedIndex: _calculateSelectedIndex(context, hasTeamAccess),
            onDestinationSelected: (index) =>
                _onItemTapped(index, context, hasTeamAccess),
            destinations: destinations,
          ),
        ),
      ),
    );
  }

  bool _checkTeamAccess(String? role) {
    if (role == null) return false;
    // Normalizar quitando tildes y pasando a mayúsculas
    final normalizedRole = role
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U');

    // Lista de roles/cargos que tienen acceso
    // Incluimos ANALISTA DE GENTE Y GESTION explícitamente
    return [
      'SUPERVISOR',
      'JEFE',
      'COORDINADOR',
      'GERENTE',
      'ADMIN',
      'ANALISTA DE GENTE Y GESTION',
      'GENTE Y GESTION', // Para cubrir variantes
    ].any((r) => normalizedRole.contains(r));
  }

  int _calculateSelectedIndex(BuildContext context, bool hasTeamAccess) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/home')) return 0;

    if (hasTeamAccess) {
      if (location.startsWith('/team') ||
          location.startsWith('/manual-attendance'))
        return 1;
      if (location.startsWith('/history')) return 2;
      if (location.startsWith('/requests')) return 3;
      if (location.startsWith('/profile')) return 4;
    } else {
      if (location.startsWith('/history')) return 1;
      if (location.startsWith('/requests')) return 2;
      if (location.startsWith('/profile')) return 3;
    }

    return 0;
  }

  void _onItemTapped(int index, BuildContext context, bool hasTeamAccess) {
    if (hasTeamAccess) {
      switch (index) {
        case 0:
          context.go('/home');
          break;
        case 1:
          context.go('/team');
          break;
        case 2:
          context.go('/history');
          break;
        case 3:
          context.go('/requests');
          break;
        case 4:
          context.go('/profile');
          break;
      }
    } else {
      switch (index) {
        case 0:
          context.go('/home');
          break;
        case 1:
          context.go('/history');
          break;
        case 2:
          context.go('/requests');
          break;
        case 3:
          context.go('/profile');
          break;
      }
    }
  }
}

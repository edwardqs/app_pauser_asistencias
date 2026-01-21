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
    final userRole = storage.employeeType; // O storage.role si lo cambiamos

    final hasTeamAccess = _checkTeamAccess(userRole);

    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Inicio',
      ),
      if (hasTeamAccess)
        const NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Equipo',
        ),
      const NavigationDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history),
        label: 'Historial',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Perfil',
      ),
    ];

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _calculateSelectedIndex(context, hasTeamAccess),
        onDestinationSelected: (index) => _onItemTapped(index, context, hasTeamAccess),
        destinations: destinations,
      ),
    );
  }

  bool _checkTeamAccess(String? role) {
    if (role == null) return false;
    final upperRole = role.toUpperCase();
    return [
      'SUPERVISOR',
      'JEFE',
      'COORDINADOR',
      'GERENTE',
      'ADMIN'
    ].any((r) => upperRole.contains(r));
  }

  int _calculateSelectedIndex(BuildContext context, bool hasTeamAccess) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/home')) return 0;
    
    if (hasTeamAccess) {
      if (location.startsWith('/team')) return 1;
      if (location.startsWith('/history')) return 2;
      if (location.startsWith('/profile')) return 3;
    } else {
      if (location.startsWith('/history')) return 1;
      if (location.startsWith('/profile')) return 2;
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
          context.go('/profile');
          break;
      }
    }
  }
}

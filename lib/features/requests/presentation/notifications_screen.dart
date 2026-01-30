import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/requests/data/requests_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Marcar como leídas al salir o entrar? Mejor al verlas.
    // Lo haremos en el build item o al cerrar.
    // Para simplificar, marcaremos todas como leídas al abrir esta pantalla tras un pequeño delay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAllAsRead();
    });
  }

  Future<void> _markAllAsRead() async {
    final employeeId = ref.read(storageServiceProvider).employeeId;
    if (employeeId == null) return;

    // Obtenemos las no leídas primero (esto es una optimización,
    // idealmente el repo tendría un método markAllRead)
    // Por ahora, dejaremos que el usuario interactúe o marcaremos las visibles.
    // Vamos a asumir que al abrir la pantalla, el usuario "ve" las notificaciones.

    // NOTA: Como es un Stream, es complejo obtener los IDs exactos sin suscribirse.
    // Mejor implementamos un botón "Marcar todo como leído" o lo hacemos automático en el backend.
    // Por ahora, visualmente las mostraremos.
  }

  @override
  Widget build(BuildContext context) {
    final employeeId = ref.watch(storageServiceProvider).employeeId;

    if (employeeId == null) {
      return const Scaffold(body: Center(child: Text('No identificado')));
    }

    final notificationsAsync = ref.watch(
      notificationsStreamProvider(employeeId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showPreferencesDialog(context, employeeId),
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No tienes notificaciones',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Recopilar IDs no leídos para marcar
          final unreadIds = notifications
              .where((n) => n['is_read'] == false)
              .map((n) => n['id'] as String)
              .toList();

          if (unreadIds.isNotEmpty) {
            // Marcar como leídas en segundo plano
            Future.delayed(const Duration(seconds: 2), () {
              ref
                  .read(requestsRepositoryProvider)
                  .markNotificationsAsRead(unreadIds);
            });
          }

          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (ctx, i) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final isRead = notification['is_read'] ?? false;
              final date = DateTime.parse(notification['created_at']).toLocal();

              return Container(
                color: isRead ? Colors.white : Colors.blue.withOpacity(0.05),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isRead
                        ? Colors.grey[200]
                        : Colors.blue[100],
                    child: Icon(
                      _getIconForType(notification['type']),
                      color: isRead ? Colors.grey : Colors.blue,
                    ),
                  ),
                  title: Text(
                    notification['title'],
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(notification['message']),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(date),
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'REQUEST_UPDATE':
        return Icons.assignment_turned_in;
      case 'REMINDER':
        return Icons.alarm;
      default:
        return Icons.notifications;
    }
  }

  void _showPreferencesDialog(BuildContext context, String employeeId) {
    showDialog(
      context: context,
      builder: (context) =>
          NotificationPreferencesDialog(employeeId: employeeId),
    );
  }
}

class NotificationPreferencesDialog extends ConsumerStatefulWidget {
  final String employeeId;
  const NotificationPreferencesDialog({super.key, required this.employeeId});

  @override
  ConsumerState<NotificationPreferencesDialog> createState() =>
      _NotificationPreferencesDialogState();
}

class _NotificationPreferencesDialogState
    extends ConsumerState<NotificationPreferencesDialog> {
  bool _pushEnabled = true;
  bool _emailEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await ref
          .read(requestsRepositoryProvider)
          .getNotificationPreferences(widget.employeeId);
      if (mounted) {
        setState(() {
          _pushEnabled = prefs['push_enabled'] ?? true;
          _emailEnabled = prefs['email_enabled'] ?? true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _savePreferences() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(requestsRepositoryProvider)
          .updateNotificationPreferences(
            widget.employeeId,
            _pushEnabled,
            _emailEnabled,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Preferencias guardadas')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Preferencias de Notificación'),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Notificaciones Push'),
                  subtitle: const Text('Recibir alertas en el dispositivo'),
                  value: _pushEnabled,
                  onChanged: (val) => setState(() => _pushEnabled = val),
                ),
                SwitchListTile(
                  title: const Text('Correo Electrónico'),
                  subtitle: const Text('Recibir alertas por email'),
                  value: _emailEnabled,
                  onChanged: (val) => setState(() => _emailEnabled = val),
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _savePreferences,
          child: const Text('GUARDAR'),
        ),
      ],
    );
  }
}

// Provider para el stream
final notificationsStreamProvider = StreamProvider.family
    .autoDispose<List<Map<String, dynamic>>, String>((ref, employeeId) {
      return ref
          .watch(requestsRepositoryProvider)
          .watchNotifications(employeeId);
    });

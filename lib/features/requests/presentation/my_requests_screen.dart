import 'dart:io';
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/requests/data/requests_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MyRequestsScreen extends ConsumerStatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  ConsumerState<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends ConsumerState<MyRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Fondo general blanco
      body: Stack(
        children: [
          // 1. Header Background (Más alto para TabBar)
          Container(
            height: 200,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
          ),

          // 2. Content
          SafeArea(
            child: Column(
              children: [
                // Title
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Center(
                    child: Text(
                      'Mis Solicitudes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // TabBar Custom
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        color: Colors.white,
                      ),
                      labelColor: const Color(0xFF2563EB),
                      unselectedLabelColor: Colors.white,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Nueva Solicitud'),
                        Tab(text: 'Historial'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // TabBarView Content
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: TabBarView(
                      controller: _tabController,
                      children: const [_NewRequestForm(), _RequestsHistory()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewRequestForm extends ConsumerStatefulWidget {
  const _NewRequestForm();

  @override
  ConsumerState<_NewRequestForm> createState() => _NewRequestFormState();
}

class _NewRequestFormState extends ConsumerState<_NewRequestForm> {
  final _formKey = GlobalKey<FormState>();
  String _selectedType = 'VACACIONES';
  DateTime? _startDate;
  DateTime? _endDate;
  final _reasonController = TextEditingController();
  File? _evidenceFile;
  String? _evidenceFileName;
  bool _isLoading = false;

  final List<String> _requestTypes = [
    'VACACIONES',
    'PERMISO PERSONAL',
    'SALUD / MÉDICO',
    'LICENCIA',
  ];

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'pdf', 'png', 'jpeg'],
    );

    if (result != null) {
      setState(() {
        _evidenceFile = File(result.files.single.path!);
        _evidenceFileName = result.files.single.name;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione fechas de inicio y fin')),
      );
      return;
    }

    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La fecha fin no puede ser anterior a la inicio'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final storage = ref.read(storageServiceProvider);
      final employeeId = storage.employeeId;

      if (employeeId == null) throw Exception('No se encontró ID de empleado');

      await ref
          .read(requestsRepositoryProvider)
          .createRequest(
            employeeId: employeeId,
            requestType: _selectedType,
            startDate: _startDate!,
            endDate: _endDate!,
            reason: _reasonController.text,
            evidenceFile: _evidenceFile,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud enviada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        // Limpiar formulario
        setState(() {
          _startDate = null;
          _endDate = null;
          _reasonController.clear();
          _evidenceFile = null;
          _evidenceFileName = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Obtener datos del usuario desde StorageService
    final storage = ref.watch(storageServiceProvider);
    final fullName = storage.fullName ?? 'Empleado Desconocido';
    final dni = storage.dni ?? '---';
    final position = storage.position ?? 'Cargo no definido';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SECCIÓN B: DATOS DEL TRABAJADOR (Read-Only Header)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DATOS DEL TRABAJADOR',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  _buildInfoRow('Nombres y Apellidos:', fullName),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildInfoRow('DNI:', dni)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildInfoRow('Cargo:', position)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // SECCIÓN C: MOTIVO (Tipo de Solicitud)
            const Text('MOTIVO', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _requestTypes
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _selectedType = val!),
            ),
            const SizedBox(height: 20),

            // FECHAS (Salida y Retorno)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FECHA DE SALIDA', // Label exacto de la papeleta
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _startDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null)
                            setState(() => _startDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Text(
                            _startDate != null
                                ? DateFormat('dd/MM/yyyy').format(_startDate!)
                                : 'Seleccionar',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FECHA DE RETORNO', // Label exacto de la papeleta
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _endDate ?? _startDate ?? DateTime.now(),
                            firstDate: _startDate ?? DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null) setState(() => _endDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Text(
                            _endDate != null
                                ? DateFormat('dd/MM/yyyy').format(_endDate!)
                                : 'Seleccionar',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Motivo (Detallado)
            const Text(
              'Motivo / Justificación',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _reasonController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Explique brevemente el motivo de su solicitud...',
                border: OutlineInputBorder(),
              ),
              validator: (val) => val == null || val.isEmpty
                  ? 'Este campo es obligatorio'
                  : null,
            ),
            const SizedBox(height: 20),

            // Adjunto (Simulando Papeleta Física o Sustento)
            // Solo mostrar si NO es vacaciones
            if (_selectedType != 'VACACIONES') ...[
              const Text(
                'Adjuntar Sustento (Obligatorio)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickFile,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.shade400,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade50,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _evidenceFile != null
                            ? Icons.check_circle
                            : Icons.upload_file,
                        color: _evidenceFile != null
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _evidenceFileName ??
                              'Subir foto o PDF (Cita médica, etc.)',
                          style: TextStyle(
                            color: _evidenceFileName != null
                                ? Colors.black
                                : Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_evidenceFile != null)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _evidenceFile = null;
                            _evidenceFileName = null;
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ] else ...[
              const SizedBox(height: 32),
            ],

            // Botón Enviar
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('ENVIAR SOLICITUD'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _RequestsHistory extends ConsumerWidget {
  const _RequestsHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    final employeeId = storage.employeeId;

    if (employeeId == null) {
      return const Center(
        child: Text('No se encontró información del empleado'),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ref.read(requestsRepositoryProvider).watchMyRequests(employeeId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No tienes solicitudes registradas'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            final status = req['status'] ?? 'PENDIENTE';
            final color = _getStatusColor(status);
            final isApproved = status == 'APROBADO';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: color.withOpacity(0.3), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.1),
                        child: Icon(_getStatusIcon(status), color: color),
                      ),
                      title: Text(
                        req['request_type'] ?? 'SOLICITUD',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('${req['start_date']} - ${req['end_date']}'),
                          Text('${req['total_days']} días'),
                          if (req['notes'] != null)
                            Text(
                              req['notes'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withOpacity(0.5)),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (isApproved) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final pdfUrl = req['pdf_url'];
                              if (pdfUrl != null &&
                                  pdfUrl.toString().isNotEmpty) {
                                final uri = Uri.parse(pdfUrl);
                                try {
                                  // Intentar abrir con navegador externo o app de PDF predeterminada
                                  if (!await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  )) {
                                    // Fallback: Intentar en Webview (PlatformDefault) si falla
                                    if (!await launchUrl(
                                      uri,
                                      mode: LaunchMode.platformDefault,
                                    )) {
                                      throw 'No se pudo abrir el enlace';
                                    }
                                  }
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error al abrir PDF: $e'),
                                    ),
                                  );
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'El PDF aún no se ha generado. Espere unos momentos o contacte a RRHH.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Descargar Papeleta (PDF)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade50,
                              foregroundColor: Colors.blue.shade800,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'APROBADO':
        return Colors.green;
      case 'RECHAZADO':
        return Colors.red;
      case 'PENDIENTE':
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'APROBADO':
        return Icons.check;
      case 'RECHAZADO':
        return Icons.close;
      case 'PENDIENTE':
      default:
        return Icons.access_time;
    }
  }

  String _extractType(String? notes) {
    if (notes == null) return 'SOLICITUD';
    if (notes.startsWith('[')) {
      final end = notes.indexOf(']');
      if (end != -1) {
        return notes.substring(1, end);
      }
    }
    return 'SOLICITUD';
  }
}

import 'dart:io';
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/requests/data/requests_repository.dart';
import 'package:app_asistencias_pauser/features/requests/utils/papeleta_html_generator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

final myRequestsProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, employeeId) {
      return ref.watch(requestsRepositoryProvider).watchMyRequests(employeeId);
    });

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
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Fondo decorativo superior
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
          SafeArea(
            child: Column(
              children: [
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

// -----------------------------------------------------------------------------
// FORMULARIO DE NUEVA SOLICITUD (COMPLETO)
// -----------------------------------------------------------------------------
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

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

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

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(
        2025,
      ), // Permitir fechas pasadas (ej. descansos médicos)
      lastDate: DateTime(2030), // Extender fecha límite futura
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          // Resetear fin si es menor al inicio
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = null;
          }
        } else {
          _endDate = picked;
        }
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

      final requestId = await ref
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
            content: Text('Solicitud registrada. Generando documento...'),
            backgroundColor: Colors.blue,
          ),
        );

        // Generar PDF automáticamente
        bool success = false;
        try {
          success = await generateAndUploadPdf(
            context: context,
            ref: ref,
            requestId: requestId,
            requestData: {
              'request_type': _selectedType,
              'start_date': _startDate!.toIso8601String(),
              'end_date': _endDate!.toIso8601String(),
            },
            storage: storage,
          );
        } catch (e) {
          debugPrint("Error generando PDF inicial: $e");
        }

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Solicitud y documento generados correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Solicitud registrada. PDF pendiente de generar (ver Historial).',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }

        // Limpiar formulario
        setState(() {
          _startDate = null;
          _endDate = null;
          _reasonController.clear();
          _evidenceFile = null;
          _evidenceFileName = null;
          _selectedType = 'VACACIONES';
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
    final storage = ref.watch(storageServiceProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bienvenido, ${storage.fullName ?? "Colaborador"}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // TIPO DE SOLICITUD
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: InputDecoration(
                labelText: 'Tipo de Solicitud',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              items: _requestTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedType = v!),
            ),
            const SizedBox(height: 16),

            // FECHAS
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Desde',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: const Icon(Icons.calendar_today, size: 20),
                      ),
                      child: Text(
                        _startDate == null
                            ? 'Seleccionar'
                            : DateFormat('dd/MM/yyyy').format(_startDate!),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Hasta',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: const Icon(Icons.calendar_today, size: 20),
                      ),
                      child: Text(
                        _endDate == null
                            ? 'Seleccionar'
                            : DateFormat('dd/MM/yyyy').format(_endDate!),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // MOTIVO
            TextFormField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'Motivo / Detalle',
                hintText: 'Describe brevemente la razón...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'El motivo es requerido' : null,
            ),
            const SizedBox(height: 16),

            // ADJUNTAR EVIDENCIA (Solo si no es Vacaciones)
            if (_selectedType != 'VACACIONES') ...[
              OutlinedButton.icon(
                onPressed: _pickFile,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  _evidenceFile == null ? Icons.attach_file : Icons.check,
                  color: _evidenceFile == null ? Colors.grey : Colors.green,
                ),
                label: Text(
                  _evidenceFileName ?? 'Adjuntar Evidencia (Médica/Otros)',
                  style: TextStyle(
                    color: _evidenceFile == null ? Colors.grey : Colors.green,
                  ),
                ),
              ),
              if (_evidenceFileName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 12),
                  child: Text(
                    'Archivo seleccionado: $_evidenceFileName',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              const SizedBox(height: 24),
            ],

            // BOTÓN ENVIAR
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E40AF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'REGISTRAR SOLICITUD',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HELPER PARA GENERAR PDF
// -----------------------------------------------------------------------------
Future<bool> generateAndUploadPdf({
  required BuildContext context,
  required WidgetRef ref,
  required String requestId,
  required Map<String, dynamic> requestData,
  required StorageService storage,
}) async {
  try {
    final employeeName = storage.fullName ?? 'DESCONOCIDO';
    final employeeDni = storage.dni ?? '00000000';
    final employeePosition = storage.position ?? 'SIN CARGO';
    final employeeSede = storage.sede ?? 'TRUJILLO';

    final startDate = DateTime.parse(requestData['start_date'].toString());
    final endDate = DateTime.parse(requestData['end_date'].toString());
    final requestType = requestData['request_type'].toString();

    // 1. Generar HTML
    final htmlContent = PapeletaHtmlGenerator.generate(
      employeeName: employeeName,
      employeeDni: employeeDni,
      employeePosition: employeePosition,
      employeeSede: employeeSede,
      requestType: requestType,
      startDate: startDate,
      endDate: endDate,
      emissionDate: DateTime.now(),
    );

    // 2. Convertir a PDF (Uint8List) con timeout
    final pdfBytes = await Printing.convertHtml(
      html: htmlContent,
      format: PdfPageFormat.a4,
    ).timeout(const Duration(seconds: 15));

    // 3. Subir a Supabase
    await ref
        .read(requestsRepositoryProvider)
        .uploadGeneratedPdf(
          requestId: requestId,
          employeeDni: employeeDni,
          pdfBytes: pdfBytes,
        );

    return true;
  } catch (e) {
    debugPrint('Error generando PDF: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generando documento: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return false;
  }
}

// -----------------------------------------------------------------------------
// HISTORIAL DE SOLICITUDES (CON DESCARGA Y SUBIDA)
// -----------------------------------------------------------------------------
class _RequestsHistory extends ConsumerStatefulWidget {
  const _RequestsHistory();

  @override
  ConsumerState<_RequestsHistory> createState() => _RequestsHistoryState();
}

class _RequestsHistoryState extends ConsumerState<_RequestsHistory> {
  String? _generatingId;

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageServiceProvider);
    final employeeId = storage.employeeId;

    if (employeeId == null) {
      return const Center(
        child: Text('No se encontró información del empleado'),
      );
    }

    return ref
        .watch(myRequestsProvider(employeeId))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
          data: (requests) {
            if (requests.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      'No tienes solicitudes registradas',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
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

                // Variables clave para el flujo
                final pdfUrl = req['pdf_url']; // PDF Emitido por web
                final signedUrl = req['signed_file_url']; // Archivo subido
                final requestType = req['request_type'] ?? '';
                final isGenerating = _generatingId == req['id'];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: color.withOpacity(0.3), width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.1),
                            child: Icon(_getStatusIcon(status), color: color),
                          ),
                          title: Text(
                            requestType,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                '${_formatDate(req['start_date'])} - ${_formatDate(req['end_date'])}',
                              ),
                              Text('${req['total_days']} días'),
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
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        // === ZONA DE ACCIONES (Descarga y Subida) ===
                        if (status == 'APROBADO' ||
                            (status == 'PENDIENTE' && pdfUrl != null)) ...[
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // BOTÓN 1: DESCARGAR (Solo si existe PDF)
                                if (pdfUrl != null)
                                  TextButton.icon(
                                    icon: const Icon(
                                      Icons.download_rounded,
                                      size: 20,
                                    ),
                                    label: const Text(
                                      'Descargar',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    onPressed: () async {
                                      try {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Preparando descarga...',
                                            ),
                                            duration: Duration(seconds: 1),
                                          ),
                                        );

                                        final response = await http.get(
                                          Uri.parse(pdfUrl),
                                        );

                                        if (response.statusCode == 200) {
                                          await Printing.sharePdf(
                                            bytes: response.bodyBytes,
                                            filename:
                                                'papeleta_${req['id']}.pdf',
                                          );
                                        } else {
                                          throw Exception(
                                            'Error descarga: ${response.statusCode}',
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text('Error: $e'),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  )
                                else if (status == 'PENDIENTE' && isGenerating)
                                  const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                else if (status == 'PENDIENTE' &&
                                    requestType.contains('VACACIONES'))
                                  // Botón para Generar si no existe
                                  TextButton.icon(
                                    icon: const Icon(
                                      Icons.picture_as_pdf,
                                      size: 20,
                                      color: Colors.blue,
                                    ),
                                    label: const Text(
                                      'Generar PDF',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    onPressed: () async {
                                      setState(() => _generatingId = req['id']);
                                      await generateAndUploadPdf(
                                        context: context,
                                        ref: ref,
                                        requestId: req['id'],
                                        requestData: req,
                                        storage: storage,
                                      );
                                      if (mounted)
                                        setState(() => _generatingId = null);
                                    },
                                  ),

                                // BOTÓN 2: SUBIR FIRMADO
                                if (signedUrl == null)
                                  // Habilitar subida si: NO es vacaciones (es sustento médico) O SI es vacaciones y ya hay PDF para firmar
                                  (!requestType.contains('VACACIONES') ||
                                          pdfUrl != null)
                                      ? ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.blue.shade700,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.upload_file,
                                            size: 16,
                                          ),
                                          label: const Text(
                                            'Subir Firmado',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          onPressed: () => _showUploadDialog(
                                            context,
                                            ref,
                                            req['id'],
                                            employeeId,
                                          ),
                                        )
                                      : const SizedBox.shrink()
                                else
                                  // Si ya subió el documento
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 16,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Enviado',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Mensaje instruccional si está pendiente
                          if (status == 'PENDIENTE' &&
                              signedUrl == null &&
                              pdfUrl != null)
                            Container(
                              width: double.infinity,
                              color: Colors.orange.withOpacity(0.1),
                              padding: const EdgeInsets.all(8),
                              child: const Text(
                                'Acción requerida: Descargar, firmar y subir el documento para su aprobación.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],

                        // Botón Cancelar (Solo si es Pendiente y no ha subido firma aun)
                        if (status == 'PENDIENTE' && signedUrl == null) ...[
                          if (pdfUrl == null)
                            const Divider(
                              height: 1,
                            ), // Divider si no se puso arriba
                          TextButton.icon(
                            onPressed: () =>
                                _confirmCancel(context, ref, req['id']),
                            icon: const Icon(
                              Icons.cancel_outlined,
                              color: Colors.red,
                              size: 18,
                            ),
                            label: const Text(
                              'CANCELAR SOLICITUD',
                              style: TextStyle(color: Colors.red, fontSize: 12),
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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _showUploadDialog(
    BuildContext context,
    WidgetRef ref,
    String requestId,
    String employeeId,
  ) async {
    File? selectedFile;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Subir Documento Firmado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Toma una foto clara del documento firmado o sube el PDF escaneado.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                    );
                    if (result != null) {
                      setModalState(() {
                        selectedFile = File(result.files.single.path!);
                      });
                    }
                  },
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: selectedFile == null
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt,
                                size: 40,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Tocar para seleccionar archivo',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 40,
                                color: Colors.green,
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: Text(
                                  selectedFile!.path.split('/').last,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E40AF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: selectedFile == null
                        ? null
                        : () async {
                            // Guardamos una referencia al ScaffoldMessenger antes de cerrar el modal
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.pop(context); // Cerrar modal

                            try {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Subiendo documento...'),
                                ),
                              );

                              await ref
                                  .read(requestsRepositoryProvider)
                                  .uploadSignedDocument(
                                    requestId: requestId,
                                    employeeId: employeeId,
                                    file: selectedFile!,
                                  );

                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '¡Documento subido correctamente!',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                    child: const Text(
                      'ENVIAR DOCUMENTO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Solicitud'),
        content: const Text('¿Estás seguro de cancelar esta solicitud?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (context.mounted) {
        try {
          await ref.read(requestsRepositoryProvider).cancelRequest(id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Solicitud cancelada')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error: $e')));
          }
        }
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'APROBADO':
        return Colors.green;
      case 'COMPLETADO':
        return Colors.purple;
      case 'RECHAZADO':
        return Colors.red;
      case 'CANCELADO':
        return Colors.grey;
      case 'PENDIENTE':
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'APROBADO':
        return Icons.check;
      case 'COMPLETADO':
        return Icons.all_inbox;
      case 'RECHAZADO':
        return Icons.close;
      case 'CANCELADO':
        return Icons.block;
      case 'PENDIENTE':
      default:
        return Icons.access_time;
    }
  }
}

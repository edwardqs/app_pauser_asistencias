import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/team/data/team_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class ManualAttendanceScreen extends ConsumerStatefulWidget {
  const ManualAttendanceScreen({super.key});

  @override
  ConsumerState<ManualAttendanceScreen> createState() =>
      _ManualAttendanceScreenState();
}

class _ManualAttendanceScreenState
    extends ConsumerState<ManualAttendanceScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedEmployeeId;
  DateTime _selectedDate = DateTime.now(); // Fijar a Hoy
  TimeOfDay _checkInTime = TimeOfDay.now(); // Fijar a Ahora
  TimeOfDay? _checkOutTime; // Opcional, empieza vacío
  String _recordType = 'ASISTENCIA'; // Valor inicial temporal
  final TextEditingController _notesController = TextEditingController();

  // Gestión de Motivos
  List<Map<String, dynamic>> _absenceReasons = [];
  bool _isLoadingReasons = true;
  bool _requiresEvidence = false;
  String? _evidenceFilePath;
  String? _evidenceFileName;

  List<Map<String, dynamic>> _teamMembers = [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTeamMembers();
    _loadAbsenceReasons();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadAbsenceReasons() async {
    try {
      final reasons = await ref
          .read(teamRepositoryProvider)
          .getAbsenceReasons();

      if (mounted) {
        setState(() {
          _absenceReasons = reasons;
          _isLoadingReasons = false;

          // Establecer valor inicial válido si hay motivos cargados
          if (reasons.isNotEmpty) {
            // Buscar si 'ASISTENCIA' existe, si no, usar el primero
            final defaultReason = reasons.firstWhere(
              (r) => r['name'] == 'ASISTENCIA',
              orElse: () => reasons.first,
            );
            _recordType = defaultReason['name'];
            _requiresEvidence = defaultReason['requires_evidence'] ?? false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingReasons = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error cargando motivos: $e')));
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'pdf', 'png', 'jpeg'],
      );

      if (result != null) {
        setState(() {
          _evidenceFilePath = result.files.single.path;
          _evidenceFileName = result.files.single.name;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error seleccionando archivo: $e')),
      );
    }
  }

  Future<void> _loadTeamMembers() async {
    try {
      final storage = ref.read(storageServiceProvider);
      final supervisorId = storage.employeeId;
      final sede = storage.sede;
      final businessUnit = storage.businessUnit;
      final role = (storage.employeeType ?? '').toUpperCase();

      if (supervisorId == null) {
        throw Exception('No se encontró ID de supervisor');
      }

      final isAdmin =
          role == 'ADMIN' ||
          role == 'SUPER ADMIN' ||
          role.contains('RRHH') ||
          role.contains('GENTE');

      final team = await ref.read(teamRepositoryProvider).getTeamAttendance(
            supervisorId,
            sede: sede,
            businessUnit: businessUnit,
            isAdmin: isAdmin,
          );

      // Extraer empleados únicos
      final uniqueEmployees = <String, Map<String, dynamic>>{};
      for (var member in team) {
        // Validación de nulidad: asegurarse que employee_id no sea nulo
        if (member['employee_id'] == null) continue;

        final empId = member['employee_id'] as String;
        if (!uniqueEmployees.containsKey(empId)) {
          uniqueEmployees[empId] = {
            'employee_id': empId,
            'full_name':
                member['full_name'] ?? 'Sin Nombre', // Valor por defecto
            'position': member['position'] ?? 'Sin Cargo', // Valor por defecto
          };
        }
      }

      setState(() {
        _teamMembers = uniqueEmployees.values.toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error cargando equipo: $e')));
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      locale: const Locale('es'),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime(bool isCheckIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isCheckIn ? _checkInTime : (_checkOutTime ?? _checkInTime),
    );

    if (picked != null) {
      setState(() {
        if (isCheckIn) {
          _checkInTime = picked;
        } else {
          _checkOutTime = picked;
        }
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seleccione un empleado')));
      return;
    }

    // Validación de evidencia requerida
    if (_requiresEvidence && _evidenceFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este motivo requiere adjuntar un archivo de evidencia',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final storage = ref.read(storageServiceProvider);
      final supervisorId = storage.employeeId;

      if (supervisorId == null) {
        throw Exception('No se encontró ID de supervisor');
      }

      // Subir evidencia si existe
      String? evidenceUrl;
      if (_evidenceFilePath != null && _evidenceFileName != null) {
        // Generar nombre único para evitar colisiones
        final uniqueName =
            '${DateTime.now().millisecondsSinceEpoch}_$_evidenceFileName';
        evidenceUrl = await ref
            .read(teamRepositoryProvider)
            .uploadEvidence(_evidenceFilePath!, uniqueName);
      }

      // Combinar fecha con horas
      final checkIn = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _checkInTime.hour,
        _checkInTime.minute,
      );

      DateTime? checkOut;
      if (_checkOutTime != null) {
        checkOut = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          _checkOutTime!.hour,
          _checkOutTime!.minute,
        );

        if (checkOut.isBefore(checkIn)) {
          // Asumir que es al día siguiente si es menor? O mostrar error?
          // Por seguridad, mostrar error.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'La hora de salida no puede ser anterior a la entrada',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() => _submitting = false);
          return;
        }
      }

      await ref
          .read(teamRepositoryProvider)
          .registerManualAttendance(
            employeeId: _selectedEmployeeId!,
            supervisorId: supervisorId,
            workDate: _selectedDate,
            checkIn: checkIn,
            checkOut: checkOut,
            recordType: _recordType,
            notes: _notesController.text.isEmpty ? null : _notesController.text,
            evidenceUrl: evidenceUrl, // Pasar URL de evidencia
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registro manual creado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. Header Background
          Container(
            height: 150,
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
                // AppBar Custom
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Text(
                        'Registro Manual',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Información
                                  Card(
                                    elevation: 0,
                                    color: Colors.blue.shade50,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            color: Colors.blue.shade700,
                                          ),
                                          const SizedBox(width: 12),
                                          const Expanded(
                                            child: Text(
                                              'Registre asistencias manualmente para su equipo',
                                              style: TextStyle(fontSize: 13),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Selector de empleado
                                  const Text(
                                    'Empleado *',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: _selectedEmployeeId,
                                    decoration: InputDecoration(
                                      hintText: 'Seleccione un empleado',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      prefixIcon: const Icon(Icons.person),
                                    ),
                                    items: _teamMembers
                                        .map<DropdownMenuItem<String>>((
                                          member,
                                        ) {
                                          return DropdownMenuItem<String>(
                                            value: member['employee_id'],
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  member['full_name'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                Text(
                                                  member['position'],
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        })
                                        .toList(),
                                    onChanged: (value) {
                                      setState(
                                        () => _selectedEmployeeId = value,
                                      );
                                    },
                                    validator: (value) {
                                      if (value == null)
                                        return 'Seleccione un empleado';
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),

                                  // Fecha (Solo Lectura)
                                  const Text(
                                    'Fecha (Hoy) *',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  InputDecorator(
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.calendar_today,
                                        color: Colors.grey,
                                      ),
                                      fillColor: Colors.grey.shade50,
                                      filled: true,
                                      enabled: false,
                                    ),
                                    child: Text(
                                      DateFormat(
                                        'EEEE, d MMMM yyyy',
                                        'es',
                                      ).format(_selectedDate),
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Hora de entrada (Solo Lectura - Ahora)
                                  const Text(
                                    'Hora de Entrada (Ahora) *',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  InputDecorator(
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.access_time,
                                        color: Colors.grey,
                                      ),
                                      fillColor: Colors.grey.shade50,
                                      filled: true,
                                      enabled: false,
                                    ),
                                    child: Text(
                                      _checkInTime.format(context),
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Tipo de registro
                                  const Text(
                                    'Tipo de Registro *',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _isLoadingReasons
                                      ? const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: CircularProgressIndicator(),
                                          ),
                                        )
                                      : DropdownButtonFormField<String>(
                                          value: _recordType,
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                            prefixIcon: const Icon(
                                              Icons.category,
                                            ),
                                          ),
                                          items: _absenceReasons
                                              .map<DropdownMenuItem<String>>((
                                                reason,
                                              ) {
                                                return DropdownMenuItem<String>(
                                                  value: reason['name'],
                                                  child: Text(reason['name']),
                                                );
                                              })
                                              .toList(),
                                          onChanged: (value) {
                                            if (value != null) {
                                              setState(() {
                                                _recordType = value;
                                                final reason = _absenceReasons
                                                    .firstWhere(
                                                      (r) => r['name'] == value,
                                                      orElse: () => {
                                                        'requires_evidence':
                                                            false,
                                                      },
                                                    );
                                                _requiresEvidence =
                                                    reason['requires_evidence'] ??
                                                    false;
                                              });
                                            }
                                          },
                                        ),
                                  const SizedBox(height: 20),

                                  // Selector de Archivo (Condicional)
                                  if (_requiresEvidence ||
                                      _evidenceFilePath != null) ...[
                                    Text(
                                      'Evidencia / Archivo ${_requiresEvidence ? "*" : "(Opcional)"}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    InkWell(
                                      onTap: _pickFile,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color:
                                                _requiresEvidence &&
                                                    _evidenceFilePath == null
                                                ? Colors.red.shade300
                                                : Colors.grey.shade300,
                                            style: BorderStyle.solid,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          color: Colors.grey.shade50,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _evidenceFilePath != null
                                                  ? Icons.check_circle
                                                  : Icons.upload_file,
                                              color: _evidenceFilePath != null
                                                  ? Colors.green
                                                  : Colors.grey,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                _evidenceFileName ??
                                                    'Seleccionar archivo (PDF, Imagen)',
                                                style: TextStyle(
                                                  color:
                                                      _evidenceFileName != null
                                                      ? Colors.black
                                                      : Colors.grey.shade600,
                                                  fontWeight:
                                                      _evidenceFileName != null
                                                      ? FontWeight.w500
                                                      : FontWeight.normal,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (_evidenceFilePath != null)
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  color: Colors.grey,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    _evidenceFilePath = null;
                                                    _evidenceFileName = null;
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (_requiresEvidence &&
                                        _evidenceFilePath == null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                          left: 12,
                                        ),
                                        child: Text(
                                          'Es obligatorio adjuntar evidencia para este motivo',
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 20),
                                  ],

                                  // Notas
                                  const Text(
                                    'Notas (Opcional)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _notesController,
                                    maxLines: 3,
                                    decoration: InputDecoration(
                                      hintText:
                                          'Agregue notas o comentarios...',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      prefixIcon: const Icon(Icons.note),
                                    ),
                                  ),
                                  const SizedBox(height: 32),

                                  // Botón de envío
                                  ElevatedButton(
                                    onPressed: _submitting ? null : _submitForm,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: _submitting
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Registrar Asistencia',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                  // Espacio extra para scroll
                                  const SizedBox(height: 40),
                                ],
                              ),
                            ),
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

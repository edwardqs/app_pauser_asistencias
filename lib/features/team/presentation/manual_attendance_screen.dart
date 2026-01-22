import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/team/data/team_repository.dart';
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
  DateTime _selectedDate = DateTime.now().subtract(const Duration(days: 1));
  TimeOfDay _checkInTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay? _checkOutTime = const TimeOfDay(hour: 17, minute: 0);
  String _recordType = 'ASISTENCIA';
  final TextEditingController _notesController = TextEditingController();

  List<Map<String, dynamic>> _teamMembers = [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTeamMembers();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadTeamMembers() async {
    try {
      final storage = ref.read(storageServiceProvider);
      final supervisorId = storage.employeeId;

      if (supervisorId == null) {
        throw Exception('No se encontró ID de supervisor');
      }

      final team = await ref
          .read(teamRepositoryProvider)
          .getTeamAttendance(supervisorId);

      // Extraer empleados únicos
      final uniqueEmployees = <String, Map<String, dynamic>>{};
      for (var member in team) {
        // Validación de nulidad: asegurarse que employee_id no sea nulo
        if (member['employee_id'] == null) continue;
        
        final empId = member['employee_id'] as String;
        if (!uniqueEmployees.containsKey(empId)) {
          uniqueEmployees[empId] = {
            'employee_id': empId,
            'full_name': member['full_name'] ?? 'Sin Nombre', // Valor por defecto
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

    setState(() => _submitting = true);

    try {
      final storage = ref.read(storageServiceProvider);
      final supervisorId = storage.employeeId;

      if (supervisorId == null) {
        throw Exception('No se encontró ID de supervisor');
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
      appBar: AppBar(
        title: const Text('Registro Manual'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Información
                    Card(
                      color: Colors.blue.shade50,
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _selectedEmployeeId,
                      decoration: InputDecoration(
                        hintText: 'Seleccione un empleado',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.person),
                      ),
                      items: _teamMembers.map<DropdownMenuItem<String>>(( 
                        member,
                      ) {
                        return DropdownMenuItem<String>(
                          value: member['employee_id'],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedEmployeeId = value);
                      },
                      validator: (value) {
                        if (value == null) return 'Seleccione un empleado';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Fecha
                    const Text(
                      'Fecha *',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selectDate,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          DateFormat(
                            'EEEE, d MMMM yyyy',
                            'es',
                          ).format(_selectedDate),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Hora de entrada
                    const Text(
                      'Hora de Entrada *',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _selectTime(true),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.access_time),
                        ),
                        child: Text(_checkInTime.format(context)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Hora de salida
                    const Text(
                      'Hora de Salida (Opcional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _selectTime(false),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.access_time_filled),
                          suffixIcon: _checkOutTime != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() => _checkOutTime = null);
                                  },
                                )
                              : null,
                        ),
                        child: Text(
                          _checkOutTime?.format(context) ??
                              'Sin hora de salida',
                          style: TextStyle(
                            color: _checkOutTime == null
                                ? Colors.grey.shade600
                                : Colors.black,
                          ),
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _recordType,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.category),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'ASISTENCIA',
                          child: Text('Asistencia'),
                        ),
                        DropdownMenuItem(
                          value: 'PERMISO',
                          child: Text('Permiso'),
                        ),
                        DropdownMenuItem(
                          value: 'VACACIONES',
                          child: Text('Vacaciones'),
                        ),
                        DropdownMenuItem(
                          value: 'LICENCIA',
                          child: Text('Licencia Médica'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _recordType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Notas
                    const Text(
                      'Notas (Opcional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Agregue notas o comentarios...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.note),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Botón de envío
                    ElevatedButton(
                      onPressed: _submitting ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                  ],
                ),
              ),
            ),
    );
  }
}

import 'dart:io' as io; // Alias para evitar conflicto
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/features/team/data/team_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

final teamAttendanceProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final storage = ref.watch(storageServiceProvider);
      final supervisorId = storage.employeeId;
      final sede = storage.sede;
      final role = (storage.employeeType ?? '').toUpperCase();

      if (supervisorId == null) return [];

      final isAdmin =
          role == 'ADMIN' ||
          role == 'SUPER ADMIN' ||
          role.contains('RRHH') ||
          role.contains('GENTE');

      return ref
          .watch(teamRepositoryProvider)
          .getTeamAttendance(supervisorId, sede: sede, isAdmin: isAdmin);
    });

// Provider para el filtro seleccionado (Notifier)
class TeamFilterNotifier extends Notifier<String> {
  @override
  String build() => 'todos';

  void setFilter(String filter) => state = filter;
}

final teamFilterProvider = NotifierProvider<TeamFilterNotifier, String>(
  TeamFilterNotifier.new,
);

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamAttendanceProvider);
    final currentFilter = ref.watch(teamFilterProvider);

    // Verificar permisos de Supervisor (Solo RRHH)
    final storage = ref.watch(storageServiceProvider);
    final userPosition = (storage.position ?? '').trim().toUpperCase();
    final userRole = (storage.employeeType ?? '')
        .trim()
        .toUpperCase(); // Usamos employeeType donde guardamos el rol

    final isSupervisor =
        userPosition.contains('GENTE Y GESTIÓN') || // Normalizado con tilde
        userPosition.contains('GENTE Y GESTION') ||
        userPosition.contains('RRHH') ||
        userPosition.contains('GENTE & GESTION') ||
        userPosition.contains('SEGURIDAD Y SALUD') || // Para SST
        userPosition.contains('JEFE') || // Nuevo: Jefes de área
        userPosition.contains('GERENTE') || // Nuevo: Gerentes
        userPosition.contains('COORDINADOR') || // Nuevo: Coordinadores
        userPosition.contains('SUPERVISOR') || // Nuevo: Supervisores
        userRole.contains('JEFE_RRHH') ||
        userRole.contains('ANALISTA_RRHH') ||
        userRole == 'ADMIN' ||
        userRole == 'SUPER ADMIN';

    if (!isSupervisor) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Container(
              height: 120,
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
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        'Mi Equipo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text('No tienes permisos para ver esta sección.'),
                          Text(
                            'Solo personal de Gente y Gestión.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
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
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Mi Equipo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: () => ref.invalidate(teamAttendanceProvider),
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
                    child: teamAsync.when(
                      data: (team) {
                        if (team.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No tienes empleados asignados o no hay datos.',
                                ),
                              ],
                            ),
                          );
                        }

                        // Lógica de filtrado
                        final filteredTeam = team.where((member) {
                          final isLate = member['is_late'] == true;
                          final isAbsent =
                              member['record_type'] == 'INASISTENCIA' ||
                              member['record_type'] == 'AUSENCIA';
                          final hasCheckIn = member['check_in'] != null;

                          // Puntual: Tiene check-in y NO es tarde
                          final isPuntual = hasCheckIn && !isLate;

                          // Tardanza: Es tarde (con o sin check-in, aunque usualmente con check-in)
                          final isTardanza = isLate;

                          switch (currentFilter) {
                            case 'puntuales':
                              return isPuntual;
                            case 'tardanzas':
                              return isTardanza;
                            case 'inasistencias':
                              return isAbsent;
                            default:
                              return true;
                          }
                        }).toList();

                        // Resumen de contadores (Globales, sin filtrar)
                        final total = team.length;

                        // Presentes: Tienen check_in (incluye puntuales y tardanzas)
                        final presentes = team
                            .where((e) => e['check_in'] != null)
                            .length;

                        // Pendientes: No tienen check_in Y no son inasistencia
                        final pendientes = team
                            .where(
                              (e) =>
                                  e['check_in'] == null &&
                                  e['record_type'] != 'INASISTENCIA' &&
                                  e['record_type'] != 'AUSENCIA',
                            )
                            .length;

                        // Ausentes: Son inasistencia explícita
                        final ausentes = team
                            .where(
                              (e) =>
                                  e['record_type'] == 'INASISTENCIA' ||
                                  e['record_type'] == 'AUSENCIA',
                            )
                            .length;

                        return Column(
                          children: [
                            // Header con métricas
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStat(
                                    'Total',
                                    total.toString(),
                                    Colors.blue,
                                  ),
                                  _buildStat(
                                    'Presentes',
                                    presentes.toString(),
                                    Colors.green,
                                  ),
                                  _buildStat(
                                    'Pendientes',
                                    pendientes.toString(),
                                    Colors.orange,
                                  ),
                                  _buildStat(
                                    'Ausentes',
                                    ausentes.toString(),
                                    Colors.red,
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),

                            // Filtros
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  _FilterChip(
                                    label: 'Todos',
                                    value: 'todos',
                                    groupValue: currentFilter,
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'Puntuales',
                                    value: 'puntuales',
                                    groupValue: currentFilter,
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'Tardanzas',
                                    value: 'tardanzas',
                                    groupValue: currentFilter,
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'Inasistencias',
                                    value: 'inasistencias',
                                    groupValue: currentFilter,
                                  ),
                                ],
                              ),
                            ),

                            // Lista de empleados filtrada
                            Expanded(
                              child: filteredTeam.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No hay registros con este filtro',
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.all(16),
                                      itemCount: filteredTeam.length,
                                      itemBuilder: (context, index) {
                                        final member = filteredTeam[index];
                                        return _buildMemberCard(
                                          context,
                                          member,
                                        );
                                      },
                                    ),
                            ),
                          ],
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Center(child: Text('Error: $err')),
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

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildMemberCard(BuildContext context, Map<String, dynamic> member) {
    final fullName = member['full_name'] ?? 'Sin Nombre';
    final position = member['position'] ?? 'Cargo no definido';
    final profilePic = member['profile_picture_url'];
    final checkIn = member['check_in'];
    final checkOut = member['check_out'];
    final isLate = member['is_late'] == true;
    final notes = member['notes'];
    final recordType = member['record_type'];
    final employeeId = member['employee_id'];

    Color statusColor;
    String statusText;

    if (recordType == 'INASISTENCIA' ||
        recordType == 'AUSENCIA' ||
        recordType == 'FALTA JUSTIFICADA' ||
        recordType == 'AUSENCIA SIN JUSTIFICAR' ||
        recordType == 'FALTA_INJUSTIFICADA') {
      statusColor = Colors.red;
      statusText = 'Ausente';
    } else if (recordType == 'DESCANSO MÉDICO') {
      statusColor = Colors.indigo;
      statusText = 'Desc. Médico';
    } else if (recordType == 'LICENCIA CON GOCE' || recordType == 'LICENCIA') {
      statusColor = Colors.purple;
      statusText = 'Licencia';
    } else if (recordType == 'VACACIONES') {
      statusColor = Colors.orange;
      statusText = 'Vacaciones';
    } else if (checkOut != null) {
      statusColor = Colors.grey;
      statusText = 'Salida';
    } else if (checkIn != null) {
      if (isLate) {
        statusColor = Colors.orange.shade800; // Color distintivo para tardanza
        statusText = 'Tardanza';
      } else {
        statusColor = Colors.green;
        statusText =
            'Puntual'; // 'En Jornada' -> 'Puntual' es más claro si hay distinción
      }
    } else {
      statusColor = Colors.orange;
      statusText = 'Pendiente';
    }

    return GestureDetector(
      onLongPress: () {
        // Habilitar registro manual al mantener presionado (solo para admins/supervisores)
        _showManualRegisterModal(context, employeeId, fullName);
      },
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: profilePic != null
                        ? NetworkImage(profilePic)
                        : null,
                    child: profilePic == null
                        ? Icon(Icons.person, color: Colors.grey.shade400)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          position,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Botón de acción rápida (Menú de 3 puntos)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'manual_register') {
                        _showManualRegisterModal(context, employeeId, fullName);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'manual_register',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit_calendar,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                                SizedBox(width: 8),
                                Text('Registrar Manualmente'),
                              ],
                            ),
                          ),
                        ],
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              // ... resto de la tarjeta (check-in/check-out info)
              if (checkIn != null ||
                  notes != null ||
                  recordType == 'INASISTENCIA' ||
                  recordType == 'AUSENCIA') ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (checkIn != null)
                      Row(
                        children: [
                          const Icon(Icons.login, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat(
                              'hh:mm a',
                            ).format(DateTime.parse(checkIn).toLocal()),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (isLate)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'TARDE',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    if (checkOut != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.logout,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat(
                              'hh:mm a',
                            ).format(DateTime.parse(checkOut).toLocal()),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                  ],
                ),
                if (notes != null && notes.toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.note, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            notes,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showManualRegisterModal(
    BuildContext context,
    String? employeeId,
    String fullName,
  ) {
    if (employeeId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          _ManualRegisterSheet(employeeId: employeeId, fullName: fullName),
    );
  }
}

class _ManualRegisterSheet extends ConsumerStatefulWidget {
  final String employeeId;
  final String fullName;

  const _ManualRegisterSheet({
    required this.employeeId,
    required this.fullName,
  });

  @override
  ConsumerState<_ManualRegisterSheet> createState() =>
      _ManualRegisterSheetState();
}

class _ManualRegisterSheetState extends ConsumerState<_ManualRegisterSheet> {
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String _selectedType = 'IN';
  final _notesController = TextEditingController();
  bool _isLoading = false;
  io.File? _evidenceFile;
  String? _evidenceFileName;

  // Inicializamos con valores por defecto para asegurar que siempre se vean
  List<Map<String, dynamic>> _absenceReasons = [
    {'name': 'ENFERMEDAD COMUN', 'requires_evidence': true},
    {'name': 'MOTIVOS DE SALUD', 'requires_evidence': true},
    {'name': 'MOTIVOS FAMILIARES', 'requires_evidence': false},
    {'name': 'PERMISO', 'requires_evidence': false},
    {'name': 'VACACIONES', 'requires_evidence': false},
  ];
  bool _isLoadingReasons = false;
  bool _dynamicEvidenceRequired = false;

  // Gestión de Subcategorías (Descanso Médico)
  String? _selectedSubcategory;
  final List<String> _medicalSubcategories = [
    'Accidente común',
    'Accidente de trabajo',
    'Enfermedad común',
    'Maternidad',
  ];

  // Límite de tardanza (07:00 AM)
  static const _lateLimitHour = 7;
  static const _lateLimitMinute = 0;

  @override
  void initState() {
    super.initState();
    // Intentamos cargar del servidor, si falla, ya tenemos los locales
    _loadReasonsFromServer();
  }

  Future<void> _loadReasonsFromServer() async {
    // No ponemos isLoading en true para no bloquear la UI con el spinner
    try {
      final reasons = await ref
          .read(teamRepositoryProvider)
          .getAbsenceReasons();
      if (mounted && reasons.isNotEmpty) {
        setState(() {
          _absenceReasons = reasons;
        });
      }
    } catch (e) {
      // print('Error loading reasons (usando locales): $e');
    }
  }

  bool get _isLate {
    // Si no es Entrada, verificamos si el motivo requiere evidencia
    if (_selectedType != 'IN') {
      return _dynamicEvidenceRequired;
    }

    // Si es Entrada, verificamos horario
    if (_selectedType == 'IN') {
      if (_selectedTime.hour > _lateLimitHour) return true;
      if (_selectedTime.hour == _lateLimitHour &&
          _selectedTime.minute > _lateLimitMinute) {
        return true;
      }
    }
    return false;
  }

  Future<void> _pickEvidence() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _evidenceFile = io.File(
          result.files.single.path!,
        ); // Uso de alias correcto
        _evidenceFileName = result.files.single.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Registro Manual: ${widget.fullName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Fecha y Hora
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    // No InkWell = No Clickable
                    decoration: const InputDecoration(
                      labelText: 'Fecha (Hoy)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(
                        Icons.calendar_today,
                        color: Colors.grey,
                      ),
                      fillColor: Color(0xFFF5F5F5),
                      filled: true,
                      enabled: false,
                    ),
                    child: Text(
                      DateFormat('dd/MM/yyyy').format(_selectedDate),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InputDecorator(
                    // No InkWell = No Clickable
                    decoration: const InputDecoration(
                      labelText: 'Hora (Ahora)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.access_time, color: Colors.grey),
                      fillColor: Color(0xFFF5F5F5),
                      filled: true,
                      enabled: false,
                    ),
                    child: Text(
                      DateFormat('hh:mm a').format(
                        DateTime(
                          2022,
                          1,
                          1,
                          _selectedTime.hour,
                          _selectedTime.minute,
                        ),
                      ),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tipo de Registro (Dinámico)
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Tipo de Registro',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: 'IN',
                  child: Text('Entrada (Check-in)'),
                ),
                // Mapear motivos
                ..._absenceReasons
                    .where((r) => r['name'] != 'ASISTENCIA')
                    .map<DropdownMenuItem<String>>((reason) {
                      return DropdownMenuItem<String>(
                        value: reason['name'],
                        child: Text(
                          reason['name'],
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    })
                    .toList(), // Importante el toList()
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedType = val;
                    _selectedSubcategory =
                        null; // Resetear subcategoría al cambiar tipo

                    // Buscar si requiere evidencia
                    if (val != 'IN') {
                      final r = _absenceReasons.firstWhere(
                        (element) => element['name'] == val,
                        orElse: () => {'requires_evidence': false},
                      );
                      _dynamicEvidenceRequired =
                          r['requires_evidence'] ?? false;
                    } else {
                      _dynamicEvidenceRequired = false;
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // Selector de Subcategoría (Solo para Descanso Médico)
            if (_selectedType == 'DESCANSO MÉDICO') ...[
              DropdownButtonFormField<String>(
                value: _selectedSubcategory,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Descanso *',
                  border: OutlineInputBorder(),
                ),
                items: _medicalSubcategories
                    .map(
                      (sub) => DropdownMenuItem(value: sub, child: Text(sub)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedSubcategory = val),
                validator: (val) =>
                    val == null ? 'Seleccione una opción' : null,
              ),
              const SizedBox(height: 16),
            ],

            // Notas
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Motivo / Observación',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              validator: (val) {
                if (_isLate && (val == null || val.isEmpty)) {
                  return 'Requerido para tardanza/motivos especiales';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Evidencia (Obligatoria si es Tarde o Motivo Especial)
            if (_isLate) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedType != 'IN'
                                ? 'Este motivo requiere evidencia obligatoria'
                                : 'Tardanza detectada (>07:00). Requiere evidencia.',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _pickEvidence,
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        _evidenceFileName ?? 'Adjuntar Evidencia (PDF/IMG)',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.orange.shade800,
                        elevation: 0,
                        side: BorderSide(color: Colors.orange.shade300),
                      ),
                    ),
                    if (_evidenceFile == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '* Obligatorio',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Botón Guardar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text('GUARDAR REGISTRO'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validar Evidencia
    if (_isLate && _evidenceFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe adjuntar evidencia para este registro'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final storage = ref.read(storageServiceProvider);
      final supervisorId = storage.employeeId;

      if (supervisorId == null) {
        throw Exception('No se encontró ID de supervisor');
      }

      // Obtener ubicación
      final position = await _getCurrentLocation();
      // Map<String, dynamic>? locationData; // Eliminado por no uso
      if (position != null) {
        /* locationData = {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'timestamp': position.timestamp.toIso8601String(),
        }; */
      }

      // Subir evidencia si existe
      String? evidenceUrl;
      if (_evidenceFile != null) {
        evidenceUrl = await storage.uploadEvidence(_evidenceFile!);
      }

      // Construir fechas
      final datePart = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final timePart =
          '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00';
      final fullDateTime = DateTime.parse('${datePart}T$timePart');

      await ref
          .read(teamRepositoryProvider)
          .registerManualAttendance(
            employeeId: widget.employeeId,
            supervisorId: supervisorId,
            workDate: _selectedDate,
            checkIn: fullDateTime,
            // checkOut eliminado
            recordType: _selectedType == 'IN' ? 'ASISTENCIA' : _selectedType,
            subcategory: _selectedSubcategory, // Pasar subcategoría
            notes: _notesController.text,
            evidenceUrl: evidenceUrl,
            // isLate: _isLate, // Ya no se pasa, lo calcula el backend o es parte del recordType
            // location: locationData, // RPC register_manual_attendance no recibe location aún, pero lo dejamos preparado
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro guardado correctamente')),
        );
        // Forzar actualización completa del provider
        ref.invalidate(teamAttendanceProvider);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Error al guardar';
        if (e.toString().contains('duplicate key') ||
            e.toString().contains('already exists')) {
          errorMessage =
              'Ya existe un registro para este empleado en esta fecha.';
        } else if (e.toString().contains('Exception:')) {
          errorMessage = e.toString().replaceAll('Exception:', '').trim();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _FilterChip extends ConsumerWidget {
  final String label;
  final String value;
  final String groupValue;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.groupValue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = value == groupValue;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          ref.read(teamFilterProvider.notifier).setFilter(value);
        }
      },
      selectedColor: Colors.blue.shade100,
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue.shade900 : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

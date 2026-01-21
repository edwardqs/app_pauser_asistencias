import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:app_asistencias_pauser/features/attendance/data/attendance_repository.dart';

class AbsenceScreen extends ConsumerStatefulWidget {
  final String employeeId;
  const AbsenceScreen({super.key, required this.employeeId});

  @override
  ConsumerState<AbsenceScreen> createState() => _AbsenceScreenState();
}

class _AbsenceScreenState extends ConsumerState<AbsenceScreen> {
  final _reasonController = TextEditingController();
  File? _evidenceFile;
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 50);
    if (picked != null) {
      setState(() => _evidenceFile = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingrese el motivo')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(attendanceRepositoryProvider).reportAbsence(
        employeeId: widget.employeeId,
        reason: _reasonController.text.trim(),
        evidenceFile: _evidenceFile,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inasistencia reportada correctamente'), backgroundColor: Colors.green),
        );
        context.pop(); // Go back to home
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportar Inasistencia')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Por favor explique el motivo de su inasistencia:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            const Text(
              'Adjuntar evidencia (Opcional):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Cámara'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galería'),
                  ),
                ),
              ],
            ),
            if (_evidenceFile != null) ...[
              const SizedBox(height: 16),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_evidenceFile!, fit: BoxFit.cover),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _evidenceFile = null),
                    icon: const CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 14,
                      child: Icon(Icons.close, color: Colors.red, size: 18),
                    ),
                  ),
                ],
              ),
            ],
            const Spacer(),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('ENVIAR REPORTE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

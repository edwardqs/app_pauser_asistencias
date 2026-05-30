import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

export 'package:file_picker/file_picker.dart' show FileType;

class CrossFile {
  final Uint8List bytes;
  final String name;
  final String extension;

  const CrossFile({
    required this.bytes,
    required this.name,
    required this.extension,
  });

  static Future<CrossFile?> pick({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;

    final name = file.name;
    final ext = name.contains('.') ? name.split('.').last : '';

    return CrossFile(bytes: bytes, name: name, extension: ext);
  }
}

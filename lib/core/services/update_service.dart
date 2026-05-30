import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String releaseNotes;
  final bool forceUpdate;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    required this.forceUpdate,
  });
}

class UpdateService {
  static final _supabase = Supabase.instance.client;

  /// Consulta la última versión disponible en `app_versions`
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await _supabase
          .from('app_versions')
          .select('version, build_number, apk_url, release_notes, force_update')
          .order('build_number', ascending: false)
          .limit(1);

      if (response == null || response is! List || response.isEmpty) return null;

      final data = Map<String, dynamic>.from(response.first as Map);
      return UpdateInfo(
        version: data['version'] ?? '',
        buildNumber: (data['build_number'] as num?)?.toInt() ?? 0,
        apkUrl: data['apk_url'] ?? '',
        releaseNotes: data['release_notes'] ?? '',
        forceUpdate: data['force_update'] ?? false,
      );
    } catch (e) {
      print('UpdateService ERROR: $e');
      return null;
    }
  }

  /// Obtiene la versión instalada actualmente
  static Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  /// Obtiene el build number actual
  static Future<int> getCurrentBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// Descarga el APK y lo abre para instalar
  static Future<String> downloadAndInstall(UpdateInfo update) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/app_asistencias_${update.version}.apk';

    final response = await http.get(Uri.parse(update.apkUrl));
    if (response.statusCode != 200) {
      throw Exception('Error al descargar: HTTP ${response.statusCode}');
    }

    final file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);

    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      throw Exception('Error al abrir el instalador: ${result.message}');
    }

    return filePath;
  }
}

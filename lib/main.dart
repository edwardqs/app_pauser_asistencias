import 'dart:io';
import 'package:app_asistencias_pauser/core/router/app_router.dart';
import 'package:app_asistencias_pauser/core/constants/supabase_constants.dart';
import 'package:app_asistencias_pauser/core/services/storage_service.dart';
import 'package:app_asistencias_pauser/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Fix: el motor TLS de Flutter rechaza la cadena de certificados del servidor
// self-hosted aunque el certificado sea válido en navegadores.
class _TrustSelfHostedCert extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) =>
              host == 'supabase.pauserdistribucionessac.com';
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TrustSelfHostedCert();
  await initializeDateFormatting('es');

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConstants.url,
    anonKey: SupabaseConstants.anonKey,
  );

  // Initialize Storage
  final storageService = await StorageService.init();

  // Clear session on fresh install or version update to prevent
  // stale sessions from persisting across device installs or builds.
  final packageInfo = await PackageInfo.fromPlatform();
  final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
  final storedVersion = storageService.appVersion;
  if (storedVersion != currentVersion) {
    await storageService.clearSession();
    await storageService.saveAppVersion(currentVersion);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }

  runApp(
    ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storageService)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Usar el routerProvider para mantener el estado entre hot reloads
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'App Asistencias',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],
    );
  }
}

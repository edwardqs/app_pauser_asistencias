# INSTRUCCIONES DE CORRECCIÓN QA — app_pauser_asistencias
**Rol:** Senior QA Tester → Instrucciones para Desarrollador / Claude Code  
**Proyecto:** `app_pauser_asistencias` (Flutter 3.41 + Riverpod + Supabase)  
**Fecha:** 10/03/2026  
**Prioridad:** Aplicar correcciones en el orden indicado. No saltear pasos.

---

## CONTEXTO GENERAL

Estas instrucciones documentan los problemas detectados en el proceso de QA de la app móvil Flutter de registro de asistencias. Están ordenados de mayor a menor criticidad. Cada paso incluye: el archivo exacto a modificar, la línea aproximada de referencia, el código actual defectuoso y el código corregido que debe reemplazarlo.

> **Regla de oro:** Después de aplicar cada corrección, compilar y verificar que `flutter analyze` no reporte nuevos errores antes de pasar al siguiente paso.

---

## PASO 1 — CORREGIR EL BUG CRÍTICO DE REGISTRO MANUAL

**Archivo:** `lib/features/team/data/team_repository.dart`  
**Método:** `registerManualAttendance()`  
**Problema:** Cuando el RPC `register_manual_attendance` falla con una excepción de Supabase (PostgrestException, violación de constraint, error RLS), el código intenta acceder a `response['success']` sobre un objeto que puede ser `null` o no ser un `Map`, causando un `Null check operator used on a null value`. El mensaje de error que ve el usuario es técnico e incomprensible.

**Código actual (líneas 128–151):**
```dart
Future<void> registerManualAttendance({
  required String employeeId,
  required String supervisorId,
  required DateTime workDate,
  required DateTime checkIn,
  DateTime? checkOut,
  required String recordType,
  String? subcategory,
  String? notes,
  String? evidenceUrl,
  bool isLate = false,
  Map<String, dynamic>? location,
}) async {
  try {
    final response = await _supabase.rpc(
      'register_manual_attendance',
      params: {
        'p_employee_id': employeeId,
        'p_supervisor_id': supervisorId,
        'p_work_date': workDate.toIso8601String().split('T')[0],
        'p_check_in': checkIn.toUtc().toIso8601String(),
        'p_check_out': checkOut?.toUtc().toIso8601String(),
        'p_record_type': recordType,
        'p_subcategory': subcategory,
        'p_notes': notes,
        'p_evidence_url': evidenceUrl,
        'p_is_late': isLate,
        'p_location': location,
      },
    );

    if (response['success'] == false) {
      throw Exception(response['message']);
    }
  } catch (e) {
    throw Exception('Error registrando asistencia manual: $e');
  }
}
```

**Código corregido — reemplazar el método completo:**
```dart
Future<void> registerManualAttendance({
  required String employeeId,
  required String supervisorId,
  required DateTime workDate,
  required DateTime checkIn,
  DateTime? checkOut,
  required String recordType,
  String? subcategory,
  String? notes,
  String? evidenceUrl,
  bool isLate = false,
  Map<String, dynamic>? location,
}) async {
  try {
    final response = await _supabase.rpc(
      'register_manual_attendance',
      params: {
        'p_employee_id': employeeId,
        'p_supervisor_id': supervisorId,
        'p_work_date': workDate.toIso8601String().split('T')[0],
        'p_check_in': checkIn.toUtc().toIso8601String(),
        'p_check_out': checkOut?.toUtc().toIso8601String(),
        'p_record_type': recordType,
        'p_subcategory': subcategory,
        'p_notes': notes,
        'p_evidence_url': evidenceUrl,
        'p_is_late': isLate,
        'p_location': location,
      },
    );

    // CORRECCIÓN: verificar null y tipo antes de acceder a campos del mapa
    if (response == null) {
      throw Exception('El servidor no devolvió respuesta. Intente nuevamente.');
    }

    if (response is Map && response['success'] == false) {
      final msg = response['message'] as String? ?? 'Error desconocido en el servidor';
      throw Exception(msg);
    }

  } on PostgrestException catch (e) {
    // CORRECCIÓN: capturar errores específicos de Supabase con mensajes claros
    switch (e.code) {
      case '23514': // Violación de CHECK constraint (tipo de registro no válido)
        throw Exception(
          'El tipo de registro "$recordType" no es válido en la base de datos. '
          'Contacte al administrador para actualizar los tipos permitidos.',
        );
      case '23505': // Violación de UNIQUE constraint (registro duplicado)
        throw Exception(
          'Ya existe un registro de asistencia para este empleado en la fecha seleccionada.',
        );
      case '42501': // Insufficient privilege / RLS
        throw Exception(
          'No tiene permisos para registrar este tipo de asistencia. '
          'Verifique que su sesión esté activa.',
        );
      default:
        throw Exception('Error de base de datos (${e.code}): ${e.message}');
    }
  } catch (e) {
    if (e is Exception) rethrow;
    throw Exception('Error inesperado al registrar asistencia manual: $e');
  }
}
```

**Verificación:** Después de este cambio, compilar con `flutter analyze`. Seleccionar un tipo distinto a ASISTENCIA en el formulario de Registro Manual y confirmar que el mensaje de error que se muestra al usuario es legible y descriptivo en lugar del texto técnico de excepción.

---

## PASO 2 — AGREGAR IMPORT DE PostgrestException EN team_repository.dart

**Archivo:** `lib/features/team/data/team_repository.dart`  
**Problema:** El Paso 1 usa `PostgrestException`, que requiere su import específico.

**Verificar que al inicio del archivo existan estas líneas. Si no están, agregarlas:**
```dart
import 'dart:io' as java_io;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // PostgrestException viene de aquí
```

`PostgrestException` está incluida en el paquete `supabase_flutter`, por lo que no requiere import adicional si ya está ese import. Confirmar que el import de `supabase_flutter` esté presente.

---

## PASO 3 — BLOQUEAR EL FORMULARIO DURANTE CARGA DE TIPOS DE REGISTRO

**Archivo:** `lib/features/team/presentation/manual_attendance_screen.dart`  
**Método:** `build()` → sección del `ElevatedButton` "Registrar Asistencia"  
**Problema:** El botón de envío está activo incluso cuando los tipos de registro aún están cargándose de la base de datos (`_isLoadingReasons = true`). Si el usuario presiona el botón en ese momento, `_recordType` contiene el valor inicial hardcodeado `'ASISTENCIA'` que puede no coincidir con lo que el usuario ve en pantalla.

**Código actual (aproximadamente línea 744):**
```dart
ElevatedButton(
  onPressed: _submitting ? null : _submitForm,
  ...
)
```

**Código corregido — agregar condición de `_isLoadingReasons`:**
```dart
ElevatedButton(
  // CORRECCIÓN: bloquear también si los motivos aún están cargando
  onPressed: (_submitting || _isLoadingReasons) ? null : _submitForm,
  style: ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF2563EB),
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 2,
  ),
  child: (_submitting || _isLoadingReasons)
      ? const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
      : const Text(
          'Registrar Asistencia',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
),
```

---

## PASO 4 — CORREGIR LA BASE DE DATOS: VERIFICAR CHECK CONSTRAINT

**Contexto:** Este paso se ejecuta en el **Supabase SQL Editor** del proyecto `valzrmcdxvxzgwfzcshz.supabase.co`, no en el código Flutter.

**Objetivo:** La columna `record_type` en la tabla `attendance` probablemente tiene un CHECK constraint que solo acepta ciertos valores. Debe incluir todos los valores que pueden venir de la tabla `absence_reasons`.

**Paso 4.1 — Verificar el constraint actual:**
```sql
-- Ejecutar en Supabase SQL Editor
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'attendance'::regclass
  AND contype = 'c'
ORDER BY conname;
```

**Paso 4.2 — Ver todos los valores actuales en absence_reasons:**
```sql
SELECT name, is_active FROM absence_reasons ORDER BY name;
```

**Paso 4.3 — Si el constraint NO incluye todos los valores de absence_reasons, actualizarlo:**
```sql
-- Primero eliminar el constraint existente (reemplazar 'attendance_record_type_check' por el nombre real)
ALTER TABLE attendance
  DROP CONSTRAINT IF EXISTS attendance_record_type_check;

-- Luego crear uno nuevo que incluya todos los tipos válidos
-- ADAPTAR esta lista según los resultados del Paso 4.2
ALTER TABLE attendance
  ADD CONSTRAINT attendance_record_type_check
  CHECK (record_type IN (
    'ASISTENCIA',
    'IN',
    'OUT',
    'AUSENCIA',
    'INASISTENCIA',
    'FALTA_INJUSTIFICADA',
    'PERMISO',
    'ENFERMEDAD COMUN',
    'MOTIVOS DE SALUD',
    'MOTIVOS FAMILIARES',
    'DESCANSO MÉDICO',
    'VACACIONES',
    'LICENCIA'
    -- Agregar aquí cualquier otro valor presente en absence_reasons
  ));
```

**Verificación del Paso 4:** Después de actualizar el constraint, intentar un INSERT manual de prueba:
```sql
-- Probar que el INSERT con un tipo de la tabla absence_reasons ya no falla
INSERT INTO attendance (employee_id, work_date, record_type, status, validated)
VALUES (
  (SELECT id FROM employees LIMIT 1), -- cualquier empleado de prueba
  CURRENT_DATE,
  'PERMISO',
  'justificado',
  false
);
-- Si no hay error, el constraint fue actualizado correctamente.
-- Hacer ROLLBACK si solo es prueba:
ROLLBACK;
```

---

## PASO 5 — CORREGIR EL LOGOUT: AGREGAR supabase.auth.signOut()

**Archivo:** `lib/features/auth/presentation/auth_controller.dart`  
**Método:** `signOut()`  
**Problema:** El método limpia la sesión local de SharedPreferences pero no cierra la sesión en Supabase Auth. El token JWT sigue activo en el cliente hasta que expira de forma natural. Esto significa que si alguien accede al cliente Supabase interno después del logout, aún podría hacer llamadas autenticadas.

**Código actual (líneas 109–122):**
```dart
Future<void> signOut() async {
  state = const AsyncValue.loading();
  final storage = ref.read(storageServiceProvider);

  ref.invalidate(employeeStatusProvider);

  await storage.clearSession();
  state = const AsyncValue.data(null);
}
```

**Código corregido:**
```dart
Future<void> signOut() async {
  state = const AsyncValue.loading();
  final storage = ref.read(storageServiceProvider);

  // Invalidar providers con datos del usuario antes de limpiar
  ref.invalidate(employeeStatusProvider);

  // CORRECCIÓN: cerrar sesión en Supabase Auth para invalidar JWT
  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {
    // Si ya expiró o no había sesión activa, ignorar el error
  }

  await storage.clearSession();
  state = const AsyncValue.data(null);
}
```

---

## PASO 6 — CORREGIR EL BUG EN AuthNotifier.logout()

**Archivo:** `lib/core/services/auth_notifier.dart`  
**Método:** `logout()`  
**Problema:** Al llamar a `logout()`, el estado se fija inicialmente con `isAuthenticated: true` mientras está cargando. Si ocurre algún error durante el proceso, la UI puede quedar en un estado inconsistente mostrando al usuario como autenticado cuando no debería estarlo.

**Código actual — localizar la línea con:**
```dart
state = const AuthState(isAuthenticated: true, isLoading: true);
```

**Código corregido — reemplazar esa única línea por:**
```dart
// CORRECCIÓN: durante el logout, el estado de autenticación debe ser false
state = const AuthState(isAuthenticated: false, isLoading: true);
```

---

## PASO 7 — MEJORAR MENSAJES DE ERROR EN LoginScreen

**Archivo:** `lib/features/auth/presentation/login_screen.dart`  
**Método:** `_handleLogin()` → bloque `else` que muestra el SnackBar de error  
**Problema:** El mensaje de error que se muestra al usuario incluye el prefijo "Exception:" y la cadena completa de la excepción Dart, lo que resulta técnico e incomprensible para usuarios finales.

**Código actual (líneas 48–57):**
```dart
final state = ref.read(authControllerProvider);
if (state.hasError) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(state.error.toString()),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
```

**Código corregido:**
```dart
final state = ref.read(authControllerProvider);
if (state.hasError) {
  // CORRECCIÓN: limpiar el prefijo técnico "Exception:" del mensaje
  final rawError = state.error.toString();
  final cleanError = rawError
      .replaceAll('Exception: ', '')
      .replaceAll('FormatException: ', '')
      .trim();
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(cleanError.isNotEmpty ? cleanError : 'Error al iniciar sesión. Intente nuevamente.'),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
```

---

## PASO 8 — REEMPLAZAR print() POR LOGGER CONDICIONAL

**Archivos afectados:**
- `lib/features/attendance/data/attendance_repository.dart`
- `lib/features/auth/presentation/auth_controller.dart`

**Problema:** El código de producción usa `print()` para depuración, lo que expone información sensible (emails, IDs, errores internos) en los logs del dispositivo, accesibles con `adb logcat` en Android.

**Paso 8.1 — En `attendance_repository.dart`, reemplazar todos los print() así:**

Localizar:
```dart
print('Error en getEmployeeDayStatus RPC: $e');
print('Attendance found locally (RPC missed it): ${localAttendance['id']}');
print('Error en fallback local: $e');
print('Error uploading evidence: $e');
print('Error auto-registering absence: $e');
```

Reemplazar cada uno por:
```dart
// Para errores en desarrollo (solo en modo debug):
assert(() { debugPrint('Error en getEmployeeDayStatus RPC: $e'); return true; }());
// O simplemente eliminar los print() que no son necesarios en producción
```

Si se prefiere mantener logs solo en desarrollo, al inicio del archivo agregar:
```dart
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
```

Y reemplazar cada `print('...')` por:
```dart
if (kDebugMode) debugPrint('...');
```

**Paso 8.2 — En `auth_controller.dart`**, localizar y eliminar o proteger:
```dart
print("Login en Supabase Auth exitoso para: $email");
print("ADVERTENCIA: Falló autenticación en Supabase Auth: $authError");
```

Reemplazar por:
```dart
if (kDebugMode) debugPrint("Supabase Auth: session iniciada para usuario");
if (kDebugMode) debugPrint("Supabase Auth: advertencia al iniciar sesión (${authError.runtimeType})");
```

Agregar al inicio del archivo si no está:
```dart
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
```

---

## PASO 9 — IMPLEMENTAR TIMEOUT EN LLAMADAS A SUPABASE

**Archivos afectados:** `lib/features/attendance/data/attendance_repository.dart` y `lib/features/team/data/team_repository.dart`

**Problema:** Las llamadas a Supabase no tienen timeout definido. Si el servidor no responde, el usuario ve un `CircularProgressIndicator` indefinidamente sin posibilidad de reintentar.

**Solución — envolver las llamadas de alto riesgo con `.timeout()`:**

Ejemplo en `attendance_repository.dart`, método `checkIn()`:
```dart
// CORRECCIÓN: agregar timeout de 15 segundos
final response = await _supabase.rpc(
  'register_attendance',
  params: { ... },
).timeout(
  const Duration(seconds: 15),
  onTimeout: () => throw TimeoutException(
    'El servidor tardó demasiado en responder. Verifique su conexión a internet.',
  ),
);
```

Aplicar el mismo patrón `.timeout(const Duration(seconds: 15), onTimeout: () => throw ...)` en:
- `getEmployeeDayStatus()` en `attendance_repository.dart`
- `registerManualAttendance()` en `team_repository.dart`
- `getTeamAttendance()` en `team_repository.dart`
- `loginRPC()` en `auth_repository.dart`

Agregar al inicio de los archivos afectados si no está:
```dart
import 'dart:async' show TimeoutException;
```

---

## PASO 10 — MIGRAR DATOS SENSIBLES A flutter_secure_storage

**Archivo:** `lib/core/services/storage_service.dart`  
**Problema:** El `employee_id` (UUID único del empleado), el `dni` y el `profile_picture` URL se guardan en `SharedPreferences`, que no está cifrado en Android. Un dispositivo rooteado puede leer estos valores directamente.

**Paso 10.1 — Agregar la dependencia en `pubspec.yaml`:**
```yaml
dependencies:
  # Agregar esta línea (mantener las demás):
  flutter_secure_storage: ^9.2.4
```

Luego ejecutar:
```bash
flutter pub get
```

**Paso 10.2 — Modificar `StorageService` para usar almacenamiento seguro para datos sensibles:**

Al inicio de `storage_service.dart`, agregar:
```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
```

En la clase `StorageService`, agregar una instancia de `FlutterSecureStorage`:
```dart
class StorageService {
  // ... constantes existentes ...
  
  final SharedPreferences _prefs;
  final SupabaseClient _supabase;
  // CORRECCIÓN: almacenamiento cifrado para datos sensibles
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ... resto de la clase ...
}
```

Modificar `saveUserSession()` para guardar el `employee_id` y el `dni` en almacenamiento seguro:
```dart
Future<void> saveUserSession({
  required String employeeId,
  required String fullName,
  required String dni,
  // ... resto de parámetros ...
}) async {
  // CORRECCIÓN: datos sensibles en secure storage
  await _secureStorage.write(key: keyEmployeeId, value: employeeId);
  await _secureStorage.write(key: keyDni, value: dni);
  
  // Datos no sensibles pueden quedar en SharedPreferences
  await _prefs.setString(keyFullName, fullName);
  // ... resto igual ...
}
```

Actualizar el getter `employeeId` para leer desde secure storage:
```dart
// NOTA: como getters síncronos no pueden ser async, se recomienda
// cargar estos valores en la inicialización y cachearlos en memoria:
String? _cachedEmployeeId;

String? get employeeId => _cachedEmployeeId;

// Agregar método de inicialización async:
static Future<StorageService> init() async {
  final prefs = await SharedPreferences.getInstance();
  final service = StorageService(prefs);
  // Cargar el employee_id desde secure storage al inicio
  service._cachedEmployeeId = await service._secureStorage.read(key: keyEmployeeId);
  return service;
}
```

> **Nota para el desarrollador:** Este cambio es el más invasivo estructuralmente. Si hay restricciones de tiempo, como mínimo proteger el campo `keyEmployeeId` y `keyDni`. Los demás campos (sede, posición, nombre) son de menor riesgo.

---

## PASO 11 — MOVER AUTO-REGISTRO DE FALTAS AL SERVIDOR

**Archivo:** `lib/features/attendance/presentation/home_screen.dart`  
**Problema:** El auto-registro de faltas injustificadas se dispara desde el cliente Flutter (líneas 350–363). Cuando el empleado abre la app después de las 18:00 sin haber marcado asistencia, la app llama automáticamente a `registerUnjustifiedAbsence()`. Esto es problemático porque:
1. Puede dispararse en días no laborables si el empleado abre la app
2. Puede generar múltiples llamadas si el provider se invalida varias veces
3. La lógica de negocio de "quién merece una falta" no debe estar en el cliente

**Corrección en el cliente — eliminar el bloque de auto-registro del build():**

Localizar y **eliminar completamente** este bloque en `home_screen.dart`:
```dart
// ELIMINAR todo este bloque:
if (shouldRegisterFalta) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref
        .read(attendanceRepositoryProvider)
        .registerUnjustifiedAbsence(employeeId!)
        .then((_) {
          ref.invalidate(employeeStatusProvider(employeeId));
        });
  });
}
```

**Corrección en la base de datos — crear un cron job en Supabase:**

Ejecutar en el SQL Editor de Supabase (requiere extensión `pg_cron`):
```sql
-- Verificar que pg_cron esté habilitado:
SELECT * FROM pg_extension WHERE extname = 'pg_cron';

-- Crear el cron job para registrar faltas injustificadas automáticamente
-- Se ejecutará todos los días hábiles a las 18:00 hora Lima (23:00 UTC)
SELECT cron.schedule(
  'registrar-faltas-diarias',
  '0 23 * * 1-5',  -- Lunes a Viernes a las 23:00 UTC (18:00 Lima)
  $$
    SELECT register_auto_absence(id)
    FROM employees
    WHERE is_active = true
      AND can_mark_attendance = true
      AND NOT EXISTS (
        SELECT 1 FROM attendance
        WHERE attendance.employee_id = employees.id
          AND attendance.work_date = CURRENT_DATE
      );
  $$
);
```

Si `pg_cron` no está disponible, la alternativa es mover la verificación a la función `get_employee_day_status` para que devuelva `should_register_absence = true` y que el servidor lo maneje, eliminando la responsabilidad del cliente.

---

## PASO 12 — AGREGAR VALIDACIÓN DE CONTRASEÑA EN LOGIN

**Archivo:** `lib/features/auth/presentation/login_screen.dart`  
**Problema:** El campo de contraseña solo valida que no esté vacío. No hay validación de longitud mínima.

**Localizar el validador del campo contraseña (aproximadamente línea 266):**
```dart
validator: (value) => value == null || value.isEmpty
    ? 'Requerido'
    : null,
```

**Reemplazar por:**
```dart
validator: (value) {
  if (value == null || value.isEmpty) return 'La contraseña es requerida';
  if (value.length < 6) return 'Mínimo 6 caracteres';
  return null;
},
```

---

## PASO 13 — VERIFICAR SINCRONIZACIÓN DE BASE DE DATOS (ANÁLISIS)

**Contexto:** Este paso no modifica código. Es una verificación arquitectónica crítica.

**Problema documentado:** La app móvil usa `https://valzrmcdxvxzgwfzcshz.supabase.co` mientras la web usa `https://161.132.48.71:8443`. Si son instancias de PostgreSQL distintas, los registros de asistencias del móvil no son visibles en la web.

**Verificación — ejecutar en el SQL Editor de la web (servidor Elastika):**
```sql
-- Si ambos están conectados al mismo PostgreSQL, esta consulta debería devolver registros:
SELECT COUNT(*) FROM attendance WHERE created_at > NOW() - INTERVAL '7 days';
```

**Verificación — ejecutar en el SQL Editor de Supabase Cloud:**
```sql
-- Mismo query:
SELECT COUNT(*) FROM attendance WHERE created_at > NOW() - INTERVAL '7 days';
```

Si los conteos son distintos, las bases de datos están desincronizadas y se debe definir una estrategia:
- **Opción A:** Hacer que la app móvil apunte también al servidor Elastika (si tiene certificado válido o se configura SSL bypass en Flutter)
- **Opción B:** Configurar replicación lógica de PostgreSQL entre ambas instancias
- **Opción C:** Migrar todo a la instancia cloud y actualizar la web para usar la misma URL

Actualizar `lib/core/constants/supabase_constants.dart` si se elige la Opción A:
```dart
class SupabaseConstants {
  // VERIFICAR con el equipo de infraestructura si se debe cambiar esta URL:
  static const String url = 'https://valzrmcdxvxzgwfzcshz.supabase.co';
  static const String anonKey = 'sb_publishable_YCl_ZZzYwOwT63liBv0-tA_PussK-rh';
}
```

---

## ORDEN DE EJECUCIÓN RECOMENDADO

| Orden | Paso | Tipo | Tiempo estimado |
|-------|------|------|-----------------|
| 1 | Paso 4 — Verificar CHECK constraint en BD | SQL | 15 min |
| 2 | Paso 1 — Corregir NPE en registerManualAttendance | Código | 10 min |
| 3 | Paso 2 — Verificar import PostgrestException | Código | 2 min |
| 4 | Paso 3 — Bloquear botón durante carga de tipos | Código | 5 min |
| 5 | Paso 5 — Agregar supabase.auth.signOut() al logout | Código | 5 min |
| 6 | Paso 6 — Corregir bug de AuthNotifier.logout() | Código | 2 min |
| 7 | Paso 7 — Mensajes de error limpios en LoginScreen | Código | 5 min |
| 8 | Paso 12 — Validación de contraseña en Login | Código | 3 min |
| 9 | Paso 8 — Reemplazar print() por debugPrint | Código | 10 min |
| 10 | Paso 9 — Implementar timeout en RPCs | Código | 15 min |
| 11 | Paso 11 — Eliminar auto-registro de faltas del cliente | Código + SQL | 20 min |
| 12 | Paso 13 — Verificar sincronización de bases de datos | SQL | 30 min |
| 13 | Paso 10 — Migrar a flutter_secure_storage | Código | 45 min |

---

## VERIFICACIÓN FINAL

Después de aplicar todos los cambios, ejecutar:

```bash
# 1. Análisis estático sin errores
flutter analyze

# 2. Compilar para verificar que no hay errores de compilación
flutter build apk --debug

# 3. Correr pruebas unitarias si existen
flutter test
```

Luego realizar las siguientes pruebas manuales en el dispositivo o emulador:

1. **Login:** Intentar con credenciales incorrectas → verificar mensaje de error sin texto "Exception:"
2. **Registro Manual:** Seleccionar tipo "PERMISO" → verificar que ya no aparece error rojo
3. **Registro Manual:** Seleccionar tipo "ENFERMEDAD COMUN" → verificar guardado exitoso
4. **Logout:** Cerrar sesión → verificar que al abrir la app nuevamente pide login
5. **Sin conexión:** Intentar marcar asistencia sin internet → verificar mensaje de timeout en 15 segundos

---

*Documento generado por Senior QA Tester | 10/03/2026*  
*Versión: 1.0 | Para uso de Claude Code / Desarrollador Flutter*

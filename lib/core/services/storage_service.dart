import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('StorageService must be initialized');
});

class StorageService {
  static const String keyEmployeeId = 'employee_id';
  static const String keyFullName = 'full_name';
  static const String keyDni = 'dni';
  static const String keySede = 'sede';
  static const String keyBusinessUnit = 'business_unit';
  static const String keyEmployeeType = 'employee_type';
  static const String keyPosition = 'position';
  static const String keyProfilePicture = 'profile_picture';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  Future<void> saveUserSession({
    required String employeeId,
    required String fullName,
    required String dni,
    required String? sede,
    required String? businessUnit,
    required String? employeeType,
    required String? position,
    String? profilePicture,
  }) async {
    await _prefs.setString(keyEmployeeId, employeeId);
    await _prefs.setString(keyFullName, fullName);
    await _prefs.setString(keyDni, dni);

    if (sede != null) await _prefs.setString(keySede, sede);
    if (businessUnit != null)
      await _prefs.setString(keyBusinessUnit, businessUnit);
    if (employeeType != null)
      await _prefs.setString(keyEmployeeType, employeeType);
    if (position != null) await _prefs.setString(keyPosition, position);
    if (profilePicture != null)
      await _prefs.setString(keyProfilePicture, profilePicture);
  }

  Future<void> updateProfilePicture(String url) async {
    await _prefs.setString(keyProfilePicture, url);
  }

  Future<void> clearSession() async {
    await _prefs.clear();
  }

  String? get employeeId => _prefs.getString(keyEmployeeId);
  String? get fullName => _prefs.getString(keyFullName);
  String? get dni => _prefs.getString(keyDni);
  String? get sede => _prefs.getString(keySede);
  String? get businessUnit => _prefs.getString(keyBusinessUnit);
  String? get employeeType => _prefs.getString(keyEmployeeType);
  String? get position => _prefs.getString(keyPosition);
  String? get profilePicture => _prefs.getString(keyProfilePicture);

  // Aliases for compatibility
  String? get role => employeeType;
  String? get userName => fullName;

  bool get isAuthenticated => employeeId != null;
}

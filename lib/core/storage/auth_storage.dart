import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStorage {
  static const _storage = FlutterSecureStorage();

  static const _keyToken      = 'access_token';
  static const _keyRole       = 'active_role';
  static const _keyUserId     = 'user_id';
  static const _keyEmail      = 'email';

  // Token
  static Future<void> saveToken(String token) async =>
      await _storage.write(key: _keyToken, value: token);

  static Future<String?> getToken() async =>
      await _storage.read(key: _keyToken);

  static Future<void> deleteToken() async =>
      await _storage.delete(key: _keyToken);

  // Rol activo
  static Future<void> saveRole(String role) async =>
      await _storage.write(key: _keyRole, value: role);

  static Future<String?> getRole() async =>
      await _storage.read(key: _keyRole);

  // Usuario
  static Future<void> saveUser({
    required String userId,
    required String email,
    required String role,
  }) async {
    await _storage.write(key: _keyUserId, value: userId);
    await _storage.write(key: _keyEmail,  value: email);
    await _storage.write(key: _keyRole,   value: role);
  }

  // Limpiar todo al logout
  static Future<void> clear() async => await _storage.deleteAll();

  // ¿Está logueado?
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
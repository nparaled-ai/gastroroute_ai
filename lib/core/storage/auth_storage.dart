import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const _storage = FlutterSecureStorage();

  static const _keyToken           = 'access_token';
  static const _keyRole            = 'active_role';
  static const _keyUserId          = 'user_id';
  static const _keyEmail           = 'email';
  static const _keyLanguage        = 'language';
  static const _keySavedEmail      = 'saved_email';
  static const _keySavedPassword   = 'saved_password';
  static const _keyRememberMe      = 'remember_me';

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

  static Future<String?> getEmail() async =>
      await _storage.read(key: _keyEmail);

  static Future<void> saveLanguage(String lang) async =>
      await _storage.write(key: _keyLanguage, value: lang);

  static Future<String?> getLanguage() async =>
      await _storage.read(key: _keyLanguage);

  // Recordar credenciales (SharedPreferences - más fiable que SecureStorage para esto)
  // Solo se recuerda el CORREO. La contraseña NO se guarda nunca (antes se guardaba en claro en las
  // preferencias del móvil); la sesión dura 60 días y no hace falta volver a escribirla. El parámetro `password`
  // se conserva para no tocar a quien llama, y se ignora.
  static Future<void> saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_email', email);
    await prefs.remove('saved_password');   // borra la que dejaron versiones anteriores
    await prefs.setBool('remember_me', true);
  }

  static Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_email');
    await prefs.remove('saved_password');
    await prefs.setBool('remember_me', false);
  }

  static Future<Map<String, String?>> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? false;
    await prefs.remove('saved_password');   // limpieza de la contraseña guardada por versiones anteriores
    return {
      'email':       rememberMe ? prefs.getString('saved_email') : null,
      'password':    null,
      'remember_me': rememberMe ? 'true' : 'false',
    };
  }

  // Limpiar todo al logout
  static Future<void> clear() async => await _storage.deleteAll();

  // ¿Está logueado?
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
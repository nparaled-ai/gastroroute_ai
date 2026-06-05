import 'package:dio/dio.dart';
import 'api_client.dart';
import '../storage/auth_storage.dart';

class AuthService {
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      final response = await ApiClient.dio.post('/auth/login', data: {
        'email':    email,
        'password': password,
      });

      final data = response.data;

      // Guardar credenciales si se pidió
      if (rememberMe) {
        await AuthStorage.saveCredentials(email, password);
      } else {
        await AuthStorage.clearCredentials();
      }

      // Si tiene varios roles, devuelve lista para elegir
      if (data['select_role'] == true) {
        return {
          'select_role': true,
          'user_id':     data['user_id'],
          'roles':       data['roles'],
        };
      }

      // Login directo con un rol
      await AuthStorage.saveToken(data['access_token']);
      await AuthStorage.saveUser(
        userId: data['user']['id'].toString(),
        email:  data['user']['email'],
        role:   data['user']['active_role'],
      );

      return {'success': true, 'role': data['user']['active_role']};

    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<Map<String, dynamic>> selectRole({
    required int userId,
    required String role,
    required String password,
  }) async {
    try {
      final response = await ApiClient.dio.post('/auth/login/select-role', data: {
        'user_id':  userId,
        'role':     role,
        'password': password,
      });

      final data = response.data;

      await AuthStorage.saveToken(data['access_token']);
      await AuthStorage.saveUser(
        userId: data['user']['id'].toString(),
        email:  data['user']['email'],
        role:   data['user']['active_role'],
      );

      return {'success': true, 'role': data['user']['active_role']};

    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<Map<String, dynamic>> registerRider({
    required String email,
    required String password,
    required String nickname,
  }) async {
    try {
      final response = await ApiClient.dio.post('/auth/register/rider', data: {
        'email':    email,
        'password': password,
        'nickname': nickname,
      });

      return {'success': true, 'message': response.data['message']};

    } on DioException catch (e) {
      final errors = e.response?.data['errors'];
      if (errors != null) {
        final firstError = (errors as Map).values.first[0];
        return {'error': firstError};
      }
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<void> logout() async {
    try {
      await ApiClient.dio.post('/auth/logout');
    } catch (_) {}
    await AuthStorage.clear();
  }
}
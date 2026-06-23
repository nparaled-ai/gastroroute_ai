import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class PasswordResetService {
  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await ApiClient.dio.post('/auth/forgot-password',
          data: {'email': email});
      return {'message': response.data['message'], 'debug_token': response.data['debug_token']};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    }
  }

  static Future<Map<String, dynamic>> validateToken(
      String email, String token) async {
    try {
      final response = await ApiClient.dio.post('/auth/validate-token',
          data: {'email': email, 'token': token});
      return {'valid': response.data['valid'] ?? true};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Token inválido.'};
    }
  }

  static Future<Map<String, dynamic>> resetPassword(
      String email, String token, String password, String confirmation) async {
    try {
      final response = await ApiClient.dio.post('/auth/reset-password', data: {
        'email': email,
        'token': token,
        'password': password,
        'password_confirmation': confirmation,
      });
      return {'message': response.data['message']};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al restablecer.'};
    }
  }
}

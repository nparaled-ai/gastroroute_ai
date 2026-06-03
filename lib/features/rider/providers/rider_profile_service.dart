import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class RiderProfileService {
  static Future<Map<String, dynamic>> getProfile() async {
    try {
      final response = await ApiClient.dio.get('/rider/profile');
      return {'profile': response.data};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    try {
      final response = await ApiClient.dio.put('/rider/profile', data: data);
      return {'profile': response.data};
    } on DioException catch (e) {
      final errors = e.response?.data['errors'];
      if (errors != null) {
        final firstError = (errors as Map).values.first[0];
        return {'error': firstError};
      }
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    }
  }

  static Future<Map<String, dynamic>> getMotos() async {
    try {
      final response = await ApiClient.dio.get('/rider/motos');
      return {'motos': response.data};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<Map<String, dynamic>> addMoto(Map<String, dynamic> data) async {
    try {
      final response = await ApiClient.dio.post('/rider/motos', data: data);
      return {'moto': response.data};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<Map<String, dynamic>> updateMoto(int id, Map<String, dynamic> data) async {
    try {
      final response = await ApiClient.dio.put('/rider/motos/$id', data: data);
      return {'moto': response.data};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<Map<String, dynamic>> deleteMoto(int id) async {
    try {
      await ApiClient.dio.delete('/rider/motos/$id');
      return {'success': true};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<Map<String, dynamic>> setPrimaryMoto(int id) async {
    try {
      final response = await ApiClient.dio.patch('/rider/motos/$id/primary');
      return {'success': true, 'moto': response.data['moto']};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }
}
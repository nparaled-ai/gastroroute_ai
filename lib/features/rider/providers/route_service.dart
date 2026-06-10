import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class RouteService {
  static Future<Map<String, dynamic>> generateRoute(Map<String, dynamic> data) async {
    try {
      final response = await ApiClient.dio.post('/rider/routes/generate', data: data);
      return {'result': response.data};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<Map<String, dynamic>> getMyRoutes() async {
    try {
      final response = await ApiClient.dio.get('/rider/routes');
      return {'routes': response.data};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<Map<String, dynamic>> getRoute(int id) async {
    try {
      final response = await ApiClient.dio.get('/rider/routes/$id');
      return {'route': response.data};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }

  static Future<Map<String, dynamic>> saveRoute(Map<String, dynamic> saveData) async {
    try {
      final response = await ApiClient.dio.post('/rider/routes/save', data: {'_save_data': saveData});
      return {'route': response.data['route'], 'message': response.data['message']};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al guardar.'};
    }
  }

  static Future<Map<String, dynamic>> refreshWeather(dynamic lat, dynamic lng) async {
    try {
      final response = await ApiClient.dio.get('/rider/routes/weather', queryParameters: {
        'lat': '$lat',
        'lng': '$lng',
      });
      return {'weather': response.data['weather']};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al actualizar el clima.'};
    }
  }

  static Future<Map<String, dynamic>> publishRoute(int id, String visibility) async {
    try {
      final response = await ApiClient.dio.patch('/rider/routes/$id/publish', data: {
        'visibility': visibility,
      });
      return {'success': true, 'route': response.data['route']};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'Error de conexión.',
      };
    }
  }
}

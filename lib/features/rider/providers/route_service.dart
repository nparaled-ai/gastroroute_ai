import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

/// Señal global para que MyRoutesScreen recargue cuando se guarda una ruta
final routeListRefresh = ValueNotifier<int>(0);

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

  /// Imagen del recorrido planificado de una ruta guardada.
  ///
  /// Se pide como bytes porque el endpoint requiere el token que inyecta el
  /// interceptor de Dio, que Image.network no aplicaría.
  static Future<Uint8List?> mapImage(int routeId) async {
    try {
      final response = await ApiClient.dio.get<List<int>>(
        '/rider/routes/$routeId/map',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  /// Imagen de una ruta recién generada, que todavía no está guardada y por
  /// tanto no tiene id: el recorrido se manda en la petición.
  static Future<Uint8List?> mapPreview(
    String polyline,
    List<Map<String, dynamic>> waypoints,
  ) async {
    try {
      final response = await ApiClient.dio.post<List<int>>(
        '/rider/routes/map-preview',
        data: {
          'polyline': polyline,
          'waypoints': waypoints
              .where((w) => w['lat'] != null && w['lng'] != null)
              .map((w) => {'lat': w['lat'], 'lng': w['lng']})
              .toList(),
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> getMyRoutes() async {
    try {
      final response = await ApiClient.dio.get('/rider/routes');
      final data = response.data as Map<String, dynamic>;
      // 'drafts' y 'no_date' se eliminaron del backend: eran grupos que nunca
      // podían tener nada. Las rutas rodadas van aparte, en RouteTrackingService.
      return {
        'upcoming': List<Map<String, dynamic>>.from(data['upcoming'] ?? []),
        'not_done': List<Map<String, dynamic>>.from(data['not_done'] ?? []),
        'received': List<Map<String, dynamic>>.from(data['received'] ?? []),
      };
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
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

  static Future<Map<String, dynamic>> refreshWeather(dynamic lat, dynamic lng, {String? date}) async {
    try {
      final params = <String, dynamic>{'lat': '$lat', 'lng': '$lng'};
      if (date != null) params['date'] = date;
      final response = await ApiClient.dio.get('/rider/routes/weather', queryParameters: params);
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

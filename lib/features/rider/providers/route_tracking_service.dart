import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

/// Llamadas a la API de tracking de rutas.
///
/// Ojo: los kilómetros los recalcula siempre el servidor a partir del track
/// que se sube al finalizar. Lo que calcula la app en tiempo real es solo
/// para mostrarlo por pantalla mientras se rueda.
class RouteTrackingService {
  /// Tracking activo del motero, o null si no hay ninguno.
  ///
  /// Se consulta al arrancar la app para recuperar una ruta interrumpida
  /// (reinicio del móvil, app cerrada por el sistema).
  static Future<Map<String, dynamic>?> getActive() async {
    try {
      final response = await ApiClient.dio.get('/rider/trackings/active');

      // Sin tracking activo el servidor responde 204 sin cuerpo. Antes
      // respondía {} (Laravel convierte json(null) en un objeto vacío), y eso
      // no es null: se tomaba por un tracking, se leía tracking['id'] como int
      // y la recuperación reventaba. Se exige que traiga id para darlo por
      // bueno, venga lo que venga del servidor.
      final data = response.data;
      if (data is! Map || data['id'] == null) return null;

      return Map<String, dynamic>.from(data);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> start(int routeId, {bool manual = true}) async {
    try {
      final response = await ApiClient.dio.post('/rider/trackings/start', data: {
        'route_id': routeId,
        'started_manually': manual,
      });

      return {'tracking': Map<String, dynamic>.from(response.data)};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al iniciar el tracking.'};
    }
  }

  /// Sube el track completo y cierra el tracking.
  ///
  /// [track] es una lista de puntos `[lat, lng, timestampSegundos, precisión]`.
  static Future<Map<String, dynamic>> finish(int trackingId, List<List<num>> track) async {
    try {
      final response = await ApiClient.dio.patch(
        '/rider/trackings/$trackingId/finish',
        data: {'track': track},
      );
      return {'tracking': Map<String, dynamic>.from(response.data)};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al finalizar la ruta.'};
    }
  }

  static Future<bool> discard(int trackingId) async {
    try {
      await ApiClient.dio.post('/rider/trackings/$trackingId/discard');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> history() async {
    try {
      final response = await ApiClient.dio.get('/rider/trackings');
      return List<Map<String, dynamic>>.from(response.data);
    } catch (_) {
      return [];
    }
  }

  /// Resumen de una ruta ya finalizada, para reabrirlo sin repetir la detección.
  static Future<Map<String, dynamic>?> summary(int trackingId) async {
    try {
      final response = await ApiClient.dio.get('/rider/trackings/$trackingId/summary');
      return Map<String, dynamic>.from(response.data);
    } catch (_) {
      return null;
    }
  }

  /// Imagen del mapa con el track dibujado.
  ///
  /// Se pide como bytes en lugar de usar Image.network porque el endpoint
  /// requiere el token de autenticación, que inyecta el interceptor de Dio.
  static Future<Uint8List?> mapImage(int trackingId) async {
    try {
      final response = await ApiClient.dio.get<List<int>>(
        '/rider/trackings/$trackingId/map',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  /// Marca a mano un POI como visitado.
  static Future<Map<String, dynamic>?> confirmPoi(int trackingId, int poiId) async {
    try {
      final response = await ApiClient.dio.post('/rider/trackings/$trackingId/pois/$poiId');
      return Map<String, dynamic>.from(response.data);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> removePoi(int trackingId, int poiId) async {
    try {
      await ApiClient.dio.delete('/rider/trackings/$trackingId/pois/$poiId');
      return true;
    } catch (_) {
      return false;
    }
  }
}

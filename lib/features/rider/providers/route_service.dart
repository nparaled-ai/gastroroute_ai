import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

/// Señal global para que MyRoutesScreen recargue cuando se guarda una ruta
final routeListRefresh = ValueNotifier<int>(0);

class RouteService {
  /// Cuánto se espera a que el servidor genere una ruta con IA.
  ///
  /// Muy por encima de los 30 s por defecto de ApiClient, y a propósito. Una
  /// generación encadena la llamada a la IA, la geocodificación y **varias**
  /// vueltas a Google Directions: `trimWaypointsToFit` vuelve a pedir la ruta
  /// cada vez que recorta un waypoint que no cabe en la distancia pedida, y
  /// cada vuelta son 1-2 s. Con el timeout general la petición se cortaba a
  /// mitad de trabajo y la app lo enseñaba como "Error de conexión" cuando la
  /// conexión estaba perfectamente y el servidor seguía calculando.
  ///
  /// Solo se alarga esta llamada: subir el timeout global haría que una caída
  /// real tardase minutos en detectarse en el resto de la app.
  static const _generateTimeout = Duration(minutes: 2);

  static Future<Map<String, dynamic>> generateRoute(Map<String, dynamic> data) async {
    try {
      final response = await ApiClient.dio.post(
        '/rider/routes/generate',
        data: data,
        options: Options(receiveTimeout: _generateTimeout),
      );
      return {'result': response.data};
    } on DioException catch (e) {
      return {'error': _messageFor(e, 'planner.generate_timeout')};
    }
  }

  /// Mensaje de error para el motero.
  ///
  /// Se distingue el corte por tiempo del fallo de red: son cosas distintas y
  /// "Error de conexión" ante un timeout despista, porque invita a revisar el
  /// wifi cuando el problema es que la operación tarda.
  static String _messageFor(DioException e, String timeoutKey) {
    final fromServer = e.response?.data is Map
        ? (e.response!.data as Map)['message']
        : null;
    if (fromServer != null) return fromServer.toString();

    switch (e.type) {
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionTimeout:
        return timeoutKey.tr();
      default:
        return 'common.connection_error'.tr();
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

  /// Instante real de la salida, en UTC, a partir del reloj de pared.
  ///
  /// `departure_date` y `departure_time` son hora local del motero, y el
  /// servidor corre en UTC sin saber en qué huso está cada uno. Lo calcula
  /// aquí el móvil porque es el único que conoce su zona y su horario de
  /// verano sin equivocarse. El servidor lo usa para mandar el aviso de salida
  /// y no toca los otros dos campos, que siguen siendo lo que se muestra.
  static String? _departureUtc(Map<String, dynamic> saveData) {
    final date = saveData['departure_date']?.toString();
    if (date == null || date.isEmpty) return null;

    final day = DateTime.tryParse(date);
    if (day == null) return null;

    final parts = (saveData['departure_time']?.toString() ?? '').split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return DateTime(day.year, day.month, day.day, hour, minute)
        .toUtc()
        .toIso8601String();
  }

  static Future<Map<String, dynamic>> saveRoute(Map<String, dynamic> saveData) async {
    try {
      final payload = Map<String, dynamic>.from(saveData);
      final utc = _departureUtc(payload);
      if (utc != null) payload['departure_at_utc'] = utc;

      final response = await ApiClient.dio.post('/rider/routes/save', data: {'_save_data': payload});
      final route = response.data['route'];

      // El aviso de salida ya NO se programa aquí. Lo manda el servidor por
      // push (comando routes:send-departure-reminders), a partir del
      // departure_at_utc que se envía arriba.
      return {'route': route, 'message': response.data['message']};
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

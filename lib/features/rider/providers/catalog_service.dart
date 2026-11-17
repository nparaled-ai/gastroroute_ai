import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

/// Rutas moteras: el catálogo de rutas comprobadas y las que publican los moteros.
///
/// Consultarlo no cuesta nada en Google: el enlace de Maps lo traza Google al abrirlo.
/// Solo `prepare` llama a Google (tres Directions, al preparar la ruta para guardarla).
class CatalogService {
  /// Tiempo de espera de `prepare`: son tres trazados y la previsión del tiempo.
  static const _prepareTimeout = Duration(seconds: 60);

  /// Una página de la lista. Devuelve `null` si falló.
  static Future<Map<String, dynamic>?> list(Map<String, dynamic> params) async {
    try {
      final r = await ApiClient.dio.get('/rider/catalog/routes', queryParameters: params);
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> detail(int id) async {
    try {
      final r = await ApiClient.dio.get('/rider/catalog/routes/$id');
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException {
      return null;
    }
  }

  /// Opiniones aprobadas de una ruta, de 20 en 20. `null` si falló.
  static Future<Map<String, dynamic>?> ratings(int id, {int page = 1}) async {
    try {
      final r = await ApiClient.dio.get(
        '/rider/catalog/routes/$id/ratings',
        queryParameters: {'page': page},
      );
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException {
      return null;
    }
  }

  /// Vota una ruta que se ha rodado. Devuelve `{message}` o `{error}`.
  static Future<Map<String, dynamic>> rate(
    int id, {
    required int routeId,
    int? stars,
    bool? wasOpen,
    bool? roadworks,
    String? comment,
  }) async {
    try {
      final r = await ApiClient.dio.post('/rider/catalog/routes/$id/rating', data: {
        'route_id': routeId,
        if (stars != null) 'stars': stars,
        if (wasOpen != null) 'was_open': wasOpen,
        if (roadworks != null) 'roadworks': roadworks,
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      });
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      return {'error': _message(e)};
    }
  }

  /// El plan de ESTE motero para la ruta: acercamiento + ruta + regreso, con avisos,
  /// paradas para comer, gasolina y tiempo. Devuelve el cuerpo o `{error}`.
  static Future<Map<String, dynamic>> prepare(int id, Map<String, dynamic> body) async {
    try {
      final r = await ApiClient.dio.post(
        '/rider/catalog/routes/$id/prepare',
        data: body,
        options: Options(receiveTimeout: _prepareTimeout),
      );
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      return {'error': _message(e)};
    }
  }

  static String _message(DioException e) {
    final d = e.response?.data;
    if (d is Map && d['message'] != null) return d['message'].toString();
    return '';
  }
}

import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

/// La cola de moderación del administrador (y del moderador que delegue).
class ModerationService {
  /// Lo pendiente de cada tipo. Vacío si no se pudo pedir.
  static Future<Map<String, int>> summary() async {
    try {
      final r = await ApiClient.dio.get('/admin/moderation/summary');
      final d = Map<String, dynamic>.from(r.data as Map);
      return {for (final e in d.entries) e.key: (e.value as num).toInt()};
    } on DioException {
      return {};
    }
  }

  /// Comentarios de sitios de comer. `reviewed` = ya decididos. null si falló.
  static Future<List<Map<String, dynamic>>?> comments({bool reviewed = false}) async {
    try {
      final r = await ApiClient.dio.get(
        '/admin/moderation/comments',
        queryParameters: {'status': reviewed ? 'reviewed' : 'pending'},
      );
      return List<Map<String, dynamic>>.from(
        (r.data['comments'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } on DioException {
      return null;
    }
  }

  /// `approved` o `rejected`. true si se guardó.
  static Future<bool> decide(int id, String decision) async {
    try {
      await ApiClient.dio.patch(
        '/admin/moderation/comments/$id',
        data: {'decision': decision},
      );
      return true;
    } on DioException {
      return false;
    }
  }

  /// Rutas que los moteros piden publicar, con el borrador que ha rellenado el servidor.
  /// null si falló.
  static Future<List<Map<String, dynamic>>?> routes() async {
    try {
      final r = await ApiClient.dio.get('/admin/moderation/routes');
      return List<Map<String, dynamic>>.from(
        (r.data['routes'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } on DioException {
      return null;
    }
  }

  /// Países con zonas y, del elegido, sus comunidades y provincias (para corregir la zona de una ruta).
  /// {countries: [{code,name}], areas: [{key,name}], regions: [{key,name}]}; null si falló.
  static Future<Map<String, dynamic>?> zones({String? country}) async {
    try {
      final r = await ApiClient.dio.get('/admin/moderation/zones',
          queryParameters: {if (country != null) 'country': country});
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException {
      return null;
    }
  }

  /// Rutas del catálogo parecidas a una ruta pendiente, con su trazado para compararlas.
  /// {mine: {title, km, polyline}, similar: [...]}; null si falló.
  static Future<Map<String, dynamic>?> similar(int routeId) async {
    try {
      final r = await ApiClient.dio.get(
        '/admin/moderation/routes/$routeId/similar',
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException {
      return null;
    }
  }

  /// Aprueba (con las correcciones sobre el borrador) o rechaza una ruta. Devuelve null si
  /// salió bien, o el mensaje de error.
  static Future<String?> decideRoute(
    int id,
    String decision, {
    Map<String, dynamic> overrides = const {},
    String? reason,
  }) async {
    try {
      await ApiClient.dio.patch('/admin/moderation/routes/$id', data: {
        'decision': decision,
        ...overrides,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
      return null;
    } on DioException catch (e) {
      final d = e.response?.data;
      return d is Map && d['message'] != null ? d['message'].toString() : '';
    }
  }

  /// Comentarios de las rutas del catálogo pendientes. null si falló.
  static Future<List<Map<String, dynamic>>?> catalogComments() async {
    try {
      final r = await ApiClient.dio.get('/admin/moderation/catalog-comments');
      return List<Map<String, dynamic>>.from(
        (r.data['comments'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } on DioException {
      return null;
    }
  }

  /// `approved`, `rejected` o `annulled`. true si se guardó.
  static Future<bool> decideCatalogComment(int id, String decision) async {
    try {
      await ApiClient.dio.patch('/admin/moderation/catalog-comments/$id',
          data: {'decision': decision});
      return true;
    } on DioException {
      return false;
    }
  }
}

import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class AchievementService {
  /// Catálogo completo con el progreso del motero.
  ///
  /// Incluye también los bloqueados: la pantalla los muestra atenuados para
  /// que se vea lo que queda por conseguir.
  static Future<Map<String, dynamic>?> getAll() async {
    try {
      final response = await ApiClient.dio.get('/rider/achievements');
      return Map<String, dynamic>.from(response.data);
    } catch (_) {
      return null;
    }
  }

  /// Logros conseguidos por otro motero, para su perfil.
  ///
  /// Devuelve `visible: false` si su configuración de privacidad no lo permite.
  static Future<Map<String, dynamic>?> ofRider(String nickname) async {
    try {
      final response = await ApiClient.dio.get('/rider/achievements/rider/$nickname');
      return Map<String, dynamic>.from(response.data);
    } catch (_) {
      return null;
    }
  }

  /// Logros desbloqueados pendientes de celebrar.
  static Future<List<Map<String, dynamic>>> pending() async {
    try {
      final response = await ApiClient.dio.get('/rider/achievements/pending');
      return List<Map<String, dynamic>>.from(response.data);
    } catch (_) {
      return [];
    }
  }

  /// Marca como vistos los logros ya celebrados.
  static Future<void> markCelebrated(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      await ApiClient.dio.post('/rider/achievements/celebrated', data: {'ids': ids});
    } on DioException catch (_) {}
  }
}

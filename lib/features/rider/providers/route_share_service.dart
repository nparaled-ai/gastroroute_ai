import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class RouteShareService {
  static Future<Map<String, dynamic>> share(
    int routeId, {
    required String visibility,
    List<int>? friendIds,
  }) async {
    try {
      final data = <String, dynamic>{'visibility': visibility};
      if (friendIds != null && friendIds.isNotEmpty) {
        data['friend_ids'] = friendIds;
      }
      final response = await ApiClient.dio.post('/rider/routes/$routeId/share', data: data);
      return {
        'success': true,
        'message': response.data['message'],
        'notified_count': response.data['notified_count'],
      };
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? e.message ?? 'Error al compartir.';
      return {'error': msg};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> join(int routeId) async {
    try {
      final response = await ApiClient.dio.post('/rider/routes/$routeId/join');
      return {'success': true, 'message': response.data['message']};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al apuntarse.'};
    }
  }

  static Future<Map<String, dynamic>> leave(int routeId) async {
    try {
      await ApiClient.dio.delete('/rider/routes/$routeId/join');
      return {'success': true};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error.'};
    }
  }

  static Future<Map<String, dynamic>> getParticipants(int routeId) async {
    try {
      final response = await ApiClient.dio.get('/rider/routes/$routeId/participants');
      return {
        'confirmed':  List<Map<String, dynamic>>.from(response.data['confirmed'] ?? []),
        'pending':    List<Map<String, dynamic>>.from(response.data['pending']   ?? []),
        'count':      response.data['count']    ?? 0,
        'is_joined':  response.data['is_joined'] ?? false,
        'is_owner':   response.data['is_owner']  ?? false,
      };
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error.'};
    }
  }

  static Future<Map<String, dynamic>> getRoute(int routeId) async {
    try {
      final response = await ApiClient.dio.get('/rider/routes/$routeId/view');
      return {'route': response.data};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error.'};
    }
  }
}

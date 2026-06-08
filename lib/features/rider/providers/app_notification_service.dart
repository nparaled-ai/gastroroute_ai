import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class AppNotificationService {
  static Future<Map<String, dynamic>> getNotifications() async {
    try {
      final response = await ApiClient.dio.get('/rider/notifications');
      return {
        'notifications': List<Map<String, dynamic>>.from(response.data['notifications']),
        'unread_count':  response.data['unread_count'],
      };
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error.'};
    }
  }

  static Future<int> getUnreadCount() async {
    try {
      final response = await ApiClient.dio.get('/rider/notifications/unread');
      return response.data['unread_count'] ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> markAllRead() async {
    try {
      await ApiClient.dio.patch('/rider/notifications/read-all');
    } catch (_) {}
  }

  static Future<void> markRead(int id) async {
    try {
      await ApiClient.dio.patch('/rider/notifications/$id/read');
    } catch (_) {}
  }
}

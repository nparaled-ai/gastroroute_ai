import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class FriendshipService {
  // Buscar moteros
  static Future<Map<String, dynamic>> search(String query) async {
    try {
      final response = await ApiClient.dio.get('/rider/friends/search', queryParameters: {'q': query});
      return {'results': List<Map<String, dynamic>>.from(response.data)};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    }
  }

  // Enviar solicitud
  static Future<Map<String, dynamic>> sendRequest(int friendId) async {
    try {
      final response = await ApiClient.dio.post('/rider/friends/request', data: {'friend_id': friendId});
      return {'success': true, 'message': response.data['message']};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    }
  }

  // Aceptar solicitud
  static Future<Map<String, dynamic>> accept(int friendshipId) async {
    try {
      await ApiClient.dio.patch('/rider/friends/$friendshipId/accept');
      return {'success': true};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    }
  }

  // Rechazar solicitud
  static Future<Map<String, dynamic>> reject(int friendshipId) async {
    try {
      await ApiClient.dio.patch('/rider/friends/$friendshipId/reject');
      return {'success': true};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    }
  }

  // Eliminar amistad
  static Future<Map<String, dynamic>> unfriend(int friendUserId) async {
    try {
      await ApiClient.dio.delete('/rider/friends/$friendUserId');
      return {'success': true};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    }
  }

  // Lista de amigos
  static Future<Map<String, dynamic>> getFriends() async {
    try {
      final response = await ApiClient.dio.get('/rider/friends');
      return {'friends': List<Map<String, dynamic>>.from(response.data)};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    }
  }

  // Solicitudes recibidas
  static Future<Map<String, dynamic>> getPendingReceived() async {
    try {
      final response = await ApiClient.dio.get('/rider/friends/pending/received');
      return {'requests': List<Map<String, dynamic>>.from(response.data)};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    }
  }

  // Solicitudes enviadas
  static Future<Map<String, dynamic>> getPendingSent() async {
    try {
      final response = await ApiClient.dio.get('/rider/friends/pending/sent');
      return {'requests': List<Map<String, dynamic>>.from(response.data)};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    }
  }
}

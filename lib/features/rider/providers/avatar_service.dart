import 'package:dio/dio.dart';
import 'dart:io';
import '../../../core/api/api_client.dart';

class AvatarService {
  static Future<Map<String, dynamic>> uploadAvatar(File imageFile) async {
    try {
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(
          imageFile.path,
          filename: 'avatar.jpg',
        ),
      });

      final response = await ApiClient.dio.post(
        '/rider/profile/avatar',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      // Reemplazar localhost por la IP base del servidor
      String avatarUrl = response.data['avatar_url'] ?? '';
      final baseUrl = ApiClient.dio.options.baseUrl;
      final uri = Uri.parse(baseUrl);
      final serverBase = '${uri.scheme}://${uri.host}:${uri.port}';
      avatarUrl = avatarUrl.replaceFirst('http://localhost', serverBase);

      return {'avatar_url': avatarUrl};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al subir la imagen.'};
    }
  }
}

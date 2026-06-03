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

      return {'avatar_url': response.data['avatar_url']};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al subir la imagen.'};
    }
  }
}

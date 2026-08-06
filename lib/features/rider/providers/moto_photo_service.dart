import 'dart:io';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class MotoPhotoService {
  static Future<Map<String, dynamic>> uploadPhoto(int motoId, File imageFile) async {
    try {
      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(imageFile.path, filename: 'moto.jpg'),
      });

      final response = await ApiClient.dio.post(
        '/rider/motos/$motoId/photo',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      String photoUrl = response.data['photo_url'] ?? '';
      final baseUrl = ApiClient.dio.options.baseUrl;
      final uri = Uri.parse(baseUrl);
      final serverBase = '${uri.scheme}://${uri.host}:${uri.port}';
      photoUrl = photoUrl.replaceFirst('http://localhost', serverBase);

      return {'photo_url': photoUrl};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al subir la foto.'};
    }
  }

  static Future<Map<String, dynamic>> deletePhoto(int motoId) async {
    try {
      await ApiClient.dio.delete('/rider/motos/$motoId/photo');
      return {'success': true};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al eliminar la foto.'};
    }
  }
}

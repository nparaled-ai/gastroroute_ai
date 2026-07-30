import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class RouteImportService {
  static Future<Map<String, dynamic>> importFromUrl({
    required String url,
    int? motoId,
    String? departureDate,
    String? departureTime,
  }) async {
    try {
      final response = await ApiClient.dio.post('/rider/routes/import', data: {
        'url':            url,
        if (motoId != null)       'moto_id':        motoId,
        if (departureDate != null) 'departure_date': departureDate,
        if (departureTime != null) 'departure_time': departureTime,
      });
      return {'result': response.data};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al importar la ruta.'};
    }
  }

  static Future<Map<String, dynamic>> importFromGpx({
    required String filePath,
    required String fileName,
    int? motoId,
    String? departureDate,
    String? departureTime,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        if (motoId != null)        'moto_id':        motoId.toString(),
        if (departureDate != null) 'departure_date': departureDate,
        if (departureTime != null) 'departure_time': departureTime,
      });
      final response = await ApiClient.dio.post(
        '/rider/routes/import-gpx',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      return {'result': response.data};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'Error al importar el archivo GPX.'};
    }
  }
}

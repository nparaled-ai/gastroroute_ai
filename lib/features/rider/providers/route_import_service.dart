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
}

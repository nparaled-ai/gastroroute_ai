import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';

import 'api_client.dart';

/// Denunciar una ruta de «Rutas moteras» o uno de sus comentarios.
class ReportService {
  /// null = enviada; si no, el motivo del fallo ya traducido.
  static Future<String?> send({
    required String targetType, // catalog_route | catalog_comment
    required int targetId,
    required String reason,
    required String details,
  }) async {
    try {
      await ApiClient.dio.post('/rider/reports', data: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'details': details,
        'good_faith': true,
      });
      return null;
    } on DioException catch (e) {
      final d = e.response?.data;
      return d is Map && d['message'] != null ? '${d['message']}' : 'common.connection_error'.tr();
    }
  }
}

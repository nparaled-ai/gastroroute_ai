import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';

import 'api_client.dart';

/// Cambiar la contraseña y eliminar la cuenta.
class AccountService {
  /// Cambia la contraseña. El servidor cierra las demás sesiones y devuelve un token nuevo para esta, que se guarda
  /// aquí para no echar al motero de su propia app. `{'ok': true}` o `{'error': mensaje}`.
  static Future<Map<String, dynamic>> changePassword({
    required String current,
    required String password,
    required String confirmation,
  }) async {
    try {
      final r = await ApiClient.dio.post('/auth/change-password', data: {
        'current_password': current,
        'password': password,
        'password_confirmation': confirmation,
      });
      final token = r.data['access_token'];
      if (token is String && token.isNotEmpty) {
        await ApiClient.saveToken(token);
      }
      return {'ok': true, 'message': r.data['message']};
    } on DioException catch (e) {
      return {'error': _mensaje(e)};
    }
  }

  /// Elimina la cuenta y todos sus datos. Pide la contraseña (o, en cuentas de Google, la palabra de confirmación).
  static Future<Map<String, dynamic>> deleteAccount({String? password, String? confirm}) async {
    try {
      final r = await ApiClient.dio.delete('/auth/account', data: {
        if (password != null) 'password': password,
        if (confirm != null) 'confirm': confirm,
      });
      return {'ok': true, 'message': r.data['message']};
    } on DioException catch (e) {
      return {'error': _mensaje(e)};
    }
  }

  static String _mensaje(DioException e) {
    final errors = e.response?.data is Map ? e.response?.data['errors'] : null;
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return '${first.first}';
    }
    final m = e.response?.data is Map ? e.response?.data['message'] : null;
    return m is String ? m : 'common.connection_error'.tr();
  }
}

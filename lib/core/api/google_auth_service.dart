import 'package:easy_localization/easy_localization.dart';
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'api_client.dart';
import '../storage/auth_storage.dart';

class GoogleAuthService {
  static final _googleSignIn = GoogleSignIn(
    serverClientId: '1063655022495-5763pug6e9bsqduiipdnb3os514n1n5v.apps.googleusercontent.com',
  );

  /// [acceptTerms]: la cuenta NUEVA de Google necesita aceptar los terminos y la politica. La primera llamada va sin
  /// ella; si el servidor contesta 428 (`consent_required`) la pantalla pregunta y vuelve a llamar con `true`.
  static Future<Map<String, dynamic>> signIn({bool acceptTerms = false}) async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return {'cancelled': true};

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) return {'error': 'errors.google_token'.tr()};

      final response = await ApiClient.dio.post('/auth/google', data: {
        'id_token': idToken,
        if (acceptTerms) 'accept_terms': true,
      });

      final data = response.data;

      if (data['select_role'] == true) {
        return {
          'select_role': true,
          'selection_token': data['selection_token'],
          'user_id': data['user_id'],
          'roles': data['roles'],
        };
      }

      await AuthStorage.saveToken(data['access_token']);
      await AuthStorage.saveUser(
        userId: data['user']['id'].toString(),
        email: data['user']['email'],
        role: data['user']['active_role'],
      );

      return {'success': true, 'role': data['user']['active_role']};

    } on DioException catch (e) {
      if (e.response?.statusCode == 428 && e.response?.data is Map && e.response?.data['consent_required'] == true) {
        return {'consent_required': true};
      }
      return {'error': e.response?.data['message'] ?? 'common.connection_error'.tr()};
    } catch (e) {
      return {'error': 'errors.google_login'.tr()};
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}

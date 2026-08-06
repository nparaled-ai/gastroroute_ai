import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'api_client.dart';
import '../storage/auth_storage.dart';

class GoogleAuthService {
  static final _googleSignIn = GoogleSignIn(
    serverClientId: '1063655022495-5763pug6e9bsqduiipdnb3os514n1n5v.apps.googleusercontent.com',
  );

  static Future<Map<String, dynamic>> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return {'cancelled': true};

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) return {'error': 'No se pudo obtener el token de Google.'};

      final response = await ApiClient.dio.post('/auth/google', data: {
        'id_token': idToken,
      });

      final data = response.data;

      if (data['select_role'] == true) {
        return {
          'select_role': true,
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
      return {'error': e.response?.data['message'] ?? 'Error de conexión.'};
    } catch (e) {
      return {'error': 'Error al iniciar sesión con Google.'};
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:dio/dio.dart';
import 'api_client.dart';
import '../storage/auth_storage.dart';

class AuthService {
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      final response = await ApiClient.dio.post('/auth/login', data: {
        'email':    email,
        'password': password,
      });

      final data = response.data;

      // Guardar credenciales si se pidió
      if (rememberMe) {
        await AuthStorage.saveCredentials(email, password);
      } else {
        await AuthStorage.clearCredentials();
      }

      // Si tiene varios roles, devuelve lista para elegir
      if (data['select_role'] == true) {
        return {
          'select_role': true,
          'user_id':     data['user_id'],
          'roles':       data['roles'],
        };
      }

      // Login directo con un rol
      await AuthStorage.saveToken(data['access_token']);
      await AuthStorage.saveUser(
        userId: data['user']['id'].toString(),
        email:  data['user']['email'],
        role:   data['user']['active_role'],
      );

      return {'success': true, 'role': data['user']['active_role']};

    } on DioException catch (e) {
      final data = e.response?.data;
      if (e.response?.statusCode == 403 && data?['verify_pending'] == true) {
        return {
          'verify_pending': true,
          'email': data['email'] ?? '',
          'message': data['message'] ?? '',
        };
      }
      return {
        'error': data?['message'] ?? 'common.connection_error'.tr(),
      };
    }
  }

  static Future<Map<String, dynamic>> selectRole({
    required int userId,
    required String role,
    String password = '',
    // Con Google no hay contraseña: el servidor da un boleto de cinco minutos.
    String? selectionToken,
  }) async {
    try {
      final response = await ApiClient.dio.post('/auth/login/select-role', data: {
        'user_id':  userId,
        'role':     role,
        if (selectionToken != null && selectionToken.isNotEmpty)
          'selection_token': selectionToken
        else
          'password': password,
      });

      final data = response.data;

      await AuthStorage.saveToken(data['access_token']);
      await AuthStorage.saveUser(
        userId: data['user']['id'].toString(),
        email:  data['user']['email'],
        role:   data['user']['active_role'],
      );

      return {'success': true, 'role': data['user']['active_role']};

    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'common.connection_error'.tr(),
      };
    }
  }

  static Future<Map<String, dynamic>> registerRider({
    required String email,
    required String password,
    required String nickname,
  }) async {
    try {
      final response = await ApiClient.dio.post('/auth/register/rider', data: {
        'email':    email,
        'password': password,
        'nickname': nickname,
      });

      final data = response.data;
      if (data['verify_pending'] == true) {
        return {
          'verify_pending': true,
          'email': data['email'] ?? '',
          'message': data['message'] ?? '',
        };
      }
      return {'success': true, 'message': data['message']};

    } on DioException catch (e) {
      final errors = e.response?.data['errors'];
      if (errors != null) {
        final firstError = (errors as Map).values.first[0];
        return {'error': firstError};
      }
      return {
        'error': e.response?.data['message'] ?? 'common.connection_error'.tr(),
      };
    }
  }

  static Future<Map<String, dynamic>> resendVerification(String email) async {
    try {
      final response = await ApiClient.dio.post('/auth/resend-verification', data: {'email': email});
      return {'success': true, 'message': response.data['message']};
    } on DioException catch (e) {
      return {'error': e.response?.data['message'] ?? 'common.connection_error'.tr()};
    }
  }

  /// Los perfiles de la persona con lo pendiente en cada uno. Vacío si falla.
  static Future<List<Map<String, dynamic>>> profiles() async {
    try {
      final r = await ApiClient.dio.get('/auth/profiles');
      return List<Map<String, dynamic>>.from(
        (r.data['profiles'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } catch (_) {
      return [];
    }
  }

  /// Cambia de perfil SIN cerrar sesión ni escribir la contraseña: el servidor
  /// da un token nuevo para un perfil que la persona ya tiene.
  static Future<Map<String, dynamic>> switchRole(String role) async {
    try {
      final response = await ApiClient.dio.post('/auth/switch-role', data: {'role': role});
      final data = response.data;

      await AuthStorage.saveToken(data['access_token']);
      await AuthStorage.saveUser(
        userId: data['user']['id'].toString(),
        email:  data['user']['email'],
        role:   data['user']['active_role'],
      );

      return {'success': true, 'role': data['user']['active_role']};
    } on DioException catch (e) {
      return {
        'error': e.response?.data['message'] ?? 'common.connection_error'.tr(),
      };
    }
  }

  static Future<void> logout() async {
    // El identificador de avisos de este movil: el servidor lo borra para que no
    // lleguen avisos a quien ya salió, y luego se tira en el propio movil para
    // que quien entre después reciba uno nuevo.
    String? fcm;
    try {
      fcm = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    try {
      await ApiClient.dio.post('/auth/logout', data: {if (fcm != null) 'fcm_token': fcm});
    } catch (_) {}

    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}

    await AuthStorage.clear();
  }
}
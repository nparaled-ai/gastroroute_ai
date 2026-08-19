import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Callback que el router registra al iniciarse para redirigir al login sin dependencia circular
void Function()? onUnauthorized;

class ApiClient {
  static const String baseUrl = 'http://192.168.0.104:8000/api/v1';

  static final _storage = FlutterSecureStorage();

  static Dio get dio {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'access_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // Enviar idioma al backend para mensajes de error localizados
          final lang = await _storage.read(key: 'language') ?? 'es';
          options.headers['Accept-Language'] = lang;
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await _storage.delete(key: 'access_token');
            onUnauthorized?.call();
          }
          return handler.next(error);
        },
      ),
    );

    return dio;
  }

  static Future<void> saveToken(String token) async {
    await _storage.write(key: 'access_token', value: token);
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: 'access_token');
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: 'access_token');
  }
}

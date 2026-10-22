import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/api/api_client.dart';

/// Asistente para crear rutas: convierte una frase del motero en campos.
///
/// El formulario pide más de veinte datos para algo que se piensa en una frase.
/// Esto no lo sustituye —sigue ahí para quien lo prefiera— sino que le pone otra
/// puerta delante.
class RouteAssistantService {
  /// Interpreta la frase.
  ///
  /// Devuelve `understood: false` con un motivo cuando no hay que seguir: la
  /// frase no habla de una ruta, o pide un viaje de varios días, que de momento
  /// queda fuera.
  /// [lat] y [lng] son la posición del motero, si se tiene.
  ///
  /// Hacen falta para cuando dice que sale "desde casa": la IA no sabe dónde
  /// vive, así que marca el campo y el servidor lo convierte en un sitio con
  /// nombre. Sin posición, el origen se queda vacío y la pantalla lo pide en
  /// rojo, que es lo correcto: inventarlo sería peor.
  static Future<Map<String, dynamic>> interpret(
    String text, {
    double? lat,
    double? lng,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/rider/routes/interpret',
        data: {
          'text': text,
          if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
        },
      );

      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      return {
        'understood': false,
        'reason': 'error',
        'error': e.response?.data?['message'] ?? 'errors.connection'.tr(),
      };
    } catch (_) {
      return {
        'understood': false,
        'reason': 'error',
        'error': 'errors.connection'.tr(),
      };
    }
  }

  /// La zona del motero, para los ejemplos: "Pirineo Aragonés", "Sierra de
  /// Madrid"...
  ///
  /// Devuelve null si no hay ninguna cerca, y entonces los ejemplos van sin
  /// zona. No es un error: en media España no hay un POI destacado a menos de
  /// 150 km.
  static Future<String?> zone(double lat, double lng) async {
    try {
      final response = await ApiClient.dio.get(
        '/rider/routes/assistant-zone',
        queryParameters: {'lat': lat, 'lng': lng},
      );

      return response.data['zone'];
    } catch (_) {
      return null;
    }
  }

  /// Las zonas de su entorno, para ofrecerlas como dirección de la ruta.
  ///
  /// Son las mismas de `zone`, pero varias y sin repetir: tres destacados del
  /// Pirineo dan "Pirineo Aragonés" una vez, no tres. Lista vacía si no hay
  /// ninguna cerca, y entonces solo quedan "que decida la IA" y escribirla.
  static Future<List<String>> zones(double lat, double lng) async {
    try {
      final response = await ApiClient.dio.get(
        '/rider/routes/assistant-zone',
        queryParameters: {'lat': lat, 'lng': lng},
      );

      return List<String>.from(response.data['zones'] ?? const []);
    } catch (_) {
      return const [];
    }
  }
}

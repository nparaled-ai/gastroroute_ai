import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/api/api_client.dart';

/// Puntos de interés de nuestra base de datos, para elegirlos al generar.
///
/// Es distinto de los "puntos obligatorios" que el motero escribe a mano: de
/// estos sabemos el id, las coordenadas exactas y la categoría, así que entran
/// en la ruta sin que nadie tenga que adivinar dónde están.
class PoiService {
  /// POIs alrededor del origen que CABEN en la distancia pedida.
  ///
  /// El radio lo decide el servidor a partir de [km]: si pides 100 km solo te
  /// ofrece los de 25 km a la redonda. Así no puedes elegir un punto que
  /// reviente tu ruta.
  static Future<Map<String, dynamic>> nearby({
    required String origin,
    String? destination,
    int? km,
    bool circular = true,
    int? radiusKm,
    String? category,
    String? query,
  }) async {
    try {
      final response = await ApiClient.dio.get(
        '/rider/pois/nearby',
        queryParameters: {
          'origin': origin,
          if (destination != null && destination.isNotEmpty)
            'destination': destination,
          if (km != null) 'km': km,
          'circular': circular ? 1 : 0,
          if (radiusKm != null) 'radius_km': radiusKm,
          if (category != null) 'category': category,
          if (query != null && query.isNotEmpty) 'q': query,
        },
      );

      return {
        'pois': List<Map<String, dynamic>>.from(response.data['pois'] ?? []),
        'categories':
            List<Map<String, dynamic>>.from(response.data['categories'] ?? []),
        'radius_km': response.data['radius_km'],
        // El que le toca a la ruta, sin contar lo que el motero haya elegido.
        'base_radius_km': response.data['base_radius_km'],
        // Hasta dónde puede abrirlo: en el corredor depende de lo largo que
        // sea el viaje.
        'max_radius_km': response.data['max_radius_km'],
        // 'ring' en circulares, 'corridor' en rutas con destino.
        'mode': response.data['mode'],
      };
    } on DioException catch (e) {
      return {'error': e.response?.data?['message'] ?? 'errors.connection'.tr()};
    } catch (_) {
      return {'error': 'errors.connection'.tr()};
    }
  }

  /// El mismo conjunto de puntos, en un mapa, numerados igual que la lista.
  ///
  /// [selected] se pinta en naranja, igual que en la lista.
  static Future<Uint8List?> nearbyMap({
    required String origin,
    String? destination,
    int? km,
    bool circular = true,
    int? radiusKm,
    String? category,
    String? query,
    List<int> selected = const [],
  }) async {
    try {
      final response = await ApiClient.dio.get<List<int>>(
        '/rider/pois/nearby/map',
        queryParameters: {
          'origin': origin,
          if (destination != null && destination.isNotEmpty)
            'destination': destination,
          if (km != null) 'km': km,
          'circular': circular ? 1 : 0,
          if (radiusKm != null) 'radius_km': radiusKm,
          if (category != null) 'category': category,
          if (query != null && query.isNotEmpty) 'q': query,
          if (selected.isNotEmpty) 'selected[]': selected,
        },
        options: Options(responseType: ResponseType.bytes),
      );

      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }
}

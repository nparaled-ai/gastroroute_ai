import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// Elegir un punto en el mapa: el sitio exacto del que se sale o al que se va.
///
/// Escribir la dirección no basta cuando la salida de una quedada es "la
/// gasolinera de la salida del pueblo" o "el bar del cruce": el texto acaba
/// geocodificado en el centro de la localidad, y la detección de salida trabaja
/// con un radio de 1 km alrededor del origen. Aquí la coordenada es la que el
/// motero ha puesto, sin interpretaciones.
///
/// El pin NO se arrastra: está clavado en el centro y lo que se mueve es el
/// mapa. Con un dedo gordo sobre un marcador pequeño, arrastrar falla; mover el
/// mapa bajo una mira fija acierta siempre, y es como lo hacen las apps que el
/// motero ya usa.
class MapPointPickerScreen extends StatefulWidget {
  /// Qué se está eligiendo, para el título: punto de salida o destino.
  final String title;

  /// Dónde abrir el mapa. Si no hay nada, se usa la posición del motero.
  final LatLng? initial;

  const MapPointPickerScreen({super.key, required this.title, this.initial});

  @override
  State<MapPointPickerScreen> createState() => _MapPointPickerScreenState();
}

class _MapPointPickerScreenState extends State<MapPointPickerScreen> {
  /// Zaragoza. Solo se usa si no hay punto previo y el GPS no contesta: un
  /// mapa centrado en el océano a escala de continente no es un punto de
  /// partida, es una pantalla en blanco.
  static const _fallback = LatLng(41.6488, -0.8891);

  GoogleMapController? _map;

  late LatLng _center = widget.initial ?? _fallback;

  /// Cómo se llama el punto que hay ahora bajo la mira.
  String? _place;

  /// La dirección completa, debajo y en pequeño.
  ///
  /// Va aparte del nombre a propósito: el nombre es lo que se guarda con la
  /// ruta y tiene que ser corto, pero para saber si has puesto el pin en la
  /// gasolinera correcta hace falta la calle y el número.
  String? _address;

  /// Se consulta el nombre mientras el motero mira: si tuviera que esperar al
  /// confirmar, no sabría qué está eligiendo hasta después de elegirlo.
  bool _naming = false;

  /// Para descartar respuestas de consultas viejas: el mapa se mueve más
  /// deprisa que la red, y sin esto el nombre que acaba en pantalla es el de
  /// la última respuesta en llegar, no el del punto actual.
  int _lookup = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) {
      _goToMyLocation(animate: false);
    } else {
      _nameCenter();
    }
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation({bool animate = true}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _nameCenter();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;

      final target = LatLng(position.latitude, position.longitude);
      setState(() => _center = target);

      if (animate) {
        await _map?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
      } else {
        await _map?.moveCamera(CameraUpdate.newLatLngZoom(target, 15));
      }
      _nameCenter();
    } catch (_) {
      _nameCenter();
    }
  }

  /// Cómo se llama lo que hay bajo la mira.
  ///
  /// Va por `/location/search?reverse=1`, que usa Photon y Nominatim: gratis,
  /// y es el mismo camino que ya usa el resto de la app para esto.
  Future<void> _nameCenter() async {
    final id = ++_lookup;
    setState(() => _naming = true);

    try {
      final response = await ApiClient.dio.get('/location/search',
          queryParameters: {
            'q': '${_center.latitude},${_center.longitude}',
            'reverse': '1',
            'lang': context.locale.languageCode,
          });

      if (!mounted || id != _lookup) return;

      final data = response.data as List? ?? [];
      setState(() {
        _naming = false;
        _place = data.isEmpty ? null : data.first['description'] as String?;
        _address = data.isEmpty ? null : data.first['address'] as String?;
      });
    } catch (_) {
      if (!mounted || id != _lookup) return;
      setState(() {
        _naming = false;
        _place = null;
        _address = null;
      });
    }
  }

  /// Siempre se devuelven las coordenadas, aunque no se haya podido poner
  /// nombre al sitio. El punto es el dato que importa; el nombre solo sirve
  /// para que el motero lo reconozca en la lista.
  void _confirm() {
    Navigator.pop(context, {
      'description': _place ?? _coordsText,
      'lat': _center.latitude,
      'lng': _center.longitude,
    });
  }

  String get _coordsText =>
      '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: Text(widget.title,
            style: const TextStyle(
                color: AppColors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'map_picker.my_location'.tr(),
            icon: const Icon(Icons.my_location, color: AppColors.cyan),
            onPressed: _goToMyLocation,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: _center, zoom: 14),
                  onMapCreated: (c) => _map = c,
                  // El nombre se pide al PARAR, no mientras se arrastra: una
                  // consulta por fotograma sería inútil y cara.
                  onCameraMove: (position) => _center = position.target,
                  onCameraIdle: _nameCenter,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),

                // La mira. Va un poco por encima del centro geométrico porque
                // la punta del pin es lo que señala, no su centro.
                const IgnorePointer(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 34),
                    child: Icon(Icons.location_on,
                        color: AppColors.orange, size: 44),
                  ),
                ),
              ],
            ),
          ),

          Container(
            width: double.infinity,
            color: AppColors.surface,
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('map_picker.hint'.tr(),
                    style:
                        const TextStyle(color: AppColors.grey, fontSize: 12)),
                const SizedBox(height: 4),
                // Alto fijo: sin él, la tarjeta crece y encoge con cada
                // dirección y el botón de confirmar se mueve bajo el dedo.
                SizedBox(
                  height: 46,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(Icons.place_outlined,
                            color: AppColors.grey, size: 17),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _naming
                            ? Text('map_picker.naming'.tr(),
                                style: const TextStyle(
                                    color: AppColors.greyText, fontSize: 13))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _place ?? _coordsText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _address ?? _coordsText,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.grey,
                                        fontSize: 12,
                                        height: 1.25),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('map_picker.confirm'.tr(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

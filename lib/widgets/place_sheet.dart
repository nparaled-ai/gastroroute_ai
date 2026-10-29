import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../core/api/api_client.dart';
import '../core/theme/app_theme.dart';
import '../features/rider/screens/map_point_picker_screen.dart';

class PlaceSheet extends StatefulWidget {
  final String title;

  /// El punto que ya tenía este campo, para abrir el mapa ahí.
  final LatLng? initial;

  const PlaceSheet({super.key, required this.title, this.initial});

  @override
  State<PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<PlaceSheet> {
  final _controller = TextEditingController();

  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 3) return;
    setState(() => _loading = true);

    try {
      // poi=1 para que devuelva también gasolineras y bares: en una ruta en
      // grupo se queda en un sitio concreto, no en "Jaca".
      final response = await ApiClient.dio.get('/location/search',
          queryParameters: {'q': query, 'lang': 'es', 'poi': '1'});

      if (!mounted) return;
      setState(() {
        _loading = false;
        _results = List<Map<String, dynamic>>.from(
            (response.data as List? ?? []).map((p) => {
                  'description': p['description'],
                  'address': p['address'],
                  'lat': p['lat'],
                  'lng': p['lng'],
                }));
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useMyLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      final response = await ApiClient.dio.get('/location/search',
          queryParameters: {
            'q': '${position.latitude},${position.longitude}',
            'reverse': '1',
            'lang': 'es',
          });

      final data = response.data as List? ?? [];
      if (!mounted || data.isEmpty) return;

      // Las coordenadas viajan con el nombre: son las del GPS, exactas, y si
      // solo se mandara el texto el servidor volvería a geocodificarlo y
      // acabaríamos en el centro de la localidad.
      Navigator.pop(context, {
        'description': data.first['description'],
        'lat': position.latitude,
        'lng': position.longitude,
      });
    } catch (_) {}
  }

  /// Abrir el mapa para poner el punto a dedo.
  ///
  /// Se abre donde esté el punto que ya tuviera, si lo tenía: afinar "la
  /// gasolinera de Sariñena" es lo normal, y empezar cada vez desde el GPS
  /// obligaría a buscar el sitio otra vez.
  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => MapPointPickerScreen(
          title: widget.title,
          initial: widget.initial,
        ),
      ),
    );

    if (!mounted || result == null) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),

            ListTile(
              leading: const Icon(Icons.my_location, color: AppColors.cyan),
              title: Text('planner.use_my_location'.tr(),
                  style: const TextStyle(color: AppColors.cyan, fontSize: 14)),
              onTap: _useMyLocation,
            ),

            // El tercer camino, y el único que da el punto EXACTO: escribir
            // una dirección deja que la geocodificación decida, y para "la
            // gasolinera del cruce" eso acaba en el centro del pueblo.
            ListTile(
              leading: const Icon(Icons.map_outlined, color: AppColors.cyan),
              title: Text('map_picker.open'.tr(),
                  style: const TextStyle(color: AppColors.cyan, fontSize: 14)),
              subtitle: Text('map_picker.open_hint'.tr(),
                  style:
                      const TextStyle(color: AppColors.grey, fontSize: 11)),
              onTap: _pickOnMap,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onSubmitted: _search,
                onChanged: (q) {
                  if (q.trim().length >= 3) _search(q);
                },
                style: const TextStyle(color: AppColors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'planner.search_place'.tr(),
                  hintStyle:
                      const TextStyle(color: AppColors.grey, fontSize: 13),
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.grey, size: 19),
                  filled: true,
                  fillColor: AppColors.background,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: AppColors.orange),
              ),

            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                children: _results
                    .map((r) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined,
                              color: AppColors.grey, size: 18),
                          title: Text('${r['description']}',
                              style: const TextStyle(
                                  color: AppColors.white, fontSize: 13)),
                          // Dos sitios pueden llamarse igual en el mismo
                          // pueblo; la dirección es lo que los distingue.
                          subtitle: r['address'] == null
                              ? null
                              : Text('${r['address']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.grey, fontSize: 12)),
                          onTap: () => Navigator.pop(context, r),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

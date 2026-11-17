import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/polyline_codec.dart';

/// Mapa con dos trazados superpuestos para compararlos: el de la ruta que se revisa (naranja)
/// y el de una ruta del catálogo (azul). Se encuadra solo sobre los dos.
class RouteOverlayMap extends StatefulWidget {
  final String? mine;
  final String? other;
  final double height;

  const RouteOverlayMap({super.key, required this.mine, required this.other, this.height = 260});

  @override
  State<RouteOverlayMap> createState() => _RouteOverlayMapState();
}

class _RouteOverlayMapState extends State<RouteOverlayMap> {
  GoogleMapController? _map;

  List<LatLng> _decode(String? s) => (s == null || s.isEmpty) ? const [] : decodePolyline(s);

  Set<Polyline> get _lines {
    final a = _decode(widget.mine);
    final b = _decode(widget.other);
    return {
      // La del catálogo debajo (más ancha) y la de la ruta revisada encima: donde coinciden se ve.
      if (b.length > 1)
        Polyline(polylineId: const PolylineId('other'), points: b, color: AppColors.cyan, width: 8),
      if (a.length > 1)
        Polyline(polylineId: const PolylineId('mine'), points: a, color: AppColors.orange, width: 4),
    };
  }

  void _frame() {
    final all = [..._decode(widget.mine), ..._decode(widget.other)];
    if (_map == null || all.isEmpty) return;
    var minLat = all.first.latitude, maxLat = minLat, minLng = all.first.longitude, maxLng = minLng;
    for (final p in all) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _map!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      40,
    ));
  }

  @override
  void didUpdateWidget(covariant RouteOverlayMap old) {
    super.didUpdateWidget(old);
    if (old.other != widget.other || old.mine != widget.mine) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _frame());
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = _decode(widget.mine).isNotEmpty
        ? _decode(widget.mine).first
        : (_decode(widget.other).isNotEmpty ? _decode(widget.other).first : const LatLng(40.4, -3.7));

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: first, zoom: 8),
          onMapCreated: (c) {
            _map = c;
            Future.delayed(const Duration(milliseconds: 300), _frame);
          },
          polylines: _lines,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
        ),
      ),
    );
  }
}

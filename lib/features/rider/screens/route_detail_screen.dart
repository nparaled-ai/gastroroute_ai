import 'dart:async';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../widgets/rider_avatar.dart';
import '../../../widgets/route_waypoints_view.dart';
import '../../../widgets/route_map_image.dart';
import '../providers/route_service.dart';
import '../providers/route_share_service.dart';
import '../providers/friendship_service.dart';
import '../providers/route_tracking_service.dart';
import '../../../core/services/route_tracking_manager.dart';
import '../../../core/services/battery_optimization.dart';

class RouteDetailScreen extends StatefulWidget {
  final int routeId;
  const RouteDetailScreen({super.key, required this.routeId});

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  Map<String, dynamic>? _route;
  List<Map<String, dynamic>> _confirmed = [];
  List<Map<String, dynamic>> _pending   = [];
  List<Map<String, dynamic>> _declined  = [];
  int  _count      = 0;
  bool _loading    = true;
  bool _isOwner    = false;
  bool _isJoined   = false;
  bool _isDeclined = false;
  bool _joining    = false;
  bool _refreshingWeather = false;
  bool _startingTracking  = false;

  /// Para no repetir la oferta de empezar cada vez que se recarga la ruta.
  bool _startOffered = false;

  /// Ventana alrededor de la hora de salida en la que se ofrece grabar.
  ///
  /// Generosa por detrás: es normal salir con retraso, y el motero que abre la
  /// app una hora tarde sigue queriendo grabar su ruta.
  static const _startWindowBefore = Duration(minutes: 30);
  static const _startWindowAfter  = Duration(hours: 2);

  /// Distancia máxima al origen para dar por hecho que se está saliendo.
  ///
  /// Amplia a propósito: el punto de salida suele ser un bar o una gasolinera
  /// cercana, no la coordenada exacta que puso la IA.
  static const double _startNearOriginM = 1000;
  bool _publishing = false;
  Map<String, dynamic>? _currentWeather;

  /// Para repintar los botones cuando arranca o termina una grabación.
  ///
  /// La ruta puede finalizarse o descartarse desde otra pantalla, y entonces
  /// esta tiene que volver a ofrecer "Iniciar ruta" sin recargar nada.
  StreamSubscription<TrackingState>? _trackingSub;

  @override
  void initState() {
    super.initState();
    _loadRoute();

    _trackingSub = RouteTrackingManager.instance.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _trackingSub?.cancel();
    super.dispose();
  }

  Future<void> _downloadGpx() async {
    final routeId = _route?['id'];
    if (routeId == null) return;
    try {
      final dir      = await getApplicationDocumentsDirectory();
      final filename = '${(_route?['title'] ?? 'ruta').toString().replaceAll(RegExp(r'[^\w]'), '_')}.gpx';
      final savePath = '${dir.path}/$filename';

      await ApiClient.dio.download(
        '/rider/routes/$routeId/gpx',
        savePath,
        options: Options(responseType: ResponseType.bytes),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('route_detail.gpx_saved'.tr(namedArgs: {'file': filename})),
        backgroundColor: AppColors.cyan,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('route_detail.gpx_error'.tr()),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _loadRoute() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      RouteShareService.getRoute(widget.routeId),
      RouteShareService.getParticipants(widget.routeId),
    ]);
    if (!mounted) return;
    setState(() {
      _route      = results[0]['route'];
      _isOwner    = results[1]['is_owner']   ?? results[0]['route']?['is_owner'] ?? false;
      _isJoined   = results[1]['is_joined']  ?? false;
      _isDeclined = results[1]['is_declined'] ?? false;
      _count      = results[1]['count']      ?? 0;
      _confirmed  = List<Map<String, dynamic>>.from(results[1]['confirmed'] ?? []);
      _declined   = List<Map<String, dynamic>>.from(results[1]['declined']  ?? []);
      _pending    = List<Map<String, dynamic>>.from(results[1]['pending']   ?? []);
      _loading    = false;
    });

    _offerStartIfDeparting();
  }

  /// Si el motero está en el origen y a la hora, le ofrece empezar a grabar.
  ///
  /// Es la mitad no-GPS del arranque automático: detectar la salida con la app
  /// cerrada exigiría ubicación en segundo plano, que se descartó por la
  /// fricción en las tiendas. Esto cubre el caso real —el motero abre la app,
  /// o llega aquí desde el aviso de salida— sin pedir ningún permiso nuevo.
  ///
  /// Se PREGUNTA, no se arranca solo: empezar a grabar la ubicación sin que
  /// nadie lo haya pedido sorprende, y es de las cosas que acaban en malas
  /// reseñas. El diálogo deja «Empezar» como acción principal, así que sigue
  /// siendo un solo toque.
  Future<void> _offerStartIfDeparting() async {
    if (_startOffered || !mounted || _route == null) return;

    // Ya se está grabando algo: no hay nada que ofrecer.
    if (RouteTrackingManager.instance.isTracking) return;

    // Ni tampoco si esta ruta ya se rodó.
    if (_hasBeenRidden) return;

    // Solo tiene sentido en rutas que el motero va a hacer.
    if (!_isOwner && !_isJoined) return;

    final departure = _departureOf(_route!);
    if (departure == null) return;

    final now = DateTime.now();
    if (now.isBefore(departure.subtract(_startWindowBefore)) ||
        now.isAfter(departure.add(_startWindowAfter))) {
      return;
    }

    // El permiso NO se pide aquí: si el motero aún no lo ha dado, preguntarle
    // por sorpresa al abrir una ruta es peor que no ofrecer nada. Se le pedirá
    // cuando pulse «Iniciar ruta».
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return;
    }

    final originLat = _coord(_route!['origin_lat']);
    final originLng = _coord(_route!['origin_lng']);
    if (originLat == null || originLng == null) return;

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return; // Sin posición fiable, no se ofrece nada.
    }

    if (!mounted) return;

    // Se vuelven a comprobar las condiciones DESPUÉS de esperar al GPS.
    //
    // Entre la comprobación de arriba y este punto pasan hasta 8 segundos, y
    // en ese hueco el motero puede haber pulsado ya «Iniciar ruta». Ocurrió:
    // el diálogo salía encima de «Ruta en curso» y, al aceptarlo, arrancaba
    // una SEGUNDA grabación sobre la que ya estaba en marcha.
    //
    // La comprobación de ModalRoute evita además que el diálogo aparezca
    // sobre otra pantalla: showDialog lo pinta por encima de todo aunque esta
    // ya no sea la pantalla visible.
    if (_startOffered ||
        RouteTrackingManager.instance.isTracking ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    final metres = RouteTrackingManager.haversine(
      position.latitude, position.longitude, originLat, originLng,
    );
    if (metres > _startNearOriginM) return;

    _startOffered = true;

    final start = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('tracking.departing_title'.tr(),
            style: const TextStyle(color: AppColors.white)),
        content: Text('tracking.departing_body'.tr(),
            style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('tracking.not_now'.tr(),
                style: const TextStyle(color: AppColors.grey)),
          ),
          ElevatedButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
            child: Text('tracking.start_now'.tr(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (start == true && mounted) await _startTracking();
  }

  /// Combina `departure_date` y `departure_time`, que llegan como texto.
  static DateTime? _departureOf(Map<String, dynamic> route) {
    final date = route['departure_date']?.toString();
    if (date == null || date.isEmpty) return null;

    final day = DateTime.tryParse(date);
    if (day == null) return null;

    final parts = (route['departure_time']?.toString() ?? '').split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  Future<void> _repeatRoute() async {
    String? date;
    String time = '09:00';

    await showDialog(
      context: context,
      builder: (ctx) {
        final dateCtrl = TextEditingController();
        final timeCtrl = TextEditingController(text: '09:00');
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              const Icon(Icons.replay, color: AppColors.cyan, size: 22),
              const SizedBox(width: 8),
              Text('repeat.title'.tr(),
                  style: const TextStyle(color: AppColors.white, fontSize: 18)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('repeat.pick_datetime'.tr(),
                  style: const TextStyle(color: AppColors.grey, fontSize: 13)),
              const SizedBox(height: 20),
              // Fecha
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    date = picked.toIso8601String().split('T')[0];
                    dateCtrl.text = date!;
                    setS(() {});
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: dateCtrl.text.isEmpty
                        ? AppColors.greyDark : AppColors.cyan),
                  ),
                  child: Row(children: [
                    const Icon(Icons.event, color: AppColors.cyan, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      dateCtrl.text.isEmpty ? 'repeat.pick_date'.tr() : dateCtrl.text,
                      style: TextStyle(
                        color: dateCtrl.text.isEmpty ? AppColors.grey : AppColors.cyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              // Hora
              GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: const TimeOfDay(hour: 9, minute: 0),
                  );
                  if (picked != null) {
                    time = '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}';
                    timeCtrl.text = time;
                    setS(() {});
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.greyDark),
                  ),
                  child: Row(children: [
                    const Icon(Icons.schedule, color: AppColors.orange, size: 18),
                    const SizedBox(width: 10),
                    Text(timeCtrl.text,
                        style: const TextStyle(
                            color: AppColors.orange, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('common.cancel'.tr(),
                    style: const TextStyle(color: AppColors.grey)),
              ),
              ElevatedButton(
                onPressed: date == null ? null : () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
                child: Text('common.save'.tr(),
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );

    if (date == null || !mounted) return;

    // Preparar datos de la copia
    final saveData = Map<String, dynamic>.from(_route!);
    saveData['departure_date'] = date;
    saveData['departure_time'] = time;
    saveData.remove('id');
    saveData.remove('status');
    saveData.remove('visibility');
    saveData.remove('created_at');
    saveData.remove('updated_at');
    saveData.remove('gpx_temp_path');

    // Actualizar clima para la nueva fecha
    Map<String, dynamic>? freshWeather;
    final lat = _route!['origin_lat'];
    final lng = _route!['origin_lng'];
    if (lat != null && lng != null) {
      final weatherResult = await RouteService.refreshWeather(
        double.tryParse(lat.toString()) ?? lat,
        double.tryParse(lng.toString()) ?? lng,
        date: date,
      );
      freshWeather = weatherResult['weather'];
    }
    if (freshWeather != null) {
      saveData['weather_summary'] = {'current': freshWeather};
    } else {
      saveData.remove('weather_summary');
    }

    // Navegar a la pantalla de resultado igual que una ruta nueva
    if (!mounted) return;
    context.push('/rider/route-result', extra: {
      'route': saveData,
      'weather': freshWeather,
      'ai_summary': _route!['ai_summary'],
      'form_data': {},
      '_save_data': saveData,
    });
  }

  Future<void> _dismiss() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('route_detail.dismiss_title'.tr(),
            style: const TextStyle(color: AppColors.white)),
        content: Text('route_detail.dismiss_body'.tr(),
            style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('route_detail.dismiss_confirm'.tr(),
                  style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    final result = await RouteShareService.dismiss(widget.routeId);
    if (!mounted) return;
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
    } else {
      context.pop(); // volver a la lista
      // my_routes_screen recarga al volver gracias al await en onTap
    }
  }

  Future<void> _decline() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('route_detail.decline_title'.tr(),
            style: const TextStyle(color: AppColors.white)),
        content: Text('route_detail.decline_body'.tr(),
            style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('route_detail.decline_title'.tr(),
                  style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    final result = await RouteShareService.decline(widget.routeId);
    if (!mounted) return;
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('route_detail.declined_done'.tr()),
            backgroundColor: AppColors.grey));
      _loadRoute();
    }
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    final result = await RouteShareService.join(widget.routeId);
    if (!mounted) return;
    setState(() => _joining = false);
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'route_detail.joined'.tr()),
            backgroundColor: Colors.green));
      _loadRoute();
    }
  }

  Future<void> _leave() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('route_detail.leave_title'.tr(),
            style: const TextStyle(color: AppColors.white)),
        content: Text('route_detail.leave_body'.tr(),
            style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('route_detail.leave_confirm'.tr(),
                  style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    await RouteShareService.leave(widget.routeId);
    _loadRoute();
  }

  Future<void> _openMaps() async {
    final uri = _mapsUri();

    // Antes era `if (url == null) return;`: el boton no fallaba, simplemente
    // no hacia nada. Y `google_maps_url` esta a NULL en todas las rutas que no
    // pasaron por getDirections, asi que no hacer nada era lo habitual.
    if (uri == null || !await canLaunchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('route_detail.maps_unavailable'.tr()),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// URL de Google Maps para esta ruta.
  ///
  /// Se prefiere la que guardó el servidor, porque lleva los `place_id` y Maps
  /// clava los sitios. Pero solo existe en las rutas que pasaron por
  /// `GoogleMapsService::getDirections`; las demás la tienen a NULL. En ese
  /// caso se construye aquí con las coordenadas, que siempre están.
  Uri? _mapsUri() {
    final stored = _route?['google_maps_url'];
    if (stored is String && stored.isNotEmpty) return Uri.tryParse(stored);

    final oLat = _coord(_route?['origin_lat']);
    final oLng = _coord(_route?['origin_lng']);
    if (oLat == null || oLng == null) return null;

    // En las circulares no hay destino: se vuelve al origen.
    final dLat = _coord(_route?['destination_lat']) ?? oLat;
    final dLng = _coord(_route?['destination_lng']) ?? oLng;

    // El esquema de URL de Maps admite 9 puntos intermedios como máximo.
    final wps = <String>[];
    for (final wp in (_route?['waypoints'] as List? ?? const [])) {
      if (wp is! Map) continue;
      final lat = _coord(wp['lat']);
      final lng = _coord(wp['lng']);
      if (lat == null || lng == null) continue;
      wps.add('$lat,$lng');
      if (wps.length == 9) break;
    }

    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=$oLat,$oLng'
      '&destination=$dLat,$dLng'
      '${wps.isEmpty ? '' : '&waypoints=${wps.join('|')}'}'
      '&travelmode=driving',
    );
  }

  /// Arranca el tracking GPS de esta ruta y abre la pantalla "Ruta en curso".
  Future<void> _startTracking() async {
    if (_route == null) return;
    setState(() => _startingTracking = true);

    // Sin permiso de ubicación no hay nada que grabar.
    if (!await RouteTrackingManager.ensurePermission()) {
      if (!mounted) return;
      setState(() => _startingTracking = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('tracking.no_permission'.tr()),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    final result = await RouteTrackingService.start(_route!['id'] as int);

    if (!mounted) return;

    if (result['error'] != null) {
      setState(() => _startingTracking = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['error']),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    final tracking = result['tracking'] as Map<String, dynamic>;

    // OJO: las coordenadas llegan como TEXTO, no como número — el cast
    // decimal:7 de Eloquent las serializa así. Un `as num?` aquí revienta.
    //
    // Punto donde acaba la ruta, para detectar la llegada. En las circulares
    // no hay destino: se vuelve al origen.
    final endLat = _coord(_route!['destination_lat']) ?? _coord(_route!['origin_lat']);
    final endLng = _coord(_route!['destination_lng']) ?? _coord(_route!['origin_lng']);

    // La ruta se mete en los datos del tracking para que la barra inferior
    // pueda abrir la pantalla de ruta en curso sin pedir nada al servidor:
    // esa barra se pulsa en mitad de la sierra, sin cobertura.
    final trackingData = <String, dynamic>{
      ...tracking,
      'route': tracking['route'] ?? _route,
    };

    await RouteTrackingManager.instance.start(
      trackingId: tracking['id'] as int,
      routeId: _route!['id'] as int,
      data: trackingData,
      targetLat: endLat,
      targetLng: endLng,
    );

    if (!mounted) return;
    setState(() => _startingTracking = false);

    // Aviso del ahorro de batería: una sola vez, y solo si hace falta. No
    // bloquea — la ruta ya está grabándose.
    unawaited(BatteryOptimization.warnIfNeeded(context));

    context.push('/rider/tracking', extra: trackingData);
  }

  /// Coordenada del servidor a double, venga como número o como texto.
  static double? _coord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<void> _refreshWeather() async {
    final lat  = _route?['origin_lat'];
    final lng  = _route?['origin_lng'];
    final date = _route?['departure_date'];
    if (lat == null || lng == null) return;
    setState(() => _refreshingWeather = true);
    final result = await RouteService.refreshWeather(lat, lng, date: date);
    if (!mounted) return;
    setState(() {
      _refreshingWeather = false;
      if (result['weather'] != null) _currentWeather = result['weather'];
    });
    if (result['weather']?['is_forecast'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('route_detail.weather_forecast_notice'.tr()),
        backgroundColor: AppColors.cyan,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _showShareDialog({bool friendsOnly = false}) {
    final excludeIds = [
      ..._pending.map((p) => p['user_id'] as int),
      ..._confirmed.map((p) => p['user_id'] as int),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ShareBottomSheet(
        onShareFriends: (ids) => _shareWithFriends(ids),
        onSharePublic:  () => _sharePublic(),
        excludeUserIds: friendsOnly ? excludeIds : [],
        friendsOnly:    friendsOnly,
      ),
    );
  }

  Future<void> _shareWithFriends(List<int> friendIds) async {
    setState(() => _publishing = true);
    final result = await RouteShareService.share(
        _route!['id'], visibility: 'friends', friendIds: friendIds);
    if (!mounted) return;
    setState(() => _publishing = false);
    _handleShareResult(result);
  }

  Future<void> _sharePublic() async {
    setState(() => _publishing = true);
    final result = await RouteShareService.share(_route!['id'], visibility: 'public');
    if (!mounted) return;
    setState(() => _publishing = false);
    _handleShareResult(result);
  }

  void _handleShareResult(Map<String, dynamic> result) {
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'route_detail.shared'.tr()),
            backgroundColor: Colors.green));
      setState(() { _route = null; _loading = true; });
      _loadRoute();
    }
  }

  Map<String, dynamic>? get _weather {
    if (_currentWeather != null) return _currentWeather;
    // Primero intentar campo directo 'weather' (devuelto por /view)
    if (_route?['weather'] != null) return Map<String, dynamic>.from(_route!['weather']);
    // Fallback: weather_summary (formato antiguo)
    final ws = _route?['weather_summary'];
    if (ws == null) return null;
    if (ws is Map) return Map<String, dynamic>.from(ws['current'] ?? ws);
    return null;
  }

  int? get _fuelRangeKm => _route?['fuel_range_km'] as int?;

  // Había aquí un `_isFuture` con el mismo fallo que `_isPast`: comparaba la
  // fecha a las 00:00 contra el instante actual, así que la ruta de hoy no era
  // ni futura ni presente. Se ha quitado; donde se usaba ahora va `!_isPast`.

  /// ¿La fecha de la ruta ya pasó?
  ///
  /// Se compara por DÍA, no por instante. `departure_date` es solo la fecha
  /// ("2026-10-10"), así que se parsea como las 00:00 de ese día: comparar eso
  /// con `DateTime.now()` hacía que la ruta de HOY contara como pasada desde
  /// que amanecía. Dos efectos, y el segundo era el gordo:
  ///  - "Repetir" aparecía en la ruta de hoy todo el día, incluso rodándola.
  ///  - El clima está detrás de `!_isPast`, así que la ruta de hoy no enseñaba
  ///    el tiempo. El día que más importa.
  bool get _isPast {
    final raw = _route?['departure_date'];
    if (raw == null) return false;

    final date = DateTime.tryParse(raw.toString());
    if (date == null) return false;

    final now = DateTime.now();
    return DateTime(date.year, date.month, date.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }

  /// ¿Se puede reprogramar esta ruta?
  ///
  /// Tiene sentido en dos casos: la rodaste y quieres volver a hacerla, o se
  /// te pasó la fecha y no saliste. En una ruta que aún está por delante no
  /// aporta nada, porque ya la tienes programada.
  bool get _canRepeat => _isOwner && (_isPast || _hasBeenRidden);

  /// La ruta ya tiene alguna salida grabada.
  bool get _hasBeenRidden => _route?['has_been_ridden'] == true;

  /// ¿Es hoy el día de la ruta?
  bool get _isToday {
    final raw = _route?['departure_date'];
    if (raw == null) return false;

    final date = DateTime.tryParse(raw.toString());
    if (date == null) return false;

    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// ¿Se puede arrancar el tracking de esta ruta?
  ///
  /// Solo el día previsto, y solo si es tuya o te has unido. En una ruta que
  /// es dentro de tres semanas no tiene sentido, y además arrancarla guardaría
  /// una salida con la fecha de hoy: la ruta pasaría a Rodadas y perderías la
  /// planificación sin quererlo. En las pasadas tampoco, porque para eso está
  /// Repetir, que crea una copia con fecha nueva.
  /// Y que no se haya rodado ya.
  ///
  /// Sin esa condición, una ruta ya hecha seguía ofreciendo "Iniciar ruta" el
  /// resto del día: se entraba desde el aviso de salida, que sigue en la
  /// bandeja, y la app invitaba a grabarla otra vez. Para volver a hacerla
  /// está "Repetir", que crea una ruta nueva con su fecha.
  ///
  /// Las descartadas no cuentan como rodadas, así que si el motero descartó
  /// una grabación sí puede volver a empezar.
  /// Y que no haya ya una grabación en marcha, de esta ruta o de otra.
  ///
  /// Sin esta condición el botón "Iniciar ruta" seguía ahí con una ruta
  /// grabándose, y pulsarlo era destructivo sin avisar: el servidor marca como
  /// descartado el tracking anterior al abrir uno nuevo
  /// (`RouteTrackingController::start`). O sea que entrar en una ruta de
  /// Previstas y pulsar por curiosidad te tiraba la ruta que estabas rodando.
  bool get _canStartTracking =>
      _isToday &&
      (_isOwner || _isJoined) &&
      !_hasBeenRidden &&
      !RouteTrackingManager.instance.isTracking;

  /// Se está grabando precisamente esta ruta.
  bool get _isTrackingThisRoute =>
      RouteTrackingManager.instance.isTracking &&
      _route != null &&
      RouteTrackingManager.instance.routeId == _route!['id'];

  /// Se está grabando otra ruta distinta de esta.
  bool get _isTrackingOtherRoute =>
      RouteTrackingManager.instance.isTracking && !_isTrackingThisRoute;

  /// Abre la pantalla de la ruta que se está grabando.
  void _openTracking() {
    final data = RouteTrackingManager.instance.data;
    if (data != null) {
      context.push('/rider/tracking', extra: data);
      return;
    }

    // Sin los datos guardados no se puede pintar esa pantalla. Es raro, pero
    // mejor decirlo que dejar un botón que no hace nada.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('tracking.resume_failed'.tr()),
      backgroundColor: AppColors.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(_route?['title'] ?? 'Ruta',
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.grey),
              onPressed: _loadRoute),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _route == null
              ? Center(
                  child: Text('route_detail.not_found'.tr(),
                      style: const TextStyle(color: AppColors.grey)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                    // ── Header ────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          AppColors.orange.withOpacity(0.2),
                          AppColors.surface,
                        ]),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.orange.withOpacity(0.3)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_route!['title'] ?? '',
                            style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        if (_route!['description'] != null) ...[
                          const SizedBox(height: 6),
                          Text(_route!['description'],
                              style: const TextStyle(
                                  color: AppColors.grey, fontSize: 13, height: 1.5)),
                        ],
                        const SizedBox(height: 12),
                        Row(children: [
                          _Chip(Icons.route, '${_route!['distance_km']} km',
                              AppColors.orange),
                          const SizedBox(width: 8),
                          _Chip(
                              Icons.access_time,
                              '${((_route!['duration_minutes'] ?? 0) / 60).toStringAsFixed(1)} h',
                              AppColors.cyan),
                          const SizedBox(width: 8),
                          _Chip(Icons.terrain, _route!['difficulty'] ?? '',
                              AppColors.gold),
                        ]),
                      ]),
                    ),

                    const SizedBox(height: 16),

                    // ── Creador ───────────────────────────────────────
                    if (_route!['owner'] != null) _buildOwner(),

                    // ── Fecha/hora ────────────────────────────────────
                    if (_route!['departure_date'] != null ||
                        _route!['departure_time'] != null)
                      _buildDeparture(),

                    // ── Clima (solo si la ruta no ha pasado) ──────────
                    // En una ruta cuya fecha ya pasó, el tiempo no aporta
                    // nada: o está vacío, o son datos guardados de entonces.
                    if (!_isPast) ...[
                      if (_weather != null)
                        _buildWeather()
                      else
                        _buildWeatherUnavailable(),
                    ],

                    // ── Autonomía ─────────────────────────────────────
                    if (_fuelRangeKm != null) _buildFuel(),

                    // ── Mapa del recorrido ────────────────────────────
                    const SizedBox(height: 20),
                    RouteMapImage(
                      title: 'route_detail.route_map'.tr(),
                      loader: () => RouteService.mapImage(widget.routeId),
                    ),
                    const SizedBox(height: 20),

                    // ── Waypoints ─────────────────────────────────────
                    Text('route_detail.waypoints'.tr(),
                        style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    RouteWaypointsView(
                      route: _route!,
                      weather: _weather,
                      aiSummary: null,
                    ),

                    // ── Participantes (solo si no es privada) ─────────
                    // Amigos: todos los invitados ven todo
                    // Pública: todos ven confirmados, solo creador ve declinados
                    if (_route!['visibility'] == 'friends' ||
                        _route!['visibility'] == 'public') ...[  
                      const SizedBox(height: 8),
                      _buildParticipants(),
                    ],

                    const SizedBox(height: 20),

                    // ── Botón iniciar tracking (solo el día de la ruta) ──
                    if (_canStartTracking) ...[
                      ElevatedButton(
                        onPressed: _startingTracking ? null : _startTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_startingTracking)
                                const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                              else
                                const Icon(Icons.play_arrow,
                                    color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text('tracking.start_route'.tr(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                            ]),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Ya se está grabando ESTA ruta ─────────────────
                    // En vez de "Iniciar", que la volvería a empezar, se
                    // ofrece volver a la grabación en marcha.
                    if (_isTrackingThisRoute) ...[
                      ElevatedButton(
                        onPressed: _openTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.fiber_manual_record,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 8),
                              Text('tracking.view_in_progress'.tr(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                            ]),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Se está grabando OTRA ruta ────────────────────
                    // Aquí no se puede empezar: el servidor descartaría la
                    // que está en marcha. Se explica y se da la salida.
                    if (_isTrackingOtherRoute && _isToday && !_hasBeenRidden) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.greyDark),
                        ),
                        child: Row(children: [
                          const Icon(Icons.info_outline,
                              color: AppColors.grey, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('tracking.other_in_progress'.tr(),
                                style: const TextStyle(
                                    color: AppColors.grey,
                                    fontSize: 12,
                                    height: 1.4)),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _openTracking,
                          child: Text('tracking.view_in_progress'.tr(),
                              style: const TextStyle(color: AppColors.orange)),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Botón Google Maps ─────────────────────────────
                    ElevatedButton(
                      onPressed: _openMaps,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.map, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text('route_detail.open_maps'.tr(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ]),
                    ),

                    // ── Botón descargar GPX ───────────────────────────
                    if (_route?['source_type'] == 'gpx') ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _downloadGpx,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          side: const BorderSide(color: AppColors.cyan),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.download, color: AppColors.cyan, size: 20),
                              const SizedBox(width: 8),
                              Text('route_detail.download_gpx'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.cyan,
                                      fontWeight: FontWeight.w700)),
                            ]),
                      ),
                    ],

                    // ── Botones invitado: Apuntarme / No puedo ir / Olvidar ──
                    if (!_isOwner) ...[  
                      const SizedBox(height: 12),
                      if (_isDeclined)
                        // Ya declinó
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.grey.withOpacity(0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.cancel_outlined, color: AppColors.grey, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text('route_detail.declined_banner'.tr(),
                                style: const TextStyle(color: AppColors.grey))),
                            TextButton(
                              onPressed: _join,
                              child: Text('route_detail.change_mind'.tr(),
                                  style: const TextStyle(color: AppColors.cyan, fontSize: 12)),
                            ),
                          ]),
                        )
                      else
                        Row(children: [
                          // Botón apuntarme (si no está apuntado)
                          if (!_isJoined)
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _joining ? null : _join,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.orange,
                                  minimumSize: const Size(0, 52),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _joining
                                    ? const SizedBox(width: 20, height: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2))
                                    : Text('route_detail.join_button'.tr(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                              ),
                            ),
                          // Si está apuntado en ruta de amigos → "No puedo ir"
                          //
                          // Salvo que ya la esté rodando o la haya rodado: a
                          // esas alturas "no puedo ir" no describe nada. Ya
                          // fuiste.
                          if (_isJoined &&
                              _route!['visibility'] == 'friends' &&
                              !_isTrackingThisRoute &&
                              !_hasBeenRidden)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _decline,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 52),
                                  side: const BorderSide(color: AppColors.error),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text('route_detail.decline_title'.tr(),
                                    style: const TextStyle(
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          // "No puedo ir" para rutas de amigos no apuntado
                          if (!_isJoined && _route!['visibility'] == 'friends') ...[  
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: _decline,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 52),
                                side: const BorderSide(color: AppColors.grey),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                              ),
                              child: Text('route_detail.decline_title'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.grey, fontSize: 13)),
                            ),
                          ],
                          // "Olvidar" solo en rutas públicas no apuntado
                          if (!_isJoined && _route!['visibility'] == 'public') ...[  
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: _dismiss,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 52),
                                side: const BorderSide(color: AppColors.grey),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                              ),
                              child: const Text('Olvidar',
                                  style: TextStyle(
                                      color: AppColors.grey, fontSize: 13)),
                            ),
                          ],
                        ]),
                    ],

                    // ── Compartir (ruta propia y privada, aún por hacer) ──
                    // Lo que hace este botón es mandar INVITACIONES para
                    // unirse a la ruta. Eso solo tiene sentido en una ruta que
                    // todavía no ha ocurrido: a una que va rodando, que ya
                    // terminó o cuya fecha pasó, no se une nadie.
                    //
                    // Antes se permitía en rutas pasadas, con el criterio de
                    // que "compartir una ruta es compartir el recorrido, no la
                    // fecha". Decisión del usuario (2026-10-10): no. Enseñar
                    // el recorrido de una ruta hecha para que otros la repitan
                    // es otra cosa distinta, y tiene su propio sitio: el
                    // catálogo de rutas públicas, que está pendiente.
                    if (_isOwner &&
                        _route!['visibility'] == 'private' &&
                        !_isTrackingThisRoute &&
                        !_hasBeenRidden &&
                        !_isPast) ...[
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _publishing ? null : _showShareDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _publishing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                    const Icon(Icons.share_outlined,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text('route_detail.share_route'.tr(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                                  ]),
                      ),
                    ],

                    // ── Repetir (rodadas o no realizadas, propias) ────
                    if (_canRepeat) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _repeatRoute,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          side: const BorderSide(color: AppColors.cyan),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.replay,
                                  color: AppColors.cyan, size: 20),
                              const SizedBox(width: 8),
                              Text('repeat.button'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.cyan,
                                      fontWeight: FontWeight.w700)),
                            ]),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ]),
                ),
    );
  }

  Widget _buildOwner() {
    final owner = _route!['owner'];
    final name = '${owner['first_name'] ?? ''} ${owner['last_name'] ?? ''}'.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Creador', style: TextStyle(color: AppColors.grey, fontSize: 13)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.greyDark),
        ),
        child: Row(children: [
          RiderAvatar(
              avatarUrl: owner['avatar_url'],
              level: owner['experience_level'] ?? 'novato',
              size: 44),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isNotEmpty ? name : owner['nickname'] ?? '',
                style: const TextStyle(
                    color: AppColors.white, fontWeight: FontWeight.w700)),
            if (owner['nickname'] != null)
              Text('@${owner['nickname']}',
                  style: const TextStyle(color: AppColors.orange, fontSize: 12)),
          ])),
          if (_isOwner)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Tú',
                  style: TextStyle(
                      color: AppColors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildDeparture() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cyan.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.event, color: AppColors.cyan, size: 16),
          const SizedBox(width: 8),
          if (_route!['departure_date'] != null)
            Text(_formatDate(_route!['departure_date']),
                style: const TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          if (_route!['departure_time'] != null) ...[
            const SizedBox(width: 12),
            const Icon(Icons.schedule, color: AppColors.cyan, size: 14),
            const SizedBox(width: 4),
            Text('route_detail.departure_time'.tr(
                    namedArgs: {'time': '${_route!['departure_time']}'}),
                style: const TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildWeatherUnavailable() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyDark),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.grey, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(
          'planner.weather_forecast_notice'.tr(),
          style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4),
        )),
      ]),
    );
  }

  Widget _buildWeather() {
    final w = _weather!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.greyDark),
        ),
        child: Row(children: [
          const Icon(Icons.wb_sunny_outlined, color: AppColors.gold, size: 24),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${(w['temp'] as num?)?.toStringAsFixed(0)}°C · ${w['description'] ?? ''}',
                style: const TextStyle(
                    color: AppColors.white, fontWeight: FontWeight.w600)),
            Row(children: [
              Text(
                w['is_forecast'] == true ? 'Previsión · ' : 'Ahora · ',
                style: TextStyle(
                  color: w['is_forecast'] == true
                      ? AppColors.cyan
                      : AppColors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                w['humidity'] != null
                    ? 'Viento ${w['wind_speed']} m/s · Humedad ${w['humidity']}%'
                    : 'Viento ${w['wind_speed']} m/s',
                style: const TextStyle(color: AppColors.grey, fontSize: 11),
              ),
            ]),
          ])),
          // Botón refrescar clima: en cualquier ruta que no haya pasado.
          //
          // Estaba condicionado a `_isFuture`, que para la ruta de HOY es
          // falso (compara la fecha a las 00:00 contra ahora). Justo el día de
          // la ruta, que es cuando refrescar el tiempo sirve de algo, no había
          // botón.
          if (!_isPast)
            GestureDetector(
              onTap: _refreshingWeather ? null : _refreshWeather,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                ),
                child: _refreshingWeather
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: AppColors.cyan, strokeWidth: 2))
                    : const Icon(Icons.refresh,
                        color: AppColors.cyan, size: 18),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildFuel() {
    final dist = ((_route!['distance_km'] ?? 0) as num).toDouble();
    final needsFuel = dist > _fuelRangeKm!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: needsFuel
                  ? AppColors.error.withOpacity(0.4)
                  : AppColors.greyDark),
        ),
        child: Row(children: [
          Icon(Icons.local_gas_station,
              color: needsFuel ? AppColors.error : AppColors.grey, size: 22),
          const SizedBox(width: 12),
          Text('route_detail.fuel_range'.tr(namedArgs: {'km': '$_fuelRangeKm'}),
              style: const TextStyle(
                  color: AppColors.white, fontWeight: FontWeight.w600)),
          if (needsFuel) ...[
            const SizedBox(width: 8),
            Text('route_detail.needs_fuel'.tr(),
                style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildParticipants() {
    final isPublic = _route!['visibility'] == 'public';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Confirmados ───────────────────────────────────────
      Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
        const SizedBox(width: 8),
        Text('route_detail.confirmed_count'.tr(namedArgs: {'count': '$_count'}),
            style: const TextStyle(
                color: AppColors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        if (_isOwner &&
            _route!['visibility'] == 'friends' &&
            _pending.isEmpty)
          _inviteButton(),
      ]),
      const SizedBox(height: 12),
      if (_confirmed.isEmpty)
        _emptyBox('route_detail.nobody_confirmed'.tr())
      else
        ..._confirmed.map((p) => _ParticipantRow(p: p)),

      // ── Pendientes ────────────────────────────────────────
      if (!isPublic && _pending.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.schedule, color: AppColors.gold, size: 18),
          const SizedBox(width: 8),
          Text('route_detail.pending_count'
                  .tr(namedArgs: {'count': '${_pending.length}'}),
              style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_isOwner && _route!['visibility'] == 'friends')
            _inviteButton(label: 'common.add'.tr()),
        ]),
        const SizedBox(height: 12),
        ..._pending.map((p) => _ParticipantRow(p: p)),
      ],

      // ── Declinados ────────────────────────────────────────
      if ((!isPublic || _isOwner) && _declined.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.cancel_outlined, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Text('route_detail.declined_count'
                  .tr(namedArgs: {'count': '${_declined.length}'}),
              style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        ..._declined.map((p) => _ParticipantRow(p: p)),
      ],

      const SizedBox(height: 8),
    ]);
  }

  Widget _inviteButton({String? label}) {
    label ??= 'route_detail.invite'.tr();
    return GestureDetector(
      onTap: () => _showShareDialog(friendsOnly: true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.cyan.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.person_add_outlined, color: AppColors.cyan, size: 14),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: AppColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _emptyBox(String text) => Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.greyDark),
        ),
        child:
            Center(child: Text(text, style: const TextStyle(color: AppColors.grey))),
      );

  String _formatDate(String? date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date);
      const days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
      const months = [
        'ene', 'feb', 'mar', 'abr', 'may', 'jun',
        'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
      ];
      return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return date;
    }
  }
}

// ─── Chip info ────────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─── Fila participante ────────────────────────────────────────────────────────
class _ParticipantRow extends StatelessWidget {
  final Map<String, dynamic> p;
  const _ParticipantRow({required this.p});

  @override
  Widget build(BuildContext context) {
    final name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    final status = p['status'] ?? 'pending';
    final Color badgeColor;
    final String badgeText;
    switch (status) {
      case 'confirmed':
        badgeColor = Colors.green;
        badgeText = '✅ Apuntado';
        break;
      case 'declined':
        badgeColor = AppColors.error;
        badgeText = '❌ No puede ir';
        break;
      default:
        badgeColor = AppColors.gold;
        badgeText = '⏳ Pendiente';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withOpacity(0.25)),
      ),
      child: Row(children: [
        RiderAvatar(
            avatarUrl: p['avatar_url'],
            level: p['experience_level'] ?? 'novato',
            size: 40),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isNotEmpty ? name : p['nickname'] ?? '',
              style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          if (p['nickname'] != null)
            Text('@${p['nickname']}',
                style: const TextStyle(color: AppColors.orange, fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: badgeColor.withOpacity(0.3)),
          ),
          child: Text(badgeText,
              style: TextStyle(
                  color: badgeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─── Bottom sheet compartir ───────────────────────────────────────────────────
class _ShareBottomSheet extends StatefulWidget {
  final Function(List<int>) onShareFriends;
  final VoidCallback onSharePublic;
  final List<int> excludeUserIds;
  final bool friendsOnly;

  const _ShareBottomSheet({
    required this.onShareFriends,
    required this.onSharePublic,
    this.excludeUserIds = const [],
    this.friendsOnly = false,
  });

  @override
  State<_ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<_ShareBottomSheet> {
  int _step = 0;
  List<Map<String, dynamic>> _friends = [];
  Set<int> _selected = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.friendsOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFriends());
    }
  }

  Future<void> _loadFriends() async {
    setState(() => _loading = true);
    final result = await FriendshipService.getFriends();
    if (!mounted) return;
    setState(() {
      _friends = List<Map<String, dynamic>>.from(result['friends'] ?? [])
          .where((f) => !widget.excludeUserIds.contains(f['user_id']))
          .toList();
      _loading = false;
      _step = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.greyDark,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          if (_step == 0) ..._buildMenu(),
          if (_step == 1) ..._buildFriendSelector(),
        ]),
      ),
    );
  }

  List<Widget> _buildMenu() => [
        Text('route_detail.how_to_share'.tr(),
            style: const TextStyle(
                color: AppColors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        _OptionTile(
          icon: Icons.people_outlined,
          color: AppColors.cyan,
          title: 'route_detail.with_friends'.tr(),
          desc: 'route_detail.with_friends_desc'.tr(),
          onTap: _loadFriends,
          trailing: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: AppColors.cyan, strokeWidth: 2))
              : const Icon(Icons.arrow_forward_ios,
                  color: AppColors.cyan, size: 14),
        ),
        const SizedBox(height: 12),
        _OptionTile(
          icon: Icons.public,
          color: AppColors.orange,
          title: 'route_detail.public_zone'.tr(),
          desc: 'route_detail.public_zone_desc'.tr(),
          onTap: () {
            Navigator.pop(context);
            widget.onSharePublic();
          },
        ),
        const SizedBox(height: 8),
      ];

  List<Widget> _buildFriendSelector() => [
        Row(children: [
          if (!widget.friendsOnly)
            GestureDetector(
              onTap: () => setState(() => _step = 0),
              child: const Icon(Icons.arrow_back_ios,
                  color: AppColors.grey, size: 18),
            ),
          const SizedBox(width: 8),
          Text('route_detail.select_friends'.tr(),
              style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_friends.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                if (_selected.length == _friends.length)
                  _selected.clear();
                else
                  _selected =
                      _friends.map((f) => f['user_id'] as int).toSet();
              }),
              child: Text(
                  _selected.length == _friends.length
                      ? 'Quitar todos'
                      : 'Todos',
                  style:
                      const TextStyle(color: AppColors.grey, fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 16),
        if (_friends.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.excludeUserIds.isNotEmpty
                  ? 'Todos tus amigos ya han sido invitados.'
                  : 'No tienes amigos aún.',
              style: const TextStyle(color: AppColors.grey),
            ),
          )
        else
          SizedBox(
            height: 280,
            child: ListView.builder(
              itemCount: _friends.length,
              itemBuilder: (ctx, i) {
                final f = _friends[i];
                final uid = f['user_id'] as int;
                final chk = _selected.contains(uid);
                final name =
                    '${f['first_name'] ?? ''} ${f['last_name'] ?? ''}'
                        .trim();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: RiderAvatar(
                      avatarUrl: f['avatar_url'],
                      level: f['experience_level'] ?? 'novato',
                      size: 44),
                  title: Text(name.isNotEmpty ? name : f['nickname'] ?? '',
                      style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600)),
                  subtitle: f['nickname'] != null
                      ? Text('@${f['nickname']}',
                          style: const TextStyle(
                              color: AppColors.orange, fontSize: 12))
                      : null,
                  trailing: Checkbox(
                    value: chk,
                    activeColor: AppColors.cyan,
                    side: const BorderSide(color: AppColors.grey),
                    onChanged: (_) => setState(() {
                      if (chk)
                        _selected.remove(uid);
                      else
                        _selected.add(uid);
                    }),
                  ),
                  onTap: () => setState(() {
                    if (chk)
                      _selected.remove(uid);
                    else
                      _selected.add(uid);
                  }),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final ids = _selected.toList();
                  Navigator.pop(context);
                  widget.onShareFriends(ids);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyan,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            _selected.isEmpty
                ? 'Selecciona al menos un amigo'
                : 'Compartir con ${_selected.length} amigo${_selected.length > 1 ? 's' : ''}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
      ];
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final VoidCallback onTap;
  final Widget? trailing;

  const _OptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text(title,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(height: 3),
            Text(desc,
                style: const TextStyle(
                    color: AppColors.grey, fontSize: 12, height: 1.3)),
          ])),
          const SizedBox(width: 8),
          trailing ?? Icon(Icons.arrow_forward_ios, color: color, size: 14),
        ]),
      ),
    );
  }
}

// ─── Bottom sheet para repetir ruta (con opción guardar/compartir) ───────────────────────
class _RepeatShareBottomSheet extends StatefulWidget {
  final VoidCallback onSaveOnly;
  final Function(List<int>) onShareFriends;
  final VoidCallback onSharePublic;
  const _RepeatShareBottomSheet({
    required this.onSaveOnly,
    required this.onShareFriends,
    required this.onSharePublic,
  });

  @override
  State<_RepeatShareBottomSheet> createState() => _RepeatShareBottomSheetState();
}

class _RepeatShareBottomSheetState extends State<_RepeatShareBottomSheet> {
  int _step = 0;
  List<Map<String, dynamic>> _friends = [];
  bool _loading = false;
  Set<int> _selected = {};

  Future<void> _loadFriends() async {
    setState(() => _loading = true);
    final result = await FriendshipService.getFriends();
    if (!mounted) return;
    setState(() {
      _friends = List<Map<String, dynamic>>.from(result['friends'] ?? []);
      _loading = false;
      _step = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.greyDark, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            if (_step == 0) ..._buildMenu(),
            if (_step == 1) ..._buildFriendSelector(),
          ]),
      ),
    );
  }

  List<Widget> _buildMenu() => [
    Text('route_result.what_to_do'.tr(),
        style: const TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
    const SizedBox(height: 20),
    _OptionTile(
      icon: Icons.lock_outline, color: AppColors.grey,
      title: 'route_detail.save_for_me'.tr(),
      desc: 'route_detail.save_for_me_desc'.tr(),
      onTap: () { Navigator.pop(context); widget.onSaveOnly(); },
    ),
    const SizedBox(height: 12),
    _OptionTile(
      icon: Icons.people_outlined, color: AppColors.cyan,
      title: 'route_result.share_friends'.tr(),
      desc: 'route_detail.with_friends_desc'.tr(),
      onTap: _loadFriends,
      trailing: _loading
          ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2))
          : const Icon(Icons.arrow_forward_ios, color: AppColors.cyan, size: 14),
    ),
    const SizedBox(height: 12),
    _OptionTile(
      icon: Icons.public, color: AppColors.orange,
      title: 'route_result.share_public'.tr(),
      desc: 'route_detail.public_zone_desc'.tr(),
      onTap: () { Navigator.pop(context); widget.onSharePublic(); },
    ),
    const SizedBox(height: 8),
  ];

  List<Widget> _buildFriendSelector() => [
    Row(children: [
      GestureDetector(
        onTap: () => setState(() => _step = 0),
        child: const Icon(Icons.arrow_back_ios, color: AppColors.grey, size: 18)),
      const SizedBox(width: 8),
      Text('route_detail.select_friends'.tr(),
          style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      const Spacer(),
      if (_friends.isNotEmpty)
        GestureDetector(
          onTap: () => setState(() {
            if (_selected.length == _friends.length) _selected.clear();
            else _selected = _friends.map((f) => f['user_id'] as int).toSet();
          }),
          child: Text(
              _selected.length == _friends.length
                  ? 'route_detail.deselect_all'.tr()
                  : 'route_detail.select_all'.tr(),
              style: const TextStyle(color: AppColors.grey, fontSize: 12)),
        ),
    ]),
    const SizedBox(height: 16),
    if (_friends.isEmpty)
      Padding(padding: const EdgeInsets.all(16),
          child: Text('route_result.no_friends'.tr(),
              style: const TextStyle(color: AppColors.grey)))
    else
      SizedBox(
        height: 260,
        child: ListView.builder(
          itemCount: _friends.length,
          itemBuilder: (ctx, i) {
            final f = _friends[i];
            final uid = f['user_id'] as int;
            final chk = _selected.contains(uid);
            final name = '${f['first_name'] ?? ''} ${f['last_name'] ?? ''}'.trim();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: RiderAvatar(avatarUrl: f['avatar_url'],
                  level: f['experience_level'] ?? 'novato', size: 44),
              title: Text(name.isNotEmpty ? name : f['nickname'] ?? '',
                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
              subtitle: f['nickname'] != null
                  ? Text('@${f['nickname']}', style: const TextStyle(color: AppColors.orange, fontSize: 12))
                  : null,
              trailing: Checkbox(
                value: chk, activeColor: AppColors.cyan,
                side: const BorderSide(color: AppColors.grey),
                onChanged: (_) => setState(() {
                  if (chk) _selected.remove(uid); else _selected.add(uid);
                }),
              ),
              onTap: () => setState(() {
                if (chk) _selected.remove(uid); else _selected.add(uid);
              }),
            );
          },
        ),
      ),
    const SizedBox(height: 12),
    ElevatedButton(
      onPressed: _selected.isEmpty ? null : () {
        final ids = _selected.toList();
        Navigator.pop(context);
        widget.onShareFriends(ids);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.cyan,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        _selected.isEmpty ? 'Selecciona al menos un amigo'
            : 'Compartir con ${_selected.length} amigo${_selected.length > 1 ? 's' : ''}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ),
    const SizedBox(height: 8),
  ];
}

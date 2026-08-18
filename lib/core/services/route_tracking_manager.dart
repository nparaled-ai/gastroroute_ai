import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gestiona el tracking GPS de una ruta en curso.
///
/// Responsabilidades:
///  - Recoger posiciones mientras se rueda y acumular el track.
///  - Persistirlo en local tras cada punto, para que sobreviva a un cierre de
///    la app o a un reinicio del móvil (decisión del plan, 8.1: se recupera).
///  - Calcular distancia y velocidad en tiempo real, solo para mostrarlas.
///
/// Los kilómetros que cuentan para logros los recalcula el servidor al subir
/// el track: lo que se calcula aquí es informativo.
class RouteTrackingManager {
  RouteTrackingManager._();
  static final RouteTrackingManager instance = RouteTrackingManager._();

  static const _kTrackKey     = 'tracking_track';
  static const _kTrackingId   = 'tracking_id';
  static const _kRouteId      = 'tracking_route_id';
  static const _kStartedAt    = 'tracking_started_at';

  /// Precisión peor que esta y el punto se descarta. Mismo umbral que aplica
  /// el servidor: sin él, el ruido del GPS infla los kilómetros estando parado.
  static const double _maxAccuracyM = 50;

  /// Desplazamiento mínimo entre puntos. Evita acumular ruido en semáforos.
  static const int _minDistanceM = 10;

  /// Cada cuánto se refresca el texto de la notificación persistente.
  static const _notificationInterval = Duration(seconds: 10);

  StreamSubscription<Position>? _positionSub;
  DateTime? _lastNotificationUpdate;

  /// Puntos como `[lat, lng, timestampSegundos, precisión]`.
  final List<List<num>> _track = [];

  int? _trackingId;
  int? _routeId;
  DateTime? _startedAt;

  double _distanceM = 0;

  final _stateController = StreamController<TrackingState>.broadcast();
  Stream<TrackingState> get stream => _stateController.stream;

  bool get isTracking => _trackingId != null;
  int? get trackingId => _trackingId;
  int? get routeId => _routeId;
  DateTime? get startedAt => _startedAt;
  List<List<num>> get track => List.unmodifiable(_track);

  TrackingState get state => TrackingState(
        trackingId: _trackingId,
        routeId: _routeId,
        startedAt: _startedAt,
        distanceKm: _distanceM / 1000,
        pointsCount: _track.length,
        lastPoint: _track.isEmpty ? null : _track.last,
      );

  /// Comprueba y solicita el permiso de ubicación.
  ///
  /// Solo se pide "mientras se usa la app": no se pide ubicación en segundo
  /// plano, por la decisión de evitar la revisión de Google Play. Lo que
  /// mantiene vivo el tracking con la app en segundo plano es el servicio en
  /// primer plano, no el permiso de background location.
  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final located = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    if (!located) return false;

    // Sin permiso de notificaciones (Android 13+) no se puede mostrar la
    // notificación persistente, y sin ella no arranca el servicio.
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    return true;
  }

  /// Configura el servicio en primer plano. Debe llamarse antes de arrancarlo.
  static void initForegroundService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'route_tracking',
        channelName: 'Tracking de rutas',
        channelDescription:
            'Notificación permanente mientras se graba una ruta.',
        // El canal va en importancia baja: es informativa, no debe sonar ni
        // vibrar cada vez que se actualizan los kilómetros.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // El tracking lo mueve el stream de geolocator, no un temporizador:
        // el servicio solo mantiene vivo el proceso.
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<void> _startForegroundService() async {
    initForegroundService();

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 3001,
      notificationTitle: 'tracking.notification_title'.tr(),
      notificationText: 'tracking.notification_start'.tr(),
    );
  }

  Future<void> _updateForegroundService() async {
    // A 90 km/h con filtro de 10 m llegan unos 2 puntos por segundo: refrescar
    // la notificación en cada uno es un gasto absurdo. Basta cada 10 s.
    final now = DateTime.now();
    if (_lastNotificationUpdate != null &&
        now.difference(_lastNotificationUpdate!) < _notificationInterval) {
      return;
    }
    _lastNotificationUpdate = now;

    if (!await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.updateService(
      notificationTitle: 'tracking.notification_title'.tr(),
      notificationText: 'tracking.notification_progress'.tr(
        namedArgs: {'km': (_distanceM / 1000).toStringAsFixed(1)},
      ),
    );
  }

  Future<void> _stopForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// Arranca el tracking. [trackingId] es el id devuelto por el servidor.
  Future<void> start({required int trackingId, required int routeId}) async {
    if (_positionSub != null) await stop();

    _trackingId = trackingId;
    _routeId    = routeId;
    _startedAt  = DateTime.now();
    _track.clear();
    _distanceM = 0;

    await _persist();
    await _startForegroundService();
    _listen();
    _stateController.add(state);
  }

  /// Reanuda un tracking interrumpido, recuperando el track guardado en local.
  ///
  /// Devuelve false si no había nada guardado, o si lo guardado corresponde a
  /// otro tracking distinto del que el servidor da por activo.
  Future<bool> resume({required int trackingId, required int routeId}) async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getInt(_kTrackingId) != trackingId) return false;

    final raw = prefs.getString(_kTrackKey);
    if (raw == null) return false;

    _track
      ..clear()
      ..addAll(
        (jsonDecode(raw) as List).map((p) => List<num>.from(p as List)),
      );

    _trackingId = trackingId;
    _routeId    = routeId;

    final startedMs = prefs.getInt(_kStartedAt);
    _startedAt = startedMs != null
        ? DateTime.fromMillisecondsSinceEpoch(startedMs)
        : DateTime.now();

    _distanceM = _recalculateDistance();

    await _startForegroundService();
    _listen();
    _stateController.add(state);
    return true;
  }

  /// Detiene la escucha del GPS y devuelve el track acumulado.
  Future<List<List<num>>> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    await _stopForegroundService();

    final result = List<List<num>>.from(_track);

    _trackingId = null;
    _routeId    = null;
    _startedAt  = null;
    _track.clear();
    _distanceM = 0;
    _lastNotificationUpdate = null;

    await _clearPersisted();
    _stateController.add(state);

    return result;
  }

  void _listen() {
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: _minDistanceM,
      ),
    ).listen(_onPosition, onError: (e) => debugPrint('Tracking GPS: $e'));
  }

  Future<void> _onPosition(Position position) async {
    if (position.accuracy > _maxAccuracyM) return;

    final point = <num>[
      position.latitude,
      position.longitude,
      position.timestamp.millisecondsSinceEpoch ~/ 1000,
      position.accuracy,
    ];

    if (_track.isNotEmpty) {
      final last = _track.last;
      final d = haversine(
        last[0].toDouble(), last[1].toDouble(),
        position.latitude, position.longitude,
      );

      // El distanceFilter de geolocator ya filtra, pero el stream puede emitir
      // igualmente puntos muy juntos si mejora la precisión.
      if (d < _minDistanceM) return;

      _distanceM += d;
    }

    _track.add(point);

    await _persist();
    await _updateForegroundService();
    _stateController.add(state);
  }

  double _recalculateDistance() {
    var meters = 0.0;
    for (var i = 1; i < _track.length; i++) {
      meters += haversine(
        _track[i - 1][0].toDouble(), _track[i - 1][1].toDouble(),
        _track[i][0].toDouble(),     _track[i][1].toDouble(),
      );
    }
    return meters;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTrackKey, jsonEncode(_track));
    if (_trackingId != null) await prefs.setInt(_kTrackingId, _trackingId!);
    if (_routeId != null)    await prefs.setInt(_kRouteId, _routeId!);
    if (_startedAt != null) {
      await prefs.setInt(_kStartedAt, _startedAt!.millisecondsSinceEpoch);
    }
  }

  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTrackKey);
    await prefs.remove(_kTrackingId);
    await prefs.remove(_kRouteId);
    await prefs.remove(_kStartedAt);
  }

  /// Distancia en metros entre dos coordenadas.
  static double haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);

    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLng / 2), 2);

    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}

/// Instantánea del estado del tracking, para pintar la pantalla.
class TrackingState {
  final int? trackingId;
  final int? routeId;
  final DateTime? startedAt;
  final double distanceKm;
  final int pointsCount;
  final List<num>? lastPoint;

  const TrackingState({
    this.trackingId,
    this.routeId,
    this.startedAt,
    this.distanceKm = 0,
    this.pointsCount = 0,
    this.lastPoint,
  });

  bool get isActive => trackingId != null;

  Duration get elapsed =>
      startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);

  /// Velocidad media en km/h desde el inicio.
  double get avgSpeedKmh {
    final h = elapsed.inSeconds / 3600;
    return h > 0 ? distanceKm / h : 0;
  }
}

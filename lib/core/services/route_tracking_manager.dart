import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  static const _kTargetLat    = 'tracking_target_lat';
  static const _kTargetLng    = 'tracking_target_lng';
  static const _kHasLeft      = 'tracking_has_left';
  static const _kArrivalDone  = 'tracking_arrival_done';
  static const _kData         = 'tracking_data';

  /// Radio alrededor del destino para dar la ruta por terminada.
  static const double _arrivalRadiusM = 300;

  /// Hay que quedarse dentro del radio este tiempo antes de avisar.
  ///
  /// Sin esto, pasar por delante del destino a mitad de ruta —o rodear la
  /// manzana buscando aparcamiento— dispararía el aviso.
  static const _arrivalDwell = Duration(minutes: 3);

  /// Hay que haberse alejado al menos esto del destino antes de que la
  /// detección se arme.
  ///
  /// Es imprescindible en rutas circulares, donde el destino ES el origen: sin
  /// este guardado, al arrancar ya estarías "en el destino" y te preguntaría
  /// si finalizas nada más salir de casa.
  static const double _arrivalArmAfterM = 2000;

  /// Precisión peor que esta y el punto se descarta. Mismo umbral que aplica
  /// el servidor: sin él, el ruido del GPS infla los kilómetros estando parado.
  ///
  /// Estaba en 50 m y se bajó tras medirlo: un punto con ±50 m de error no
  /// dice dónde estás, y era el que alimentaba los kilómetros fantasma.
  static const double _maxAccuracyM = 25;

  /// Desplazamiento mínimo entre puntos, en metros.
  ///
  /// Es un SUELO, no el umbral definitivo: el que se aplica de verdad es el
  /// mayor entre este valor y la precisión del propio punto (ver
  /// [_noiseFloorFor]). Con un umbral fijo de 10 m se estaba midiendo con más
  /// finura que la que tiene el dato, y cualquier salto del GPS pasaba el
  /// filtro. Medido con el móvil quieto encima de la mesa: 10 puntos, 0,1 km
  /// de recorrido inventado y 2-4 km/h de velocidad fantasma.
  static const double _minDistanceM = 15;

  /// Umbral real de movimiento para un punto: nunca por debajo de su error.
  static double _noiseFloorFor(double accuracy) =>
      accuracy > _minDistanceM ? accuracy : _minDistanceM;

  /// Mismo valor que [_minDistanceM], como entero, para el filtro de
  /// geolocator, que lo exige en una expresión constante.
  static const int _gpsFilterM = 15;

  /// Cada cuánto se refresca el texto de la notificación persistente.
  static const _notificationInterval = Duration(seconds: 10);

  StreamSubscription<Position>? _positionSub;
  DateTime? _lastNotificationUpdate;

  /// Puntos como `[lat, lng, timestampSegundos, precisión]`.
  final List<List<num>> _track = [];

  int? _trackingId;
  int? _routeId;
  DateTime? _startedAt;

  /// El tracking tal y como lo devolvió el servidor, con su ruta dentro.
  ///
  /// Se guarda aquí porque la pantalla de ruta en curso lo necesita para
  /// pintarse, y a ella se llega desde la barra inferior, que puede pulsarse
  /// en mitad de la sierra sin cobertura. Si hubiera que pedirlo al servidor
  /// en ese momento, la barra no llevaría a ningún sitio justo cuando más
  /// falta hace.
  Map<String, dynamic>? _data;

  double _distanceM = 0;

  /// Punto donde acaba la ruta: el destino, o el origen si es circular.
  double? _targetLat;
  double? _targetLng;

  /// Si ya se ha salido de la zona del destino. Ver [_arrivalArmAfterM].
  bool _hasLeft = false;

  /// Desde cuándo se está dentro del radio de llegada, o null si se está fuera.
  DateTime? _nearSince;

  /// Para no repetir el aviso de llegada en la misma ruta.
  bool _arrivalNotified = false;

  final _stateController = StreamController<TrackingState>.broadcast();
  Stream<TrackingState> get stream => _stateController.stream;

  bool get isTracking => _trackingId != null;
  int? get trackingId => _trackingId;
  int? get routeId => _routeId;
  DateTime? get startedAt => _startedAt;
  List<List<num>> get track => List.unmodifiable(_track);

  /// Datos del tracking en curso, para abrir su pantalla. Ver [_data].
  Map<String, dynamic>? get data => _data;

  TrackingState get state => TrackingState(
        trackingId: _trackingId,
        routeId: _routeId,
        startedAt: _startedAt,
        distanceKm: _distanceM / 1000,
        pointsCount: _track.length,
        lastPoint: _track.isEmpty ? null : _track.last,
        arrived: _arrivalNotified,
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
  ///
  /// [targetLat]/[targetLng] son el punto donde acaba la ruta: el destino, o
  /// el origen si es circular. Si no se pasan, no hay detección de llegada y
  /// el motero tendrá que finalizar a mano.
  /// [data] es el tracking que devolvió el servidor, con su ruta dentro. Ver
  /// [_data]: es lo que permite abrir la pantalla de ruta sin cobertura.
  Future<void> start({
    required int trackingId,
    required int routeId,
    Map<String, dynamic>? data,
    double? targetLat,
    double? targetLng,
  }) async {
    if (_positionSub != null) await stop();

    _trackingId = trackingId;
    _routeId    = routeId;
    _data       = data;
    _startedAt  = DateTime.now();
    _targetLat  = targetLat;
    _targetLng  = targetLng;
    _hasLeft    = false;
    _nearSince  = null;
    _arrivalNotified = false;
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
  Future<bool> resume({
    required int trackingId,
    required int routeId,
    Map<String, dynamic>? data,
  }) async {
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

    // Si quien recupera trae los datos frescos del servidor, mandan esos; si
    // no (sin cobertura), se usan los que se guardaron al arrancar.
    _data = data ?? _readPersistedData(prefs);

    final startedMs = prefs.getInt(_kStartedAt);
    _startedAt = startedMs != null
        ? DateTime.fromMillisecondsSinceEpoch(startedMs)
        : DateTime.now();

    _distanceM = _recalculateDistance();

    // Estado de la detección de llegada, para que sobreviva a un cierre de la
    // app: sin esto, al recuperar una ruta ya avanzada se perdería el "ya me
    // he alejado" y la llegada no se detectaría.
    _targetLat = prefs.getDouble(_kTargetLat);
    _targetLng = prefs.getDouble(_kTargetLng);
    _hasLeft   = prefs.getBool(_kHasLeft) ?? false;
    _arrivalNotified = prefs.getBool(_kArrivalDone) ?? false;
    _nearSince = null;

    await _startForegroundService();
    _listen();
    _stateController.add(state);
    return true;
  }

  /// Detiene la escucha del GPS y devuelve el track acumulado.
  Future<List<List<num>>> stop() async {
    final result = await pauseRecording();
    await clear();
    return result;
  }

  /// Deja de grabar, pero CONSERVA el track, en memoria y en disco.
  ///
  /// Es lo que hay que usar al finalizar o descartar, en vez de [stop]: el
  /// track solo se borra ([clear]) cuando el servidor confirma que lo tiene.
  ///
  /// Antes se llamaba a stop(), que borraba todo, ANTES de subir. Si la
  /// subida fallaba —y al final de una ruta de montaña, sin cobertura, es lo
  /// más probable— el motero reintentaba y stop() le devolvía un track vacío;
  /// eso caía en "ruta demasiado corta", se descartaba, y la ruta entera se
  /// perdía con sus POIs y sus logros.
  ///
  /// Se puede llamar varias veces: si ya no se grababa, solo devuelve el track.
  Future<List<List<num>>> pauseRecording() async {
    await _positionSub?.cancel();
    _positionSub = null;
    await _stopForegroundService();
    return List<List<num>>.from(_track);
  }

  /// Borra todo el estado del tracking, en memoria y en disco.
  ///
  /// Solo debe llamarse cuando el servidor ya tiene la ruta (finalizada o
  /// descartada). Si se llama antes y la subida falla, el track se pierde.
  Future<void> clear() async {
    await _positionSub?.cancel();
    _positionSub = null;
    await _stopForegroundService();

    _trackingId = null;
    _routeId    = null;
    _data       = null;
    _startedAt  = null;
    _targetLat  = null;
    _targetLng  = null;
    _hasLeft    = false;
    _nearSince  = null;
    _arrivalNotified = false;
    _track.clear();
    _distanceM = 0;
    _lastNotificationUpdate = null;

    // Si la ruta se cierra antes de que el motero toque el aviso de llegada,
    // ese aviso se queda colgado en la bandeja apuntando a una ruta que ya no
    // existe.
    try {
      await FlutterLocalNotificationsPlugin().cancel(_arrivalNotificationId);
    } catch (_) {}

    await _clearPersisted();
    _stateController.add(state);
  }

  void _listen() {
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings(),
    ).listen(_onPosition, onError: (e) => debugPrint('Tracking GPS: $e'));
  }

  /// Ajustes del GPS, distintos en cada plataforma.
  ///
  /// En Android el proceso lo mantiene vivo el servicio en primer plano. En
  /// iOS no existe tal cosa: hay que pedir explícitamente que se sigan
  /// entregando posiciones en segundo plano, o el sistema suspende la app al
  /// bloquear el móvil y la ruta se queda a medias. Con permiso "mientras se
  /// usa" iOS lo permite, a cambio de mostrar la barra azul al motero —
  /// que además es honesto: se le está avisando de que se le graba.
  static LocationSettings _locationSettings() {
    // Suelo: el filtro fino, que además mira la precisión de cada punto, se
    // aplica en _onPosition.
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: _gpsFilterM,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        // iOS pausa por su cuenta cuando cree que no te mueves, y al hacerlo
        // deja de entregar posiciones sin avisar. En una ruta con paradas
        // largas eso corta la grabación sin que el motero lo sepa.
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.otherNavigation,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: _gpsFilterM,
    );
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

      // Deriva del GPS: si el salto no supera el error del propio punto, no
      // hay forma de distinguir movimiento de ruido, así que se descarta el
      // punto entero.
      //
      // Antes el umbral era fijo (10 m) y se aceptaban puntos de hasta ±50 m,
      // o sea que se medía con más finura que la del dato. Con el móvil quieto
      // encima de la mesa el recorrido crecía ~0,1 km cada 2 minutos: en una
      // ruta de 8 horas son más de 20 km inventados, que además contarían para
      // los logros y para los límites del antitrampa.
      final floor = _noiseFloorFor(
        position.accuracy > last[3].toDouble()
            ? position.accuracy
            : last[3].toDouble(),
      );

      if (d < floor) return;

      _distanceM += d;
    }

    _track.add(point);

    await _persist();
    await _checkArrival(position);
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
    if (_targetLat != null) await prefs.setDouble(_kTargetLat, _targetLat!);
    if (_targetLng != null) await prefs.setDouble(_kTargetLng, _targetLng!);
    await prefs.setBool(_kHasLeft, _hasLeft);
    await prefs.setBool(_kArrivalDone, _arrivalNotified);
    if (_data != null) await prefs.setString(_kData, jsonEncode(_data));
  }

  /// Lee el tracking guardado. Devuelve null si no hay o si está corrupto: es
  /// un dato de conveniencia, nunca una razón para no recuperar la grabación.
  Map<String, dynamic>? _readPersistedData(SharedPreferences prefs) {
    final raw = prefs.getString(_kData);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTrackKey);
    await prefs.remove(_kTrackingId);
    await prefs.remove(_kRouteId);
    await prefs.remove(_kStartedAt);
    await prefs.remove(_kTargetLat);
    await prefs.remove(_kTargetLng);
    await prefs.remove(_kHasLeft);
    await prefs.remove(_kArrivalDone);
    await prefs.remove(_kData);
  }

  /// Mira si el motero ha llegado al final de la ruta y, si es así, le avisa.
  ///
  /// El aviso NO cierra la ruta solo: abre la app para que el motero confirme.
  /// Es a propósito — al finalizar se muestra el resumen con los POIs
  /// detectados y los logros conseguidos, y cerrarla en silencio desde la
  /// pantalla de bloqueo le haría perderse justo eso.
  Future<void> _checkArrival(Position position) async {
    if (_arrivalNotified) return;
    if (_targetLat == null || _targetLng == null) return;

    final d = haversine(
      position.latitude, position.longitude, _targetLat!, _targetLng!,
    );

    // Primero hay que alejarse: en una circular el destino es el origen, así
    // que al arrancar ya se está "llegando".
    if (!_hasLeft) {
      if (d > _arrivalArmAfterM) {
        _hasLeft = true;
        await _persist();
      }
      return;
    }

    if (d > _arrivalRadiusM) {
      _nearSince = null;
      return;
    }

    // Dentro del radio: hay que quedarse un rato para descartar que sea un
    // simple paso por delante.
    _nearSince ??= DateTime.now();
    if (DateTime.now().difference(_nearSince!) < _arrivalDwell) return;

    _arrivalNotified = true;
    await _persist();
    await _notifyArrival();
  }

  Future<void> _notifyArrival() async {
    try {
      final fln = FlutterLocalNotificationsPlugin();

      await fln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_arrivalChannel);

      await fln.show(
        _arrivalNotificationId,
        'tracking.arrival_title'.tr(),
        'tracking.arrival_body'.tr(),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _arrivalChannel.id,
            _arrivalChannel.name,
            channelDescription: _arrivalChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            sound: _arrivalChannel.sound,
          ),
          iOS: const DarwinNotificationDetails(sound: 'sound_moto.mp3'),
        ),
        payload: 'tracking',
      );
    } catch (e) {
      // Que falle el aviso no puede tumbar la grabación, que es lo importante.
      debugPrint('Aviso de llegada no mostrado: $e');
    }
  }

  static const _arrivalNotificationId = 910001;

  static const _arrivalChannel = AndroidNotificationChannel(
    'route_arrival',
    'Llegada a destino',
    description: 'Aviso al llegar al final de una ruta que estás grabando.',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('sound_moto'),
  );

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

  /// El gestor ha detectado que se ha llegado al final de la ruta.
  ///
  /// La detección vive solo en RouteTrackingManager, no en la pantalla: tiene
  /// que funcionar con la app cerrada, que es cuando de verdad hace falta.
  /// La pantalla, si está abierta, se limita a reaccionar a esta bandera.
  final bool arrived;

  const TrackingState({
    this.trackingId,
    this.routeId,
    this.startedAt,
    this.distanceKm = 0,
    this.pointsCount = 0,
    this.lastPoint,
    this.arrived = false,
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

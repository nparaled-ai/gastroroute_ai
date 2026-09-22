import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../features/rider/providers/app_notification_service.dart';
import '../router.dart';

// Handler para mensajes en background (top-level, fuera de clase)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase ya está inicializado antes de llegar aquí
}

class PushNotificationService {
  static final _fln = FlutterLocalNotificationsPlugin();
  static final _messaging = FirebaseMessaging.instance;

  static const _androidChannel = AndroidNotificationChannel(
    'gastroroute_default',
    'GAStroRouteAI',
    description: 'Notificaciones de rutas y amigos',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('sound_moto'),
  );

  /// Al pulsar una notificación local (app en primer plano).
  static void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    debugPrint('[push] toque con app en PRIMER PLANO, payload=$payload');
    if (payload == null) return;

    // Aviso de llegada a destino: lleva a la ruta en curso, que es donde está
    // el botón de finalizar y el resumen.
    if (payload == 'tracking') {
      router.push('/rider/tracking');
      return;
    }

    if (payload.startsWith('route:')) {
      _openRoute(int.tryParse(payload.substring('route:'.length)));
    }
  }

  /// Ruta que abrir en cuanto la app esté lista.
  ///
  /// Necesario porque `init()` se ejecuta ANTES de `runApp`: en ese momento no
  /// hay árbol de widgets ni Navigator, así que navegar desde ahí no hace nada
  /// —la llamada se pierde sin error— y además el `redirect` de autenticación
  /// del router aún no ha decidido si el motero tiene sesión. Se guarda aquí y
  /// la pantalla de inicio la consume cuando ya puede navegar de verdad.
  static int? _pendingRouteId;

  /// Devuelve la ruta pendiente y la olvida, para que no se abra dos veces.
  static int? consumePendingRoute() {
    final id = _pendingRouteId;
    _pendingRouteId = null;
    return id;
  }

  /// Lleva al detalle de la ruta.
  ///
  /// Sin esto la notificación solo abre la app por donde se quedara, cuando lo
  /// útil es dejar al motero en la pantalla de la ruta, que es donde está el
  /// botón de iniciar el tracking — y es justo lo que le estás pidiendo que
  /// haga con el aviso de salida.
  static void _openRoute(int? routeId) {
    debugPrint('[push] _openRoute($routeId)');
    if (routeId == null) return;
    router.push('/rider/routes/$routeId');
  }

  /// Ruta que venga en la carga de datos de un push.
  static int? _routeIdOf(RemoteMessage message) =>
      int.tryParse('${message.data['route_id']}');

  static Future<void> init() async {
    // Registrar handler de background
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Pedir permisos (iOS + Android 13+)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Crear canal Android
    await _fln
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // Inicializar flutter_local_notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _fln.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Al tocar un push que llega con la app en segundo plano.
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      debugPrint('[push] toque con app en SEGUNDO PLANO, data=${m.data}');
      _openRoute(_routeIdOf(m));
    });

    // Y el mismo caso con la app cerrada del todo: el push que la arrancó no
    // pasa por onMessageOpenedApp, hay que preguntarlo explícitamente. Es el
    // escenario normal del aviso de salida, así que sin esto el motero abre la
    // app y no acaba donde esperaba.
    //
    // Aquí NO se navega: esto corre antes de runApp. Solo se anota.
    final initial = await _messaging.getInitialMessage();
    debugPrint('[push] arranque: getInitialMessage='
        '${initial == null ? "null (no se abrio desde un push)" : "data=${initial.data}"}');
    if (initial != null) _pendingRouteId = _routeIdOf(initial);

    // Mensaje en primer plano → mostrar notificación local
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      final routeId = _routeIdOf(message);
      _fln.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            sound: const RawResourceAndroidNotificationSound('sound_moto'),
          ),
          iOS: const DarwinNotificationDetails(sound: 'sound_moto.mp3'),
        ),
        // Para que tocarla lleve a la ruta también en primer plano.
        payload: routeId == null ? null : 'route:$routeId',
      );
    });

    // Refrescar token si cambia (cuando ya esté autenticado)
    _messaging.onTokenRefresh.listen((_) => registerToken());
  }

  static Future<void> registerToken() async {
    try {
      final token = Platform.isIOS
          ? await _messaging.getAPNSToken()
          : await _messaging.getToken();
      if (token != null) {
        await AppNotificationService.registerFcmToken(token);
      }
    } catch (_) {}
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../features/rider/providers/app_notification_service.dart';
import '../api/auth_service.dart';
import '../router.dart';
import '../storage/auth_storage.dart';
import 'route_tracking_manager.dart';

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

  /// Canal de los avisos de Moderación: SIN sonido propio, para que Android use el
  /// tono de notificación estándar del móvil y no el de la moto.
  static const _moderationChannel = AndroidNotificationChannel(
    'gastroroute_moderation',
    'Moderación',
    importance: Importance.high,
  );

  /// Vuelve a crear el canal con el texto en el idioma del motero.
  ///
  /// `init()` corre antes de `runApp`, cuando aún no hay idioma cargado y `.tr()`
  /// devolvería la clave. Android actualiza nombre y descripción de un canal que
  /// ya existe (no su importancia), así que basta con crearlo otra vez.
  static Future<void> refreshChannelTexts() async {
    try {
      await _fln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(AndroidNotificationChannel(
            _androidChannel.id,
            _androidChannel.name,
            description: 'channels.default_desc'.tr(),
            importance: _androidChannel.importance,
            sound: _androidChannel.sound,
          ));
      await _fln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(AndroidNotificationChannel(
            _moderationChannel.id,
            'channels.moderation'.tr(),
            description: 'channels.moderation_desc'.tr(),
            importance: _moderationChannel.importance,
          ));
    } catch (e) {
      debugPrint('[push] no se pudo actualizar el texto del canal: $e');
    }
  }

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

    if (payload == 'moderation') {
      openModeration();
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

  /// Un aviso de Moderación pulsado con la app cerrada: se abrirá cuando la app esté lista.
  static bool _pendingModeration = false;

  static bool consumePendingModeration() {
    final p = _pendingModeration;
    _pendingModeration = false;
    return p;
  }

  /// Lleva a la cola de comentarios, cambiando antes al perfil de administración
  /// (o de moderador) si se estaba en otro. No cambia de perfil mientras se graba
  /// una ruta.
  static Future<void> openModeration() async {
    if (RouteTrackingManager.instance.isTracking) return;
    final role = await AuthStorage.getRole();
    if (role != 'admin' && role != 'moderator') {
      var r = await AuthService.switchRole('admin');
      if (r['success'] != true) r = await AuthService.switchRole('moderator');
      if (r['success'] != true) return;
    }
    router.go('/admin/moderation');
    router.push('/admin/moderation/comments');
  }

  static bool _isModeration(RemoteMessage m) => m.data['screen'] == 'moderation';

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
      if (_isModeration(m)) {
        openModeration();
        return;
      }
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
    if (initial != null) {
      if (_isModeration(initial)) {
        _pendingModeration = true;
      } else {
        _pendingRouteId = _routeIdOf(initial);
      }
    }

    // Mensaje en primer plano → mostrar notificación local
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      final routeId = _routeIdOf(message);
      final moderacion = _isModeration(message);
      _fln.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: moderacion
              ? AndroidNotificationDetails(
                  _moderationChannel.id,
                  _moderationChannel.name,
                  importance: Importance.high,
                  priority: Priority.high,
                  icon: '@mipmap/ic_launcher',
                )
              : AndroidNotificationDetails(
                  _androidChannel.id,
                  _androidChannel.name,
                  channelDescription: _androidChannel.description,
                  importance: Importance.high,
                  priority: Priority.high,
                  icon: '@mipmap/ic_launcher',
                  sound: const RawResourceAndroidNotificationSound('sound_moto'),
                ),
          iOS: moderacion
              ? const DarwinNotificationDetails()
              : const DarwinNotificationDetails(sound: 'sound_moto.mp3'),
        ),
        // Para que tocarla lleve a la ruta (o a Moderación) también en primer plano.
        payload: moderacion ? 'moderation' : (routeId == null ? null : 'route:$routeId'),
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

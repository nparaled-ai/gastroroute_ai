import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../features/rider/providers/app_notification_service.dart';

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
    'GastroRouteAI',
    description: 'Notificaciones de rutas y amigos',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('sound_moto'),
  );

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
    );

    // Mensaje en primer plano → mostrar notificación local
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
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

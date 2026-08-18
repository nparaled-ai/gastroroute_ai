import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Aviso local a la hora de salida de una ruta guardada.
///
/// Es la mitad no-GPS de la opción B: como no se pide permiso de ubicación en
/// segundo plano, el inicio de ruta no se puede detectar con la app cerrada.
/// En su lugar se programa un aviso por fecha y hora: "¿Sales hoy de ruta?".
///
/// Se programa de forma inexacta a propósito. Pedir SCHEDULE_EXACT_ALARM
/// complica la distribución en Google Play y aquí no aporta nada: da igual que
/// el aviso llegue cinco minutos tarde.
class RouteReminderService {
  static final _fln = FlutterLocalNotificationsPlugin();

  /// Offset para que los ids no choquen con los de otras notificaciones.
  static const _idBase = 900000;

  static const _channel = AndroidNotificationChannel(
    'route_reminders',
    'Avisos de salida',
    description: 'Aviso a la hora de salida de tus rutas guardadas.',
    importance: Importance.high,
  );

  static bool _ready = false;

  static Future<void> _init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();

    await _fln
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    _ready = true;
  }

  /// Reprograma los avisos de todas las rutas.
  ///
  /// Cancela los anteriores y vuelve a programar solo las rutas futuras: así
  /// se recogen sin esfuerzo los cambios de fecha y las rutas borradas.
  static Future<void> sync(List<Map<String, dynamic>> routes) async {
    await _init();

    for (final route in routes) {
      final id = route['id'];
      if (id is! int) continue;

      await _fln.cancel(_idBase + id);

      final when = _departureOf(route);
      if (when == null || when.isBefore(DateTime.now())) continue;

      await _schedule(id, route['title']?.toString() ?? '', when);
    }
  }

  static Future<void> cancelFor(int routeId) async {
    await _init();
    await _fln.cancel(_idBase + routeId);
  }

  static Future<void> _schedule(int routeId, String title, DateTime when) async {
    try {
      await _fln.zonedSchedule(
        _idBase + routeId,
        'tracking.reminder_title'.tr(),
        'tracking.reminder_body'.tr(namedArgs: {'route': title}),
        tz.TZDateTime.from(when, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // Inexacto a proposito: ver nota de cabecera sobre SCHEDULE_EXACT_ALARM.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // La hora de salida es hora local del motero, no absoluta.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        payload: 'route:$routeId',
      );
    } catch (e) {
      debugPrint('No se pudo programar el aviso de la ruta $routeId: $e');
    }
  }

  /// Combina `departure_date` (YYYY-MM-DD) y `departure_time` (HH:mm).
  ///
  /// Ambos se guardan como texto en la BD, de ahí el parseo manual.
  static DateTime? _departureOf(Map<String, dynamic> route) {
    final date = route['departure_date']?.toString();
    if (date == null || date.isEmpty) return null;

    final day = DateTime.tryParse(date);
    if (day == null) return null;

    final time = route['departure_time']?.toString() ?? '';
    final parts = time.split(':');

    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return DateTime(day.year, day.month, day.day, hour, minute);
  }
}

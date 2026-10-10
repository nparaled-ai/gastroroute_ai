import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Exención de la optimización de batería, para que no corten la grabación.
///
/// El servicio en primer plano mantiene vivo el proceso frente a lo normal:
/// que el motero abra otra app, o que arranque sola la del fabricante de la
/// moto al conectarse por Bluetooth. Eso NO interrumpe la grabación.
///
/// Lo que sí la interrumpe es el ahorro de batería agresivo de algunos
/// fabricantes —Xiaomi/MIUI el primero—, que mata el proceso entero aunque
/// tenga un servicio en primer plano. Contra eso no hay código posible: solo
/// que el motero marque la app como exenta.
///
/// Se usa [FlutterForegroundTask.openIgnoreBatteryOptimizationSettings], que
/// abre los ajustes del sistema, en vez de `requestIgnoreBatteryOptimization`,
/// que lo haría de un toque pero exige declarar
/// `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` en el manifest — un permiso de los
/// que Google Play revisa a mano. Misma razón por la que se evitó pedir
/// ubicación en segundo plano.
class BatteryOptimization {
  BatteryOptimization._();

  /// Para no repetir el aviso en cada ruta si ya se dijo "ahora no".
  static const _kAsked = 'battery_exemption_asked';

  /// Avisa una sola vez, si hace falta. Llamar al arrancar una grabación.
  ///
  /// No devuelve nada ni bloquea: la ruta arranca igual. Que el motero no
  /// quiera tocar los ajustes no es motivo para no grabarle la ruta.
  static Future<void> warnIfNeeded(BuildContext context) async {
    if (!Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAsked) == true) return;

    // Puede fallar en móviles raros: no es nada por lo que tumbar un arranque
    // de ruta.
    try {
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) return;
    } catch (_) {
      return;
    }

    if (!context.mounted) return;

    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('tracking.battery_title'.tr(),
            style: const TextStyle(color: AppColors.white)),
        content: Text('tracking.battery_body'.tr(),
            style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('tracking.not_now'.tr(),
                style: const TextStyle(color: AppColors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('tracking.battery_open'.tr(),
                style: const TextStyle(color: AppColors.orange)),
          ),
        ],
      ),
    );

    // Se marca como preguntado en los dos casos: si dijo "ahora no", no se le
    // vuelve a insistir cada vez que sale de ruta.
    await prefs.setBool(_kAsked, true);

    if (open != true) return;

    try {
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    } catch (_) {}
  }
}

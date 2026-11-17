import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Aviso de que lo pedido es demasiado para un día. No bloquea nada.
///
/// Decidido el 10-10-2026: se puede pedir hasta 800 km sin que nadie diga nada, y
/// una ruta de un día se disfruta en 350 km y se sufre en 600. El aviso salta a
/// partir de 500 km (o 10 horas de ruta), con la cuenta de la propia app:
/// unos 50 km/h de media en carretera secundaria, como en el encargo de la IA.
class LongDayNotice extends StatelessWidget {
  /// Kilómetros pedidos, si se piden en km.
  final num? km;

  /// Horas pedidas, si se piden en horas.
  final num? hours;

  const LongDayNotice({super.key, this.km, this.hours});

  static const _kmLimit = 500;
  static const _hoursLimit = 10;
  static const _kmPerHour = 50;

  /// Las horas de ruta que son lo pedido, o null si no es un día largo.
  static int? longHours({num? km, num? hours}) {
    if (km != null && km >= _kmLimit) return (km / _kmPerHour).round();
    if (hours != null && hours >= _hoursLimit) return hours.round();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final h = longHours(km: km, hours: hours);
    if (h == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.10),
        border: const Border(left: BorderSide(color: AppColors.orange, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.orange, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'planner.long_day'.tr(namedArgs: {'hours': '$h'}),
              style: const TextStyle(color: AppColors.orange, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Aviso bajo la opción de ir por autopista o autovía: la app de Google Maps puede tener
/// guardado «evitar autopistas / peajes» y entonces las ignora aunque aquí se hayan marcado
/// (el enlace solo sabe añadir «evitar», no quitarlo). Visto en el móvil el 17-11-2026.
///
/// Se enseña solo cuando el motero PERMITE autopistas.
class HighwaysMapsNotice extends StatelessWidget {
  const HighwaysMapsNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        border: const Border(left: BorderSide(color: AppColors.gold, width: 3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, color: AppColors.gold, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'common.maps_highways_notice'.tr(),
            style: const TextStyle(color: AppColors.gold, fontSize: 12.5, height: 1.4),
          ),
        ),
      ]),
    );
  }
}

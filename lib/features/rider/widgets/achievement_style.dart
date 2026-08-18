import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Colores e iconos de los logros.
///
/// Vive aparte porque lo usan tres pantallas: la lista, el detalle y la
/// celebración. Si cada una tuviera su propia tabla acabarían divergiendo.
class AchievementStyle {
  /// Colores de nivel. Bronce y plata no están en AppColors porque solo se
  /// usan aquí; oro y platino reutilizan los de la app.
  static const bronce  = Color(0xFFCD7F32);
  static const plata   = Color(0xFFC0C0C0);
  static const oro     = AppColors.gold;
  static const platino = AppColors.cyan;

  static Color tierColor(String? tier) {
    switch (tier) {
      case 'bronce':  return bronce;
      case 'plata':   return plata;
      case 'oro':     return oro;
      case 'platino': return platino;
      default:        return AppColors.grey;
    }
  }

  /// Color del texto sobre la insignia de nivel: los claros necesitan texto
  /// oscuro para leerse.
  static Color tierTextColor(String? tier) {
    return (tier == 'plata' || tier == 'oro')
        ? AppColors.background
        : AppColors.white;
  }

  static const _categoryIcons = {
    'km':       Icons.route_outlined,
    'routes':   Icons.map_outlined,
    'gastro':   Icons.restaurant_outlined,
    'pois':     Icons.place_outlined,
    'explorer': Icons.explore_outlined,
    'social':   Icons.people_outline,
  };

  static const _specialIcons = {
    'madrugador':        Icons.wb_twilight,
    'noctambulo':        Icons.nightlight_outlined,
    'trotamundos':       Icons.flag_outlined,
    'gastronomico':      Icons.restaurant_menu,
    'circular':          Icons.refresh,
    'cuatro_estaciones': Icons.wb_sunny_outlined,
    'constante':         Icons.emoji_events_outlined,
    'turista':           Icons.photo_camera_outlined,
    'explorador':        Icons.travel_explore,
    'en_grupo':          Icons.groups_outlined,
    'coleccionista':     Icons.collections_bookmark_outlined,
  };

  static IconData categoryIcon(String category) =>
      _categoryIcons[category] ?? Icons.emoji_events_outlined;

  static IconData specialIcon(String? code) =>
      _specialIcons[code] ?? Icons.star_outline;

  /// Clave de traducción del nombre de una categoría progresiva.
  static String categoryLabel(String category) => 'achievements.category_$category';

  /// Clave de traducción del nombre de un logro especial.
  static String specialLabel(String? code) => 'achievements.special_$code';
}

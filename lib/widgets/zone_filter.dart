import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Filtro por país y por zona (comunidades arriba, provincias debajo) para las listas de rutas
/// del motero: Próximas, No realizadas, Recibidas y Rodadas.
///
/// Las opciones salen de las propias rutas: cada una trae `zone_country` / `zone_area` /
/// `zone_region` (país y códigos ISO 3166-2) y sus nombres ya traducidos (`zone_*_name`). Así solo
/// se ofrece lo que el motero tiene. El desplegable de país solo sale si hay rutas de 2 países o
/// más; el de zona, si alguna ruta tiene zona, y solo enseña las del país elegido.
class ZoneFilter {
  /// Lo que la ruta dice de sí misma: TODOS los países y zonas por los que pasa (`zone_options`,
  /// una ruta puede cruzar los Pirineos) y, si el servidor aún no los manda, el de la salida.
  static Map<String, List<Map<String, dynamic>>> _options(Map<String, dynamic> r) {
    List<Map<String, dynamic>> lista(dynamic v) => v is List
        ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    final o = r['zone_options'];
    if (o is Map) {
      return {
        'countries': lista(o['countries']),
        'areas': lista(o['areas']),
        'regions': lista(o['regions']),
      };
    }
    final c = '${r['zone_country'] ?? ''}';
    final a = '${r['zone_area'] ?? ''}';
    final g = '${r['zone_region'] ?? ''}';

    return {
      'countries': c.isEmpty ? [] : [{'code': c, 'name': '${r['zone_country_name'] ?? c}'}],
      'areas': a.isEmpty ? [] : [{'key': a, 'country': c, 'name': '${r['zone_area_name'] ?? a}'}],
      'regions': g.isEmpty ? [] : [{'key': g, 'country': c, 'name': '${r['zone_region_name'] ?? g}'}],
    };
  }

  /// Países de las rutas: código -> nombre.
  static Map<String, String> countries(Iterable<Map<String, dynamic>> routes) {
    final out = <String, String>{};
    for (final r in routes) {
      for (final c in _options(r)['countries']!) {
        out['${c['code']}'] = '${c['name']}';
      }
    }
    return out;
  }

  /// Opciones del desplegable de zona para el país elegido (o todos).
  static List<DropdownMenuItem<String?>> zoneItems(
      Iterable<Map<String, dynamic>> routes, String? country) {
    final areas = <String, String>{};
    final regions = <String, String>{};
    for (final r in routes) {
      final o = _options(r);
      for (final a in o['areas']!) {
        if (country == null || '${a['country']}' == country) areas['${a['key']}'] = '${a['name']}';
      }
      for (final g in o['regions']!) {
        if (country == null || '${g['country']}' == country) regions['${g['key']}'] = '${g['name']}';
      }
    }
    if (areas.isEmpty && regions.isEmpty) return const [];

    List<MapEntry<String, String>> sorted(Map<String, String> m) =>
        m.entries.toList()..sort((x, y) => x.value.toLowerCase().compareTo(y.value.toLowerCase()));
    Widget header(String t) => Text(t,
        style: const TextStyle(
            color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.4));

    return [
      DropdownMenuItem<String?>(value: null, child: Text('catalog.all_regions'.tr())),
      if (areas.isNotEmpty) ...[
        DropdownMenuItem<String?>(
            enabled: false, value: '#a', child: header('catalog.zone_areas'.tr().toUpperCase())),
        for (final e in sorted(areas)) DropdownMenuItem<String?>(value: 'a:${e.key}', child: Text(e.value)),
      ],
      if (regions.isNotEmpty) ...[
        DropdownMenuItem<String?>(
            enabled: false, value: '#r', child: header('catalog.zone_regions'.tr().toUpperCase())),
        for (final e in sorted(regions)) DropdownMenuItem<String?>(value: 'r:${e.key}', child: Text(e.value)),
      ],
    ];
  }

  /// ¿Cumple la ruta con el país y la zona elegidos (`a:ES-AR` / `r:ES-Z`)? Basta con que pase por
  /// ellos: una ruta que cruza a Francia sale al filtrar por Francia. Sin elegir, sí.
  static bool matches(Map<String, dynamic> route, String? country, String? zone) {
    final o = _options(route);
    if (country != null && !o['countries']!.any((c) => '${c['code']}' == country)) return false;
    if (zone == null) return true;
    if (zone.startsWith('a:')) return o['areas']!.any((a) => '${a['key']}' == zone.substring(2));
    if (zone.startsWith('r:')) return o['regions']!.any((g) => '${g['key']}' == zone.substring(2));
    return true;
  }
}

/// Los desplegables de país y zona, uno junto al otro. No se pintan si no hay nada que elegir.
class ZoneFilterBar extends StatelessWidget {
  final List<Map<String, dynamic>> routes;
  final String? country;
  final String? zone;
  final void Function(String? country, String? zone) onChanged;

  const ZoneFilterBar({
    super.key,
    required this.routes,
    required this.country,
    required this.zone,
    required this.onChanged,
  });

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
        child: DropdownButtonHideUnderline(child: child),
      );

  @override
  Widget build(BuildContext context) {
    final countries = ZoneFilter.countries(routes);
    final showCountry = countries.length >= 2;
    final selCountry = showCountry && countries.containsKey(country) ? country : null;
    final zones = ZoneFilter.zoneItems(routes, selCountry);
    if (!showCountry && zones.isEmpty) return const SizedBox.shrink();

    final selZone = zones.any((i) => i.value == zone) ? zone : null;
    final names = countries.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        if (showCountry)
          Expanded(
            child: _box(DropdownButton<String?>(
              isExpanded: true,
              value: selCountry,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: AppColors.white, fontSize: 14),
              hint: Text('catalog.all_countries'.tr(), style: const TextStyle(color: AppColors.grey)),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('catalog.all_countries'.tr())),
                for (final e in names) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
              ],
              // Al cambiar de país la zona elegida ya no vale
              onChanged: (c) => onChanged(c, null),
            )),
          ),
        if (showCountry && zones.isNotEmpty) const SizedBox(width: 8),
        if (zones.isNotEmpty)
          Expanded(
            child: _box(DropdownButton<String?>(
              isExpanded: true,
              value: selZone,
              dropdownColor: AppColors.surface,
              icon: const Icon(Icons.place_outlined, color: AppColors.grey, size: 18),
              style: const TextStyle(color: AppColors.white, fontSize: 14),
              hint: Text('catalog.all_regions'.tr(), style: const TextStyle(color: AppColors.grey)),
              items: zones,
              onChanged: (z) => onChanged(selCountry, z),
            )),
          ),
      ]),
    );
  }
}

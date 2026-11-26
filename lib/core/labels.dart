import 'package:flutter/widgets.dart';
import 'package:easy_localization/easy_localization.dart';

/// Los valores que manda el servidor, en el idioma del motero.
///
/// El servidor habla en castellano por dentro —`difficulty` viaja como
/// `tranquila | moderada | exigente` y el nivel como `novato | intermedio |
/// experto`— porque son valores de un enum, no texto para leer. Lo que no se
/// puede hacer es pintarlos tal cual, y era lo que pasaba el 03-11-2026 en
/// tres sitios: la ficha de la ruta recién generada, el detalle de una ruta
/// guardada y el selector de nivel del perfil. Un alemán con la app en alemán
/// leía «exigente».
///
/// Aquí en un solo sitio, y no un `switch` por pantalla, para que la cuarta
/// pantalla que lo necesite no vuelva a inventarse su propia traducción.

/// Cuánto aprieta la ruta: `tranquila | moderada | exigente`.
///
/// Sin emoji, a diferencia de `planner.easy|moderate|hard`: esas son las
/// pastillas del planificador, y aquí el texto va dentro de una insignia que
/// ya lleva su icono.
String paceLabel(dynamic valor) => switch ('$valor') {
      'tranquila' => 'common.pace_easy'.tr(),
      'exigente' => 'common.pace_hard'.tr(),
      _ => 'common.pace_moderate'.tr(),
    };

/// El nivel del motero: `novato | intermedio | experto`.
///
/// Reutiliza las claves de la insignia del perfil, que ya están en los seis
/// idiomas, así que van en mayúsculas igual que allí.
String levelLabel(dynamic valor) => switch ('$valor') {
      'experto' => 'profile.level_expert'.tr(),
      'intermedio' => 'profile.level_intermediate'.tr(),
      _ => 'profile.level_novice'.tr(),
    };

/// Un número con un decimal en el idioma de la app: «22,9» en castellano o
/// alemán, «22.9» en inglés. Antes `toStringAsFixed(1)` ponía punto en todos
/// (visto en alemán el 25-11-2026).
String dec1(BuildContext context, dynamic v) =>
    NumberFormat('0.0', context.locale.toString()).format((v as num?) ?? 0);

/// «Honda PCX125 · 2021 · 125 cc», saltándose lo que no esté puesto. Año y
/// cilindrada no son obligatorios, y una moto sin ellos salía como
/// «Honda PCX125 ·  · cc» (visto el 25-11-2026).
String motoLabel(Map? m, {bool year = true}) {
  if (m == null) return '';
  String t(dynamic v) => v == null ? '' : '$v'.trim();
  final partes = <String>[
    '${t(m['brand'])} ${t(m['model'])}'.trim(),
    if (year) t(m['year']),
    if (t(m['engine_cc']).isNotEmpty && t(m['engine_cc']) != '0') '${t(m['engine_cc'])} cc',
  ];
  return partes.where((p) => p.isNotEmpty).join(' · ');
}

/// Las etiquetas de una ruta (`montana`, `curvas`…) viajan en castellano y sin
/// tildes: son valores, no texto. Se pintaban tal cual («montana»). Las que no
/// conocemos no se enseñan (y `importada` es una marca interna).
String? tagLabel(dynamic tag) {
  final k = 'route_tags.${'$tag'.trim().toLowerCase()}';
  final t = k.tr();
  return t == k ? null : t;
}


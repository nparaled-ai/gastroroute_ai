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

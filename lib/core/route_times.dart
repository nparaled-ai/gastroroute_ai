/// Las horas de una ruta cuando se repite a otra hora de salida.
///
/// Una ruta guarda **horas de reloj** —«llegas a las 10:10»—, no solo minutos
/// desde la salida: cada punto (`estimated_arrival_time`), la parada de
/// almorzar y la de comer (`estimated_time`) y la mejor hora de salida del
/// resumen de la IA (`best_departure_time`).
///
/// «Repetir» copiaba la ruta con la fecha y la hora nuevas y se dejaba todo eso
/// como estaba, así que repetir a las 11:00 una ruta de las 09:00 enseñaba los
/// puntos a las 10:10, **antes de salir**. Pasó el 04-11-2026 con la ruta de
/// prueba, y con la caducidad de las rutas «Repetir» es el camino normal de
/// quien llega tarde: cada repetición habría salido con las horas descuadradas.
///
/// Se mueven las cuatro lo mismo que se mueve la salida. Es una suma de
/// minutos: sin llamadas a Google ni a la IA, y por tanto sin coste.
library;

/// Minutos desde las 00:00 de una hora «HH:MM», o null si no se puede leer.
int? _minutesOf(String? time) {
  if (time == null) return null;
  final parts = time.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _format(int minutes) {
  // El módulo de Dart ya es positivo, pero una ruta que cruza la medianoche
  // lleva horas como «00:30»: tiene que seguir cruzándola tras moverla.
  final total = ((minutes % 1440) + 1440) % 1440;
  return '${(total ~/ 60).toString().padLeft(2, '0')}'
      ':${(total % 60).toString().padLeft(2, '0')}';
}

/// Mueve las horas de [data] lo que va de [oldDeparture] a [newDeparture].
///
/// Modifica [data] **sustituyendo** las estructuras de dentro por copias, nunca
/// tocándolas: [data] es una copia superficial de la ruta que se está viendo, y
/// los puntos y las paradas son los mismos objetos que ella. Mutarlos cambiaría
/// las horas de la pantalla de detrás.
///
/// Si no se puede leer alguna de las dos salidas no se toca nada: sin saber
/// cuánto se ha movido no hay forma honrada de mover las demás.
void shiftRouteTimes(
  Map<String, dynamic> data,
  String? oldDeparture,
  String newDeparture,
) {
  final from = _minutesOf(oldDeparture);
  final to = _minutesOf(newDeparture);
  if (from == null || to == null) return;

  final delta = to - from;
  if (delta == 0) return;

  String? shift(dynamic time) {
    final m = _minutesOf(time?.toString());
    return m == null ? time?.toString() : _format(m + delta);
  }

  final waypoints = data['waypoints'];
  if (waypoints is List) {
    final moved = <dynamic>[];
    for (final w in waypoints) {
      if (w is Map && w['estimated_arrival_time'] != null) {
        final copy = Map<String, dynamic>.from(w);
        copy['estimated_arrival_time'] = shift(w['estimated_arrival_time']);
        moved.add(copy);
      } else {
        moved.add(w);
      }
    }
    data['waypoints'] = moved;
  }

  for (final key in const ['lunch_stop', 'dinner_stop']) {
    final stop = data[key];
    if (stop is Map && stop['estimated_time'] != null) {
      final copy = Map<String, dynamic>.from(stop);
      copy['estimated_time'] = shift(stop['estimated_time']);
      data[key] = copy;
    }
  }

  final summary = data['ai_summary'];
  if (summary is Map && summary['best_departure_time'] != null) {
    final copy = Map<String, dynamic>.from(summary);
    copy['best_departure_time'] = shift(summary['best_departure_time']);
    data['ai_summary'] = copy;
  }
}

/// Una parada de comer que se ha quitado, y la hora a la que habría caído.
typedef RemovedMeal = ({String key, String time});

/// Quita las paradas de comer que, a su hora nueva, ya no caen en hora de comer.
///
/// Decidido el 04-11-2026, con un caso real: una ruta de las 09:00 con el
/// almuerzo a las 11:08, repetida a las 11:00, deja el almuerzo a las 13:08,
/// que en España ya no es hora de almorzar sino de comer; repetida a las 16:00
/// lo deja a las 18:08, que no es hora de nada. Mover las horas no basta: hay
/// que mirar si la parada sigue teniendo sentido.
///
/// Las franjas ([windows]) las manda el servidor, que es quien sabe a qué hora
/// se come en el país de la ruta (`App\Support\MealHours`): son la misma
/// estructura que `meal_windows`, con `lunch` y `dinner` y un `from` y un `to`.
/// Escribirlas también aquí sería tener dos copias, y la segunda se queda vieja.
/// Sin franjas no se quita nada.
///
/// Los extremos valen: a las 12:00 en punto todavía se almuerza.
///
/// Quita **la parada, no el punto**: el sitio sigue en la ruta como un punto
/// más, que es por donde se pasa de todas formas.
///
/// Devuelve lo quitado, para poder decírselo al motero.
List<RemovedMeal> dropOutOfHoursMeals(
  Map<String, dynamic> data,
  Map<dynamic, dynamic>? windows,
) {
  final removed = <RemovedMeal>[];
  if (windows == null) return removed;

  const stops = {'lunch_stop': 'lunch', 'dinner_stop': 'dinner'};

  stops.forEach((key, windowKey) {
    final stop = data[key];
    final window = windows[windowKey];
    if (stop is! Map || window is! Map) return;

    final time = stop['estimated_time']?.toString();
    final at = _minutesOf(time);
    final from = _minutesOf(window['from']?.toString());
    final to = _minutesOf(window['to']?.toString());
    if (at == null || from == null || to == null) return;

    if (at < from || at > to) {
      data[key] = null;
      removed.add((key: key, time: time!));
    }
  });

  return removed;
}

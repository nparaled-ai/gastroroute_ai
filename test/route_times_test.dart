import 'package:flutter_test/flutter_test.dart';
import 'package:gastroroute_ai/core/route_times.dart';

/// La ruta #8 tal como la guarda el servidor: sale a las 09:00.
Map<String, dynamic> ruta09() => {
      'departure_time': '09:00',
      'waypoints': [
        {'name': 'Fortín', 'estimated_arrival_time': '10:10', 'estimated_minutes_from_start': 70},
        {'name': 'Castillo de Zaida', 'estimated_arrival_time': '10:18', 'estimated_minutes_from_start': 78},
        {'name': 'Espartidero', 'estimated_arrival_time': '11:08', 'estimated_minutes_from_start': 128},
      ],
      'lunch_stop': {'location': 'Espartidero', 'estimated_time': '11:08'},
      'dinner_stop': null,
      'ai_summary': {'best_departure_time': '09:00', 'fuel_stops': [120]},
    };

List<String> horas(Map<String, dynamic> d) =>
    [for (final w in d['waypoints'] as List) (w as Map)['estimated_arrival_time'] as String];

void main() {
  test('repetir a las 11:00 una ruta de las 09:00 mueve todo dos horas', () {
    final d = ruta09();
    shiftRouteTimes(d, '09:00', '11:00');

    expect(horas(d), ['12:10', '12:18', '13:08']);
    expect(d['lunch_stop']['estimated_time'], '13:08');
    expect(d['ai_summary']['best_departure_time'], '11:00');
  });

  test('los minutos desde la salida y lo demás no se tocan', () {
    final d = ruta09();
    shiftRouteTimes(d, '09:00', '11:00');

    expect((d['waypoints'] as List)[0]['estimated_minutes_from_start'], 70);
    expect(d['lunch_stop']['location'], 'Espartidero');
    expect(d['ai_summary']['fuel_stops'], [120]);
    expect(d['dinner_stop'], isNull);
  });

  test('se puede mover hacia atrás: repetir a las 07:30', () {
    final d = ruta09();
    shiftRouteTimes(d, '09:00', '07:30');

    expect(horas(d), ['08:40', '08:48', '09:38']);
  });

  test('una ruta que cruza la medianoche sigue cruzándola', () {
    final d = <String, dynamic>{
      'waypoints': [
        {'estimated_arrival_time': '23:30'},
        {'estimated_arrival_time': '00:40'},
      ],
    };
    shiftRouteTimes(d, '22:00', '23:00');

    expect(horas(d), ['00:30', '01:40']);
  });

  test('moverlo hacia atrás pasando por la medianoche', () {
    final d = <String, dynamic>{
      'waypoints': [
        {'estimated_arrival_time': '00:30'},
      ],
    };
    shiftRouteTimes(d, '09:00', '08:00');

    expect(horas(d), ['23:30']);
  });

  test('NO muta la ruta original: la pantalla de detrás sigue como estaba', () {
    final original = ruta09();
    final copia = Map<String, dynamic>.from(original); // superficial, como en la app

    shiftRouteTimes(copia, '09:00', '11:00');

    expect(horas(original), ['10:10', '10:18', '11:08']);
    expect(original['lunch_stop']['estimated_time'], '11:08');
    expect(original['ai_summary']['best_departure_time'], '09:00');
    expect(horas(copia), ['12:10', '12:18', '13:08']);
  });

  test('misma hora de salida: no hace nada', () {
    final d = ruta09();
    shiftRouteTimes(d, '09:00', '09:00');

    expect(horas(d), ['10:10', '10:18', '11:08']);
  });

  test('si no se puede leer la salida vieja, no se toca nada', () {
    for (final vieja in [null, '', 'mañana', '9']) {
      final d = ruta09();
      shiftRouteTimes(d, vieja, '11:00');
      expect(horas(d), ['10:10', '10:18', '11:08'], reason: 'salida vieja: $vieja');
    }
  });

  test('una ruta sin paradas ni resumen no revienta', () {
    final d = <String, dynamic>{'waypoints': [], 'lunch_stop': null, 'ai_summary': null};
    shiftRouteTimes(d, '09:00', '11:00');
    expect(d['waypoints'], isEmpty);
  });

  group('paradas de comer fuera de hora', () {
    // España, tal como las manda el servidor (MealHours).
    final es = {
      'lunch': {'from': '09:00', 'to': '12:00', 'default': '11:00'},
      'dinner': {'from': '13:00', 'to': '15:00', 'default': '14:00'},
    };

    Map<String, dynamic> repetida(String hora) {
      final d = ruta09();
      shiftRouteTimes(d, '09:00', hora);
      return d;
    }

    test('a las 08:00 el almuerzo cae a las 10:08 y se queda', () {
      final d = repetida('08:00');
      final quitadas = dropOutOfHoursMeals(d, es);

      expect(quitadas, isEmpty);
      expect(d['lunch_stop']['estimated_time'], '10:08');
    });

    test('a las 11:00 el almuerzo cae a las 13:08 y se quita', () {
      final d = repetida('11:00');
      final quitadas = dropOutOfHoursMeals(d, es);

      expect(quitadas, [(key: 'lunch_stop', time: '13:08')]);
      expect(d['lunch_stop'], isNull);
    });

    test('a las 16:00 cae a las 18:08, que no es hora de nada: se quita', () {
      final d = repetida('16:00');
      final quitadas = dropOutOfHoursMeals(d, es);

      expect(quitadas.map((q) => q.key), ['lunch_stop']);
      expect(d['lunch_stop'], isNull);
    });

    test('quitar la parada no quita el punto: el sitio sigue en la ruta', () {
      final d = repetida('11:00');
      dropOutOfHoursMeals(d, es);

      expect(horas(d), ['12:10', '12:18', '13:08']);
      expect((d['waypoints'] as List).length, 3);
    });

    test('los extremos valen: las 12:00 todavia es almuerzo, las 12:01 no', () {
      final justo = <String, dynamic>{
        'lunch_stop': {'location': 'X', 'estimated_time': '12:00'},
      };
      expect(dropOutOfHoursMeals(justo, es), isEmpty);
      expect(justo['lunch_stop'], isNotNull);

      final pasado = <String, dynamic>{
        'lunch_stop': {'location': 'X', 'estimated_time': '12:01'},
      };
      expect(dropOutOfHoursMeals(pasado, es), hasLength(1));
      expect(pasado['lunch_stop'], isNull);
    });

    test('la comida se juzga con su franja, no con la del almuerzo', () {
      final bien = <String, dynamic>{
        'dinner_stop': {'location': 'X', 'estimated_time': '14:00'},
      };
      expect(dropOutOfHoursMeals(bien, es), isEmpty);

      final mal = <String, dynamic>{
        'dinner_stop': {'location': 'X', 'estimated_time': '11:30'},
      };
      expect(dropOutOfHoursMeals(mal, es).map((q) => q.key), ['dinner_stop']);
    });

    test('se pueden quitar las dos a la vez', () {
      final d = <String, dynamic>{
        'lunch_stop': {'estimated_time': '18:00'},
        'dinner_stop': {'estimated_time': '19:00'},
      };
      expect(dropOutOfHoursMeals(d, es), hasLength(2));
      expect(d['lunch_stop'], isNull);
      expect(d['dinner_stop'], isNull);
    });

    test('las franjas son las del pais: a las 12:30 en Francia ya se come', () {
      final fr = {
        'lunch': {'from': '10:00', 'to': '11:30'},
        'dinner': {'from': '12:00', 'to': '14:00'},
      };
      final d = <String, dynamic>{
        'dinner_stop': {'estimated_time': '12:30'},
      };
      expect(dropOutOfHoursMeals(d, fr), isEmpty);
      // y esa misma hora, con las de España, estaria fuera
      expect(dropOutOfHoursMeals({'dinner_stop': {'estimated_time': '12:30'}}, es), hasLength(1));
    });

    test('sin franjas no se quita nada', () {
      final d = repetida('16:00');
      expect(dropOutOfHoursMeals(d, null), isEmpty);
      expect(d['lunch_stop'], isNotNull);
    });

    test('paradas que no existen o sin hora: no revienta ni quita', () {
      final d = <String, dynamic>{
        'lunch_stop': null,
        'dinner_stop': {'location': 'X', 'estimated_time': null},
      };
      expect(dropOutOfHoursMeals(d, es), isEmpty);
      expect(d['dinner_stop'], isNotNull);
    });
  });
}
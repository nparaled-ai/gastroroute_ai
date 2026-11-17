import 'package:flutter_test/flutter_test.dart';
import 'package:gastroroute_ai/widgets/zone_filter.dart';

void main() {
  pruebasFrontera();
  final routes = <Map<String, dynamic>>[
    {'zone_country': 'ES', 'zone_country_name': 'España', 'zone_area': 'ES-AR', 'zone_region': 'ES-Z'},
    {'zone_country': 'ES', 'zone_country_name': 'España', 'zone_area': 'ES-CT', 'zone_region': 'ES-B'},
    {'zone_country': 'FR', 'zone_country_name': 'Francia', 'zone_area': 'FR-ARA', 'zone_region': 'FR-38'},
    {'title': 'sin zona'},
  ];

  test('países: uno por código, sin las rutas sin zona', () {
    expect(ZoneFilter.countries(routes), {'ES': 'España', 'FR': 'Francia'});
  });

  test('sin filtros pasan todas, también las rutas sin zona', () {
    expect(routes.where((r) => ZoneFilter.matches(r, null, null)).length, 4);
  });

  test('país: solo las de ese país', () {
    expect(routes.where((r) => ZoneFilter.matches(r, 'FR', null)).length, 1);
    expect(routes.where((r) => ZoneFilter.matches(r, 'ES', null)).length, 2);
  });

  test('comunidad y provincia', () {
    expect(routes.where((r) => ZoneFilter.matches(r, null, 'a:ES-AR')).length, 1);
    expect(routes.where((r) => ZoneFilter.matches(r, 'ES', 'r:ES-B')).length, 1);
    // una zona de otro país no cuela
    expect(routes.where((r) => ZoneFilter.matches(r, 'FR', 'a:ES-AR')).length, 0);
  });

  test('las opciones de zona solo son las del país elegido', () {
    final todas = ZoneFilter.zoneItems(routes, null).map((i) => i.value).toList();
    final fr = ZoneFilter.zoneItems(routes, 'FR').map((i) => i.value).toList();
    expect(todas, containsAll(['a:ES-AR', 'a:FR-ARA', 'r:ES-Z', 'r:FR-38']));
    expect(fr.contains('a:ES-AR'), isFalse);
    expect(fr, containsAll(['a:FR-ARA', 'r:FR-38']));
  });
}

void pruebasFrontera() {
  // Una ruta que cruza los Pirineos: sale en España y pasa a Francia
  final cruza = <String, dynamic>{
    'zone_country': 'ES',
    'zone_options': {
      'countries': [
        {'code': 'ES', 'name': 'España'},
        {'code': 'FR', 'name': 'Francia'},
      ],
      'areas': [
        {'key': 'ES-AR', 'country': 'ES', 'name': 'Aragón'},
        {'key': 'FR-NAQ', 'country': 'FR', 'name': 'Nueva Aquitania'},
      ],
      'regions': [
        {'key': 'ES-HU', 'country': 'ES', 'name': 'Huesca'},
        {'key': 'FR-64', 'country': 'FR', 'name': 'Pirineos Atlánticos'},
      ],
    },
  };
  final soloEspana = <String, dynamic>{'zone_country': 'ES', 'zone_country_name': 'España', 'zone_area': 'ES-CT', 'zone_region': 'ES-B'};
  final todas = [cruza, soloEspana];

  test('frontera: se encuentra desde cualquiera de sus países y zonas', () {
    expect(todas.where((r) => ZoneFilter.matches(r, 'FR', null)).length, 1);
    expect(todas.where((r) => ZoneFilter.matches(r, 'ES', null)).length, 2);
    expect(todas.where((r) => ZoneFilter.matches(r, null, 'r:FR-64')).length, 1);
    expect(todas.where((r) => ZoneFilter.matches(r, 'FR', 'a:ES-CT')).length, 0);
  });

  test('frontera: los países y las zonas del desplegable incluyen los del otro lado', () {
    expect(ZoneFilter.countries(todas).keys, containsAll(['ES', 'FR']));
    final fr = ZoneFilter.zoneItems(todas, 'FR').map((i) => i.value).toList();
    expect(fr, containsAll(['a:FR-NAQ', 'r:FR-64']));
    expect(fr.contains('a:ES-AR'), isFalse);
  });
}

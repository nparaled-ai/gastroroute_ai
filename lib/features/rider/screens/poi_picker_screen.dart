import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/services/route_tracking_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/poi_service.dart';

/// Explorar los puntos de interés de la zona y elegir por cuáles pasar.
///
/// NO es una pantalla de reglas: aquí no se impide nada. Si el motero entra y
/// marca un sitio, es que lo quiere, y la ruta pasará por él. Lo único que se
/// hace es avisar de en qué se traduce ("estos dos obligan a desviarse").
///
/// Hay DOS geometrías, porque una ruta circular y una con destino no se
/// parecen en nada:
///
///  - **Circular**: los puntos están en un ANILLO alrededor de la salida, y lo
///    que se regula es el radio.
///  - **Con destino**: están en un CORREDOR a lo largo del trayecto, y lo que
///    se regula es cuánto te dejas desviar de la línea. Un castillo a 380 km
///    de Zaragoza camino de Santander está de camino; con un círculo alrededor
///    de la salida no aparecería nunca.
///
/// En el corredor la lista va en orden de viaje —por el kilómetro en que te lo
/// encuentras— que además deja ver si queda un tramo largo sin nada.
class PoiPickerScreen extends StatefulWidget {
  final String origin;

  /// Obligatorio en rutas con destino: sin él no hay corredor que calcular.
  final String? destination;

  final int? km;
  final bool circular;

  /// Los que ya estaban elegidos, completos y no solo sus ids.
  ///
  /// Hacen falta enteros para poder enseñarlos arriba aunque el filtro activo
  /// los deje fuera de la lista: si eliges un puerto, luego filtras por
  /// monumentos y sales, al volver no habría forma de quitarlo.
  final List<Map<String, dynamic>> selected;

  /// Filtros tal y como se dejaron la última vez, para no empezar de cero.
  final String? initialCategory;
  final String? initialQuery;
  final int? initialRadiusKm;

  /// Hacia donde quiere tirar la ruta, si lo ha dicho. El servidor filtra los
  /// candidatos a ese sector: con una direccion elegida, los puntos de la
  /// direccion contraria no son candidatos, son ruido.
  final String? zoneHint;

  const PoiPickerScreen({
    super.key,
    required this.origin,
    required this.km,
    required this.circular,
    this.destination,
    this.selected = const [],
    this.initialCategory,
    this.initialQuery,
    this.initialRadiusKm,
    this.zoneHint,
  });

  @override
  State<PoiPickerScreen> createState() => _PoiPickerScreenState();
}

class _PoiPickerScreenState extends State<PoiPickerScreen> {
  /// Tope de puntos obligatorios.
  ///
  /// Cuantos más fuerces, menos margen tiene la IA para trazar y más se
  /// desvía la distancia de lo pedido. Ocho es lo acordado para rutas largas.
  static const _maxSelected = 8;

  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _pois = [];
  List<Map<String, dynamic>> _categories = [];

  /// Los elegidos, completos. El orden es el de elección.
  late List<Map<String, dynamic>> _selected =
      List<Map<String, dynamic>>.from(widget.selected);

  bool _loading = true;
  String? _error;
  String? _category;
  int? _radiusKm;
  String _mode = 'ring';

  /// Radio que le corresponde a esta ruta por su distancia.
  ///
  /// Es FIJO: se lee de la primera respuesta del servidor y no se vuelve a
  /// tocar. Los botones salen de aquí, no del radio actual — calculándolos
  /// sobre el actual, cada pulsación movía la escalera entera y no había forma
  /// de ver los valores grandes sin ir pulsando el mayor una y otra vez.
  int? _baseRadiusKm;

  /// Tope que permite el servidor para esta ruta. Ver [_maxRadiusKm].
  int? _serverMaxRadiusKm;

  Set<int> get _selectedIds =>
      _selected.map((p) => p['id'] as int).toSet();

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _radiusKm = widget.initialRadiusKm;
    _searchController.text = widget.initialQuery ?? '';
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _isCorridor => _mode == 'corridor';

  Future<void> _load() async {
    setState(() => _loading = true);

    final result = await PoiService.nearby(
      origin: widget.origin,
      destination: widget.destination,
      km: widget.km,
      circular: widget.circular,
      radiusKm: _radiusKm,
      category: _category,
      query: _searchController.text.trim(),
      zoneHint: widget.zoneHint,
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result['error'] != null) {
        _error = result['error'];
        return;
      }

      _error = null;
      _pois = result['pois'] as List<Map<String, dynamic>>;
      _mode = result['mode'] ?? 'ring';
      _radiusKm = (result['radius_km'] as num?)?.toInt();

      // Lo manda el servidor en cada respuesta y NO depende del radio que esté
      // puesto: es el que le toca a la ruta por su distancia. Así los botones
      // son siempre los mismos, entres cuando entres.
      _baseRadiusKm = (result['base_radius_km'] as num?)?.toInt() ?? _radiusKm;
      _serverMaxRadiusKm = (result['max_radius_km'] as num?)?.toInt();

      // Los conteos por categoría vienen SIEMPRE del total de la zona, sin
      // aplicar el filtro activo (lo calcula el servidor aparte). Antes había
      // aquí un `if (_category == null)` por miedo a que un filtro puesto
      // hiciera desaparecer los demás botones; lo que conseguía era que al
      // reabrir la pantalla con una categoría guardada no saliera ninguno.
      _categories = result['categories'] as List<Map<String, dynamic>>;
    });
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), _load);
  }

  void _setCategory(String? category) {
    setState(() => _category = category);
    _load();
  }

  void _setRadius(int km) {
    setState(() => _radiusKm = km);
    _load();
  }

  void _toggle(Map<String, dynamic> poi) {
    final id = poi['id'] as int;

    setState(() {
      if (_selectedIds.contains(id)) {
        _selected.removeWhere((p) => p['id'] == id);
      } else if (_selected.length < _maxSelected) {
        _selected.add(poi);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('poi_picker.max_reached'.plural(_maxSelected)),
          backgroundColor: AppColors.surface,
        ));
      }
    });
  }

  /// Los elegidos que obligan a desviarse. Es lo que alarga la ruta: un puerto
  /// no cuesta nada porque la carretera ya pasa por él.
  ///
  /// Se cuenta sobre los ELEGIDOS, no sobre la lista visible: con un filtro
  /// puesto, los que no salen en pantalla alargan la ruta igual.
  int get _detoursSelected =>
      _selected.where((p) => p['pass_through'] != true).length;

  /// Cuánto medirá la ruta si se pasa por los puntos elegidos, a ojo.
  ///
  /// Se calcula aquí, sin pedir nada al servidor: tenemos las coordenadas de
  /// la salida y de cada punto. Es una estimación, no una medida — suma de
  /// tramos en línea recta por un factor de carretera— pero sirve para lo que
  /// tiene que servir: que no te lleves la sorpresa al generar.
  ///
  /// El orden importa. En una circular se recorren por rumbo alrededor de la
  /// salida, que es como se recorre un anillo; con destino, por el orden en
  /// que caen en el trayecto. Sumarlos en el orden en que los fuiste tocando
  /// daría un número sin sentido.
  ///
  /// Devuelve null si no hay nada que estimar.
  int? get _estimatedKm {
    if (_selected.isEmpty) return null;

    final points = List<Map<String, dynamic>>.from(_selected);

    if (_isCorridor) {
      points.sort((a, b) =>
          ((a['progress_km'] ?? 0) as num).compareTo((b['progress_km'] ?? 0) as num));
    } else {
      // Por rumbo: norte, este, sur, oeste... así el recorrido da la vuelta en
      // vez de ir y volver cruzando el centro.
      points.sort((a, b) => _bearingOrder(a).compareTo(_bearingOrder(b)));
    }

    var metres = 0.0;
    double? prevLat, prevLng;

    for (final p in points) {
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();

      if (prevLat != null) {
        metres += RouteTrackingManager.haversine(prevLat, prevLng!, lat, lng);
      }
      prevLat = lat;
      prevLng = lng;
    }

    // Faltan los extremos: de la salida al primero, y del último al cierre.
    // No se conocen las coordenadas de la salida aquí, así que se aproximan
    // con la distancia que el servidor ya calculó de cada punto.
    final first = points.first;
    final last = points.last;
    metres += ((first['distance_km'] as num).toDouble() +
            (last['distance_km'] as num).toDouble()) *
        1000;

    // La carretera real entre dos puntos mide un 20-40% más que la línea
    // recta. Es el mismo factor que se le dice a la IA en el prompt.
    return (metres / 1000 * 1.3).round();
  }

  double _bearingOrder(Map<String, dynamic> poi) {
    const compass = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    final i = compass.indexOf('${poi['direction']}');
    return i < 0 ? 0 : i.toDouble();
  }

  /// Lo que devuelve la pantalla: los puntos y cómo quedaron los filtros.
  void _close() => Navigator.pop(context, {
        'pois': _selected,
        'category': _category,
        'query': _searchController.text.trim(),
        'radius_km': _radiusKm,
      });

  /// Opciones del control de alcance.
  ///
  /// En el corredor son kilómetros absolutos: a 30 km de la carretera ya estás
  /// haciendo un desvío serio, mida el viaje 200 km o 600. En el anillo son
  /// relativos al radio que le toca a esa ruta, porque 150 km no significan lo
  /// mismo en una ruta de 100 que en una de 800.
  /// Rango del deslizador.
  ///
  /// El tope lo decide el servidor. En el anillo son 400 km —puedes mirar tan
  /// lejos como quieras, sigue siendo alrededor de tu salida— pero en el
  /// corredor depende de lo largo que sea el viaje: con el tope fijo, una ruta
  /// Zaragoza-Santander ofrecía puntos de Teruel, que cuestan 252 km de desvío
  /// sobre un viaje de 311.
  int get _minRadiusKm => _isCorridor ? 5 : 10;
  int get _maxRadiusKm => _serverMaxRadiusKm ?? (_isCorridor ? 100 : 400);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('poi_picker.title'.tr(),
            style: const TextStyle(
                color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _close,
            child: Text(
              _selected.isEmpty
                  ? 'poi_picker.done'.tr()
                  : '${'poi_picker.done'.tr()} (${_selected.length})',
              style: const TextStyle(
                  color: AppColors.orange, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: _error != null ? _buildError() : _buildBody(),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grey)),
        ),
      );

  Widget _buildBody() {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: const TextStyle(color: AppColors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'poi_picker.search_hint'.tr(),
            hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: AppColors.grey, size: 20),
            filled: true,
            fillColor: AppColors.surface,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Alcance: radio del anillo o anchura del corredor.
        Text(
          _isCorridor
              ? 'poi_picker.corridor_label'.tr()
              : 'poi_picker.radius_label'.tr(),
          style: const TextStyle(color: AppColors.grey, fontSize: 11),
        ),
        const SizedBox(height: 6),
        // Deslizador y no botones fijos.
        //
        // Primero fueron cuatro botones relativos al radio de la ruta
        // (½, ×1, ×1½, ×2). El problema: con una ruta de 300 km el radio base
        // es 60 y el tope quedaba en 120 km, sin forma de mirar más allá.
        // Aquí el rango importa más que la comodidad de un toque.
        Row(children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.orange,
                inactiveTrackColor: AppColors.greyDark,
                thumbColor: AppColors.orange,
                overlayColor: AppColors.orange.withValues(alpha: 0.15),
                trackHeight: 3,
              ),
              child: Slider(
                value: (_radiusKm ?? _baseRadiusKm ?? 60)
                    .clamp(_minRadiusKm, _maxRadiusKm)
                    .toDouble(),
                min: _minRadiusKm.toDouble(),
                max: _maxRadiusKm.toDouble(),
                divisions: (_maxRadiusKm - _minRadiusKm) ~/ 5,
                // Mientras se arrastra solo se mueve el número: la lista se
                // recarga al soltar, o serían decenas de peticiones.
                onChanged: (v) => setState(() => _radiusKm = v.round()),
                onChangeEnd: (_) => _load(),
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text('${_radiusKm ?? _baseRadiusKm ?? 60} km',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ]),

        // El que le toca a la ruta, para que se sepa cuál es el bueno.
        if (_baseRadiusKm != null && _radiusKm != _baseRadiusKm)
          GestureDetector(
            onTap: () => _setRadius(_baseRadiusKm!),
            child: Text(
              'poi_picker.recommended'.tr(namedArgs: {'km': '$_baseRadiusKm'}),
              style: const TextStyle(color: AppColors.cyan, fontSize: 11),
            ),
          ),

        const SizedBox(height: 14),

        if (_categories.isNotEmpty) ...[
          Text('poi_picker.type_label'.tr(),
              style: const TextStyle(color: AppColors.grey, fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(
                label: 'poi_picker.all'.tr(),
                selected: _category == null,
                onTap: () => _setCategory(null),
                accent: AppColors.cyan,
              ),
              ..._categories.map((c) => _Chip(
                    label: '${_categoryName(c['category'])} ${c['count']}',
                    selected: _category == c['category'],
                    onTap: () => _setCategory(c['category']),
                    accent: AppColors.cyan,
                  )),
            ],
          ),
          const SizedBox(height: 14),
        ],

        _SelectionMap(
          origin: widget.origin,
          destination: widget.destination,
          km: widget.km,
          circular: widget.circular,
          radiusKm: _radiusKm,
          category: _category,
          query: _searchController.text.trim(),
          selected: _selectedIds.toList()..sort(),
          total: _pois.length,
          zoneHint: widget.zoneHint,
        ),

        const SizedBox(height: 14),

        if (_selected.isNotEmpty) ...[
          _buildEstimate(),
          const SizedBox(height: 10),

          // Los elegidos, siempre arriba y siempre visibles.
          //
          // Van aquí y no mezclados abajo porque con un filtro puesto podrían
          // no aparecer: eliges un puerto, filtras por monumentos, y te
          // quedas sin forma de quitarlo.
          Text('poi_picker.chosen_header'.plural(_selected.length),
              style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._selected.map(_buildRow),
          const Divider(color: AppColors.greyDark, height: 24),
        ],

        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.orange)),
          )
        else if (_pois.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('poi_picker.empty'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grey, height: 1.5)),
          )
        else
          // Los elegidos ya están arriba: aquí no se repiten.
          ..._pois
              .where((p) => !_selectedIds.contains(p['id']))
              .map(_buildRow),
      ],
    );
  }

  /// Cuánto va a medir la ruta con los puntos elegidos, y si eso cuadra con lo
  /// que pediste.
  ///
  /// Enseñar el número es mucho más útil que un "será más larga": con tres
  /// puntos en direcciones opuestas la cifra se dispara sola y se entiende al
  /// instante por qué.
  Widget _buildEstimate() {
    final estimate = _estimatedKm;
    final target = widget.km;

    // Se considera que se pasa cuando supera en más de un cuarto lo pedido,
    // el mismo margen con el que el servidor descarta una ruta por larga.
    final over = estimate != null && target != null && estimate > target * 1.25;

    final color = over ? AppColors.error : AppColors.orange;

    final text = target == null
        ? 'poi_picker.estimate_plain'.tr(namedArgs: {'km': '$estimate'})
        : 'poi_picker.estimate'.tr(namedArgs: {
            'km': '$estimate',
            'target': '$target',
          });

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(over ? Icons.warning_amber_rounded : Icons.straighten,
            color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600)),
              if (_detoursSelected > 0) ...[
                const SizedBox(height: 3),
                Text('poi_picker.km_warning'.plural(_detoursSelected),
                    style: const TextStyle(
                        color: AppColors.grey, fontSize: 11, height: 1.3)),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  /// Nombre legible de la categoría, con respaldo por si aparece una nueva en
  /// la tabla que aún no esté traducida.
  String _categoryName(String? category) {
    if (category == null) return '';
    final key = 'poi_picker.cat_$category';
    final name = key.tr();
    return name == key ? category.replaceAll('_', ' ') : name;
  }

  Widget _buildRow(Map<String, dynamic> poi) {
    final id = poi['id'] as int;
    final selected = _selectedIds.contains(id);
    final passThrough = poi['pass_through'] == true;
    final label = poi['label'];
    final description = poi['description'];

    return GestureDetector(
      onTap: () => _toggle(poi),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.orange : AppColors.greyDark,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Sin número si no cabía en el mapa: se puede elegir igual.
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: label == null ? 0.07 : 0.2),
              shape: BoxShape.circle,
            ),
            child: label == null
                ? const Icon(Icons.place_outlined,
                    color: AppColors.grey, size: 13)
                : Text('$label',
                    style: const TextStyle(
                        color: AppColors.cyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${poi['name']}',
                    style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Text(
                      _subtitleFor(poi),
                      style: const TextStyle(color: AppColors.grey, fontSize: 11),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (passThrough ? Colors.green : AppColors.gold)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      passThrough
                          ? 'poi_picker.pass_through'.tr()
                          : 'poi_picker.needs_stop'.tr(),
                      style: TextStyle(
                        color: passThrough ? Colors.green : AppColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]),
                if (description != null && '$description'.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('$description',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.grey, fontSize: 10, height: 1.3)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? AppColors.orange : AppColors.greyDark,
            size: 22,
          ),
        ]),
      ),
    );
  }

  /// En el corredor lo que importa es por qué kilómetro del viaje cae y cuánto
  /// te sales; en el anillo, a qué distancia y en qué dirección está.
  String _subtitleFor(Map<String, dynamic> poi) {
    if (_isCorridor && poi['progress_km'] != null) {
      return 'poi_picker.on_route'.tr(namedArgs: {
        'at': '${poi['progress_km']}',
        'off': '${poi['distance_km']}',
      });
    }

    return '${poi['distance_km']} km · ${poi['direction']}';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = AppColors.orange,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? accent : AppColors.greyDark),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.background : AppColors.grey,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Mapa que se repinta cuando cambian los elegidos o los filtros, sin machacar
/// la API.
///
/// El mapa lo dibuja el servidor (Google Static Maps) y cada repintado se
/// factura, así que: solo se recarga si cambia algo de verdad, espera a que el
/// motero deje de tocar, y mientras llega el nuevo deja el anterior para que
/// no parpadee.
class _SelectionMap extends StatefulWidget {
  final String origin;
  final String? destination;
  final int? km;
  final bool circular;
  final int? radiusKm;
  final String? category;
  final String query;
  final List<int> selected;
  final int total;
  final String? zoneHint;

  const _SelectionMap({
    required this.origin,
    required this.destination,
    required this.km,
    required this.circular,
    required this.radiusKm,
    required this.category,
    required this.query,
    required this.selected,
    required this.total,
    required this.zoneHint,
  });

  @override
  State<_SelectionMap> createState() => _SelectionMapState();
}

class _SelectionMapState extends State<_SelectionMap> {
  /// Tope de marcadores con número de Google Static Maps.
  static const _maxOnMap = 25;
  static const _debounce = Duration(milliseconds: 700);

  Uint8List? _image;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_SelectionMap old) {
    super.didUpdateWidget(old);

    final changed = old.radiusKm != widget.radiusKm ||
        old.category != widget.category ||
        old.query != widget.query ||
        old.selected.length != widget.selected.length ||
        !old.selected.every(widget.selected.contains);

    if (!changed) return;

    _timer?.cancel();
    _timer = Timer(_debounce, _load);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final bytes = await PoiService.nearbyMap(
      origin: widget.origin,
      destination: widget.destination,
      km: widget.km,
      circular: widget.circular,
      radiusKm: widget.radiusKm,
      category: widget.category,
      query: widget.query,
      selected: widget.selected,
      zoneHint: widget.zoneHint,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      // Si falla se conserva el anterior: mejor un mapa algo desfasado que un
      // hueco gris.
      if (bytes != null) _image = bytes;
    });
  }

  /// Abre el mapa a pantalla completa, con zoom.
  ///
  /// No se pide una imagen nueva: la que ya está cargada viene a escala 2
  /// (1280x800 reales para una caja de 640x400), así que hay detalle de sobra
  /// para ampliar sin pedirle otra a Google —y sin pagarla.
  void _openFullscreen() {
    final image = _image;
    if (image == null) return;

    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: AppColors.white),
            onPressed: () => Navigator.pop(ctx),
          ),
        ),
        body: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(child: Image.memory(image)),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openFullscreen,
      child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(children: [
        if (_image != null)
          Image.memory(_image!, fit: BoxFit.cover, width: double.infinity)
        else
          Container(height: 200, color: AppColors.surface),

        // Pista de que se puede ampliar: una imagen fija no lo sugiere.
        if (_image != null)
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.zoom_out_map,
                  color: AppColors.grey, size: 15),
            ),
          ),
        if (_loading)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.orange),
              ),
            ),
          ),
        // Solo cuando la lista tiene más de los que caben: si no, sobra.
        if (widget.total > _maxOnMap)
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'poi_picker.on_map'.tr(namedArgs: {
                  'shown': '$_maxOnMap',
                  'total': '${widget.total}',
                }),
                style: const TextStyle(color: AppColors.grey, fontSize: 10),
              ),
            ),
          ),
      ]),
      ),
    );
  }
}

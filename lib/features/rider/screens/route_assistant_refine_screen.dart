import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/place_sheet.dart';
import '../providers/rider_profile_service.dart';
import '../providers/route_assistant_service.dart';
import '../providers/route_service.dart';
import 'poi_picker_screen.dart';

/// Tercera pantalla del asistente: afinar la ruta antes de generarla.
///
/// Todo lo de aquí es opcional: se puede llegar y darle a generar. Lo que no
/// puede faltar se quedó en la pantalla anterior.
///
/// El orden lo marca cuánto decide cada cosa sobre el trazado:
///  1. **Dirección** — en una circular las cuatro direcciones cumplen igual el
///     encargo, así que esto es lo único que decide el rumbo. En una ruta con
///     destino no aparece: la dirección ya la marca el destino.
///  2. **Por dónde quiero pasar** — los sitios que ha pedido el motero, de la
///     frase o del mapa. Son obligatorios y ni el radio ni el recorte los
///     tocan.
///  3. **Lo que añade la app** — relleno, y solo si el motero no ha elegido
///     nada a mano.
class RouteAssistantRefineScreen extends StatefulWidget {
  /// La frase original, que viaja con la petición y se guarda con la ruta.
  final String request;

  /// Todo lo decidido en la pantalla anterior.
  final Map<String, dynamic> fields;

  /// Se avisa al volver atrás con lo que se haya tocado aquí, para que la
  /// pantalla anterior lo guarde y no se pierda al entrar otra vez.
  final void Function(Map<String, dynamic>)? onBack;

  const RouteAssistantRefineScreen({
    super.key,
    required this.request,
    required this.fields,
    this.onBack,
  });

  @override
  State<RouteAssistantRefineScreen> createState() =>
      _RouteAssistantRefineScreenState();
}

class _RouteAssistantRefineScreenState
    extends State<RouteAssistantRefineScreen> {
  late final Map<String, dynamic> _fields =
      Map<String, dynamic>.from(widget.fields);

  /// Las zonas de su entorno, para ofrecerlas como dirección.
  ///
  /// Salen de los POIs marcados a mano como destacados, cuyo campo `region`
  /// tiene los nombres que usa un motero —Pirineo Aragonés, Sierra de Guara—
  /// mientras que los 53.000 importados traen ahí la comunidad autónoma.
  List<String> _zones = [];

  /// Los POIs elegidos en el mapa, enteros y no solo sus ids: hacen falta para
  /// enseñarlos aquí con su nombre y su desvío.
  List<Map<String, dynamic>> _pois = [];

  /// Los filtros del selector, para no empezar de cero al volver a abrirlo.
  String? _poiCategory;
  String? _poiQuery;
  int? _poiRadiusKm;

  bool _generating = false;

  /// La moto elegida, para saber si se le puede calcular la autonomia.
  ///
  /// Sin deposito y consumo no hay forma de decir cada cuanto repostar, y
  /// ofrecerlo igual seria prometer algo que el servidor no puede calcular.
  Map<String, dynamic>? _moto;

  @override
  void initState() {
    super.initState();
    _pois = List<Map<String, dynamic>>.from(_fields['_pois'] ?? const []);
    _fixMealDefaults();
    if (_circular) _loadZones();
    _loadMoto();
  }

  /// Las paradas que vienen marcadas de la frase, pero sin hora.
  ///
  /// La IA entiende "y parar a almorzar" y pone `suggest_lunch`, pero rara vez
  /// una hora, porque el motero no la ha dicho. Sin esto la parada quedaba
  /// activada y sin hora: el generador sin el dato que necesita para colocarla
  /// en el punto que toca, y en pantalla un interruptor encendido que no dice
  /// cuándo.
  void _fixMealDefaults() {
    if (_fields['suggest_lunch'] == true) {
      // Y si sale a mediodía, directamente no hay almuerzo que valga, lo
      // hubiera dicho o no.
      if (!_lunchMakesSense) {
        _fields['suggest_lunch'] = false;
        _fields['lunch_time'] = null;
      } else if (_minutesOf(_fields['lunch_time']) == null) {
        _fields['lunch_time'] = _hhmm(_defaultLunch);
      }
    }

    if (_fields['suggest_dinner'] == true &&
        _minutesOf(_fields['dinner_time']) == null) {
      _fields['dinner_time'] = _hhmm(_defaultDinner);
    }
  }

  bool get _circular => _fields['circular'] != true ? false : true;

  /// La moto de la ruta, para saber si tiene depósito y consumo cargados.
  Future<void> _loadMoto() async {
    final result = await RiderProfileService.getMotos();
    if (!mounted || result['motos'] == null) return;

    final motos = List<Map<String, dynamic>>.from(result['motos']);

    setState(() => _moto = motos.firstWhere(
          (m) => m['id'] == _fields['moto_id'],
          orElse: () => const <String, dynamic>{},
        ));
  }

  /// Si se le puede calcular la autonomía a esta moto.
  bool get _hasFuelData =>
      _moto?['fuel_capacity'] != null &&
      _moto?['consumption_per_100km'] != null;

  Future<void> _loadZones() async {
    final lat = _toDouble(_fields['origin_lat']);
    final lng = _toDouble(_fields['origin_lng']);
    if (lat == null || lng == null) return;

    final zones = await RouteAssistantService.zones(lat, lng);
    if (!mounted || zones.isEmpty) return;

    setState(() => _zones = zones);
  }

  // ─── Los sitios por los que se quiere pasar ──────────────────────────

  /// Los sitios escritos o dichos en la frase.
  List<String> get _customPoints =>
      List<String>.from(_fields['custom_points'] ?? const []);

  /// Dónde cae cada sitio escrito, cuando se pudo averiguar al buscarlo.
  ///
  /// Sin coordenada no hay forma de estimar nada: un nombre suelto no se puede
  /// medir. Por eso un sitio añadido a mano se busca, en vez de guardarse como
  /// texto a secas.
  Map<String, dynamic> get _pointCoords =>
      Map<String, dynamic>.from(_fields['_point_coords'] ?? const {});

  /// Tope del generador: 5 escritos y 8 del selector.
  bool get _canAddCustom => _customPoints.length < 5;

  Future<void> _addPoint() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => PlaceSheet(title: 'refine.add_point'.tr()),
    );

    if (result == null || !mounted) return;

    final name = '${result['description']}'.trim();
    if (name.isEmpty || _customPoints.contains(name)) return;

    setState(() {
      _fields['custom_points'] = [..._customPoints, name];

      final lat = _toDouble(result['lat']);
      final lng = _toDouble(result['lng']);
      if (lat != null && lng != null) {
        _fields['_point_coords'] = {
          ..._pointCoords,
          name: {'lat': lat, 'lng': lng},
        };
      }
    });
  }

  void _removePoint(String name) {
    setState(() {
      _fields['custom_points'] =
          _customPoints.where((p) => p != name).toList();
      _fields['_point_coords'] = Map<String, dynamic>.from(_pointCoords)
        ..remove(name);
    });
  }

  Future<void> _openPicker() async {
    final origin = '${_fields['origin'] ?? ''}';
    if (origin.isEmpty) return;

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => PoiPickerScreen(
          origin: origin,
          destination: _circular ? null : '${_fields['destination'] ?? ''}',
          // Solo se pasan los km si eligió ese modo: así el servidor acota el
          // radio a lo que de verdad cabe en su ruta.
          km: _fields['duration_mode'] == 'km'
              ? _toDouble(_fields['km'])?.round()
              : null,
          circular: _circular,
          selected: _pois,
          initialCategory: _poiCategory,
          initialQuery: _poiQuery,
          initialRadiusKm: _poiRadiusKm,
          // Si ya dijo hacia dónde tira, que el mapa no le enseñe lo que le
          // queda a la espalda.
          zoneHint: _circular ? '${_fields['zone_hint'] ?? ''}' : null,
        ),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _pois = List<Map<String, dynamic>>.from(result['pois'] ?? const []);
      _poiCategory = result['category'];
      _poiQuery = result['query'];
      _poiRadiusKm = result['radius_km'];
    });
  }

  // ─── El aviso de kilómetros ──────────────────────────────────────────

  /// Cuánto puede alargarse la ruta por los puntos elegidos.
  ///
  /// Es una ESTIMACIÓN y se dice que lo es: aquí solo hay líneas rectas. Los
  /// kilómetros de verdad los da Google al generar, y la hora de llegada a
  /// cada punto no existe hasta entonces — prometerla aquí sería inventarla.
  ///
  /// Se mide el ida y vuelta al punto más lejano, con el factor 1,3 de
  /// carretera sobre línea recta que ya usa el selector de POIs.
  int? get _estimatedKm {
    final pedidos = _toDouble(_fields['km']);
    if (pedidos == null || _fields['duration_mode'] != 'km') return null;

    final lat = _toDouble(_fields['origin_lat']);
    final lng = _toDouble(_fields['origin_lng']);
    if (lat == null || lng == null) return null;

    var lejano = 0.0;

    for (final p in _pois) {
      final pLat = _toDouble(p['lat']);
      final pLng = _toDouble(p['lng']);
      if (pLat == null || pLng == null) continue;
      lejano = math.max(lejano, _haversineKm(lat, lng, pLat, pLng));
    }

    for (final entry in _pointCoords.entries) {
      final c = entry.value;
      final pLat = _toDouble(c is Map ? c['lat'] : null);
      final pLng = _toDouble(c is Map ? c['lng'] : null);
      if (pLat == null || pLng == null) continue;
      lejano = math.max(lejano, _haversineKm(lat, lng, pLat, pLng));
    }

    if (lejano == 0) return null;

    // Un bucle que llega a un punto a X km mide como mínimo el ida y vuelta.
    final minimo = lejano * 2 * 1.3;

    return minimo > pedidos * 1.1 ? minimo.round() : null;
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    return 6371 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double? _toDouble(dynamic v) => switch (v) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };

  // ─── Pintar ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final estimated = _estimatedKm;

    return PopScope(
      // Al volver atrás se devuelve TODO lo tocado aquí, para que la pantalla
      // anterior lo guarde y al entrar otra vez siga puesto. Sin esto, ir a
      // corregir la hora de salida te borraba la dirección, los sitios y los
      // puntos de interés que acababas de elegir.
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _returnState();
      },
      child: _build(context, estimated),
    );
  }

  /// Lo que se lleva de vuelta a la pantalla anterior.
  void _returnState() {
    _fields['_pois'] = _pois;
    _onBack?.call(_fields);
  }

  /// Quien quiera enterarse de lo que se tocó aquí.
  void Function(Map<String, dynamic>)? get _onBack => widget.onBack;

  Widget _build(BuildContext context, int? estimated) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        // Explícita, no confiada a que Flutter la deduzca: la pantalla
        // anterior la pone a mano y aquí no salía.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('refine.title'.tr(),
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            Text('refine.subtitle'.tr(),
                style: const TextStyle(color: AppColors.grey, fontSize: 10.5)),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          // La dirección solo manda en las circulares.
          if (_circular) ...[
            _label('refine.direction'.tr()),
            _directionDecided ? _directionDecidedCard() : _directionCard(),
            const SizedBox(height: 14),
          ],

          _label('refine.pass_through'.tr()),
          _pointsCard(),

          if (estimated != null) ...[
            const SizedBox(height: 6),
            _estimateWarning(estimated),
          ],

          const SizedBox(height: 14),

          _label('refine.app_adds'.tr()),
          _poiStopsCard(),
          const SizedBox(height: 14),

          _label('refine.rest'.tr()),
          _restCard(),

          if (_suggestedDinner != null) ...[
            const SizedBox(height: 6),
            _mealGapWarning(_suggestedDinner!),
          ],

          const SizedBox(height: 18),

          ElevatedButton(
            onPressed:
                (_generating || _suggestedDinner != null) ? null : _generate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              disabledBackgroundColor: AppColors.greyDark,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                // Apagado dice por qué: un botón gris sin explicación obliga a
                // buscar por la pantalla qué es lo que falla.
                : Text(
                    _suggestedDinner != null
                        ? 'refine.meal_gap_short'.tr()
                        : 'assistant.generate'.tr(),
                    style: TextStyle(
                        color: _suggestedDinner != null
                            ? AppColors.grey
                            : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.grey,
                fontSize: 10.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600)),
      );

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  /// Si ya hay sitios elegidos, la dirección está decidida por ellos.
  ///
  /// Preguntarla además permitiría contradecirse —"hacia el sur" con un punto
  /// al norte— y no habría forma de saber cuál manda. Manda el punto, que es
  /// lo concreto.
  bool get _directionDecided => _customPoints.isNotEmpty || _pois.isNotEmpty;

  Widget _directionDecidedCard() {
    final first = _customPoints.isNotEmpty
        ? _customPoints.first
        : '${_pois.first['name'] ?? ''}';

    return _card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(children: [
          const Icon(Icons.explore_outlined, color: AppColors.grey, size: 16),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('refine.direction_label'.tr(),
                    style: const TextStyle(
                        color: AppColors.grey, fontSize: 10.5)),
                const SizedBox(height: 2),
                Text('refine.direction_by_points'.tr(namedArgs: {'place': first}),
                    style: const TextStyle(
                        color: AppColors.grey, fontSize: 12.5)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _directionCard() {
    final current = '${_fields['zone_hint'] ?? ''}';

    return _card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Con la etiqueta sola hay que deducir el valor del botón que esté
            // encendido. Puesto como las demás filas —etiqueta arriba, valor
            // debajo— se lee de un vistazo igual que en la pantalla anterior.
            Row(children: [
              const Icon(Icons.explore_outlined,
                  color: AppColors.grey, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('refine.direction_label'.tr(),
                        style: const TextStyle(
                            color: AppColors.grey, fontSize: 10.5)),
                    const SizedBox(height: 2),
                    Text(
                      current.isEmpty ? 'refine.let_ai'.tr() : current,
                      style: TextStyle(
                          color: current.isEmpty
                              ? AppColors.grey
                              : AppColors.white,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final zone in _zones)
                  _chip(zone, current == zone, () => _setZone(zone)),
                // "Que decida la IA" es simplemente no mandar zona.
                _chip('refine.let_ai'.tr(), current.isEmpty,
                    () => _setZone(null)),
                _chip('refine.other_zone'.tr(),
                    current.isNotEmpty && !_zones.contains(current), _askZone,
                    accent: true),
              ],
            ),
            const SizedBox(height: 8),
            Text('refine.direction_help'.tr(),
                style: const TextStyle(
                    color: AppColors.greyDark, fontSize: 10, height: 1.4)),
          ],
        ),
      ),
    );
  }

  void _setZone(String? zone) => setState(() => _fields['zone_hint'] = zone);

  Future<void> _askZone() async {
    final controller =
        TextEditingController(text: '${_fields['zone_hint'] ?? ''}');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: AppColors.white, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'refine.direction_label'.tr(),
                  labelStyle: const TextStyle(color: AppColors.grey),
                  hintText: 'refine.other_zone_hint'.tr(),
                  hintStyle: const TextStyle(
                      color: AppColors.greyDark, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  minimumSize: const Size(double.infinity, 46),
                ),
                child: Text('common.save'.tr(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );

    if (saved != true) return;

    final text = controller.text.trim();
    _setZone(text.isEmpty ? null : text);
  }

  Widget _chip(String label, bool active, VoidCallback onTap,
          {bool accent = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? AppColors.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: active
                    ? AppColors.orange
                    : (accent ? AppColors.cyan : AppColors.greyDark)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active
                      ? AppColors.background
                      : (accent ? AppColors.cyan : AppColors.grey),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      );

  Widget _pointsCard() {
    final points = _customPoints;

    return _card(
      child: Column(children: [
        for (final name in points)
          _pointRow(
            icon: Icons.chat_bubble_outline,
            iconColor: AppColors.orange,
            name: name,
            note: _noteForCustom(name),
            onRemove: () => _removePoint(name),
          ),

        for (final poi in _pois)
          _pointRow(
            icon: Icons.place_outlined,
            iconColor: AppColors.cyan,
            name: '${poi['name'] ?? ''}',
            note: 'refine.from_map'.tr(),
            onRemove: () => setState(() => _pois.remove(poi)),
          ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            if (_canAddCustom)
              _action(Icons.search, 'refine.search_place'.tr(), _addPoint),
            if (_canAddCustom) const SizedBox(width: 18),
            _action(Icons.map_outlined, 'refine.pick_on_map'.tr(), _openPicker),
          ]),
        ),
      ]),
    );
  }

  /// Lo que se sabe de un sitio escrito: a qué distancia cae, si se pudo
  /// averiguar al buscarlo.
  String _noteForCustom(String name) {
    final said = List<String>.from(widget.fields['custom_points'] ?? const []);
    final origen = said.contains(name)
        ? 'refine.you_said'.tr()
        : 'refine.added_by_you'.tr();

    final c = _pointCoords[name];
    final lat = _toDouble(_fields['origin_lat']);
    final lng = _toDouble(_fields['origin_lng']);

    if (c is! Map || lat == null || lng == null) return origen;

    final pLat = _toDouble(c['lat']);
    final pLng = _toDouble(c['lng']);
    if (pLat == null || pLng == null) return origen;

    final km = _haversineKm(lat, lng, pLat, pLng).round();
    return '$origen · ${'refine.km_from_start'.tr(namedArgs: {'km': '$km'})}';
  }

  Widget _pointRow({
    required IconData icon,
    required Color iconColor,
    required String name,
    required String note,
    required VoidCallback onRemove,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppColors.greyDark, width: 0.5)),
        ),
        child: Row(children: [
          Icon(icon, color: iconColor, size: 15),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.white, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(note,
                    style: const TextStyle(
                        color: AppColors.greyDark, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.grey, size: 16),
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(6),
          ),
        ]),
      );

  Widget _action(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: AppColors.cyan, size: 15),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: AppColors.cyan, fontSize: 12)),
        ]),
      );

  /// Almuerzo y comida demasiado pegados.
  ///
  /// No se limita a decir que está mal: trae la hora que sí vale y la pone de
  /// un toque. Un aviso que te deja el problema para que lo resuelvas tú es la
  /// mitad del trabajo.
  Widget _mealGapWarning(int suggested) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.10),
          border:
              const Border(left: BorderSide(color: AppColors.error, width: 3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'refine.meal_gap'.tr(namedArgs: {
                    'hours': '${_mealGapMinutes ~/ 60}',
                    'suggested': _hhmm(suggested),
                  }),
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 10.5, height: 1.45),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => setState(
                      () => _fields['dinner_time'] = _hhmm(suggested)),
                  child: Text(
                    'refine.meal_gap_fix'
                        .tr(namedArgs: {'time': _hhmm(suggested)}),
                    style: const TextStyle(
                        color: AppColors.cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ]),
      );

  Widget _estimateWarning(int km) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.10),
          border: const Border(
              left: BorderSide(color: AppColors.orange, width: 3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.orange, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'refine.estimate_warning'.tr(namedArgs: {
                'asked': '${_toDouble(_fields['km'])?.round() ?? 0}',
                'estimated': '$km',
              }),
              style: const TextStyle(
                  color: AppColors.orange, fontSize: 10.5, height: 1.45),
            ),
          ),
        ]),
      );

  Widget _poiStopsCard() {
    // Elegir a mano calla a la app: se decidió tras una prueba real en la que
    // se forzaron tres puertos y la ruta trajo además un castillo de cosecha
    // propia, porque el selector seguía en "pocas".
    final blocked = _pois.isNotEmpty;
    final current = '${_fields['poi_stops'] ?? 'pocas'}';

    return _card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: blocked ? 0.45 : 1,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final level in const ['ninguna', 'pocas', 'muchas', 'ai'])
                    _chip(
                      'refine.stops_$level'.tr(),
                      !blocked && current == level,
                      blocked
                          ? () {}
                          : () =>
                              setState(() => _fields['poi_stops'] = level),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              blocked
                  ? 'refine.stops_blocked'
                      .tr(namedArgs: {'n': '${_pois.length}'})
                  : 'refine.stops_help'.tr(),
              style: const TextStyle(
                  color: AppColors.greyDark, fontSize: 10, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _restCard() => _card(
        child: Column(children: [
          _mealRow(
            icon: Icons.restaurant_outlined,
            field: 'suggest_lunch',
            timeField: 'lunch_time',
            label: 'assistant.f_suggest_lunch'.tr(),
            onText: 'assistant.v_lunch'.tr(),
            offText: 'assistant.v_no_lunch'.tr(),
          ),
          _mealRow(
            icon: Icons.restaurant,
            field: 'suggest_dinner',
            timeField: 'dinner_time',
            label: 'assistant.f_suggest_dinner'.tr(),
            onText: 'assistant.v_dinner'.tr(),
            offText: 'assistant.v_no_dinner'.tr(),
          ),
          _switchRow(
            icon: Icons.alt_route,
            label: 'assistant.f_avoid_highways'.tr(),
            value: _fields['avoid_highways'] != false,
            onTap: () => setState(() => _fields['avoid_highways'] =
                !(_fields['avoid_highways'] != false)),
            onText: 'assistant.v_avoid'.tr(),
            offText: 'assistant.v_highways'.tr(),
          ),

          // Las gasolineras solo se pueden calcular con el depósito y el
          // consumo de la moto. Sin esos datos la fila se queda apagada y dice
          // por qué, en vez de desaparecer: así se entiende que existe y qué
          // falta para tenerla.
          _switchRow(
            icon: Icons.local_gas_station,
            label: 'planner.gas_stations'.tr(),
            value: _hasFuelData && _fields['suggest_gas_stations'] == true,
            enabled: _hasFuelData,
            onTap: () => setState(() => _fields['suggest_gas_stations'] =
                !(_fields['suggest_gas_stations'] == true)),
            onText: 'planner.gas_stations_desc'.tr(),
            offText: _hasFuelData
                ? 'refine.gas_off'.tr()
                : 'planner.gas_stations_no_data'.tr(),
            last: true,
          ),
        ]),
      );

  /// Una parada para comer: el interruptor y, si está puesto, su hora.
  ///
  /// La hora no es un detalle: el generador la usa para colocar la parada en
  /// el sitio que toque del recorrido y para recalcular los horarios de los
  /// puntos siguientes. Activarla sin hora dejaba al servidor sin ese dato, y
  /// el formulario de siempre la exige.
  Widget _mealRow({
    required IconData icon,
    required String field,
    required String timeField,
    required String label,
    required String onText,
    required String offText,

  }) {
    final on = _fields[field] == true;
    final time = '${_fields[timeField] ?? ''}';

    // Saliendo a mediodía no hay almuerzo que valga.
    final allowed = field == 'suggest_lunch' ? _lunchMakesSense : true;

    return _switchRow(
      icon: icon,
      label: label,
      value: on && allowed,
      enabled: allowed,
      // Con la parada puesta, tocar la fila cambia la HORA; el interruptor
      // sigue siendo quien la quita. Tocar y que se apague sin querer, cuando
      // lo que buscabas era corregir las 11:00, seria peor.
      onTap: on
          ? () => _askMealTime(timeField)
          : () => _toggleMeal(field, timeField),
      onSwitch: () => _toggleMeal(field, timeField),
      onText: time.isEmpty ? onText : '$onText · $time',
      offText: allowed
          ? offText
          : 'refine.lunch_too_late'
              .tr(namedArgs: {'time': '${_fields['departure_time'] ?? ''}'}),
    );
  }

  void _toggleMeal(String field, String timeField) {
    if (_fields[field] == true) {
      setState(() {
        _fields[field] = false;
        _fields[timeField] = null;
      });
      return;
    }

    // Al activarla se pone ya una hora razonable, en vez de abrir un selector
    // y dejar la parada a medias si se cierra. Tocar la fila la cambia.
    setState(() {
      _fields[field] = true;
      _fields[timeField] = _hhmm(
          timeField == 'lunch_time' ? _defaultLunch : _defaultDinner);
    });
  }

  /// A qué horas se almuerza y a qué horas se come, en minutos desde
  /// medianoche y de media en media hora.
  ///
  /// Son franjas reales, no una validación genérica: se almuerza de 9 a 12 y
  /// se come de 1 a 3. Ofrecer solo las horas que valen es mejor que dejar
  /// elegir cualquiera y luego reñir: no hay forma de equivocarse, y de paso
  /// la separación entre las dos paradas se garantiza sola —lo más pegadas
  /// que pueden quedar es almorzar a las 12:00 y comer a la 13:00—, así que
  /// no hace falta ninguna regla aparte.
  static const _mealWindows = {
    'lunch_time': (from: 9 * 60, to: 12 * 60),
    'dinner_time': (from: 13 * 60, to: 15 * 60),
  };

  /// Y además, tres horas entre una parada y otra.
  ///
  /// Las franjas solas dejarían almorzar a las 12:00 y comer a la 13:00, que
  /// es sentarse dos veces seguidas. Tres horas es lo máximo que cabe sin
  /// contradecir las franjas: 12:00 más tres son las 15:00, justo el tope de
  /// la franja de comidas. Con cuatro no habría ninguna hora válida.
  static const _mealGapMinutes = 180;

  /// Minutos desde medianoche de una hora guardada como "HH:MM".
  int? _minutesOf(String? value) {
    final parts = (value ?? '').split(':');
    if (parts.length != 2) return null;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return (h == null || m == null) ? null : h * 60 + m;
  }

  String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  /// A qué hora sale de ruta.
  int? get _departure => _minutesOf(_fields['departure_time']);

  /// Si tiene sentido almorzar en esta ruta.
  ///
  /// Saliendo a las 12:00 o más tarde, no: el almuerzo es de 9 a 12 y nadie
  /// para a almorzar nada más arrancar. Mejor apagarlo y decir por qué que
  /// dejar activar una parada que el generador colocaría a destiempo.
  bool get _lunchMakesSense {
    final out = _departure;
    return out == null || out < _mealWindows['lunch_time']!.to;
  }

  /// La hora a la que se propone almorzar: dos horas después de salir.
  ///
  /// Es lo que pidió el motero y encaja con cómo se rueda: las dos primeras
  /// horas se hacen del tirón. Se recorta a la franja de almuerzo, porque
  /// saliendo a las 7:00 el almuerzo no es a las 9 en punto por casualidad, y
  /// saliendo a las 11:00 no puede irse más allá de las 12.
  int get _defaultLunch {
    final window = _mealWindows['lunch_time']!;
    final out = _departure;

    if (out == null) return 11 * 60;

    // A la media hora más cercana: un almuerzo a las 11:17 no lo pone nadie.
    final propuesta = ((out + 120) / 30).round() * 30;

    return propuesta.clamp(window.from, window.to);
  }

  /// La hora a la que se propone comer: respetando el hueco del almuerzo.
  int get _defaultDinner {
    final window = _mealWindows['dinner_time']!;
    final earliest = _earliestDinner ?? window.from;

    return math.max(window.from, earliest).clamp(window.from, window.to);
  }

  /// La primera hora a la que ya se puede comer, contando el almuerzo.
  int? get _earliestDinner {
    if (_fields['suggest_lunch'] != true) return null;

    final lunch = _minutesOf(_fields['lunch_time']);
    return lunch == null ? null : lunch + _mealGapMinutes;
  }

  /// La comida se ha quedado demasiado pegada al almuerzo.
  ///
  /// Pasa al cambiar el almuerzo DESPUÉS de haber puesto la comida: el
  /// selector solo ofrece horas válidas, pero retrasar el almuerzo puede
  /// invalidar una comida que ya estaba bien elegida.
  int? get _suggestedDinner {
    if (_fields['suggest_dinner'] != true) return null;

    final dinner = _minutesOf(_fields['dinner_time']);
    final earliest = _earliestDinner;
    if (dinner == null || earliest == null || dinner >= earliest) return null;

    return math.min(earliest, _mealWindows['dinner_time']!.to);
  }

  /// Elegir la hora entre las que tienen sentido para esa comida.
  Future<bool> _askMealTime(String timeField) async {
    final window = _mealWindows[timeField]!;
    final current = '${_fields[timeField] ?? ''}';

    // Para la comida, además de su franja, lo que deje libre el almuerzo.
    final floor = timeField == 'dinner_time'
        ? math.max(window.from, _earliestDinner ?? window.from)
        : window.from;

    final options = <int>[
      for (var m = window.from; m <= window.to; m += 30)
        if (m >= floor) m,
    ];

    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'refine.meal_time_title'.tr(namedArgs: {
                  'from': _hhmm(window.from),
                  'to': _hhmm(window.to),
                }),
                style: const TextStyle(
                    color: AppColors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in options)
                  _chip(_hhmm(m), current == _hhmm(m),
                      () => Navigator.pop(ctx, m)),
              ],
            ),
          ),
        ]),
      ),
    );

    if (picked == null) return false;

    setState(() => _fields[timeField] = _hhmm(picked));
    return true;
  }

  Widget _switchRow({
    required IconData icon,
    required String label,
    required bool value,
    required VoidCallback onTap,
    required String onText,
    required String offText,
    VoidCallback? onSwitch,
    bool enabled = true,
    bool last = false,
  }) =>
      InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(
                    bottom:
                        BorderSide(color: AppColors.greyDark, width: 0.5)),
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Row(children: [
              Icon(icon, color: AppColors.grey, size: 16),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: AppColors.grey, fontSize: 10.5)),
                    const SizedBox(height: 2),
                    Text(value ? onText : offText,
                        style: const TextStyle(
                            color: AppColors.white, fontSize: 12.5)),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged:
                    enabled ? (_) => (onSwitch ?? onTap)() : null,
                activeThumbColor: AppColors.orange,
              ),
            ]),
          ),
        ),
      );

  // ─── Generar ─────────────────────────────────────────────────────────

  Future<void> _generate() async {
    setState(() => _generating = true);

    final payload = Map<String, dynamic>.from(_fields)
      ..removeWhere((k, v) =>
          v == null ||
          // Lo que empieza por _ es de la pantalla: coordenadas para estimar,
          // POIs enteros para poder enseñarlos. Al servidor le van los ids.
          k.startsWith('_') ||
          k.endsWith('_address') ||
          const {'days', 'moto', 'understood', 'multi_day'}.contains(k))
      ..['ai_request'] = widget.request
      ..['days'] = 1;

    if (_pois.isNotEmpty) {
      payload['poi_ids'] = _pois.map((p) => p['id']).toList();
    }

    final result = await RouteService.generateRoute(payload);
    if (!mounted) return;

    setState(() => _generating = false);

    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['error']),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    // Se apila, no se sustituye: desde el resultado se tiene que poder volver
    // aquí a retocar y generar otra vez, y encontrarlo todo como lo dejaste.
    // Sustituyendo, la pantalla de afinar se destruía al generar y el botón de
    // atrás te devolvía al resumen, perdiendo la dirección, los puntos
    // elegidos y las paradas.
    context.push('/rider/route-result', extra: result['result']);
  }
}

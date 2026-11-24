import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../rider/screens/catalog_screen.dart' show categoryColor;
import '../providers/moderation_service.dart';

/// Rutas que los moteros piden publicar en Rutas moteras.
///
/// Solo pueden pedirlo quienes las han rodado. El servidor ya ha rellenado el borrador
/// (país, provincia, carreteras, puertos, tipo); aquí se revisa, se corrige lo que haga
/// falta y se aprueba o se rechaza. Nada se publica sin pasar por aquí.
class ModerationRoutesScreen extends StatefulWidget {
  const ModerationRoutesScreen({super.key});

  @override
  State<ModerationRoutesScreen> createState() => _ModerationRoutesScreenState();
}

class _ModerationRoutesScreenState extends State<ModerationRoutesScreen> {
  List<Map<String, dynamic>>? _items;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ModerationService.routes();
    if (!mounted) return;
    setState(() {
      _items = r;
      _error = r == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.white),
          onPressed: () => context.pop(),
        ),
        title: Text('moderation.routes'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error) {
      return Center(
        child: TextButton(onPressed: _load, child: Text('moderation.retry'.tr())),
      );
    }
    if (_items == null) return const Center(child: CircularProgressIndicator());
    if (_items!.isEmpty) {
      return Center(
        child: Text('catalog.mod_empty_routes'.tr(),
            style: const TextStyle(color: AppColors.greyText)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(14, 14, 14, 28 + MediaQuery.of(context).padding.bottom),
        itemCount: _items!.length,
        itemBuilder: (_, i) => _RouteReview(
          key: ValueKey(_items![i]['id']),
          route: _items![i],
          onDone: _load,
        ),
      ),
    );
  }
}

class _RouteReview extends StatefulWidget {
  final Map<String, dynamic> route;
  final VoidCallback onDone;
  const _RouteReview({super.key, required this.route, required this.onDone});

  @override
  State<_RouteReview> createState() => _RouteReviewState();
}

class _RouteReviewState extends State<_RouteReview> {
  late final Map<String, dynamic> _draft =
      Map<String, dynamic>.from((widget.route['draft'] as Map?) ?? {});
  late final _name = TextEditingController(text: '${widget.route['title'] ?? ''}');
  late final _roads = TextEditingController(
      text: '${_draft['road_codes'] ?? ''}'.replaceAll('|', ', '));
  late final _passes = TextEditingController(
      text: List<String>.from((_draft['passes'] as List?) ?? const []).join(', '));
  late String _kind = '${_draft['kind'] ?? 'carretera'}';
  bool _busy = false;

  // ── Países y zonas por los que pasa (una ruta puede cruzar los Pirineos) ──
  late final List<String> _countries = _initList('countries', fallback: _draft['country']);
  late final List<String> _areas = _initList('areas', fallback: _draft['area']);
  late final List<String> _regions = _initList('regions', fallback: _draft['region']);

  /// Nombre de cada país / zona ya conocido (código o clave -> nombre).
  late final Map<String, String> _names = _initNames();

  // ── Temporada: unknown | todo_el_ano | cerrado_invierno | ocasional ──
  String _seasonType = 'unknown';
  int _opens = 5;
  int _closes = 10;

  List<String> _initList(String key, {dynamic fallback}) {
    final l = _draft[key];
    if (l is List && l.isNotEmpty) return l.map((e) => '$e').toList();
    return fallback == null || '$fallback'.isEmpty ? <String>[] : ['$fallback'];
  }

  Map<String, String> _initNames() {
    final m = <String, String>{};
    for (final c in (_draft['countries_info'] as List?) ?? const []) {
      m['${c['code']}'] = '${c['name']}';
    }
    for (final k in ['areas_info', 'regions_info']) {
      for (final z in (_draft[k] as List?) ?? const []) {
        m['${z['key']}'] = '${z['name']}';
      }
    }
    return m;
  }

  /// En qué grupos del filtro del catálogo caerá la ruta según su sinuosidad medida.
  static const _levelCategories = {
    'catalog.level_easy': ['tranquila', 'agradable'],
    'catalog.level_moderate': ['agradable', 'revirada'],
    'catalog.level_hard': ['revirada', 'muy_revirada'],
  };

  String _levels(String? cat) => _levelCategories.entries
      .where((e) => e.value.contains(cat))
      .map((e) => e.key.tr())
      .join(' · ');

  String _duration(dynamic minutes) {
    final m = (minutes as num?)?.toInt();
    if (m == null || m <= 0) return '';
    return m >= 60 ? '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min' : '$m min';
  }

  String _month(int m) => DateFormat.MMMM(context.locale.toString()).format(DateTime(2024, m));

  /// Rutas del catálogo parecidas a esta (null = aún cargando).
  List<Map<String, dynamic>>? _similar;

  @override
  void initState() {
    super.initState();
    _loadSimilar();
  }

  Future<void> _loadSimilar() async {
    final r = await ModerationService.similar((widget.route['id'] as num).toInt());
    if (!mounted) return;
    setState(() => _similar = r == null
        ? const []
        : List<Map<String, dynamic>>.from(
            ((r['similar'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map))));
  }

  @override
  void dispose() {
    _name.dispose();
    _roads.dispose();
    _passes.dispose();
    super.dispose();
  }

  List<String> _split(String text) =>
      text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _decide(String decision) async {
    String? reason;
    if (decision == 'rejected') {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          content: TextField(
            controller: c,
            maxLength: 160,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(hintText: 'common.optional'.tr()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common.cancel'.tr())),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('catalog.mod_reject_route'.tr())),
          ],
        ),
      );
      if (ok != true) return;
      reason = c.text;
    }

    setState(() => _busy = true);
    final overrides = decision == 'approved'
        ? <String, dynamic>{
            'name': _name.text.trim(),
            'road_codes': _split(_roads.text).join('|'),
            'kind': _kind,
            'passes': _split(_passes.text),
            // La salida es lo primero de cada lista
            if (_countries.isNotEmpty) 'country': _countries.first,
            'countries': _countries,
            'areas': _areas,
            'regions': _regions,
            if (_firstOf(_areas) != null) 'area': _firstOf(_areas),
            if (_firstOf(_regions) != null) 'region': _firstOf(_regions),
            if (_seasonType != 'unknown')
              'season': {
                'tipo': _seasonType,
                if (_seasonType == 'cerrado_invierno') ...{'abre': _opens, 'cierra': _closes},
              },
          }
        : <String, dynamic>{};
    final err = await ModerationService.decideRoute(
      (widget.route['id'] as num).toInt(),
      decision,
      overrides: overrides,
      reason: reason,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err.isEmpty ? 'moderation.error'.tr() : err)));
      return;
    }
    widget.onDone();
  }

  String? _firstOf(List<String> zones) {
    if (_countries.isEmpty) return zones.isEmpty ? null : zones.first;
    final c = _countries.first;
    for (final z in zones) {
      if (z.startsWith('$c-')) return z;
    }
    return zones.isEmpty ? null : zones.first;
  }

  /// Dificultad en la que saldrá en el catálogo y duración (lo medido, no editable).
  Widget _measureInfo(Map<String, dynamic> r) {
    final cat = r['category'] as String?;
    final dur = _duration(r['minutes']);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 14, runSpacing: 4, children: [
        if (cat != null)
          Text(
              'catalog.mod_curves'.tr(namedArgs: {
                'label': '${r['category_label'] ?? cat}',
                'score': '${r['score'] ?? ''}',
              }),
              style: const TextStyle(color: AppColors.white, fontSize: 13)),
        if (cat != null)
          Text('catalog.mod_filters'.tr(namedArgs: {'levels': _levels(cat)}),
              style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
        if (dur.isNotEmpty)
          Text('catalog.mod_duration'.tr(namedArgs: {'time': dur}),
              style: const TextStyle(color: AppColors.white, fontSize: 13)),
      ]),
    );
  }

  Widget _chips(String title, List<String> keys, {String Function(String)? label}) {
    if (keys.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
        Wrap(spacing: 6, runSpacing: 0, children: [
          for (final k in keys)
            InputChip(
              label: Text(label?.call(k) ?? _names[k] ?? k, style: const TextStyle(fontSize: 13)),
              visualDensity: VisualDensity.compact,
              onDeleted: () => setState(() => keys.remove(k)),
            ),
        ]),
      ]),
    );
  }

  /// Todos los países y zonas por los que pasa: se pueden quitar y añadir (el primero es la salida).
  Widget _zonesEditor() => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _chips('catalog.mod_countries'.tr(), _countries),
          _chips('catalog.mod_areas'.tr(), _areas),
          _chips('catalog.mod_regions'.tr(), _regions),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addZone,
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: Text('catalog.mod_add_zone'.tr()),
            ),
          ),
        ]),
      );

  /// Diálogo para añadir un país y una de sus zonas (comunidad o provincia).
  Future<void> _addZone() async {
    final first = await ModerationService.zones(country: _countries.isEmpty ? null : _countries.first);
    if (first == null || !mounted) return;
    var countries = List<Map<String, dynamic>>.from(
        (first['countries'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    String? country = _countries.isEmpty ? null : _countries.first;
    var zones = <Map<String, dynamic>>[
      ...List<Map<String, dynamic>>.from(
          (first['areas'] as List).map((e) => {...Map<String, dynamic>.from(e as Map), 'level': 'area'})),
      ...List<Map<String, dynamic>>.from(
          (first['regions'] as List).map((e) => {...Map<String, dynamic>.from(e as Map), 'level': 'region'})),
    ];
    String? zone;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('catalog.mod_add_zone'.tr(),
              style: const TextStyle(color: AppColors.white, fontSize: 17)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(
              isExpanded: true,
              dropdownColor: AppColors.surface,
              value: countries.any((c) => c['code'] == country) ? country : null,
              hint: Text('catalog.f_country'.tr(), style: const TextStyle(color: AppColors.grey)),
              items: [
                for (final c in countries)
                  DropdownMenuItem(value: '${c['code']}', child: Text('${c['name']}')),
              ],
              onChanged: (c) async {
                setS(() {
                  country = c;
                  zone = null;
                  zones = [];
                });
                final z = await ModerationService.zones(country: c);
                if (z == null) return;
                setS(() => zones = [
                      ...List<Map<String, dynamic>>.from((z['areas'] as List)
                          .map((e) => {...Map<String, dynamic>.from(e as Map), 'level': 'area'})),
                      ...List<Map<String, dynamic>>.from((z['regions'] as List)
                          .map((e) => {...Map<String, dynamic>.from(e as Map), 'level': 'region'})),
                    ]);
              },
            ),
            DropdownButton<String>(
              isExpanded: true,
              dropdownColor: AppColors.surface,
              value: zones.any((z) => '${z['level']}:${z['key']}' == zone) ? zone : null,
              hint: Text('catalog.all_regions'.tr(), style: const TextStyle(color: AppColors.grey)),
              items: [
                for (final z in zones)
                  DropdownMenuItem(
                      value: '${z['level']}:${z['key']}',
                      child: Text('${z['name']}${z['level'] == 'area' ? '  ·  ${'catalog.zone_areas'.tr()}' : ''}')),
              ],
              onChanged: (z) => setS(() => zone = z),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('common.cancel'.tr())),
            TextButton(
              onPressed: country == null ? null : () => Navigator.pop(ctx, true),
              child: Text('common.save'.tr(), style: const TextStyle(color: AppColors.orange)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || country == null) return;

    setState(() {
      final c = country!;
      if (!_countries.contains(c)) _countries.add(c);
      _names[c] = '${countries.firstWhere((e) => e['code'] == c, orElse: () => {'name': c})['name']}';
      if (zone != null) {
        final level = zone!.split(':').first;
        final key = zone!.substring(level.length + 1);
        final list = level == 'area' ? _areas : _regions;
        if (!list.contains(key)) list.add(key);
        _names[key] = '${zones.firstWhere((e) => e['key'] == key, orElse: () => {'name': key})['name']}';
      }
    });
  }

  /// La temporada de apertura: sin datos / todo el año / cierra en invierno (con meses) / puede cerrar con nieve.
  Widget _seasonEditor() => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('catalog.mod_season'.tr(), style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
          DropdownButton<String>(
            isExpanded: true,
            dropdownColor: AppColors.surface,
            value: _seasonType,
            style: const TextStyle(color: AppColors.white, fontSize: 14),
            items: [
              for (final t in const ['unknown', 'todo_el_ano', 'cerrado_invierno', 'ocasional'])
                DropdownMenuItem(value: t, child: Text('catalog.mod_season_$t'.tr())),
            ],
            onChanged: (t) => setState(() => _seasonType = t ?? 'unknown'),
          ),
          if (_seasonType == 'cerrado_invierno')
            Row(children: [
              Expanded(child: _monthPicker('catalog.mod_season_from'.tr(), _opens, (m) => setState(() => _opens = m))),
              const SizedBox(width: 10),
              Expanded(child: _monthPicker('catalog.mod_season_to'.tr(), _closes, (m) => setState(() => _closes = m))),
            ]),
        ]),
      );

  Widget _monthPicker(String label, int value, ValueChanged<int> onChanged) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
          DropdownButton<int>(
            isExpanded: true,
            dropdownColor: AppColors.surface,
            value: value,
            style: const TextStyle(color: AppColors.white, fontSize: 14),
            items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(_month(m)))],
            onChanged: (m) => onChanged(m ?? value),
          ),
        ],
      );

  /// Aviso de rutas parecidas ya publicadas + botón para compararlas en un mapa.
  Widget _similarBlock(Map<String, dynamic> r) {
    final list = _similar;
    if (list == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('catalog.sim_checking'.tr(), style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
        ]),
      );
    }
    if (list.isEmpty) return const SizedBox.shrink();

    final top = list.first;
    final high = top['level'] == 'high';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (high ? AppColors.error : AppColors.gold).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(Icons.copy_all, color: high ? AppColors.error : AppColors.gold, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            (high ? 'catalog.sim_notice_high' : 'catalog.sim_notice_medium')
                .tr(namedArgs: {'name': '${top['name']}', 'pct': '${top['similarity']}'}),
            style: const TextStyle(color: AppColors.white, fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: () => context.push('/admin/moderation/routes/${r['id']}/similar',
              extra: {'title': '${r['title']}'}),
          child: Text('catalog.sim_button'.tr(namedArgs: {'n': '${list.length}'})),
        ),
      ]),
    );
  }

  Widget _field(String label, TextEditingController c, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          minLines: lines > 1 ? 2 : 1,
          maxLines: lines,
          style: const TextStyle(color: AppColors.white, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: AppColors.greyText),
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    final hasTrack = r['has_track'] == true;
    final cat = r['category'] as String?;

    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r['title']}',
              style: const TextStyle(
                  color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('catalog.mod_by'.tr(namedArgs: {'nick': '${r['nickname'] ?? '—'}'}),
              style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // La salida que se publicará (nunca la casa del motero)
                if ('${r['origin'] ?? ''}'.isNotEmpty)
                  Text('catalog.mod_start'.tr(namedArgs: {'place': '${r['origin']}'}),
                      style: const TextStyle(color: AppColors.white, fontSize: 13)),
                if ('${r['destination'] ?? ''}'.isNotEmpty)
                  Text('catalog.mod_end'.tr(namedArgs: {'place': '${r['destination']}'}),
                      style: const TextStyle(color: AppColors.white, fontSize: 13)),
                Text('catalog.km_short'.tr(namedArgs: {'km': '${r['km'] ?? '?'}'}),
                    style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                if (cat != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: categoryColor(cat).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${r['score']} · ${r['category_label'] ?? cat}',
                        style: TextStyle(
                            color: categoryColor(cat),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
          if (r['google_maps_url'] != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('${r['google_maps_url']}'),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text('catalog.open_maps'.tr()),
              ),
            ),
          _similarBlock(r),
          const Divider(color: AppColors.greyDark),
          Text('catalog.mod_route_draft'.tr(),
              style: const TextStyle(color: AppColors.gold, fontSize: 12)),
          _field('catalog.mod_name'.tr(), _name, lines: 4),
          _measureInfo(r),
          _zonesEditor(),
          _field('catalog.mod_roads'.tr(), _roads),
          _field('catalog.mod_passes'.tr(), _passes, lines: 2),
          _seasonEditor(),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 8, children: [
              for (final k in const ['puerto', 'carretera', 'circular'])
                ChoiceChip(
                  label: Text(k),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ]),
          ),
          if (!hasTrack)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('catalog.mod_no_track'.tr(),
                  style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _decide('rejected'),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error)),
                child: Text('catalog.mod_reject_route'.tr(),
                    style: const TextStyle(color: AppColors.error)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy || !hasTrack ? null : () => _decide('approved'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('moderation.approve'.tr(),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

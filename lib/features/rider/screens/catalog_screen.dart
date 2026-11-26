import 'package:gastroroute_ai/core/labels.dart';
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/catalog_service.dart';

/// Rutas moteras: el catálogo de rutas comprobadas por GastroRouteAI y las que publican
/// los moteros (tras la aprobación del administrador).
///
/// Filtros a la vista: país (por defecto el del motero, se puede cambiar), zona y
/// dificultad, más el buscador. El resto (sinuosidad exacta, tipo, quién la publica, km,
/// valoración, sin cierre por temporada, cerca de mí) están en «Más filtros».
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

/// El color de cada categoría de sinuosidad.
Color categoryColor(String? c) {
  switch (c) {
    case 'muy_revirada':
      return AppColors.error;
    case 'revirada':
      return AppColors.orange;
    case 'agradable':
      return AppColors.gold;
    default:
      return AppColors.cyan;
  }
}

/// El color del estado de temporada: abierta / puede cerrar / cerrada / sin datos.
Color seasonColor(String? s) {
  switch (s) {
    case 'open':
      return const Color(0xFF4CAF50);
    case 'maybe':
      return AppColors.gold;
    case 'closed':
      return AppColors.error;
    default:
      return AppColors.greyText;
  }
}

/// La dificultad del motero (tranquila / moderada / exigente) como categorías de
/// sinuosidad. Las mismas tres que en el generador de rutas.
const _difficultyCategories = <String, List<String>>{
  'easy': ['tranquila', 'agradable'],
  'moderate': ['agradable', 'revirada'],
  'hard': ['revirada', 'muy_revirada'],
};

class _CatalogScreenState extends State<CatalogScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  final List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _facets = {};
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _error = false;

  // País: `me` = el de su perfil, hasta que llegue la primera respuesta; null = todos.
  String? _country = 'me';
  // Zona: «a:Aragón» (una comunidad entera) o «r:Zaragoza» (una provincia). null = todas.
  String? _zone;
  String? _difficulty; // easy | moderate | hard | null

  // Más filtros
  final Set<String> _categories = {};
  final Set<String> _kinds = {};
  String? _source; // gastrorouteai | community | null
  RangeValues _km = const RangeValues(0, 600);
  bool _kmActive = false;
  bool _openNow = false;
  int? _minRating;
  bool _near = false;
  double? _lat, _lng;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300 &&
          _hasMore &&
          !_loading) {
        _load(page: _page + 1);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Filtros del «Más filtros» activos (para el contador del botón).
  int get _moreActive =>
      (_categories.isNotEmpty ? 1 : 0) +
      (_kinds.isNotEmpty ? 1 : 0) +
      (_source != null ? 1 : 0) +
      (_kmActive ? 1 : 0) +
      (_openNow ? 1 : 0) +
      (_minRating != null ? 1 : 0) +
      (_near ? 1 : 0);

  Map<String, dynamic> _params(int page) {
    // La sinuosidad exacta manda sobre la dificultad si se han elegido las dos.
    final cats = _categories.isNotEmpty
        ? _categories.toList()
        : (_difficulty != null ? _difficultyCategories[_difficulty]! : <String>[]);

    return {
      'page': page,
      if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      if (cats.isNotEmpty) 'category': cats.join(','),
      if (_kinds.isNotEmpty) 'kind': _kinds.join(','),
      if (_country != null) 'country': _country,
      if (_zone != null && _zone!.startsWith('a:')) 'area': _zone!.substring(2),
      if (_zone != null && _zone!.startsWith('r:')) 'region': _zone!.substring(2),
      if (_source != null) 'source': _source,
      if (_kmActive) 'km_min': _km.start.round(),
      if (_kmActive && _km.end < 600) 'km_max': _km.end.round(),
      if (_openNow) 'open_now': 1,
      if (_minRating != null) 'min_rating': _minRating,
      if (_near && _lat != null) ...{'near_lat': _lat, 'near_lng': _lng, 'sort': 'near'},
    };
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = false;
      if (page == 1) _items.clear();
    });

    final r = await CatalogService.list(_params(page));
    if (!mounted) return;

    if (r == null) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }

    setState(() {
      _page = page;
      _items.addAll(List<Map<String, dynamic>>.from(
          (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map))));
      _hasMore = r['has_more'] == true;
      _facets = Map<String, dynamic>.from(r['filters'] as Map? ?? {});
      // El país por defecto es el del motero; desde aquí ya es un código normal.
      if (_country == 'me') _country = _facets['my_country'] as String?;
      _loading = false;
    });
  }

  /// Pide la posición del móvil para ordenar por cercanía.
  Future<bool> _locate() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return false;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
      );
      _lat = pos.latitude;
      _lng = pos.longitude;
      return true;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> get _countryOptions => List<Map<String, dynamic>>.from(
      ((_facets['countries'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));

  /// Zonas de una lista del servidor ({country, key, name, count}) para el país elegido (o todos,
  /// si no hay país), sin repetir. La `key` es lo que se manda como filtro y el `name` ya viene
  /// en el idioma del motero.
  List<Map<String, dynamic>> _zones(String facet) {
    final vistos = <String>{};
    final all = List<Map<String, dynamic>>.from(
        ((_facets[facet] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));

    return all
        .where((z) => _country == null || z['country'] == _country)
        .where((z) => vistos.add('${z['key']}'))
        .toList()
      ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
  }

  /// Comunidades / regiones: la primera parte del desplegable de zona.
  List<Map<String, dynamic>> get _areaOptions => _zones('areas');

  /// Provincias: la segunda parte, para afinar.
  List<Map<String, dynamic>> get _regionOptions => _zones('regions');

  /// Las opciones del desplegable de zona: primero las comunidades (una lista corta que se ve
  /// entera) y debajo las provincias. Las cabeceras no se pueden elegir.
  List<DropdownMenuItem<String?>> get _zoneItems {
    final areas = _areaOptions;
    final regions = _regionOptions;
    Widget header(String t) => Text(t,
        style: const TextStyle(
            color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.4));

    return [
      DropdownMenuItem<String?>(value: null, child: Text('catalog.all_regions'.tr())),
      if (areas.isNotEmpty) ...[
        DropdownMenuItem<String?>(
            enabled: false, value: '#a', child: header('catalog.zone_areas'.tr().toUpperCase())),
        for (final a in areas)
          DropdownMenuItem<String?>(value: 'a:${a['key']}', child: Text('${a['name']}')),
      ],
      if (regions.isNotEmpty) ...[
        DropdownMenuItem<String?>(
            enabled: false, value: '#r', child: header('catalog.zone_regions'.tr().toUpperCase())),
        for (final r in regions)
          DropdownMenuItem<String?>(value: 'r:${r['key']}', child: Text('${r['name']}')),
      ],
    ];
  }

  Widget _dropdown({
    required String hint,
    required String? value,
    required List<DropdownMenuItem<String?>> items,
    required ValueChanged<String?> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: value,
            isExpanded: true,
            dropdownColor: AppColors.card,
            hint: Text(hint, style: const TextStyle(color: AppColors.greyText, fontSize: 14)),
            style: const TextStyle(color: AppColors.white, fontSize: 14),
            iconEnabledColor: AppColors.greyText,
            items: items,
            onChanged: onChanged,
          ),
        ),
      );

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        void change(VoidCallback f) {
          setState(f);
          setSheet(() {});
        }

        Widget title(String t) => Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Text(t,
                  style: const TextStyle(
                      color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            );

        Widget chips(List<dynamic> options, Set<String> selected) => Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in options)
                  FilterChip(
                    label: Text('${o['name']}'),
                    selected: selected.contains('${o['code']}'),
                    onSelected: (v) => change(() {
                      v ? selected.add('${o['code']}') : selected.remove('${o['code']}');
                    }),
                  ),
              ],
            );

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                18, 12, 18, 12 + MediaQuery.of(ctx).viewInsets.bottom),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Text('catalog.more_filters'.tr(),
                        style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => change(() {
                        _categories.clear();
                        _kinds.clear();
                        _source = null;
                        _kmActive = false;
                        _km = const RangeValues(0, 600);
                        _openNow = false;
                        _minRating = null;
                        _near = false;
                      }),
                      child: Text('catalog.clear'.tr()),
                    ),
                  ]),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title('catalog.f_category'.tr()),
                          chips(List.from(_facets['categories'] ?? []), _categories),
                          title('catalog.f_kind'.tr()),
                          chips(List.from(_facets['kinds'] ?? []), _kinds),
                          title('catalog.f_source'.tr()),
                          Wrap(spacing: 8, children: [
                            for (final s in [
                              [null, 'catalog.source_all'.tr()],
                              ['gastrorouteai', 'catalog.source_gr'.tr()],
                              ['community', 'catalog.source_riders'.tr()],
                            ])
                              ChoiceChip(
                                label: Text('${s[1]}'),
                                selected: _source == s[0],
                                onSelected: (_) => change(() => _source = s[0]),
                              ),
                          ]),
                          title('catalog.f_km'.tr()),
                          RangeSlider(
                            values: _km,
                            min: 0,
                            max: 600,
                            divisions: 60,
                            labels: RangeLabels('${_km.start.round()}',
                                _km.end >= 600 ? '600+' : '${_km.end.round()}'),
                            onChanged: (v) => change(() {
                              _km = v;
                              _kmActive = v.start > 0 || v.end < 600;
                            }),
                          ),
                          title('catalog.f_rating'.tr()),
                          Wrap(spacing: 8, children: [
                            for (final n in [3, 4, 5])
                              ChoiceChip(
                                label: Text('$n ★'),
                                selected: _minRating == n,
                                onSelected: (v) => change(() => _minRating = v ? n : null),
                              ),
                          ]),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('catalog.f_open'.tr(),
                                style: const TextStyle(color: AppColors.white, fontSize: 14)),
                            value: _openNow,
                            onChanged: (v) => change(() => _openNow = v),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('catalog.f_near'.tr(),
                                style: const TextStyle(color: AppColors.white, fontSize: 14)),
                            value: _near,
                            onChanged: (v) async {
                              if (v && !await _locate()) {
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                    content: Text('common.location_failed'.tr())));
                                return;
                              }
                              change(() => _near = v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _load();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          minimumSize: const Size.fromHeight(48)),
                      child: Text('catalog.apply'.tr(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final countries = _countryOptions;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.white),
          onPressed: () => context.canPop() ? context.pop() : context.go('/rider/home'),
        ),
        title: Text('catalog.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        // Buscador
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: TextField(
            controller: _search,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(
              hintText: 'catalog.search_hint'.tr(),
              hintStyle: const TextStyle(color: AppColors.greyText),
              prefixIcon: const Icon(Icons.search, color: AppColors.greyText),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 450), () => _load());
            },
          ),
        ),
        // País y zona
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          child: Row(children: [
            Expanded(
              child: _dropdown(
                hint: 'catalog.f_country'.tr(),
                value: countries.any((c) => c['code'] == _country) ? _country : null,
                items: [
                  DropdownMenuItem<String?>(
                      value: null, child: Text('catalog.all_countries'.tr())),
                  for (final c in countries)
                    DropdownMenuItem<String?>(
                        value: '${c['code']}', child: Text('${c['name']}')),
                ],
                onChanged: (v) {
                  setState(() {
                    _country = v;
                    _zone = null; // las zonas son de cada país
                  });
                  _load();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dropdown(
                hint: 'catalog.f_region'.tr(),
                value: _zoneItems.any((i) => i.value == _zone) ? _zone : null,
                items: _zoneItems,
                onChanged: (v) {
                  setState(() => _zone = v);
                  _load();
                },
              ),
            ),
          ]),
        ),
        // Dificultad + más filtros. Un Wrap: si no caben en una línea bajan a la siguiente,
        // sin cortarse ni obligar a deslizar.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 0,
            children: [
              for (final d in const [
                ['easy', 'catalog.level_easy'],
                ['moderate', 'catalog.level_moderate'],
                ['hard', 'catalog.level_hard'],
              ])
                ChoiceChip(
                  label: Text(d[1].tr()),
                  selected: _difficulty == d[0],
                  onSelected: (v) {
                    setState(() => _difficulty = v ? d[0] : null);
                    _load();
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.tune, size: 16, color: AppColors.white),
                label: Text(
                    _moreActive > 0
                        ? '${'catalog.more_filters'.tr()} ($_moreActive)'
                        : 'catalog.more_filters'.tr(),
                    style: const TextStyle(color: AppColors.white)),
                backgroundColor: _moreActive > 0 ? AppColors.orange : AppColors.card,
                onPressed: _openFilters,
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_error && _items.isEmpty) {
      return Center(
        child: TextButton(onPressed: () => _load(), child: Text('catalog.load_error'.tr())),
      );
    }
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      // Con un botón para quitar los filtros aquí mismo: antes había que abrir «Más filtros» y buscar «Limpiar».
      // El país se queda: es dónde mira el motero, no un filtro que se le haya ido de las manos.
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('catalog.empty'.tr(), style: const TextStyle(color: AppColors.greyText)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() {
                _search.clear();
                _zone = null;
                _difficulty = null;
                _categories.clear();
                _kinds.clear();
                _source = null;
                _kmActive = false;
                _km = const RangeValues(0, 600);
                _openNow = false;
                _minRating = null;
                _near = false;
              });
              _load();
            },
            child: Text('catalog.clear_filters'.tr()),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(14, 8, 14, 24 + MediaQuery.of(context).padding.bottom),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _RouteCard(
            route: _items[i],
            onTap: () => context.push('/rider/catalog/${_items[i]['id']}'),
          );
        },
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  final VoidCallback onTap;
  const _RouteCard({required this.route, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat = route['category'] as String?;
    final rating = (route['rating'] as num?)?.toDouble();
    final votes = (route['votes'] as num?)?.toInt() ?? 0;
    final dist = route['distance_km'];
    final place = [route['region'], route['countries_label'] ?? route['country_name']]
        .where((e) => e != null && '$e'.isNotEmpty)
        .join(' · ');

    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text('${route['name']}',
                    style: const TextStyle(
                        color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              _Chip(text: '${route['category_label']}', color: categoryColor(cat)),
            ]),
            const SizedBox(height: 4),
            Text(place, style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _Info(Icons.straighten, 'catalog.km_short'.tr(namedArgs: {
                'km': '${(route['km'] as num).round()}'
              })),
              _Info(Icons.route, '${route['kind_label']}'),
              if (dist != null)
                _Info(Icons.near_me_outlined,
                    'catalog.from_you'.tr(namedArgs: {'km': '$dist'})),
              _Info(
                Icons.star,
                rating == null
                    ? 'catalog.no_rating'.tr()
                    : '${dec1(context, rating)} · ${'catalog.votes'.tr(namedArgs: {'n': '$votes'})}',
                color: rating == null ? AppColors.greyText : AppColors.gold,
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.verified_outlined,
                  size: 14,
                  color: route['source'] == 'community' ? AppColors.cyan : AppColors.orange),
              const SizedBox(width: 4),
              Expanded(
                child: Text('${route['source_label']}',
                    style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
              ),
              _Chip(
                  text: '${route['season_label']}',
                  color: seasonColor(route['season_state'] as String?),
                  small: true),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final bool small;
  const _Chip({required this.text, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9, vertical: small ? 2 : 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: small ? 11 : 12, fontWeight: FontWeight.w700)),
      );
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Info(this.icon, this.text, {this.color = AppColors.greyText});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 13)),
      ]);
}

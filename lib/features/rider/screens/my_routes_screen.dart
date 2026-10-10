import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/route_service.dart' show RouteService, routeListRefresh;
import '../providers/route_tracking_service.dart';

class MyRoutesScreen extends StatefulWidget {
  const MyRoutesScreen({super.key});

  @override
  State<MyRoutesScreen> createState() => _MyRoutesScreenState();
}

class _MyRoutesScreenState extends State<MyRoutesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _notDone  = [];
  List<Map<String, dynamic>> _received = [];

  /// Rodadas: son trackings, no rutas. Una misma ruta rodada tres veces son
  /// tres entradas, porque cada salida tiene sus km, sus POIs y su recorrido.
  List<Map<String, dynamic>> _ridden = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // El botón de crear ruta se oculta en Rodadas, así que hay que repintar
    // al cambiar de pestaña.
    _tabController.addListener(() => setState(() {}));
    routeListRefresh.addListener(_loadRoutes);
    _loadRoutes();
  }

  @override
  void dispose() {
    routeListRefresh.removeListener(_loadRoutes);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    setState(() => _loading = true);

    // Las rutas planificadas y las rodadas viven en endpoints distintos:
    // unas son filas de 'routes' y las otras trackings.
    final results = await Future.wait([
      RouteService.getMyRoutes(),
      RouteTrackingService.history(),
    ]);

    if (!mounted) return;

    final routes = results[0] as Map<String, dynamic>;

    setState(() {
      _upcoming = List<Map<String, dynamic>>.from(routes['upcoming'] ?? []);
      _notDone  = List<Map<String, dynamic>>.from(routes['not_done'] ?? []);
      _received = List<Map<String, dynamic>>.from(routes['received'] ?? []);
      _ridden   = List<Map<String, dynamic>>.from(results[1] as List);
      _loading  = false;
    });
  }

  /// Abre el resumen de una ruta rodada: mapa, km reales y POIs detectados.
  ///
  /// El listado no trae el track ni los POIs, que son cientos de KB por ruta:
  /// se piden aquí.
  Future<void> _openRide(Map<String, dynamic> ride) async {
    final summary = await RouteTrackingService.summary(ride['id'] as int);
    if (!mounted) return;

    if (summary == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('common.error'.tr()),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    await context.push('/rider/summary', extra: {...summary, 'from_history': true});
    _loadRoutes();
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
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/rider/home');
            }
          },
        ),
        title: Text('my_routes.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.grey),
            onPressed: _loadRoutes,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.orange,
          labelColor: AppColors.orange,
          unselectedLabelColor: AppColors.grey,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              child: _TabLabel(
                icon: '📅',
                label: 'my_routes.upcoming'.tr(),
                count: _upcoming.length,
                activeColor: AppColors.cyan,
              ),
            ),
            Tab(
              child: _TabLabel(
                icon: '🏍️',
                label: 'my_routes.ridden'.tr(),
                count: _ridden.length,
                activeColor: AppColors.orange,
              ),
            ),
            Tab(
              child: _TabLabel(
                icon: '📚',
                label: 'my_routes.not_done'.tr(),
                count: _notDone.length,
                activeColor: AppColors.grey,
              ),
            ),
            Tab(
              child: _TabLabel(
                icon: '📨',
                label: 'my_routes.received'.tr(),
                count: _received.length,
                activeColor: AppColors.orange,
                highlight: _received.isNotEmpty,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : TabBarView(
              controller: _tabController,
              children: [
                _RouteList(
                  routes: _upcoming,
                  empty: 'my_routes.empty_upcoming'.tr(),
                  emptyIcon: Icons.event_outlined,
                  onTap: (r) async {
                    await context.push('/rider/routes/${r['id']}');
                    _loadRoutes();
                  },
                ),
                _RiddenList(
                  rides: _ridden,
                  onTap: _openRide,
                ),
                _RouteList(
                  routes: _notDone,
                  empty: 'my_routes.empty_not_done'.tr(),
                  emptyIcon: Icons.history,
                  onTap: (r) async {
                    await context.push('/rider/routes/${r['id']}');
                    _loadRoutes();
                  },
                ),
                _RouteList(
                  routes: _received,
                  empty: 'my_routes.empty_received'.tr(),
                  emptyIcon: Icons.mail_outline,
                  onTap: (r) async {
                    await context.push('/rider/routes/${r['id']}');
                    _loadRoutes();
                  },
                ),
              ],
            ),
      floatingActionButton: _tabController.index == 1
          // En Rodadas no tiene sentido "crear ruta": ahí solo hay historia.
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/rider/create-route'),
              backgroundColor: AppColors.orange,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text('my_routes.new_route'.tr(),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
    );
  }
}

// ─── Tab label con contador ───────────────────────────────────────────────────
class _TabLabel extends StatelessWidget {
  final String icon;
  final String label;
  final int count;
  final Color activeColor;
  final bool highlight;

  const _TabLabel({
    required this.icon,
    required this.label,
    required this.count,
    required this.activeColor,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(icon, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 5),
      Text(label),
      if (count > 0) ...[
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: highlight ? AppColors.error : activeColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: TextStyle(
                  color: highlight ? Colors.white : activeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ]);
  }
}

// ─── Lista genérica de rutas con filtros ─────────────────────────────────────
class _RouteList extends StatefulWidget {
  final List<Map<String, dynamic>> routes;
  final String empty;
  final IconData emptyIcon;
  final Function(Map<String, dynamic>) onTap;

  const _RouteList({
    required this.routes,
    required this.empty,
    required this.emptyIcon,
    required this.onTap,
  });

  @override
  State<_RouteList> createState() => _RouteListState();
}

class _RouteListState extends State<_RouteList> {
  final _searchController = TextEditingController();
  String _search      = '';
  String? _difficulty; // tranquila | moderada | exigente
  String? _routeType;  // circular | destino
  String? _source;     // ai | google_maps | gpx

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    return widget.routes.where((r) {
      final title  = (r['title']  ?? '').toString().toLowerCase();
      final origin = (r['origin'] ?? '').toString().toLowerCase();
      final q      = _search.toLowerCase();
      if (q.isNotEmpty && !title.contains(q) && !origin.contains(q)) return false;
      if (_difficulty != null && r['difficulty'] != _difficulty) return false;
      if (_routeType  != null && r['route_type']  != _routeType)  return false;
      if (_source     != null && r['source_type'] != _source)     return false;
      return true;
    }).toList();
  }

  bool get _hasFilters => _search.isNotEmpty || _difficulty != null || _routeType != null || _source != null;

  void _clearFilters() => setState(() {
    _search = '';
    _searchController.clear();
    _difficulty = null;
    _routeType  = null;
    _source     = null;
  });

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Column(children: [
      // ── Barra de búsqueda ──
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: AppColors.white, fontSize: 14),
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: 'my_routes.search_hint'.tr(),
            hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: AppColors.grey, size: 20),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.grey, size: 18),
                    onPressed: () => setState(() { _search = ''; _searchController.clear(); }),
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),

      // ── Chips de filtro ──
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          children: [
            // Dificultad
            _FilterChip(label: 'my_routes.filter_easy'.tr(), active: _difficulty == 'tranquila', color: Colors.green,
                onTap: () => setState(() => _difficulty = _difficulty == 'tranquila' ? null : 'tranquila')),
            _FilterChip(label: 'my_routes.filter_moderate'.tr(), active: _difficulty == 'moderada', color: AppColors.gold,
                onTap: () => setState(() => _difficulty = _difficulty == 'moderada'  ? null : 'moderada')),
            _FilterChip(label: 'my_routes.filter_hard'.tr(), active: _difficulty == 'exigente', color: AppColors.error,
                onTap: () => setState(() => _difficulty = _difficulty == 'exigente'  ? null : 'exigente')),
            const _FilterDivider(),
            _FilterChip(label: 'my_routes.filter_circular'.tr(), active: _routeType == 'circular', color: AppColors.cyan,
                onTap: () => setState(() => _routeType = _routeType == 'circular'    ? null : 'circular')),
            _FilterChip(label: 'my_routes.filter_destination'.tr(), active: _routeType == 'destino', color: AppColors.cyan,
                onTap: () => setState(() => _routeType = _routeType == 'destino'     ? null : 'destino')),
            const _FilterDivider(),
            _FilterChip(label: 'IA', active: _source == 'ai', color: AppColors.orange,
                onTap: () => setState(() => _source = _source == 'ai'           ? null : 'ai')),
            _FilterChip(label: 'Maps', active: _source == 'google_maps', color: AppColors.orange,
                onTap: () => setState(() => _source = _source == 'google_maps'  ? null : 'google_maps')),
            _FilterChip(label: 'GPX', active: _source == 'gpx', color: AppColors.cyan,
                onTap: () => setState(() => _source = _source == 'gpx'          ? null : 'gpx')),
            if (_hasFilters) ...[
              const _FilterDivider(),
              _FilterChip(label: 'my_routes.filter_clear'.tr(), active: false, color: AppColors.grey, onTap: _clearFilters,
                  icon: Icons.close),
            ],
          ],
        ),
      ),

      // ── Lista ──
      Expanded(
        child: filtered.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_hasFilters ? Icons.filter_list_off : widget.emptyIcon,
                      color: AppColors.greyDark, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    _hasFilters ? 'my_routes.empty_filters'.tr() : widget.empty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5),
                  ),
                  if (_hasFilters) ...[
                    const SizedBox(height: 12),
                    TextButton(onPressed: _clearFilters,
                        child: Text('my_routes.filter_clear_all'.tr(), style: const TextStyle(color: AppColors.orange))),
                  ],
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _RouteCard(
                  route: filtered[i],
                  onTap: () => widget.onTap(filtered[i]),
                  isReceived: filtered[i]['is_received'] == true,
                ),
              ),
      ),
    ]);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  const _FilterChip({required this.label, required this.active, required this.color, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color : AppColors.greyDark),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, color: active ? color : AppColors.grey, size: 13), const SizedBox(width: 4)],
          Text(label, style: TextStyle(
            color: active ? color : AppColors.grey,
            fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          )),
        ]),
      ),
    );
  }
}

class _FilterDivider extends StatelessWidget {
  const _FilterDivider();
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    color: AppColors.greyDark,
  );
}


// ─── Tarjeta de ruta ──────────────────────────────────────────────────────────
class _RouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  final VoidCallback onTap;
  final bool isReceived;

  const _RouteCard({
    required this.route,
    required this.onTap,
    this.isReceived = false,
  });

  bool get _isReceived => isReceived || route['is_received'] == true;

  Color get _statusColor {
    if (_isReceived) {
      final confirmed = route['is_confirmed'] == true;
      final declined  = route['is_declined']  == true;
      return confirmed ? Colors.green
           : declined  ? AppColors.error
           : AppColors.orange;
    }
    switch (route['visibility']) {
      case 'public':  return AppColors.orange;
      case 'friends': return AppColors.cyan;
      default:        return AppColors.grey;
    }
  }

  String get _statusLabel {
    if (_isReceived) {
      final confirmed = route['is_confirmed'] == true;
      final declined  = route['is_declined']  == true;
      final visLabel  = route['visibility'] == 'public' ? 'my_routes.status_public'.tr() : 'my_routes.status_friends'.tr();
      final stateLabel = confirmed ? 'my_routes.status_joined'.tr()
          : declined  ? 'my_routes.status_declined'.tr()
          : 'my_routes.status_pending'.tr();
      return '$visLabel · $stateLabel';
    }
    switch (route['visibility']) {
      case 'public':  return 'my_routes.status_public'.tr();
      case 'friends': return 'my_routes.status_friends'.tr();
      default:        return 'my_routes.status_private'.tr();
    }
  }

  String _formatDate(String? date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date);
      final days   = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
      final months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun',
                      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) { return date; }
  }

  @override
  Widget build(BuildContext context) {
    final date = route['departure_date'];
    final time = route['departure_time'];
    final hasDate = date != null && date.toString().isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.greyDark,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Banda de fecha/hora
          if (hasDate)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.cyan.withOpacity(0.12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                    bottom: BorderSide(color: AppColors.cyan.withOpacity(0.25))),
              ),
              child: Row(children: [
                const Icon(Icons.event, color: AppColors.cyan, size: 15),
                const SizedBox(width: 7),
                Text(_formatDate(date),
                    style: const TextStyle(
                        color: AppColors.cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                if (time != null && time.toString().isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.schedule, color: AppColors.cyan, size: 14),
                  const SizedBox(width: 4),
                  Text('Salida: $time',
                      style: const TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ],
              ]),
            ),

          // Creador (si es ruta recibida de otro)
          if (_isReceived && route['owner_name'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                Icon(Icons.person_outline,
                    color: route['is_confirmed'] == true ? AppColors.cyan : AppColors.orange,
                    size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'De: ${route['owner_name']}${route['owner_nick'] != null ? ' @${route['owner_nick']}' : ''}',
                    style: TextStyle(
                        color: route['is_confirmed'] == true ? AppColors.cyan : AppColors.orange,
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(route['title'] ?? 'my_routes.no_title'.tr(),
                      style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _statusColor.withOpacity(0.35)),
                  ),
                  child: Text(_statusLabel,
                      style: TextStyle(
                          color: _statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 10),
              // Los chips se envuelven: con el de origen siempre presente, en
              // pantallas estrechas la fila se salía.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(Icons.route, '${route['distance_km'] ?? '?'} km', AppColors.orange),
                  _Chip(Icons.access_time,
                      '${(((route['duration_minutes'] ?? 0) as num) / 60).toStringAsFixed(1)} h',
                      AppColors.cyan),
                  _Chip(Icons.terrain, route['difficulty'] ?? '', AppColors.gold),
                  // Origen de la ruta. Antes solo se pintaba en las GPX, así
                  // que las de IA y las de Google Maps no mostraban nada y
                  // parecía que faltaba información según la pestaña.
                  _SourceChip(source: route['source_type']?.toString()),
                ],
              ),
              const SizedBox(height: 8),
              // Moto
              if (route['moto_info'] != null)
                Row(children: [
                  const Icon(Icons.two_wheeler, color: AppColors.grey, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${route['moto_info']['brand']} ${route['moto_info']['model'] ?? ''}'.trim() + ' · ${route['moto_info']['engine_cc']} cc',
                    style: const TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                ]),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.location_on_outlined, color: AppColors.grey, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(route['origin'] ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                ),
                // Botón Ver en Maps
                if (route['google_maps_url'] != null)
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse(route['google_maps_url']);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cyan.withOpacity(0.4)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.map_outlined, color: AppColors.cyan, size: 13),
                        SizedBox(width: 4),
                        Text('Maps', style: TextStyle(
                            color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  )
                else
                  const Icon(Icons.arrow_forward_ios, color: AppColors.greyDark, size: 12),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Lista de rutas rodadas.
///
/// A diferencia de las demás pestañas, aquí cada entrada es un TRACKING, no
/// una ruta: repetir la misma ruta tres veces son tres entradas, porque cada
/// salida tiene sus kilómetros, sus POIs y su recorrido.
class _RiddenList extends StatelessWidget {
  final List<Map<String, dynamic>> rides;
  final Future<void> Function(Map<String, dynamic>) onTap;

  const _RiddenList({required this.rides, required this.onTap});

  String _formatDate(String? iso) {
    final date = iso == null ? null : DateTime.tryParse(iso);
    return date == null ? '' : DateFormat.yMMMd().add_Hm().format(date.toLocal());
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    if (rides.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.two_wheeler, color: AppColors.grey, size: 48),
            const SizedBox(height: 16),
            Text('my_routes.empty_ridden'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5)),
          ]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rides.length,
      itemBuilder: (_, i) {
        final ride = rides[i];
        final route = Map<String, dynamic>.from(ride['route'] ?? {});
        final km = (ride['distance_km'] as num?)?.toDouble() ?? 0;
        final seconds = (ride['duration_seconds'] as num?)?.toInt() ?? 0;
        final speed = (ride['avg_speed_kmh'] as num?)?.toDouble() ?? 0;

        // Una ruta rechazada por antitrampa sigue siendo una ruta que se hizo:
        // se muestra con su motivo, en vez de desaparecer sin explicación.
        final rejected = ride['status'] == 'rejected';
        final autoClosed = ride['status'] == 'auto_closed';
        final accent = rejected ? AppColors.error : AppColors.orange;

        // Tiempo en movimiento, sin las paradas. Las rodadas anteriores a que
        // existiera este dato no lo traen: ahí se cae al tiempo total.
        final movingSeconds = (ride['moving_seconds'] as num?)?.toInt();
        final effective = movingSeconds ?? seconds;

        // La media se calcula sobre el tiempo EN MOVIMIENTO, no sobre el
        // total. Con el total, una parada larga para comer la hunde: los
        // mismos 86 km en 4 h dan 21 km/h, que no dice nada de cómo se rodó,
        // solo de cuánto se paró. Las dos duraciones se enseñan juntas, así
        // que el tiempo parado no se oculta: se ve restando una de otra.
        final speedKmh = effective > 0 ? km / (effective / 3600) : speed;

        final pois = (ride['visited_pois_count'] as num?)?.toInt() ?? 0;
        final achievements = (ride['achievements_count'] as num?)?.toInt() ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: rejected ? AppColors.error.withValues(alpha: 0.4) : AppColors.greyDark),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Barra superior con la fecha, como en el resto de pestañas.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(children: [
                const Icon(Icons.event_available, color: AppColors.cyan, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_formatDate(ride['started_at'] as String?),
                      style: const TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(route['title']?.toString() ?? 'my_routes.no_title'.tr(),
                        style: const TextStyle(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                        rejected
                            ? 'my_routes.status_not_counted'.tr()
                            : 'my_routes.status_ridden'.tr(),
                        style: TextStyle(
                            color: accent, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 10),

                Wrap(spacing: 8, runSpacing: 8, children: [
                  _Chip(Icons.route, '${km.toStringAsFixed(1)} km', AppColors.orange),
                  _Chip(Icons.access_time, _formatDuration(seconds), AppColors.cyan),
                  if (route['difficulty'] != null)
                    _Chip(Icons.terrain, route['difficulty'].toString(), AppColors.gold),
                  _SourceChip(source: route['source_type']?.toString()),
                ]),
                const SizedBox(height: 8),

                if (route['moto_info'] != null)
                  Row(children: [
                    const Icon(Icons.two_wheeler, color: AppColors.grey, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${route['moto_info']['brand']} ${route['moto_info']['model'] ?? ''}'.trim()
                            + ' · ${route['moto_info']['engine_cc']} cc',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.grey, fontSize: 12),
                      ),
                    ),
                  ]),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.location_on_outlined, color: AppColors.grey, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(route['origin']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                  ),
                ]),

                // Lo que distingue a una rodada de una ruta planificada: lo
                // que pasó de verdad.
                const SizedBox(height: 12),
                const Divider(color: AppColors.greyDark, height: 1),
                const SizedBox(height: 12),
                Row(children: [
                  _RideStat(
                    label: 'my_routes.moving'.tr(),
                    value: _formatDuration(effective),
                  ),
                  _RideStat(
                    label: 'my_routes.avg_speed'.tr(),
                    value: '${speedKmh.toStringAsFixed(0)} km/h',
                  ),
                  _RideStat(
                    label: 'my_routes.pois'.tr(),
                    value: '$pois',
                  ),
                  _RideStat(
                    label: 'my_routes.achievements'.tr(),
                    value: '$achievements',
                    color: achievements > 0 ? AppColors.gold : null,
                  ),
                ]),

                if (rejected && ride['rejected_reason'] != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'my_routes.not_counted'.tr(
                        namedArgs: {'reason': ride['rejected_reason'].toString()}),
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 11, height: 1.3),
                  ),
                ],
                if (autoClosed) ...[
                  const SizedBox(height: 10),
                  Text('my_routes.auto_closed'.tr(),
                      style: const TextStyle(color: AppColors.gold, fontSize: 11)),
                ],

                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => onTap(ride),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('my_routes.view_summary'.tr(),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Un dato de la rodada: etiqueta pequeña arriba y valor debajo.
///
/// Los cuatro reparten el ancho a partes iguales para que queden alineados
/// entre tarjetas, aunque los valores midan distinto.
class _RideStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _RideStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.grey, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color ?? AppColors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Chip que indica de dónde salió la ruta: generada con IA, importada de
/// Google Maps o de un fichero GPX.
///
/// Se pinta siempre, en las cuatro pestañas. Antes solo aparecía en las GPX,
/// lo que hacía parecer que unas pestañas mostraban menos datos que otras
/// cuando en realidad dependía del tipo de ruta que hubiera en cada una.
class _SourceChip extends StatelessWidget {
  final String? source;

  const _SourceChip({required this.source});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (source) {
      'gpx'         => (Icons.folder_open, 'my_routes.source_gpx'.tr()),
      'google_maps' => (Icons.map_outlined, 'my_routes.source_maps'.tr()),
      _             => (Icons.auto_awesome, 'my_routes.source_ai'.tr()),
    };

    return _Chip(icon, label, AppColors.cyan);
  }
}

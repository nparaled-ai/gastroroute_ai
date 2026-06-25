import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/rider_avatar.dart';
import '../providers/friendship_service.dart';
import '../providers/route_service.dart';
import '../providers/route_share_service.dart';

class RouteResultScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  const RouteResultScreen({super.key, required this.result});

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen> {
  bool _publishing        = false;
  bool _saving            = false;
  bool _refreshingWeather = false;
  bool _saved             = false; // true cuando ya se guardó
  Map<String, dynamic>? _savedRoute; // ruta guardada con ID
  Map<String, dynamic>? _currentWeather;

  Map<String, dynamic> get _route => widget.result['route'] ?? {};
  bool get _isImported => (_route['tags'] as List? ?? []).contains('importada');
  Map<String, dynamic>? get _weather     => _currentWeather ?? widget.result['weather'];
  Map<String, dynamic>? get _aiSummary   => widget.result['ai_summary'];
  List                  get _waypoints   => _route['waypoints'] ?? [];
  int?  get _routesRemaining             => widget.result['routes_remaining'];
  int?  get _fuelRangeKm                 => widget.result['fuel_range_km'];

  @override
  void initState() {
    super.initState();
    _currentWeather = widget.result['weather'];
  }

  Map<String, dynamic> _buildFormData() =>
      Map<String, dynamic>.from(widget.result['form_data'] ?? {});

  // Actualizar clima
  Future<void> _refreshWeather() async {
    setState(() => _refreshingWeather = true);
    final result = await RouteService.refreshWeather(
      _route['origin_lat'],
      _route['origin_lng'],
    );
    if (!mounted) return;
    setState(() {
      _refreshingWeather = false;
      if (result['weather'] != null) _currentWeather = result['weather'];
    });
    if (result['weather'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Clima actualizado.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ));
    }
  }

  // Solo guardar sin compartir
  Future<void> _saveOnly() async {
    if (_saved && _savedRoute != null) {
      _showSaveResult();
      return;
    }
    setState(() => _saving = true);
    final saveData = Map<String, dynamic>.from(widget.result['_save_data'] ?? {});
    final result = await RouteService.saveRoute(saveData);
    if (!mounted) return;
    setState(() { _saving = false; });
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
      return;
    }
    setState(() { _saved = true; _savedRoute = result['route']; });
    _showSaveResult();
  }

  void _showSaveResult() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          const Text('¡Ruta guardada!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Guardada en Mis Rutas. Solo tú puedes verla.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey, fontSize: 13)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/rider/route-generator', extra: _buildFormData());
            },
            child: const Text('Generar otra', style: TextStyle(color: AppColors.grey)),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); context.go('/rider/my-routes'); },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Ver mis rutas',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // Guardar y luego compartir
  Future<void> _saveAndShare() async {
    // Si ya está guardada, abrir directo el bottom sheet
    if (_saved && _savedRoute != null) {
      _showShareDialog();
      return;
    }
    setState(() => _saving = true);
    final saveData = Map<String, dynamic>.from(widget.result['_save_data'] ?? {});
    final result = await RouteService.saveRoute(saveData);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
      return;
    }
    setState(() {
      _saved      = true;
      _savedRoute = result['route'];
    });
    _showShareDialog();
  }

  // Compartir (usa _savedRoute que ya tiene ID)
  Future<void> _shareWithFriends(List<int> selectedFriendIds) async {
    final routeId = _savedRoute?['id'] ?? _route['id'];
    if (routeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error: ruta sin ID.'), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _publishing = true);
    final result = await RouteShareService.share(routeId, visibility: 'friends', friendIds: selectedFriendIds);
    if (!mounted) return;
    setState(() => _publishing = false);
    _showShareResult(result);
  }

  Future<void> _sharePublic() async {
    final routeId = _savedRoute?['id'] ?? _route['id'];
    if (routeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error: ruta sin ID.'), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _publishing = true);
    final result = await RouteShareService.share(routeId, visibility: 'public');
    if (!mounted) return;
    setState(() => _publishing = false);
    _showShareResult(result);
  }

  void _showShareResult(Map<String, dynamic> result) {
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error),
      );
      return;
    }

    // Dialog de confirmación con acciones
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          Text(
            result['message'] ?? '¡Ruta compartida!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if ((result['notified_count'] ?? 0) > 0) ...[  
            const SizedBox(height: 8),
            Text(
              '${result['notified_count']} ${result['notified_count'] == 1 ? 'motero notificado' : 'moteros notificados'}',
              style: const TextStyle(color: AppColors.grey, fontSize: 13),
            ),
          ],
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/rider/route-generator', extra: _buildFormData()..['origin'] = _route['origin']);
            },
            child: const Text('Generar otra', style: TextStyle(color: AppColors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/rider/my-routes');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Ver mis rutas', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showShareDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ShareBottomSheet(
        onShareFriends: (friendIds) => _shareWithFriends(friendIds),
        onSharePublic:  () => _sharePublic(),
        onSaveOnly:     () => _saveOnly(),
      ),
    );
  }

  Future<void> _openInGoogleMaps() async {
    final url = _route['google_maps_url'];
    if (url == null) return;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abrir Google Maps: $e'),
              backgroundColor: AppColors.error));
      }
    }
  }

  Widget _buildDayWarning() {
    final distKm = ((_route['distance_km'] ?? 0) as num).toDouble();
    final hours  = ((_route['duration_minutes'] ?? 0) as num).toDouble() / 60;
    if (distKm <= 500 && hours <= 8) return const SizedBox.shrink();
    final bool critical = distKm > 700 || hours > 12;
    final color = critical ? AppColors.error : AppColors.gold;
    final icon  = critical ? Icons.warning_rounded : Icons.info_outline;
    final message = critical
        ? '⛔ Ruta muy exigente para 1 día: ${distKm.toInt()} km / ${hours.toStringAsFixed(1)} h.'
        : '⚠️ Ruta larga para 1 día: ${distKm.toInt()} km / ${hours.toStringAsFixed(1)} h.';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _ActionBtn(label: 'Regenerar más corta', icon: Icons.auto_awesome, color: color,
              onTap: () => context.go('/rider/route-generator', extra: {..._buildFormData(), 'duration_mode': 'ai'}))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _ActionBtn(label: 'Limitar a 6 horas', icon: Icons.access_time, color: AppColors.cyan,
              onTap: () => context.go('/rider/route-generator', extra: {..._buildFormData(), 'duration_mode': 'hours', 'hours': 6}))),
          const SizedBox(width: 8),
          Expanded(child: _ActionBtn(label: 'Limitar a 350 km', icon: Icons.speed, color: AppColors.orange,
              onTap: () => context.go('/rider/route-generator', extra: {..._buildFormData(), 'duration_mode': 'km', 'km': 350}))),
        ]),
      ]),
    );
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
        title: Text('route_result.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.orange),
            onPressed: _saveAndShare,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppColors.orange.withOpacity(0.3), AppColors.surface],
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(
                  _isImported ? Icons.download_outlined : Icons.auto_awesome,
                  color: AppColors.orange, size: 16),
                const SizedBox(width: 6),
                Text(
                  _isImported ? 'Importada de Google Maps' : 'route_result.generated_by_ai'.tr(),
                  style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_routesRemaining != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.greyDark, borderRadius: BorderRadius.circular(10)),
                    child: Text('route_result.routes_remaining'.tr(args: ['$_routesRemaining']),
                        style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                  ),
              ]),
              // Fecha de salida si existe
              if (_route['departure_date'] != null) ...[  
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.event, color: AppColors.cyan, size: 14),
                  const SizedBox(width: 6),
                  Text(_route['departure_date'],
                      style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 13)),
                  if (_route['departure_time'] != null) ...[  
                    const SizedBox(width: 10),
                    const Icon(Icons.schedule, color: AppColors.cyan, size: 13),
                    const SizedBox(width: 4),
                    Text('Salida: ${_route['departure_time']}',
                        style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ]),
              ],
              const SizedBox(height: 12),
              Text(_route['title'] ?? '',
                  style: const TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(_route['description'] ?? '',
                  style: const TextStyle(color: AppColors.grey, fontSize: 13, height: 1.5)),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Stats
              Row(children: [
                _StatBadge(icon: Icons.route, label: '${_route['distance_km']} km', color: AppColors.orange),
                const SizedBox(width: 8),
                _StatBadge(icon: Icons.access_time,
                    label: '${((_route['duration_minutes'] ?? 0) / 60).toStringAsFixed(1)} h',
                    color: AppColors.cyan),
                const SizedBox(width: 8),
                _StatBadge(icon: Icons.terrain, label: _route['difficulty'] ?? '', color: AppColors.gold),
              ]),

              _buildDayWarning(),

              const SizedBox(height: 16),

              // Clima con botón actualizar
              if (_weather != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.greyDark),
                  ),
                  child: Row(children: [
                    _WeatherIcon(weather: _weather, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_weather!['temp']?.toStringAsFixed(0)}°C · ${_weather!['description']}',
                          style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                      Text('Viento ${_weather!['wind_speed']} m/s · Humedad ${_weather!['humidity']}%',
                          style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                    ])),
                    // Botón actualizar clima
                    GestureDetector(
                      onTap: _refreshingWeather ? null : _refreshWeather,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                        ),
                        child: _refreshingWeather
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2))
                            : const Icon(Icons.refresh, color: AppColors.cyan, size: 18),
                      ),
                    ),
                    if (_aiSummary?['best_departure_time'] != null) ...[
                      const SizedBox(width: 8),
                      Column(children: [
                        Text('route_result.departure'.tr(),
                            style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                        Text(_aiSummary!['best_departure_time'],
                            style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 16)),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // Autonomía
              if (_fuelRangeKm != null) ...[
                Builder(builder: (context) {
                  final fuelStops = List<num>.from(_aiSummary?['fuel_stops'] ?? []);
                  final distKm = (_route['distance_km'] ?? 0) as num;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: distKm > _fuelRangeKm!
                            ? AppColors.error.withOpacity(0.5) : AppColors.greyDark),
                    ),
                    child: Row(children: [
                      Icon(Icons.local_gas_station,
                          color: distKm > _fuelRangeKm! ? AppColors.error : AppColors.grey, size: 24),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('route_result.autonomy'.tr(args: ['$_fuelRangeKm']),
                            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                        if (fuelStops.isNotEmpty)
                          Text(
                            fuelStops.length == 1
                                ? 'Necesitas 1 parada (aprox. ${fuelStops[0]} km)'
                                : 'Necesitas ${fuelStops.length} paradas: ${fuelStops.map((k) => '${k}km').join(', ')}',
                            style: const TextStyle(color: AppColors.error, fontSize: 12),
                          ),
                      ])),
                    ]),
                  );
                }),
                const SizedBox(height: 16),
              ],

              // Waypoints
              Text('route_result.waypoints'.tr(),
                  style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _buildWaypoints(),

              const SizedBox(height: 24),

              // Almuerzo - solo si se pidió
              if (_route['lunch_stop'] != null && (widget.result['form_data']?['suggest_lunch'] == true)) ...[
                _SectionHeader(icon: Icons.restaurant_outlined,
                    label: 'route_result.lunch_stop'.tr(), color: AppColors.orange),
                const SizedBox(height: 8),
                _SuggestionCard(icon: Icons.restaurant_outlined,
                    title: _route['lunch_stop']['location'] ?? '',
                    subtitle: _route['lunch_stop']['suggestion'] ?? '',
                    badge: _route['lunch_stop']['estimated_time'], color: AppColors.orange),
                const SizedBox(height: 16),
              ],

              // Comer - solo si se pidió
              if (_route['dinner_stop'] != null && (widget.result['form_data']?['suggest_dinner'] == true)) ...[
                _SectionHeader(icon: Icons.dinner_dining,
                    label: 'route_result.dinner_stop'.tr(), color: AppColors.cyan),
                const SizedBox(height: 8),
                _SuggestionCard(icon: Icons.dinner_dining,
                    title: _route['dinner_stop']['location'] ?? '',
                    subtitle: _route['dinner_stop']['suggestion'] ?? '',
                    badge: _route['dinner_stop']['estimated_time'], color: AppColors.cyan),
                const SizedBox(height: 16),
              ],

              // Tags
              if (_route['tags'] != null && (_route['tags'] as List).isNotEmpty) ...[
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: (_route['tags'] as List).map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                    ),
                    child: Text(tag.toString(), style: const TextStyle(color: AppColors.cyan, fontSize: 12)),
                  )).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Botones
              ElevatedButton(
                onPressed: _openInGoogleMaps,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.map, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('route_result.open_maps'.tr(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
              ),

              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: (_publishing || _saving) ? null : _saveAndShare,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  side: const BorderSide(color: AppColors.orange),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: (_publishing || _saving)
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_saved ? Icons.share_outlined : Icons.save_outlined,
                            color: AppColors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text(_saved ? 'Compartir' : 'Guardar y compartir',
                            style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
                      ]),
              ),

              const SizedBox(height: 32),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildWaypoints() {
    final aiSummary         = _aiSummary ?? {};
    final fuelStops         = List<num>.from(aiSummary['fuel_stops'] ?? []);
    final totalKm           = (_route['distance_km'] ?? 0).toDouble();
    final totalMins         = (_route['duration_minutes'] ?? 1).toDouble();
    final departureTime     = aiSummary['best_departure_time'];
    final insertedFuelStops = <int>{};
    bool lunchInserted      = false;
    bool dinnerInserted     = false;
    final lunchStop  = (_route['lunch_stop'] != null && (widget.result['form_data']?['suggest_lunch'] == true))
        ? _route['lunch_stop'] : null;
    final dinnerStop = (_route['dinner_stop'] != null && (widget.result['form_data']?['suggest_dinner'] == true))
        ? _route['dinner_stop'] : null;

    int? timeToMins(String? t) {
      if (t == null) return null;
      final p = t.split(':');
      if (p.length != 2) return null;
      final h = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      if (h == null || m == null) return null;
      return h * 60 + m;
    }

    final departureMins = timeToMins(departureTime);
    final lunchMins     = timeToMins(lunchStop?['estimated_time']);
    final dinnerMins    = timeToMins(dinnerStop?['estimated_time']);
    final List<Widget> items = [];

    for (int i = 0; i < _waypoints.length; i++) {
      final wp = _waypoints[i];
      final wpName = (wp['name'] ?? '').toLowerCase();
      final wpNote = (wp['note'] ?? '').toLowerCase();

      // Filtrar waypoints de gasolinera
      if (wpName.contains('repostaje') || wpName.contains('gasolinera') ||
          wpName.contains('repostar') || wpNote.contains('repostar antes')) continue;

      // Filtrar waypoints de comida si ya tenemos dinner_stop
      if (dinnerStop != null && (wpName.contains('comida') || wpName.contains('comer') ||
          wpName.contains('dinner') || wpNote.contains('parada para comer') ||
          wpNote.contains('comida'))) continue;

      // Filtrar waypoints de almuerzo si ya tenemos lunch_stop
      if (lunchStop != null && (wpName.contains('almuerzo') || wpName.contains('lunch') ||
          wpNote.contains('almuerzo') || wpNote.contains('parada para almorzar'))) continue;

      final isFirst   = i == 0;
      final isLast    = i == _waypoints.length - 1;
      final mins      = (wp['estimated_minutes_from_start'] ?? 0).toDouble();
      final approxKm  = totalMins > 0 ? (mins / totalMins).clamp(0.0, 1.0) * totalKm : 0.0;
      final pct       = totalMins > 0 ? (mins / totalMins).clamp(0.0, 1.0) : 0.0;
      final wpAbsMins = departureMins != null ? departureMins + mins.toInt() : null;

      for (int s = 0; s < fuelStops.length; s++) {
        if (!insertedFuelStops.contains(s) && approxKm >= fuelStops[s].toDouble()) {
          insertedFuelStops.add(s);
          items.add(_FuelStopRow(km: fuelStops[s], stopNumber: s + 1, total: fuelStops.length));
        }
      }

      if (!lunchInserted && lunchStop != null) {
        final insert = wpAbsMins != null && lunchMins != null
            ? wpAbsMins >= lunchMins : pct >= 0.4;
        if (insert) {
          lunchInserted = true;
          items.add(_MealStopRow(icon: Icons.restaurant_outlined, color: AppColors.orange,
            location: lunchStop['location'] ?? '', suggestion: lunchStop['suggestion'] ?? '',
            time: lunchStop['estimated_time'], label: 'route_result.lunch_stop'.tr()));
        }
      }

      if (!dinnerInserted && dinnerStop != null) {
        final insert = wpAbsMins != null && dinnerMins != null
            ? wpAbsMins >= dinnerMins : pct >= 0.65;
        if (insert) {
          dinnerInserted = true;
          items.add(_MealStopRow(icon: Icons.dinner_dining, color: AppColors.cyan,
            location: dinnerStop['location'] ?? '', suggestion: dinnerStop['suggestion'] ?? '',
            time: dinnerStop['estimated_time'], label: 'route_result.dinner_stop'.tr()));
        }
      }

      items.add(_WaypointRow(index: i, isFirst: isFirst, isLast: isLast, wp: wp, weather: _weather));
    }

    for (int s = 0; s < fuelStops.length; s++) {
      if (!insertedFuelStops.contains(s)) {
        final li = items.length - 1;
        items.insert(li > 0 ? li : 0, _FuelStopRow(km: fuelStops[s], stopNumber: s + 1, total: fuelStops.length));
      }
    }
    if (!lunchInserted && lunchStop != null) {
      final li = items.length - 1;
      items.insert(li > 0 ? li : 0, _MealStopRow(icon: Icons.restaurant_outlined, color: AppColors.orange,
        location: lunchStop['location'] ?? '', suggestion: lunchStop['suggestion'] ?? '',
        time: lunchStop['estimated_time'], label: 'route_result.lunch_stop'.tr()));
    }
    if (!dinnerInserted && dinnerStop != null) {
      final li = items.length - 1;
      items.insert(li > 0 ? li : 0, _MealStopRow(icon: Icons.dinner_dining, color: AppColors.cyan,
        location: dinnerStop['location'] ?? '', suggestion: dinnerStop['suggestion'] ?? '',
        time: dinnerStop['estimated_time'], label: 'route_result.dinner_stop'.tr()));
    }

    return Column(children: items);
  }
}

// Bottom sheet compartir con selección de amigos
class _ShareBottomSheet extends StatefulWidget {
  final Function(List<int>) onShareFriends;
  final VoidCallback onSharePublic;
  final VoidCallback onSaveOnly;
  const _ShareBottomSheet({
    required this.onShareFriends,
    required this.onSharePublic,
    required this.onSaveOnly,
  });

  @override
  State<_ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<_ShareBottomSheet> {
// 0 = menu principal, 1 = seleccionar amigos
int _step = 0;
List<Map<String, dynamic>> _friends = [];
Set<int> _selected = {};
  bool _loading = false;
bool _shareAll = false;

Future<void> _loadFriends() async {
setState(() { _loading = true; });
  final result = await FriendshipService.getFriends();
    if (!mounted) return;
  setState(() {
  _friends = List<Map<String, dynamic>>.from(result['friends'] ?? []);
  _loading = false;
  _step = 1;
});
}

@override
  Widget build(BuildContext context) {
  return SafeArea(
    child: SingleChildScrollView(
    padding: EdgeInsets.only(
    left: 24, right: 24, top: 24,
    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
),
child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    // Handle
    Center(child: Container(width: 40, height: 4,
      decoration: BoxDecoration(color: AppColors.greyDark, borderRadius: BorderRadius.circular(2)))),
const SizedBox(height: 20),

if (_step == 0) ..._buildMainMenu(),
if (_step == 1) ..._buildFriendSelector(),
        ]),
),
);
}

List<Widget> _buildMainMenu() => [
const Text('¿Qué quieres hacer con esta ruta?',
style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
const SizedBox(height: 20),

// Opción 1 — Guardar para mí
_OptionCard(
icon: Icons.lock_outline,
color: AppColors.grey,
title: 'Guardar para mí',
desc: 'Solo tú puedes verla. Aparecerá en Mis Rutas.',
onTap: () {
Navigator.pop(context);
widget.onSaveOnly();
},
),
const SizedBox(height: 12),

// Opción 2 — Compartir con amigos
_OptionCard(
icon: Icons.people_outlined,
color: AppColors.cyan,
title: 'Compartir con amigos',
desc: 'Elige qué amigos pueden ver la ruta y apuntarse.',
onTap: _loadFriends,
trailing: _loading
          ? const SizedBox(width: 18, height: 18,
    child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2))
          : const Icon(Icons.arrow_forward_ios, color: AppColors.cyan, size: 14),
),
const SizedBox(height: 12),

// Opción 3 — Publicar para todos
_OptionCard(
icon: Icons.public,
color: AppColors.orange,
title: 'Publicar para todos',
desc: 'Cualquier motero de tu zona puede verla y apuntarse.',
onTap: () {
Navigator.pop(context);
widget.onSharePublic();
},
),
const SizedBox(height: 8),
];

List<Widget> _buildFriendSelector() => [
Row(children: [
GestureDetector(
onTap: () => setState(() => _step = 0),
child: const Icon(Icons.arrow_back_ios, color: AppColors.grey, size: 18),
      ),
const SizedBox(width: 8),
const Text('Selecciona amigos',
style: TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
const Spacer(),
if (_friends.isNotEmpty)
GestureDetector(
onTap: () => setState(() {
if (_shareAll) { _selected.clear(); _shareAll = false; }
else { _selected = _friends.map((f) => f['user_id'] as int).toSet(); _shareAll = true; }
}),
child: Text(_shareAll ? 'Quitar todos' : 'Todos',
style: const TextStyle(color: AppColors.grey, fontSize: 12)),
),
]),
const SizedBox(height: 16),

if (_friends.isEmpty)
const Padding(
padding: EdgeInsets.all(16),
child: Text('No tienes amigos aún.', style: TextStyle(color: AppColors.grey))
)
else
SizedBox(
height: 300,
child: ListView.builder(
itemCount: _friends.length,
itemBuilder: (ctx, i) {
final f   = _friends[i];
final uid = f['user_id'] as int;
final chk = _selected.contains(uid);
final name = '${f['first_name'] ?? ''} ${f['last_name'] ?? ''}'.trim();
return ListTile(
contentPadding: EdgeInsets.zero,
leading: RiderAvatar(avatarUrl: f['avatar_url'],
level: f['experience_level'] ?? 'novato', size: 44),
title: Text(name.isNotEmpty ? name : f['nickname'] ?? '',
style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
subtitle: f['nickname'] != null
? Text('@${f['nickname']}',
style: const TextStyle(color: AppColors.orange, fontSize: 12))
: null,
trailing: Checkbox(
value: chk,
activeColor: AppColors.cyan,
side: const BorderSide(color: AppColors.grey),
onChanged: (_) => setState(() {
if (chk) _selected.remove(uid); else _selected.add(uid);
}),
),
              onTap: () => setState(() {
      if (chk) _selected.remove(uid); else _selected.add(uid);
              }),
          );
        },
      ),
  ),

const SizedBox(height: 12),
  ElevatedButton(
    onPressed: _selected.isEmpty ? null : () {
      final ids = _selected.toList();
      Navigator.pop(context);
      widget.onShareFriends(ids);
    },
    style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.cyan,
minimumSize: const Size(double.infinity, 48),
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
    child: Text(
      _selected.isEmpty
            ? 'Selecciona al menos un amigo'
          : 'Compartir con ${_selected.length} amigo${_selected.length > 1 ? 's' : ''}',
style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
),
),
const SizedBox(height: 8),
];
}

// Widgets auxiliares
class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final VoidCallback onTap;
  final Widget? trailing;

  const _OptionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 3),
            Text(desc, style: const TextStyle(
                color: AppColors.grey, fontSize: 12, height: 1.3)),
          ])),
          const SizedBox(width: 8),
          trailing ?? Icon(Icons.arrow_forward_ios, color: color, size: 14),
        ]),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}

class _WaypointRow extends StatelessWidget {
  final int index;
  final bool isFirst;
  final bool isLast;
  final dynamic wp;
  final Map<String, dynamic>? weather;
  const _WaypointRow({required this.index, required this.isFirst, required this.isLast, required this.wp, this.weather});

  bool get _isLunch {
    final n = (wp['name'] ?? '').toLowerCase();
    final o = (wp['note'] ?? '').toLowerCase();
    return n.contains('almuerzo') || n.contains('lunch') || o.contains('almuerzo');
  }

  bool get _isDinner {
    final n = (wp['name'] ?? '').toLowerCase();
    final o = (wp['note'] ?? '').toLowerCase();
    return n.contains('comida') || n.contains('comer') || n.contains('dinner') || o.contains('comida');
  }

  Color get _accent => _isLunch ? AppColors.orange : _isDinner ? AppColors.cyan : AppColors.orange;

  @override
  Widget build(BuildContext context) {
    final isMeal = _isLunch || _isDinner;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: isFirst || isLast ? AppColors.orange : isMeal ? _accent : AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: isFirst || isLast ? AppColors.orange : isMeal ? _accent : AppColors.greyDark),
            boxShadow: isMeal ? [BoxShadow(color: _accent.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)] : null,
          ),
          child: Center(
            child: isFirst ? const Text('🏁', style: TextStyle(fontSize: 14))
                : isLast  ? const Text('🏆', style: TextStyle(fontSize: 14))
                : _isLunch  ? const Icon(Icons.restaurant_outlined, color: Colors.white, size: 16)
                : _isDinner ? const Icon(Icons.dinner_dining, color: Colors.white, size: 16)
                : Text('$index', style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
        if (!isLast) Container(width: 2, height: 50, color: AppColors.greyDark),
      ]),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: isMeal
              ? Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent.withOpacity(0.5)),
                  ),
                  child: _waypointContent(_accent),
                )
              : _waypointContent(AppColors.cyan),
        ),
      ),
    ]);
  }

  Widget _waypointContent(Color timeColor) {
    final isMeal = _isLunch || _isDinner;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(wp['name'] ?? '',
          style: TextStyle(
            color: isMeal ? _accent : AppColors.white,
            fontWeight: FontWeight.w700, fontSize: 14)),
      if (wp['note'] != null) ...[
        const SizedBox(height: 4),
        Text(wp['note'], style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4)),
      ],
      const SizedBox(height: 6),
      Row(children: [
        if (wp['estimated_arrival_time'] != null) ...[
          _TimeBadge(label: 'route_result.arrival'.tr(args: [wp['estimated_arrival_time']]), color: timeColor),
          const SizedBox(width: 6),
        ] else if ((wp['estimated_minutes_from_start'] ?? 0) > 0) ...[
          _TimeBadge(label: 'route_result.minutes_from_start'.tr(args: ['${wp["estimated_minutes_from_start"]}']), color: AppColors.grey),
          const SizedBox(width: 6),
        ],
        _WeatherIcon(weather: weather),
      ]),
    ]);
  }
}

class _MealStopRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String location;
  final String suggestion;
  final String? time;
  final String label;
  const _MealStopRow({required this.icon, required this.color, required this.location,
      required this.suggestion, required this.label, this.time});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)]),
          child: Center(child: Icon(icon, color: Colors.white, size: 18))),
        Container(width: 2, height: 50, color: AppColors.greyDark),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
              if (time != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.access_time, color: color, size: 11),
                    const SizedBox(width: 3),
                    Text(time!, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ],
            ]),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(location, style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
            if (suggestion.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(suggestion, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
            ],
          ]),
        ),
      )),
    ]);
  }
}

class _FuelStopRow extends StatelessWidget {
  final num km;
  final int stopNumber;
  final int total;
  const _FuelStopRow({required this.km, required this.stopNumber, required this.total});

  @override
  Widget build(BuildContext context) {
    final label = total > 1
        ? 'route_result.refuel_at'.tr(args: ['$km']) + ' ($stopNumber/$total)'
        : 'route_result.refuel_at'.tr(args: ['$km']);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gold),
          ),
          child: Center(child: total > 1
              ? Text('$stopNumber⛽', style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w800))
              : const Icon(Icons.local_gas_station, color: AppColors.gold, size: 16))),
        Container(width: 2, height: 40, color: AppColors.greyDark),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.local_gas_station, color: AppColors.gold, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          const Text('⛽ Busca gasolinera cerca', style: TextStyle(color: AppColors.grey, fontSize: 12)),
        ]),
      )),
    ]);
  }
}

class _TimeBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TimeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.access_time, color: color, size: 12),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _WeatherIcon extends StatelessWidget {
  final Map<String, dynamic>? weather;
  final double size;
  const _WeatherIcon({this.weather, this.size = 14});

  IconData get _icon {
    if (weather == null) return Icons.wb_sunny_outlined;
    final d = (weather!['description'] ?? '').toLowerCase();
    if (d.contains('tormenta') || d.contains('storm'))  return Icons.thunderstorm_outlined;
    if (d.contains('lluvia') || d.contains('rain') || d.contains('drizzle')) return Icons.umbrella_outlined;
    if (d.contains('nieve') || d.contains('snow'))      return Icons.ac_unit;
    if (d.contains('niebla') || d.contains('fog') || d.contains('mist')) return Icons.foggy;
    if (d.contains('muy nuboso') || d.contains('overcast') || d.contains('broken')) return Icons.cloud;
    if (d.contains('nubes') || d.contains('nublado') || d.contains('clouds') ||
        d.contains('parcial') || d.contains('scattered') || d.contains('few')) return Icons.wb_cloudy_outlined;
    return Icons.wb_sunny_outlined;
  }

  Color get _color {
    if (weather == null) return AppColors.gold;
    final d = (weather!['description'] ?? '').toLowerCase();
    if (d.contains('tormenta') || d.contains('storm'))  return AppColors.error;
    if (d.contains('lluvia') || d.contains('rain'))     return AppColors.cyan;
    if (d.contains('nieve') || d.contains('snow'))      return Colors.lightBlue;
    if (d.contains('muy nuboso') || d.contains('overcast')) return AppColors.grey;
    if (d.contains('nubes') || d.contains('clouds'))    return const Color(0xFFAAAAAA);
    return AppColors.gold;
  }

  @override
  Widget build(BuildContext context) {
    if (weather == null) return const SizedBox.shrink();
    final temp = weather!['temp'];
    final tempStr = temp != null ? '${temp.toStringAsFixed(0)}°' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _color.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon, color: _color, size: size),
        if (tempStr.isNotEmpty) ...[
          const SizedBox(width: 3),
          Text(tempStr, style: TextStyle(color: _color, fontSize: size - 3, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _SuggestionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final Color color;
  const _SuggestionCard({required this.icon, required this.title, required this.subtitle,
      required this.color, this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25))),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
          if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
        ])),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(badge!, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

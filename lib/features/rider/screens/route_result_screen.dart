import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/route_service.dart';

class RouteResultScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  const RouteResultScreen({super.key, required this.result});

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen> {
  bool _publishing = false;

  Map<String, dynamic> get _route          => widget.result['route'] ?? {};
  Map<String, dynamic>? get _weather       => widget.result['weather'];
  Map<String, dynamic>? get _aiSummary     => widget.result['ai_summary'];
  List                  get _waypoints     => _route['waypoints'] ?? [];
  int?                  get _routesRemaining => widget.result['routes_remaining'];
  int?                  get _fuelRangeKm   => widget.result['fuel_range_km'];

  Map<String, dynamic> _buildFormData() {
    return Map<String, dynamic>.from(widget.result['form_data'] ?? {});
  }

  Future<void> _openInGoogleMaps() async {
    final url = _route['google_maps_url'];
    if (url == null) return;
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (_) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    }
  }

  Future<void> _publish(String visibility) async {
    setState(() => _publishing = true);
    final result = await RouteService.publishRoute(_route['id'], visibility);
    if (!mounted) return;
    setState(() => _publishing = false);
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('route_result.published'.tr()), backgroundColor: Colors.green));
    }
  }

  void _showPublishDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('route_result.share_title'.tr(), style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            _ShareOption(icon: Icons.people_outlined, label: 'route_result.share_friends'.tr(), desc: 'route_result.share_friends_desc'.tr(), color: AppColors.cyan, onTap: () { Navigator.pop(ctx); _publish('friends'); }),
            const SizedBox(height: 12),
            _ShareOption(icon: Icons.public, label: 'route_result.share_public'.tr(), desc: 'route_result.share_public_desc'.tr(), color: AppColors.orange, onTap: () { Navigator.pop(ctx); _publish('public'); }),
            const SizedBox(height: 24),
          ],
        ),
      ),
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
          onPressed: () => context.go('/rider/route-generator', extra: _buildFormData()),
        ),
        title: Text('route_result.title'.tr(), style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.share_outlined, color: AppColors.orange), onPressed: _showPublishDialog),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [AppColors.orange.withOpacity(0.3), AppColors.surface]),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.auto_awesome, color: AppColors.orange, size: 16),
                  const SizedBox(width: 6),
                  Text('route_result.generated_by_ai'.tr(), style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (_routesRemaining != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.greyDark, borderRadius: BorderRadius.circular(10)),
                      child: Text('route_result.routes_remaining'.tr(args: ['$_routesRemaining']), style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                    ),
                ]),
                const SizedBox(height: 12),
                Text(_route['title'] ?? '', style: const TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(_route['description'] ?? '', style: const TextStyle(color: AppColors.grey, fontSize: 13, height: 1.5)),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Stats
                Row(children: [
                  _StatBadge(icon: Icons.route, label: '${_route['distance_km']} km', color: AppColors.orange),
                  const SizedBox(width: 8),
                  _StatBadge(icon: Icons.access_time, label: '${((_route['duration_minutes'] ?? 0) / 60).toStringAsFixed(1)} h', color: AppColors.cyan),
                  const SizedBox(width: 8),
                  _StatBadge(icon: Icons.terrain, label: _route['difficulty'] ?? '', color: AppColors.gold),
                ]),

                const SizedBox(height: 16),

                // Clima
                if (_weather != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.greyDark)),
                    child: Row(children: [
                      _WeatherIcon(weather: _weather, size: 28),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_weather!['temp']?.toStringAsFixed(0)}°C · ${_weather!['description']}',
                            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                        Text('Viento ${_weather!['wind_speed']} m/s · Humedad ${_weather!['humidity']}%',
                            style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                      ]),
                      const Spacer(),
                      if (_aiSummary?['best_departure_time'] != null)
                        Column(children: [
                          Text('route_result.departure'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                          Text(_aiSummary!['best_departure_time'], style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 16)),
                        ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // Autonomía
                if (_fuelRangeKm != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _fuelRangeKm! < (_route['distance_km'] ?? 999) ? AppColors.error.withOpacity(0.5) : AppColors.greyDark),
                    ),
                    child: Row(children: [
                      Icon(Icons.local_gas_station, color: _fuelRangeKm! < (_route['distance_km'] ?? 999) ? AppColors.error : AppColors.grey, size: 24),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('route_result.autonomy'.tr(args: ['$_fuelRangeKm']), style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                        if (_aiSummary?['fuel_stop_after_km'] != null)
                          Text('route_result.refuel_at'.tr(args: ['${_aiSummary!["fuel_stop_after_km"]}']), style: const TextStyle(color: AppColors.error, fontSize: 12)),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // Waypoints con gasolinera intercalada
                Text('route_result.waypoints'.tr(), style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),

                _buildWaypoints(),

                const SizedBox(height: 24),

                // Almuerzo
                if (_route['lunch_stop'] != null) ...[
                  _SectionHeader(icon: Icons.restaurant_outlined, label: 'route_result.lunch_stop'.tr(), color: AppColors.orange),
                  const SizedBox(height: 8),
                  _SuggestionCard(icon: Icons.restaurant_outlined, title: _route['lunch_stop']['location'] ?? '', subtitle: _route['lunch_stop']['suggestion'] ?? '', badge: _route['lunch_stop']['estimated_time'], color: AppColors.orange),
                  const SizedBox(height: 16),
                ],

                // Cena
                if (_route['dinner_stop'] != null) ...[
                  _SectionHeader(icon: Icons.dinner_dining, label: 'route_result.dinner_stop'.tr(), color: AppColors.cyan),
                  const SizedBox(height: 8),
                  _SuggestionCard(icon: Icons.dinner_dining, title: _route['dinner_stop']['location'] ?? '', subtitle: _route['dinner_stop']['suggestion'] ?? '', badge: _route['dinner_stop']['estimated_time'], color: AppColors.cyan),
                  const SizedBox(height: 16),
                ],

                // Tags
                if (_route['tags'] != null && (_route['tags'] as List).isNotEmpty) ...[
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: (_route['tags'] as List).map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.cyan.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.cyan.withOpacity(0.3))),
                      child: Text(tag.toString(), style: const TextStyle(color: AppColors.cyan, fontSize: 12)),
                    )).toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // Botón Google Maps
                ElevatedButton(
                  onPressed: _openInGoogleMaps,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, minimumSize: const Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.map, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text('route_result.open_maps'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                ),

                const SizedBox(height: 12),

                // Botón compartir
                OutlinedButton(
                  onPressed: _publishing ? null : _showPublishDialog,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52), side: const BorderSide(color: AppColors.orange), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _publishing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2))
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.share_outlined, color: AppColors.orange, size: 20),
                          const SizedBox(width: 8),
                          Text('route_result.share'.tr(), style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
                        ]),
                ),

                const SizedBox(height: 32),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaypoints() {
    final fuelStopKm    = _aiSummary?['fuel_stop_after_km'];
    final totalKm       = (_route['distance_km'] ?? 0).toDouble();
    final totalMins     = (_route['duration_minutes'] ?? 1).toDouble();
    final departureTime = _aiSummary?['best_departure_time'];
    bool fuelInserted   = false;
    bool lunchInserted  = false;
    bool dinnerInserted = false;

    final lunchStop  = _route['lunch_stop'];
    final dinnerStop = _route['dinner_stop'];

    int? timeToMins(String? time) {
      if (time == null) return null;
      final parts = time.split(':');
      if (parts.length != 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      return h * 60 + m;
    }

    final departureMins = timeToMins(departureTime);
    final lunchMins     = timeToMins(lunchStop?['estimated_time']);
    final dinnerMins    = timeToMins(dinnerStop?['estimated_time']);

    // Porcentaje de ruta para cada parada (fallback sin horas)
    // Almuerzo: 40% de la ruta, Comida: 65%
    final lunchPct  = 0.4;
    final dinnerPct = 0.65;

    final List<Widget> items = [];

    for (int i = 0; i < _waypoints.length; i++) {
      final wp      = _waypoints[i];
      final isFirst = i == 0;
      final isLast  = i == _waypoints.length - 1;
      final mins    = (wp['estimated_minutes_from_start'] ?? 0).toDouble();
      final approxKm = totalMins > 0 ? (mins / totalMins).clamp(0.0, 1.0) * totalKm : 0.0;
      final pct      = totalMins > 0 ? (mins / totalMins).clamp(0.0, 1.0) : 0.0;
      final wpAbsMins = departureMins != null ? departureMins + mins.toInt() : null;

      // Insertar gasolinera
      if (!fuelInserted && fuelStopKm != null && approxKm >= (fuelStopKm as num).toDouble()) {
        fuelInserted = true;
        items.add(_FuelStopRow(km: fuelStopKm));
      }

      // Insertar almuerzo
      if (!lunchInserted && lunchStop != null) {
        bool insert = false;
        if (wpAbsMins != null && lunchMins != null) {
          insert = wpAbsMins >= lunchMins;
        } else {
          insert = pct >= lunchPct;
        }
        if (insert) {
          lunchInserted = true;
          items.add(_MealStopRow(
            icon: Icons.restaurant_outlined,
            color: AppColors.orange,
            location: lunchStop['location'] ?? '',
            suggestion: lunchStop['suggestion'] ?? '',
            time: lunchStop['estimated_time'],
            label: 'route_result.lunch_stop'.tr(),
          ));
        }
      }

      // Insertar comida
      if (!dinnerInserted && dinnerStop != null) {
        bool insert = false;
        if (wpAbsMins != null && dinnerMins != null) {
          insert = wpAbsMins >= dinnerMins;
        } else {
          insert = pct >= dinnerPct;
        }
        if (insert) {
          dinnerInserted = true;
          items.add(_MealStopRow(
            icon: Icons.dinner_dining,
            color: AppColors.cyan,
            location: dinnerStop['location'] ?? '',
            suggestion: dinnerStop['suggestion'] ?? '',
            time: dinnerStop['estimated_time'],
            label: 'route_result.dinner_stop'.tr(),
          ));
        }
      }

      items.add(_WaypointRow(index: i, isFirst: isFirst, isLast: isLast, wp: wp, weather: _weather));
    }

    // Si llegamos al final sin insertar, añadir al final antes del último punto
    if (!lunchInserted && lunchStop != null) {
      final lastIdx = items.length - 1;
      items.insert(lastIdx > 0 ? lastIdx : 0, _MealStopRow(
        icon: Icons.restaurant_outlined, color: AppColors.orange,
        location: lunchStop['location'] ?? '', suggestion: lunchStop['suggestion'] ?? '',
        time: lunchStop['estimated_time'], label: 'route_result.lunch_stop'.tr(),
      ));
    }
    if (!dinnerInserted && dinnerStop != null) {
      final lastIdx = items.length - 1;
      items.insert(lastIdx > 0 ? lastIdx : 0, _MealStopRow(
        icon: Icons.dinner_dining, color: AppColors.cyan,
        location: dinnerStop['location'] ?? '', suggestion: dinnerStop['suggestion'] ?? '',
        time: dinnerStop['estimated_time'], label: 'route_result.dinner_stop'.tr(),
      ));
    }

    return Column(children: items);
  }
}

// Fila de waypoint normal
class _WaypointRow extends StatelessWidget {
final int index;
final bool isFirst;
final bool isLast;
final dynamic wp;
final Map<String, dynamic>? weather;

const _WaypointRow({required this.index, required this.isFirst, required this.isLast, required this.wp, this.weather});

// Detectar si es parada de almuerzo
bool get _isLunch {
final name = (wp['name'] ?? '').toLowerCase();
final note = (wp['note'] ?? '').toLowerCase();
return name.contains('almuerzo') || name.contains('lunch') || name.contains('dejeuner') ||
   note.contains('almuerzo') || note.contains('lunch') || note.contains('parada para almorzar');
}

// Detectar si es parada de comida
bool get _isDinner {
final name = (wp['name'] ?? '').toLowerCase();
final note = (wp['note'] ?? '').toLowerCase();
return name.contains('comida') || name.contains('comer') || name.contains('dinner') || name.contains('repas') ||
note.contains('comida') || note.contains('comer') || note.contains('parada para comer');
}

Color get _accentColor {
if (_isLunch)  return AppColors.orange;
if (_isDinner) return AppColors.cyan;
return AppColors.orange;
}

@override
Widget build(BuildContext context) {
final isMealStop = _isLunch || _isDinner;

return Row(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Column(children: [
Container(
width: 32, height: 32,
decoration: BoxDecoration(
color: isFirst || isLast
? AppColors.orange
  : isMealStop
    ? _accentColor
    : AppColors.surface,
shape: BoxShape.circle,
border: Border.all(color: isFirst || isLast ? AppColors.orange : _accentColor),
boxShadow: isMealStop ? [BoxShadow(color: _accentColor.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)] : null,
),
  child: Center(
      child: isFirst
            ? const Text('🏁', style: TextStyle(fontSize: 14))
              : isLast
                    ? const Text('🏆', style: TextStyle(fontSize: 14))
                      : _isLunch
                          ? const Icon(Icons.restaurant_outlined, color: Colors.white, size: 16)
                          : _isDinner
                              ? const Icon(Icons.dinner_dining, color: Colors.white, size: 16)
                              : Text('$index', style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
          if (!isLast) Container(width: 2, height: 50, color: AppColors.greyDark),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: isMealStop
                ? Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _accentColor.withOpacity(0.5), width: 1.5),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        wp['name'] ?? '',
                        style: TextStyle(color: _accentColor, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      if (wp['note'] != null) ...[  
                        const SizedBox(height: 4),
                        Text(wp['note'], style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4)),
                      ],
                      const SizedBox(height: 6),
                      Row(children: [
                        if (wp['estimated_arrival_time'] != null) ...[  
                          _TimeBadge(label: 'route_result.arrival'.tr(args: [wp['estimated_arrival_time']]), color: _accentColor),
                          const SizedBox(width: 6),
                        ] else if ((wp['estimated_minutes_from_start'] ?? 0) > 0) ...[  
                          _TimeBadge(label: 'route_result.minutes_from_start'.tr(args: ['${wp["estimated_minutes_from_start"]}']), color: AppColors.grey),
                          const SizedBox(width: 6),
                        ],
                        _WeatherIcon(weather: weather),
                      ]),
                    ]),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(wp['name'] ?? '', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    if (wp['note'] != null)
                      Text(wp['note'], style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4)),
                    const SizedBox(height: 6),
                    Row(children: [
                      if (wp['estimated_arrival_time'] != null) ...[  
                        _TimeBadge(label: 'route_result.arrival'.tr(args: [wp['estimated_arrival_time']]), color: AppColors.cyan),
                        const SizedBox(width: 6),
                      ] else if ((wp['estimated_minutes_from_start'] ?? 0) > 0) ...[  
                        _TimeBadge(label: 'route_result.minutes_from_start'.tr(args: ['${wp["estimated_minutes_from_start"]}']), color: AppColors.grey),
                        const SizedBox(width: 6),
                      ],
                      _WeatherIcon(weather: weather),
                    ]),
                  ]),
          ),
        ),
      ],
    );
  }
}

// Fila de parada de comida intercalada
class _MealStopRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String location;
  final String suggestion;
  final String? time;
  final String label;

  const _MealStopRow({
    required this.icon,
    required this.color,
    required this.location,
    required this.suggestion,
    required this.label,
    this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)],
            ),
            child: Center(child: Icon(icon, color: Colors.white, size: 18)),
          ),
          Container(width: 2, height: 50, color: AppColors.greyDark),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
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
          ),
        ),
      ],
    );
  }
}

// Fila de parada de gasolinera intercalada
class _FuelStopRow extends StatelessWidget {
  final num km;
  const _FuelStopRow({required this.km});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold),
            ),
            child: const Center(child: Icon(Icons.local_gas_station, color: AppColors.gold, size: 16)),
          ),
          Container(width: 2, height: 40, color: AppColors.greyDark),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('route_result.refuel_at'.tr(args: ['$km']), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
              Text('⛽ Busca gasolinera cerca', style: const TextStyle(color: AppColors.grey, fontSize: 12)),
            ]),
          ),
        ),
      ],
    );
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
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
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
    final desc = (weather!['description'] ?? '').toLowerCase();
    if (desc.contains('tormenta') || desc.contains('storm'))   return Icons.thunderstorm_outlined;
    if (desc.contains('lluvia') || desc.contains('rain') || desc.contains('drizzle')) return Icons.umbrella_outlined;
    if (desc.contains('nieve') || desc.contains('snow'))       return Icons.ac_unit;
    if (desc.contains('niebla') || desc.contains('fog') || desc.contains('mist')) return Icons.foggy;
    if (desc.contains('muy nuboso') || desc.contains('overcast') || desc.contains('broken')) return Icons.cloud;
    if (desc.contains('nubes') || desc.contains('nublado') || desc.contains('clouds') ||
        desc.contains('parcial') || desc.contains('scattered') || desc.contains('few')) return Icons.wb_cloudy_outlined;
    return Icons.wb_sunny_outlined;
  }

  Color get _color {
    if (weather == null) return AppColors.gold;
    final desc = (weather!['description'] ?? '').toLowerCase();
    if (desc.contains('tormenta') || desc.contains('storm'))   return AppColors.error;
    if (desc.contains('lluvia') || desc.contains('rain'))      return AppColors.cyan;
    if (desc.contains('nieve') || desc.contains('snow'))       return Colors.lightBlue;
    if (desc.contains('muy nuboso') || desc.contains('overcast')) return AppColors.grey;
    if (desc.contains('nubes') || desc.contains('clouds'))     return const Color(0xFFAAAAAA);
    return AppColors.gold;
  }

  String get _temp {
    if (weather == null) return '';
    final temp = weather!['temp'];
    if (temp == null) return '';
    return '${temp.toStringAsFixed(0)}°';
  }

  @override
  Widget build(BuildContext context) {
    if (weather == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: _color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon, color: _color, size: size),
        if (_temp.isNotEmpty) ...[
          const SizedBox(width: 3),
          Text(_temp, style: TextStyle(color: _color, fontSize: size - 3, fontWeight: FontWeight.w600)),
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
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.3))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final Color color;
  final VoidCallback onTap;
  const _ShareOption({required this.icon, required this.label, required this.desc, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
        child: Row(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            Text(desc, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
          ])),
          Icon(Icons.arrow_forward_ios, color: color, size: 14),
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
  const _SuggestionCard({required this.icon, required this.title, required this.subtitle, required this.color, this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.25))),
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

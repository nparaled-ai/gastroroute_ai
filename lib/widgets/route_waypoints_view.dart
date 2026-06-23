import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Widget compartido para mostrar waypoints, paradas y clima
/// Usado tanto en route_result_screen como en route_detail_screen
class RouteWaypointsView extends StatelessWidget {
  final Map<String, dynamic> route;
  final Map<String, dynamic>? weather;
  final Map<String, dynamic>? aiSummary;
  final bool showLunch;
  final bool showDinner;

  const RouteWaypointsView({
    super.key,
    required this.route,
    this.weather,
    this.aiSummary,
    this.showLunch  = true,
    this.showDinner = true,
  });

  List get _waypoints => route['waypoints'] ?? [];
  Map<String, dynamic>? get _lunchStop  => showLunch  ? route['lunch_stop']  : null;
  Map<String, dynamic>? get _dinnerStop => showDinner ? route['dinner_stop'] : null;

  @override
  Widget build(BuildContext context) {
    final fuelStops = List<num>.from(aiSummary?['fuel_stops'] ?? []);
    final totalKm   = ((route['distance_km'] ?? 0) as num).toDouble();
    final totalMins = ((route['duration_minutes'] ?? 1) as num).toDouble();
    final departureTime = aiSummary?['best_departure_time'] ?? route['departure_time'];

    int? timeToMins(String? t) {
      if (t == null) return null;
      final p = t.split(':');
      if (p.length != 2) return null;
      return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
    }

    final departureMins = timeToMins(departureTime);
    final lunchMins     = timeToMins(_lunchStop?['estimated_time']);
    final dinnerMins    = timeToMins(_dinnerStop?['estimated_time']);

    final insertedFuelStops = <int>{};
    bool lunchInserted  = false;
    bool dinnerInserted = false;

    final List<Widget> items = [];

    for (int i = 0; i < _waypoints.length; i++) {
      final wp     = _waypoints[i];
      final wpName = (wp['name'] ?? '').toLowerCase();
      final wpNote = (wp['note'] ?? '').toLowerCase();

      if (wpName.contains('repostaje') || wpName.contains('gasolinera') ||
          wpName.contains('repostar') || wpNote.contains('repostar antes')) continue;

      if (_dinnerStop != null && (wpName.contains('comida') || wpName.contains('comer') ||
          wpName.contains('dinner') || wpNote.contains('parada para comer') ||
          wpNote.contains('comida'))) continue;

      if (_lunchStop != null && (wpName.contains('almuerzo') || wpName.contains('lunch') ||
          wpNote.contains('almuerzo') || wpNote.contains('parada para almorzar'))) continue;

      final isFirst = i == 0;
      final isLast  = i == _waypoints.length - 1;
      final mins    = (wp['estimated_minutes_from_start'] ?? 0).toDouble();
      final approxKm = totalMins > 0 ? (mins / totalMins).clamp(0.0, 1.0) * totalKm : 0.0;
      final pct      = totalMins > 0 ? (mins / totalMins).clamp(0.0, 1.0) : 0.0;
      final wpAbsMins = departureMins != null ? departureMins + mins.toInt() : null;

      // Insertar gasolineras
      for (int s = 0; s < fuelStops.length; s++) {
        if (!insertedFuelStops.contains(s) && approxKm >= fuelStops[s].toDouble()) {
          insertedFuelStops.add(s);
          items.add(_FuelStopRow(km: fuelStops[s], stopNumber: s + 1, total: fuelStops.length));
        }
      }

      // Insertar almuerzo
      if (!lunchInserted && _lunchStop != null) {
        final insert = wpAbsMins != null && lunchMins != null
            ? wpAbsMins >= lunchMins : pct >= 0.4;
        if (insert) {
          lunchInserted = true;
          items.add(_MealStopRow(
            icon: Icons.restaurant_outlined, color: AppColors.orange,
            location: _lunchStop!['location'] ?? '', suggestion: _lunchStop!['suggestion'] ?? '',
            time: _lunchStop!['estimated_time'], label: 'Parada para almorzar',
          ));
        }
      }

      // Insertar comida
      if (!dinnerInserted && _dinnerStop != null) {
        final insert = wpAbsMins != null && dinnerMins != null
            ? wpAbsMins >= dinnerMins : pct >= 0.65;
        if (insert) {
          dinnerInserted = true;
          items.add(_MealStopRow(
            icon: Icons.dinner_dining, color: AppColors.cyan,
            location: _dinnerStop!['location'] ?? '', suggestion: _dinnerStop!['suggestion'] ?? '',
            time: _dinnerStop!['estimated_time'], label: 'Parada para comer',
          ));
        }
      }

      items.add(_WaypointRow(
        index: i, isFirst: isFirst, isLast: isLast, wp: wp, weather: weather,
      ));
    }

    // Insertar los que quedaron
    for (int s = 0; s < fuelStops.length; s++) {
      if (!insertedFuelStops.contains(s)) {
        final li = items.length - 1;
        items.insert(li > 0 ? li : 0,
            _FuelStopRow(km: fuelStops[s], stopNumber: s + 1, total: fuelStops.length));
      }
    }
    if (!lunchInserted && _lunchStop != null) {
      final li = items.length - 1;
      items.insert(li > 0 ? li : 0, _MealStopRow(
        icon: Icons.restaurant_outlined, color: AppColors.orange,
        location: _lunchStop!['location'] ?? '', suggestion: _lunchStop!['suggestion'] ?? '',
        time: _lunchStop!['estimated_time'], label: 'Parada para almorzar',
      ));
    }
    if (!dinnerInserted && _dinnerStop != null) {
      final li = items.length - 1;
      items.insert(li > 0 ? li : 0, _MealStopRow(
        icon: Icons.dinner_dining, color: AppColors.cyan,
        location: _dinnerStop!['location'] ?? '', suggestion: _dinnerStop!['suggestion'] ?? '',
        time: _dinnerStop!['estimated_time'], label: 'Parada para comer',
      ));
    }

    return Column(children: items);
  }
}

// ─── Waypoint ─────────────────────────────────────────────────────────────────
class _WaypointRow extends StatelessWidget {
  final int index;
  final bool isFirst;
  final bool isLast;
  final dynamic wp;
  final Map<String, dynamic>? weather;

  const _WaypointRow({
    required this.index, required this.isFirst,
    required this.isLast, required this.wp, this.weather,
  });

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
                  child: _content(_accent),
                )
              : _content(AppColors.cyan),
        ),
      ),
    ]);
  }

  Widget _content(Color timeColor) {
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
        if (wp['estimated_arrival_time'] != null)
          _TimeBadge(label: 'Llegada: ${wp['estimated_arrival_time']}', color: timeColor)
        else if ((wp['estimated_minutes_from_start'] ?? 0) > 0)
          _TimeBadge(label: '+${wp['estimated_minutes_from_start']} min', color: AppColors.grey),
        if (weather != null) ...[
          const SizedBox(width: 6),
          _WeatherBadge(weather: weather),
        ],
      ]),
    ]);
  }
}

// ─── Parada gasolinera ────────────────────────────────────────────────────────
class _FuelStopRow extends StatelessWidget {
  final num km;
  final int stopNumber;
  final int total;
  const _FuelStopRow({required this.km, required this.stopNumber, required this.total});

  @override
  Widget build(BuildContext context) {
    final label = total > 1
        ? '⛽ Repostar a los $km km ($stopNumber/$total)'
        : '⛽ Repostar a los $km km';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      Expanded(child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
          const Text('Busca gasolinera cerca', style: TextStyle(color: AppColors.grey, fontSize: 12)),
        ]),
      )),
    ]);
  }
}

// ─── Parada comida/almuerzo ───────────────────────────────────────────────────
class _MealStopRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String location;
  final String suggestion;
  final String? time;
  final String label;
  const _MealStopRow({
    required this.icon, required this.color, required this.location,
    required this.suggestion, required this.label, this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)],
          ),
          child: Center(child: Icon(icon, color: Colors.white, size: 18)),
        ),
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

// ─── Tiempo ───────────────────────────────────────────────────────────────────
class _TimeBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TimeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.access_time, color: color, size: 12),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─── Clima ────────────────────────────────────────────────────────────────────
class _WeatherBadge extends StatelessWidget {
  final Map<String, dynamic>? weather;
  const _WeatherBadge({this.weather});

  IconData get _icon {
    if (weather == null) return Icons.wb_sunny_outlined;
    final d = (weather!['description'] ?? '').toLowerCase();
    if (d.contains('tormenta') || d.contains('storm'))   return Icons.thunderstorm_outlined;
    if (d.contains('lluvia')   || d.contains('rain'))    return Icons.umbrella_outlined;
    if (d.contains('nieve')    || d.contains('snow'))    return Icons.ac_unit;
    if (d.contains('niebla')   || d.contains('fog'))     return Icons.foggy;
    if (d.contains('muy nuboso') || d.contains('overcast')) return Icons.cloud;
    if (d.contains('nubes')    || d.contains('clouds'))  return Icons.wb_cloudy_outlined;
    return Icons.wb_sunny_outlined;
  }

  Color get _color {
    if (weather == null) return AppColors.gold;
    final d = (weather!['description'] ?? '').toLowerCase();
    if (d.contains('tormenta')) return AppColors.error;
    if (d.contains('lluvia'))   return AppColors.cyan;
    if (d.contains('nieve'))    return Colors.lightBlue;
    if (d.contains('muy nuboso') || d.contains('overcast')) return AppColors.grey;
    if (d.contains('nubes'))    return const Color(0xFFAAAAAA);
    return AppColors.gold;
  }

  @override
  Widget build(BuildContext context) {
    if (weather == null) return const SizedBox.shrink();
    final temp = weather!['temp'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon, color: _color, size: 13),
        if (temp != null) ...[
          const SizedBox(width: 3),
          Text('${(temp as num).toStringAsFixed(0)}°',
              style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

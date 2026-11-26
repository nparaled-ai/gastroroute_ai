import 'package:gastroroute_ai/core/labels.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../features/rider/providers/route_service.dart';

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

  /// Waypoints listos para pintar, con la salida y la llegada reales.
  ///
  /// El array que llega del servidor NO incluye origen ni destino en las rutas
  /// generadas con IA: el backend los quita a propósito para que Google no
  /// pase dos veces por el mismo punto. Este widget marcaba el primer y el
  /// último elemento como salida y llegada, así que en esas rutas anunciaba
  /// que salías del primer punto intermedio: con origen en Sariñena, decía que
  /// la ruta empezaba en los Mallos de Riglos, que están a 45 minutos.
  ///
  /// En las rutas importadas de GPX el origen sí venía incluido, por eso el
  /// fallo solo se veía en las de IA.
  List get _waypoints {
    final raw = List.from(route['waypoints'] ?? []);

    final originLat = _toDouble(route['origin_lat']);
    final originLng = _toDouble(route['origin_lng']);

    if (originLat == null || originLng == null) return raw;

    final destLat = _toDouble(route['destination_lat']) ?? originLat;
    final destLng = _toDouble(route['destination_lng']) ?? originLng;

    // Se descartan los intermedios que coincidan con la salida o la llegada,
    // para no repetirlos al añadirlas explícitamente.
    final middle = raw.where((wp) {
      final lat = _toDouble(wp['lat']);
      final lng = _toDouble(wp['lng']);
      if (lat == null || lng == null) return true;
      return !_samePlace(lat, lng, originLat, originLng) &&
             !_samePlace(lat, lng, destLat, destLng);
    }).toList();

    final totalMins = ((route['duration_minutes'] ?? 0) as num).toInt();

    // La hora de salida y la de llegada se calculan aquí: los puntos
    // intermedios la traen del servidor, pero estos dos los construimos
    // nosotros y sin ella la fila se quedaba sin hora.
    final departure = route['departure_time']?.toString();

    return [
      {
        'lat': originLat,
        'lng': originLng,
        'name': route['origin'] ?? '',
        'estimated_minutes_from_start': 0,
        'estimated_arrival_time': ?departure,
      },
      ...middle,
      {
        'lat': destLat,
        'lng': destLng,
        'name': route['destination'] ?? route['origin'] ?? '',
        'estimated_minutes_from_start': totalMins,
        if (departure != null)
          'estimated_arrival_time': _addMinutes(departure, totalMins),
      },
    ];
  }

  /// Suma minutos a una hora "HH:mm". Devuelve null si no se puede leer.
  static String? _addMinutes(String? time, int minutes) {
    if (time == null) return null;

    final parts = time.split(':');
    if (parts.length < 2) return null;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;

    // El módulo mantiene la hora dentro del día si la ruta cruza medianoche.
    final total = (h * 60 + m + minutes) % (24 * 60);

    return '${(total ~/ 60).toString().padLeft(2, '0')}'
        ':${(total % 60).toString().padLeft(2, '0')}';
  }

  /// Convierte a double lo que llegue del JSON.
  ///
  /// Las coordenadas vienen como CADENA, no como número: en el backend están
  /// declaradas como decimal:7 y Laravel las serializa entre comillas. Un
  /// `as num?` sobre ellas lanza una excepción de tipo y deja la pantalla en
  /// gris. Se acepta cualquiera de las dos formas por si el casting cambia.
  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Dos coordenadas a menos de ~300 m se consideran el mismo sitio.
  static bool _samePlace(double lat1, double lng1, double lat2, double lng2) {
    const marginDegrees = 0.003;
    return (lat1 - lat2).abs() < marginDegrees && (lng1 - lng2).abs() < marginDegrees;
  }
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
          wpName.contains('repostar') || wpNote.contains('repostar antes')) {
        continue;
      }

      // Lo que manda es la marca `type` que pone el servidor (idioma aparte): las
      // palabras de abajo son el respaldo de las rutas guardadas antes de ella.
      final tipo = (wp['type'] ?? '').toString();

      if (_dinnerStop != null && (tipo == 'comida' || wpName.contains('comida') || wpName.contains('comer') ||
          wpName.contains('dinner') || wpNote.contains('parada para comer') ||
          wpNote.contains('comida'))) {
        continue;
      }

      if (_lunchStop != null && (tipo == 'almuerzo' || wpName.contains('almuerzo') || wpName.contains('lunch') ||
          wpNote.contains('almuerzo') || wpNote.contains('parada para almorzar'))) {
        continue;
      }

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
            location: _lunchStop!['location'] ?? '',
            eatery: _lunchStop!['eatery'] is Map ? Map<String, dynamic>.from(_lunchStop!['eatery']) : null,
            suggestion: _lunchStop!['suggestion'] ?? '',
            time: _lunchStop!['estimated_time'],
            label: 'route_result.lunch_stop'.tr(),
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
            location: _dinnerStop!['location'] ?? '',
            eatery: _dinnerStop!['eatery'] is Map ? Map<String, dynamic>.from(_dinnerStop!['eatery']) : null,
            suggestion: _dinnerStop!['suggestion'] ?? '',
            time: _dinnerStop!['estimated_time'],
            label: 'route_result.dinner_stop'.tr(),
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
        time: _lunchStop!['estimated_time'],
        label: 'route_result.lunch_stop'.tr(),
      ));
    }
    if (!dinnerInserted && _dinnerStop != null) {
      final li = items.length - 1;
      items.insert(li > 0 ? li : 0, _MealStopRow(
        icon: Icons.dinner_dining, color: AppColors.cyan,
        location: _dinnerStop!['location'] ?? '', suggestion: _dinnerStop!['suggestion'] ?? '',
        time: _dinnerStop!['estimated_time'],
        label: 'route_result.dinner_stop'.tr(),
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
            boxShadow: isMeal ? [BoxShadow(color: _accent.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)] : null,
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
                    color: _accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent.withValues(alpha: 0.5)),
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
        // En el primer punto la hora es la de salida, no la de llegada.
        if (wp['estimated_arrival_time'] != null)
          _TimeBadge(
            label: isFirst
                ? 'route_detail.departure_at'.tr(
                    namedArgs: {'time': '${wp['estimated_arrival_time']}'})
                : 'route_detail.arrival_at'.tr(
                    namedArgs: {'time': '${wp['estimated_arrival_time']}'}),
            color: timeColor,
          )
        else if ((wp['estimated_minutes_from_start'] ?? 0) > 0)
          _TimeBadge(
              label: 'route_detail.minutes_short'.tr(namedArgs: {
                'minutes': '${wp['estimated_minutes_from_start']}'
              }),
              color: AppColors.grey),
        // El tiempo de ESTE punto a su hora de paso, si el servidor lo manda;
        // si no, el general de la ruta.
        if ((wp['weather'] ?? weather) != null) ...[
          const SizedBox(width: 6),
          _WeatherBadge(
            weather: wp['weather'] is Map
                ? Map<String, dynamic>.from(wp['weather'])
                : weather,
          ),
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
        ? 'route_result.refuel_km_n'.tr(namedArgs: {'km': '$km', 'n': '$stopNumber', 'total': '$total'})
        : 'route_result.refuel_km'.tr(namedArgs: {'km': '$km'});
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.15),
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
          Text('route_detail.find_fuel_nearby'.tr(),
              style: const TextStyle(color: AppColors.grey, fontSize: 12)),
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

  /// El bar o restaurante concreto, si lo conocemos (norma 21): es el que se
  /// valora al terminar la ruta, así que hay que poder saber cuál es.
  final Map<String, dynamic>? eatery;
  const _MealStopRow({
    required this.icon, required this.color, required this.location,
    required this.suggestion, required this.label, this.time, this.eatery,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 2)],
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
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
              if (time != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
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
            if (eatery != null && '${eatery!['name'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('${eatery!['name']}',
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              // Las estrellas de los moteros junto al sitio, y el botón para leer
              // lo que han dejado escrito (norma 21).
              Row(children: [
                if (eatery!['rating'] != null) ...[
                  const Icon(Icons.star, color: AppColors.gold, size: 14),
                  const SizedBox(width: 3),
                  Text(
                    '${dec1(context, eatery!['rating'])} (${eatery!['votes'] ?? 0})',
                    style: const TextStyle(color: AppColors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ] else
                  Text('rating.no_votes'.tr(),
                      style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                if (eatery!['parking'] == true) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.two_wheeler, color: AppColors.cyan, size: 14),
                ],
                const Spacer(),
                if (eatery!['id'] != null)
                  GestureDetector(
                    onTap: () => _showOpinions(context, (eatery!['id'] as num).toInt()),
                    child: Text('rating.see_opinions'.tr(),
                        style: TextStyle(
                            color: color, fontSize: 12, fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline)),
                  ),
              ]),
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
        color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
        color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
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


/// Lo que dicen los moteros de un sitio de comer: media, aparcamiento y los
/// comentarios que han pasado la moderación.
Future<void> _showOpinions(BuildContext context, int eateryId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _OpinionsSheet(eateryId: eateryId),
  );
}

/// La hoja de opiniones: los comentarios llegan de 20 en 20 y la siguiente tanda
/// se pide sola al acercarse al final de la lista.
class _OpinionsSheet extends StatefulWidget {
  final int eateryId;
  const _OpinionsSheet({required this.eateryId});

  @override
  State<_OpinionsSheet> createState() => _OpinionsSheetState();
}

class _OpinionsSheetState extends State<_OpinionsSheet> {
  Map<String, dynamic>? _data;
  final List _comments = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _first();
  }

  Future<void> _first() async {
    final d = await RouteService.eateryOpinions(widget.eateryId);
    if (!mounted) return;
    setState(() {
      _data = d;
      _comments
        ..clear()
        ..addAll(d == null ? const [] : (d['comments'] as List? ?? const []));
      _hasMore = d?['has_more'] == true;
      _loading = false;
    });
  }

  Future<void> _more() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final d = await RouteService.eateryOpinions(widget.eateryId, page: _page + 1);
    if (!mounted) return;
    setState(() {
      if (d != null) {
        _page++;
        _comments.addAll(d['comments'] as List? ?? const []);
        _hasMore = d['has_more'] == true;
      }
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final comments = _comments;

    return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (ctx, scroll) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : d == null
                    ? Center(
                        child: Text('rating.opinions_error'.tr(),
                            style: const TextStyle(color: AppColors.grey)))
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.extentAfter < 300) _more();
                          return false;
                        },
                        child: ListView(controller: scroll, children: [
                        Text('${d['name']}',
                            style: const TextStyle(
                                color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Row(children: [
                          if (d['rating'] != null) ...[
                            const Icon(Icons.star, color: AppColors.gold, size: 18),
                            const SizedBox(width: 4),
                            Text('${dec1(context, d['rating'])} · '
                                '${'rating.votes'.tr(namedArgs: {'n': '${d['votes']}'})}'
                                ' · ${'rating.comments_count'.tr(namedArgs: {'n': '${d['total_comments'] ?? comments.length}'})}',
                                style: const TextStyle(color: AppColors.white, fontSize: 14)),
                          ] else
                            Text('rating.no_votes'.tr(),
                                style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                        ]),
                        if ((d['parking_yes'] ?? 0) + (d['parking_no'] ?? 0) > 0) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            const Icon(Icons.two_wheeler, color: AppColors.cyan, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'rating.parking_summary'.tr(namedArgs: {
                                'yes': '${d['parking_yes']}',
                                'total': '${(d['parking_yes'] as num) + (d['parking_no'] as num)}',
                              }),
                              style: const TextStyle(color: AppColors.grey, fontSize: 12),
                            ),
                          ]),
                        ],
                        const Divider(height: 24, color: AppColors.greyDark),
                        if (comments.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text('rating.no_comments'.tr(),
                                style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                          ),
                        for (final c in comments)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                if (c['stars'] != null) ...[
                                  for (var i = 1; i <= 5; i++)
                                    Icon(i <= (c['stars'] as num) ? Icons.star : Icons.star_border,
                                        color: AppColors.gold, size: 13),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    // Cuándo ESTUVO allí (la fecha de la rodada), que es lo que
                                    // da confianza; si no se conoce, cuándo lo escribió.
                                    '${c['nickname'] ?? 'rating.anonymous'.tr()} · ${_fechaVisita(context, c)}',
                                    style: const TextStyle(color: AppColors.grey, fontSize: 11),
                                  ),
                                ),
                              ]),
                              if (c['parked'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(children: [
                                    const Icon(Icons.two_wheeler, color: AppColors.cyan, size: 14),
                                    const SizedBox(width: 5),
                                    Text(
                                      (c['parked'] == true ? 'moderation.parking_yes' : 'moderation.parking_no').tr(),
                                      style: const TextStyle(color: AppColors.grey, fontSize: 11),
                                    ),
                                  ]),
                                ),
                              const SizedBox(height: 4),
                              Text('${c['comment']}',
                                  style: const TextStyle(
                                      color: AppColors.white, fontSize: 13, height: 1.4)),
                              if (c['translated'] == true && c['original'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('rating.original'.tr(namedArgs: {'text': '${c['original']}'}),
                                      style: const TextStyle(
                                          color: AppColors.grey, fontSize: 11, fontStyle: FontStyle.italic)),
                                ),
                            ]),
                          ),
                        if (_loadingMore)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                      ])),
          ),
        );
  }
}

/// «Estuvo el 2 nov 2026» si se conoce el día de la rodada; si no, la fecha del comentario.
String _fechaVisita(BuildContext context, Map c) {
  final iso = '${c['visited_on'] ?? ''}';
  final d = DateTime.tryParse(iso);
  if (d != null) {
    return 'rating.visited_on'.tr(
      namedArgs: {'date': DateFormat.yMMMd(context.locale.toString()).format(d)},
    );
  }
  return '${c['date'] ?? ''}';
}

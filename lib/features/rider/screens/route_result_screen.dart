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

  Map<String, dynamic> get _route => widget.result['route'] ?? {};
  Map<String, dynamic>? get _weather => widget.result['weather'];
  Map<String, dynamic>? get _aiSummary => widget.result['ai_summary'];
  List get _waypoints => _route['waypoints'] ?? [];
  int? get _routesRemaining => widget.result['routes_remaining'];
  int? get _fuelRangeKm => widget.result['fuel_range_km'];

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('route_result.published'.tr()), backgroundColor: Colors.green),
      );
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
            _ShareOption(
              icon: Icons.people_outlined,
              label: 'route_result.share_friends'.tr(),
              desc: 'route_result.share_friends_desc'.tr(),
              color: AppColors.cyan,
              onTap: () { Navigator.pop(ctx); _publish('friends'); },
            ),
            const SizedBox(height: 12),
            _ShareOption(
              icon: Icons.public,
              label: 'route_result.share_public'.tr(),
              desc: 'route_result.share_public_desc'.tr(),
              color: AppColors.orange,
              onTap: () { Navigator.pop(ctx); _publish('public'); },
            ),
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
          onPressed: () => context.go('/rider/home'),
        ),
        title: Text('route_result.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.orange),
            onPressed: _showPublishDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header naranja
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.orange.withOpacity(0.3), AppColors.surface],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppColors.orange, size: 16),
                      const SizedBox(width: 6),
                      Text('route_result.generated_by_ai'.tr(), style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_routesRemaining != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.greyDark,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('route_result.routes_remaining'.tr(args: ['$_routesRemaining']),
                            style: const TextStyle(color: AppColors.grey, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _route['title'] ?? '',
                    style: const TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _route['description'] ?? '',
                    style: const TextStyle(color: AppColors.grey, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats
                  Row(
                    children: [
                      _StatBadge(icon: Icons.route, label: '${_route['distance_km']} km', color: AppColors.orange),
                      const SizedBox(width: 8),
                      _StatBadge(icon: Icons.access_time, label: '${((_route['duration_minutes'] ?? 0) / 60).toStringAsFixed(1)} h', color: AppColors.cyan),
                      const SizedBox(width: 8),
                      _StatBadge(icon: Icons.terrain, label: _route['difficulty'] ?? '', color: AppColors.gold),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Clima
                  if (_weather != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.greyDark),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wb_sunny_outlined, color: AppColors.gold, size: 28),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_weather!['temp']?.toStringAsFixed(0)}°C · ${_weather!['description']}',
                                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Viento ${_weather!['wind_speed']} m/s · Humedad ${_weather!['humidity']}%',
                                style: const TextStyle(color: AppColors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (_aiSummary?['best_departure_time'] != null)
                                Column(
                              children: [
                                Text('route_result.departure'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                                Text(
                                  _aiSummary!['best_departure_time'],
                                  style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                              ],
                            ),
                        ],
                      ),
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
                        border: Border.all(
                          color: _fuelRangeKm! < (_route['distance_km'] ?? 999)
                              ? AppColors.error.withOpacity(0.5)
                              : AppColors.greyDark,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_gas_station,
                            color: _fuelRangeKm! < (_route['distance_km'] ?? 999) ? AppColors.error : AppColors.grey,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                'route_result.autonomy'.tr(args: ['$_fuelRangeKm']),
                                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600),
                                ),
                                if (_aiSummary?['fuel_stop_after_km'] != null)
                                Text(
                                'route_result.refuel_at'.tr(args: ['${_aiSummary!["fuel_stop_after_km"]}']),
                                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Waypoints
                  Text('route_result.waypoints'.tr(), style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),

                  ..._waypoints.asMap().entries.map((entry) {
                    final i = entry.key;
                    final wp = entry.value;
                    final isFirst = i == 0;
                    final isLast = i == _waypoints.length - 1;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isFirst || isLast ? AppColors.orange : AppColors.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.orange),
                              ),
                              child: Center(
                                child: Text(
                                  isFirst ? '🏁' : isLast ? '🏆' : '${i}',
                                  style: TextStyle(
                                    color: isFirst || isLast ? AppColors.white : AppColors.orange,
                                    fontSize: isFirst || isLast ? 14 : 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            if (!isLast)
                              Container(width: 2, height: 40, color: AppColors.greyDark),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  wp['name'] ?? '',
                                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                if (wp['note'] != null)
                                  Text(
                                    wp['note'],
                                    style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4),
                                  ),
                                if (wp['estimated_arrival_time'] != null)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.cyan.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      'route_result.arrival'.tr(args: [wp['estimated_arrival_time']]),
                                      style: const TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  )
                                else if (wp['estimated_minutes_from_start'] != null && wp['estimated_minutes_from_start'] > 0)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.greyDark.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'route_result.minutes_from_start'.tr(args: ['${wp["estimated_minutes_from_start"]}']),
                                      style: const TextStyle(color: AppColors.grey, fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }),

                  const SizedBox(height: 24),

                  // Gasolineras sugeridas
                  if (_route['waypoints'] != null && _route['gas_stops'] != null && (_route['gas_stops'] as List).isNotEmpty) ...[  
                    _SectionHeader(icon: Icons.local_gas_station, label: 'route_result.gas_stops'.tr(), color: AppColors.gold),
                    const SizedBox(height: 8),
                    ...(_route['gas_stops'] as List).map((stop) => _SuggestionCard(
                      icon: Icons.local_gas_station,
                      title: stop['name'] ?? 'Gasolinera',
                      subtitle: stop['note'] ?? 'Km ${stop['approximate_km_from_start']} desde el inicio',
                      color: AppColors.gold,
                    )),
                    const SizedBox(height: 16),
                  ],

                  // Almuerzo sugerido
                  if (_route['lunch_stop'] != null) ...[  
                    _SectionHeader(icon: Icons.restaurant_outlined, label: 'route_result.lunch_stop'.tr(), color: AppColors.orange),
                    const SizedBox(height: 8),
                    _SuggestionCard(
                      icon: Icons.restaurant_outlined,
                      title: _route['lunch_stop']['location'] ?? '',
                      subtitle: _route['lunch_stop']['suggestion'] ?? '',
                      badge: _route['lunch_stop']['estimated_time'],
                      color: AppColors.orange,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Cena sugerida
                  if (_route['dinner_stop'] != null) ...[  
                    _SectionHeader(icon: Icons.dinner_dining, label: 'route_result.dinner_stop'.tr(), color: AppColors.cyan),
                    const SizedBox(height: 8),
                    _SuggestionCard(
                      icon: Icons.dinner_dining,
                      title: _route['dinner_stop']['location'] ?? '',
                      subtitle: _route['dinner_stop']['suggestion'] ?? '',
                      badge: _route['dinner_stop']['estimated_time'],
                      color: AppColors.cyan,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Hoteles sugeridos
                  if (_route['hotel_stops'] != null && (_route['hotel_stops'] as List).isNotEmpty) ...[  
                    _SectionHeader(icon: Icons.hotel_outlined, label: 'route_result.hotels'.tr(), color: AppColors.gold),
                    const SizedBox(height: 8),
                    ...(_route['hotel_stops'] as List).map((hotel) => _SuggestionCard(
                      icon: Icons.hotel_outlined,
                      title: hotel['location'] ?? '',
                      subtitle: hotel['suggestion'] ?? '',
                      badge: 'route_result.day'.tr(args: ['${hotel["day"]}']),
                      color: AppColors.gold,
                    )),
                    const SizedBox(height: 16),
                  ],

                  // Tags
                  if (_route['tags'] != null && (_route['tags'] as List).isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
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

                  // Botón Google Maps
                  ElevatedButton(
                    onPressed: _openInGoogleMaps,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.map, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text('route_result.open_maps'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Botón compartir
                  OutlinedButton(
                    onPressed: _publishing ? null : _showPublishDialog,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      side: const BorderSide(color: AppColors.orange),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _publishing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.share_outlined, color: AppColors.orange, size: 20),
                              const SizedBox(width: 8),
                              Text('route_result.share'.tr(), style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
                            ],
                          ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
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
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
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
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                  Text(desc, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 14),
          ],
        ),
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

  const _SuggestionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
            ],
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(badge!, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

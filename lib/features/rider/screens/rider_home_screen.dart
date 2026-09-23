import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/app_notification_service.dart';
import '../providers/friendship_service.dart';
import '../providers/route_service.dart';
import '../providers/rider_profile_service.dart';
import '../providers/route_tracking_service.dart';
import '../../../core/services/route_tracking_manager.dart';
import '../../../core/services/push_notification_service.dart';
import '../providers/achievement_service.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  int _pendingRequests  = 0;
  int _acceptedRecently = 0;
  int _pendingRoutes    = 0;
  int _unreadNotifications = 0;
  int _pendingAchievements  = 0;
  String? _nickname;

  /// Ruta que sale ahora desde donde estás, o null. Ver [_checkDeparture].
  Map<String, dynamic>? _departingRoute;

  StreamSubscription<TrackingState>? _trackingSub;

  /// Ventana alrededor de la hora de salida, igual que en el detalle:
  /// generosa por detrás, porque salir con retraso es lo normal.
  static const _windowBefore = Duration(minutes: 30);
  static const _windowAfter  = Duration(hours: 2);

  /// Distancia máxima al origen. Amplia: el punto de salida real suele ser el
  /// bar o la gasolinera de al lado, no la coordenada exacta.
  static const double _nearOriginM = 1000;
  String? _gender;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadNotifications();
    _recoverTracking();
    _openRouteFromPush();
    _checkDeparture();

    // La tarjeta desaparece en cuanto arranca una grabación, venga de donde
    // venga: de la propia tarjeta, del detalle de la ruta o de recuperar una
    // interrumpida.
    //
    // Sin esto la tarjeta solo se calculaba al crear la pantalla, así que al
    // volver a Inicio con la ruta ya grabándose seguía ofreciendo empezarla.
    _trackingSub = RouteTrackingManager.instance.stream.listen((s) {
      if (!mounted) return;
      if (s.isActive && _departingRoute != null) {
        setState(() => _departingRoute = null);
      }
    });
  }

  @override
  void dispose() {
    _trackingSub?.cancel();
    super.dispose();
  }

  /// Busca una ruta que salga ahora desde donde estás, para ofrecerla arriba.
  ///
  /// Mismas condiciones que el diálogo del detalle: dentro de la ventana de
  /// salida, a menos de 1 km del origen y con el permiso de ubicación ya
  /// concedido. Aquí NO se pide el permiso: si no lo hay, no se ofrece nada.
  ///
  /// Se hace también desde Inicio porque si el motero abre la app y se queda
  /// aquí, antes no se enteraba de nada y tenía que ir a buscar la ruta.
  ///
  /// Es una tarjeta y no un diálogo a propósito: no interrumpe, y sigue ahí
  /// si no le hace caso a la primera.
  Future<void> _checkDeparture() async {
    if (RouteTrackingManager.instance.isTracking) return;

    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return;
    }

    final result = await RouteService.getMyRoutes();
    final upcoming = result['upcoming'] as List? ?? [];
    if (upcoming.isEmpty || !mounted) return;

    final now = DateTime.now();

    // Candidatas: las que están en su ventana de salida.
    final candidates = upcoming
        .map((r) => Map<String, dynamic>.from(r as Map))
        .where((r) {
          final departure = _departureOf(r);
          if (departure == null) return false;
          return now.isAfter(departure.subtract(_windowBefore)) &&
              now.isBefore(departure.add(_windowAfter));
        })
        .toList();

    if (candidates.isEmpty) return;

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return;
    }

    if (!mounted) return;

    for (final route in candidates) {
      final lat = _coord(route['origin_lat']);
      final lng = _coord(route['origin_lng']);
      if (lat == null || lng == null) continue;

      final metres = RouteTrackingManager.haversine(
        position.latitude, position.longitude, lat, lng,
      );

      if (metres <= _nearOriginM) {
        setState(() => _departingRoute = route);
        return;
      }
    }
  }

  /// Combina `departure_date` y `departure_time`, que llegan como texto.
  static DateTime? _departureOf(Map<String, dynamic> route) {
    final date = route['departure_date']?.toString();
    if (date == null || date.isEmpty) return null;

    final day = DateTime.tryParse(date);
    if (day == null) return null;

    final parts = (route['departure_time']?.toString() ?? '').split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  /// Coordenada del servidor a double: llega como TEXTO por el cast decimal:7.
  static double? _coord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// Abre la ruta del push que arrancó la app, si lo hubo.
  ///
  /// Se hace aquí y no en PushNotificationService porque aquel corre antes de
  /// `runApp`: navegar desde ahí no hace nada. Al llegar a esta pantalla ya hay
  /// sesión resuelta y Navigator montado, que es lo que hace falta.
  ///
  /// El postFrameCallback espera a que el primer frame esté pintado; sin él la
  /// navegación se lanzaría mientras esta misma pantalla se está construyendo.
  void _openRouteFromPush() {
    final routeId = PushNotificationService.consumePendingRoute();
    debugPrint('[push] Inicio recoge ruta pendiente: $routeId');
    if (routeId == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.push('/rider/routes/$routeId');
    });
  }

  /// Recupera una ruta que quedó grabándose (app cerrada por el sistema,
  /// reinicio del móvil). El servidor sabe qué tracking sigue abierto y el
  /// track parcial está guardado en local.
  Future<void> _recoverTracking() async {
    final tracking = await RouteTrackingService.getActive();
    if (tracking == null || !mounted) return;

    final recovered = await RouteTrackingManager.instance.resume(
      trackingId: tracking['id'] as int,
      routeId: tracking['route_id'] as int,
    );

    if (!recovered || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('tracking.resumed'.tr()),
      backgroundColor: AppColors.surface,
    ));

    context.push('/rider/tracking', extra: tracking);
  }

  Future<void> _loadProfile() async {
    final result = await RiderProfileService.getProfile();
    if (!mounted) return;
    setState(() {
      _nickname = result['profile']?['nickname'];
      _gender   = result['profile']?['gender'];
    });
  }

  Future<void> _loadNotifications() async {
    final friendResults = await Future.wait([
      FriendshipService.getPendingReceived(),
      FriendshipService.getPendingSent(),
      RouteService.getMyRoutes(),
    ]);
    final unread = await AppNotificationService.getUnreadCount();
    if (!mounted) return;
    final received = friendResults[0]['requests'] as List? ?? [];
    final sent     = friendResults[1]['requests'] as List? ?? [];
    final routes   = friendResults[2]['received']  as List? ?? [];

    // Filtrar aceptadas y rechazadas ya vistas
    final prefs    = await SharedPreferences.getInstance();
    final seenIds  = prefs.getStringList('seen_accepted_requests') ?? [];
    final seenRouteIds = prefs.getStringList('seen_received_routes') ?? [];
    final unseenNotifications = sent.where((s) =>
        (s['status'] == 'accepted' || s['status'] == 'rejected') &&
        !seenIds.contains('${s['friendship_id']}'),
    ).length;
    final unseenRoutes = routes.where((r) =>
        r['is_confirmed'] != true,
    ).length;

    // Logros desbloqueados que el motero todavía no ha visto celebrar.
    final pendingAchievements = await AchievementService.pending();

    if (!mounted) return;
    setState(() {
      _pendingRequests      = received.length;
      _acceptedRecently     = unseenNotifications;
      _pendingRoutes        = unseenRoutes;
      _unreadNotifications  = unread;
      _pendingAchievements  = pendingAchievements.length;
    });
  }

  /// Abre los logros. Si hay alguno sin celebrar, primero la celebración.
  ///
  /// Sin esto el contador de la tarjeta no se limpiaría nunca: los logros solo
  /// se marcan como vistos en la pantalla de celebración, y a esa únicamente
  /// se llegaba terminando otra ruta.
  Future<void> _openAchievements() async {
    final pending = await AchievementService.pending();
    if (!mounted) return;

    if (pending.isNotEmpty) {
      context.go('/rider/celebration', extra: {
        'achievements': pending,
        'next': '/rider/achievements',
      });
      return;
    }

    await context.push('/rider/achievements');
    _loadNotifications();
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            children: [
              TextSpan(text: 'GAS', style: TextStyle(color: AppColors.orange)),
              TextSpan(text: 'troRoute', style: TextStyle(color: AppColors.white)),
              TextSpan(text: 'AI', style: TextStyle(color: AppColors.cyan)),
            ],
          ),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: AppColors.white),
                onPressed: () async {
                  await context.push('/rider/notifications');
                  _loadNotifications();
                },
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.person_outlined, color: AppColors.white),
            onPressed: () => context.go('/rider/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.grey),
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              _gender == 'motera'
                  ? 'home.welcome_female'.tr()
                  : 'home.welcome_male'.tr(),
              style: const TextStyle(color: AppColors.white, fontSize: 24, fontWeight: FontWeight.w700),
            ),
            if (_nickname != null && _nickname!.isNotEmpty) ...[  
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(
                  children: [
                    const TextSpan(
                      text: ' ',
                      style: TextStyle(color: AppColors.grey, fontSize: 15),
                    ),
                    TextSpan(
                      text: '@$_nickname',
                      style: const TextStyle(
                        color: AppColors.orange,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text('home.subtitle'.tr(),
                style: const TextStyle(color: AppColors.grey, fontSize: 14)),

            // Tarjeta de salida: solo aparece si hoy sales de ruta y estás en
            // el punto de salida. Ver _checkDeparture.
            if (_departingRoute != null) ...[
              const SizedBox(height: 24),
              _DepartureCard(
                title: '${_departingRoute!['title'] ?? ''}',
                time: '${_departingRoute!['departure_time'] ?? ''}',
                onStart: () => context.push(
                  '/rider/routes/${_departingRoute!['id']}',
                ),
              ),
            ],

            const SizedBox(height: 32),

            _QuickAccessCard(
              icon: Icons.person_outlined,
              title: 'home.my_profile'.tr(),
              desc: 'home.my_profile_desc'.tr(),
              color: AppColors.orange,
              onTap: () => context.go('/rider/profile'),
            ),
            const SizedBox(height: 16),
            _QuickAccessCard(
              icon: Icons.add_road,
              title: 'home.create_route'.tr(),
              desc: 'home.create_route_desc'.tr(),
              color: AppColors.orange,
              onTap: () => context.push('/rider/create-route'),
            ),
            const SizedBox(height: 16),
            _QuickAccessCard(
              icon: Icons.route,
              title: 'home.my_routes'.tr(),
              desc: _pendingRoutes > 0
                  ? 'home.my_routes_pending'.plural(_pendingRoutes)
                  : 'home.my_routes_desc'.tr(),
              color: AppColors.cyan,
              badge: _pendingRoutes,
              badgeColor: AppColors.orange,
              onTap: () async {
                await context.push('/rider/my-routes');
                _loadNotifications();
              },
            ),
            const SizedBox(height: 16),
            _QuickAccessCard(
              icon: Icons.emoji_events_outlined,
              title: 'home.achievements'.tr(),
              desc: _pendingAchievements > 0
                  ? 'home.achievements_new'.plural(_pendingAchievements)
                  : 'home.achievements_desc'.tr(),
              color: AppColors.gold,
              badge: _pendingAchievements,
              badgeColor: AppColors.orange,
              onTap: _openAchievements,
            ),
            const SizedBox(height: 16),
            _QuickAccessCard(
              icon: Icons.people_outlined,
              title: 'home.friends'.tr(),
              desc: _pendingRequests > 0
                  ? 'home.friends_pending'.plural(_pendingRequests)
                  : _acceptedRecently > 0
                      ? 'home.friends_notification'.plural(_acceptedRecently)
                      : 'home.friends_desc'.tr(),
              color: AppColors.gold,
              badge: _pendingRequests + _acceptedRecently,
              badgeColor: _pendingRequests > 0 ? AppColors.error : AppColors.cyan,
              onTap: () async {
                await context.push('/rider/friends');
                _loadNotifications();
              },
            ),
            const SizedBox(height: 16),
            _QuickAccessCard(
              icon: Icons.restaurant_outlined,
              title: 'home.gastronomy'.tr(),
              desc: 'home.gastronomy_desc'.tr(),
              color: AppColors.gold,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso de que sales de ruta ahora, en la pantalla principal.
///
/// Es una tarjeta y no un diálogo: no interrumpe lo que el motero estuviera
/// haciendo y, si no le hace caso a la primera, sigue ahí.
class _DepartureCard extends StatelessWidget {
  final String title;
  final String time;
  final VoidCallback onStart;

  const _DepartureCard({
    required this.title,
    required this.time,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.two_wheeler, color: AppColors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'home.departing_today'.tr(namedArgs: {'time': time}),
                style: const TextStyle(
                    color: AppColors.orange,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.white, fontSize: 15)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('tracking.start_now'.tr(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  final VoidCallback onTap;
  final int badge;
  final Color badgeColor;

  const _QuickAccessCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
    required this.onTap,
    this.badge = 0,
    this.badgeColor = AppColors.error,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: badge > 0 ? AppColors.error.withOpacity(0.6) : AppColors.greyDark,
            width: badge > 0 ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                if (badge > 0)
                  Positioned(
                    top: -6, right: -6,
                    child: Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: badgeColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: TextStyle(
                          color: badge > 0 ? AppColors.error : AppColors.grey,
                          fontSize: 13,
                          fontWeight: badge > 0 ? FontWeight.w600 : FontWeight.normal)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: AppColors.grey, size: 16),
          ],
        ),
      ),
    );
  }
}

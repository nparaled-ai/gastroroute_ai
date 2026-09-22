import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
  String? _gender;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadNotifications();
    _recoverTracking();
    _openRouteFromPush();
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

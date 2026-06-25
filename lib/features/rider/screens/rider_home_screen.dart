import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/friendship_service.dart';
import '../providers/route_service.dart';
import '../providers/rider_profile_service.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  int _pendingRequests  = 0;
  int _acceptedRecently = 0;
  int _pendingRoutes    = 0;
  String? _nickname;
  String? _gender;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadNotifications();
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
    final results = await Future.wait([
      FriendshipService.getPendingReceived(),
      FriendshipService.getPendingSent(),
      RouteService.getMyRoutes(),
    ]);
    if (!mounted) return;
    final received = results[0]['requests'] as List? ?? [];
    final sent     = results[1]['requests'] as List? ?? [];
    final routes   = results[2]['received']  as List? ?? [];

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

    if (!mounted) return;
    setState(() {
      _pendingRequests  = received.length;
      _acceptedRecently = unseenNotifications;
      _pendingRoutes    = unseenRoutes;
    });
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
              TextSpan(text: 'troroute', style: TextStyle(color: AppColors.white)),
              TextSpan(text: 'AI', style: TextStyle(color: AppColors.cyan)),
            ],
          ),
        ),
        actions: [
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
                  ? '¡Bienvenida, motera!'
                  : '¡Bienvenido, motero!',
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
              title: 'Crear ruta',
              desc: 'Genera con IA, Google Maps o GPX',
              color: AppColors.orange,
              onTap: () => context.push('/rider/create-route'),
            ),
            const SizedBox(height: 16),
            _QuickAccessCard(
              icon: Icons.route,
              title: 'Mis Rutas',
              desc: _pendingRoutes > 0
                  ? '$_pendingRoutes ruta${_pendingRoutes > 1 ? 's' : ''} recibida${_pendingRoutes > 1 ? 's' : ''}'
                  : 'Ver y gestionar tus rutas',
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
              icon: Icons.people_outlined,
              title: 'Amigos',
              desc: _pendingRequests > 0
                  ? '$_pendingRequests solicitud${_pendingRequests > 1 ? 'es' : ''} pendiente${_pendingRequests > 1 ? 's' : ''}'
                  : _acceptedRecently > 0
                      ? '$_acceptedRecently notificación${_acceptedRecently > 1 ? 'es' : ''} de amistad'
                      : 'Busca y conecta con otros moteros',
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

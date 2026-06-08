import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/rider_avatar.dart';
import '../providers/route_service.dart';
import '../providers/route_share_service.dart';

class MyRoutesScreen extends StatefulWidget {
  const MyRoutesScreen({super.key});

  @override
  State<MyRoutesScreen> createState() => _MyRoutesScreenState();
}

class _MyRoutesScreenState extends State<MyRoutesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _myRoutes    = [];
  List<Map<String, dynamic>> _joinedRoutes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRoutes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    setState(() => _loading = true);
    final result = await RouteService.getMyRoutes();
    if (!mounted) return;
    setState(() {
      _myRoutes = List<Map<String, dynamic>>.from(result['routes'] ?? []);
      _loading  = false;
    });
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
        title: const Text('Mis Rutas',
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
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
          tabs: [
            Tab(text: 'Mis rutas (${_myRoutes.length})'),
            const Tab(text: 'Apuntado'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMyRoutes(),
                _buildJoinedRoutes(),
              ],
            ),
    );
  }

  Widget _buildMyRoutes() {
    if (_myRoutes.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.map_outlined, color: AppColors.greyDark, size: 64),
          const SizedBox(height: 16),
          const Text('Aún no has generado ninguna ruta.',
              style: TextStyle(color: AppColors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/rider/planner'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Crear ruta'),
          ),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myRoutes.length,
      itemBuilder: (context, index) {
        final route = _myRoutes[index];
        return _RouteCard(
          route: route,
          isOwner: true,
          onTap: () => context.push('/rider/routes/${route['id']}'),
        );
      },
    );
  }

  Widget _buildJoinedRoutes() {
    if (_joinedRoutes.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.directions_bike_outlined, color: AppColors.greyDark, size: 64),
          const SizedBox(height: 16),
          const Text('No te has apuntado a ninguna ruta aún.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _joinedRoutes.length,
      itemBuilder: (context, index) {
        final route = _joinedRoutes[index];
        return _RouteCard(
          route: route,
          isOwner: false,
          onTap: () => context.push('/rider/routes/${route['id']}'),
        );
      },
    );
  }
}

class _RouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  final bool isOwner;
  final VoidCallback onTap;

  const _RouteCard({required this.route, required this.isOwner, required this.onTap});

  Color get _visibilityColor {
    switch (route['visibility']) {
      case 'public':  return AppColors.orange;
      case 'friends': return AppColors.cyan;
      default:        return AppColors.grey;
    }
  }

  String get _visibilityLabel {
    switch (route['visibility']) {
      case 'public':  return '🌍 Pública';
      case 'friends': return '👥 Amigos';
      default:        return '🔒 Privada';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.greyDark),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(route['title'] ?? 'Sin título',
                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _visibilityColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _visibilityColor.withOpacity(0.3)),
              ),
              child: Text(_visibilityLabel,
                  style: TextStyle(color: _visibilityColor, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _Chip(icon: Icons.route, label: '${route['distance_km'] ?? '?'} km', color: AppColors.orange),
            const SizedBox(width: 8),
            _Chip(icon: Icons.access_time,
                label: '${(((route['duration_minutes'] ?? 0)) / 60).toStringAsFixed(1)} h',
                color: AppColors.cyan),
            const SizedBox(width: 8),
            _Chip(icon: Icons.terrain, label: route['difficulty'] ?? '', color: AppColors.gold),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.location_on_outlined, color: AppColors.grey, size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(route['origin'] ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.grey, fontSize: 12)),
            ),
            const Icon(Icons.arrow_forward_ios, color: AppColors.greyDark, size: 12),
          ]),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

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
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

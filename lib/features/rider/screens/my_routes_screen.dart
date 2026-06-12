import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/rider_avatar.dart';
import '../providers/route_service.dart';

class MyRoutesScreen extends StatefulWidget {
  const MyRoutesScreen({super.key});

  @override
  State<MyRoutesScreen> createState() => _MyRoutesScreenState();
}

class _MyRoutesScreenState extends State<MyRoutesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _upcoming   = [];
  List<Map<String, dynamic>> _historical = [];
  List<Map<String, dynamic>> _drafts     = [];
  List<Map<String, dynamic>> _received   = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
      _upcoming   = List<Map<String, dynamic>>.from(result['upcoming']   ?? []);
      _historical = List<Map<String, dynamic>>.from(result['historical'] ?? []);
      _drafts     = List<Map<String, dynamic>>.from(result['drafts']     ?? []);
      _received   = List<Map<String, dynamic>>.from(result['received']   ?? []);
      _loading    = false;
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
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              child: _TabLabel(
                icon: '📅',
                label: 'Previstas',
                count: _upcoming.length,
                activeColor: AppColors.cyan,
              ),
            ),
            Tab(
              child: _TabLabel(
                icon: '📚',
                label: 'Históricas',
                count: _historical.length,
                activeColor: AppColors.grey,
              ),
            ),
            Tab(
              child: _TabLabel(
                icon: '📝',
                label: 'Borradores',
                count: _drafts.length,
                activeColor: AppColors.gold,
              ),
            ),
            Tab(
              child: _TabLabel(
                icon: '📨',
                label: 'Recibidas',
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
                  empty: 'No tienes rutas previstas.\nGuarda una ruta con fecha futura.',
                  emptyIcon: Icons.event_outlined,
                  onTap: (r) => context.push('/rider/routes/${r['id']}'),
                  onNew: () => context.go('/rider/planner'),
                ),
                _RouteList(
                  routes: _historical,
                  empty: 'No tienes rutas históricas aún.',
                  emptyIcon: Icons.history,
                  onTap: (r) => context.push('/rider/routes/${r['id']}'),
                ),
                _DraftList(
                  drafts: _drafts,
                  onTap: (r) => context.push('/rider/routes/${r['id']}'),
                  onNew: () => context.go('/rider/planner'),
                ),
                _ReceivedList(
                  routes: _received,
                  onTap: (r) => context.push('/rider/routes/${r['id']}'),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/rider/planner'),
        backgroundColor: AppColors.orange,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nueva ruta',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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

// ─── Lista genérica de rutas ──────────────────────────────────────────────────
class _RouteList extends StatelessWidget {
  final List<Map<String, dynamic>> routes;
  final String empty;
  final IconData emptyIcon;
  final Function(Map<String, dynamic>) onTap;
  final VoidCallback? onNew;

  const _RouteList({
    required this.routes,
    required this.empty,
    required this.emptyIcon,
    required this.onTap,
    this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(emptyIcon, color: AppColors.greyDark, size: 64),
          const SizedBox(height: 16),
          Text(empty,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5)),
          if (onNew != null) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Crear ruta'),
            ),
          ],
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: routes.length,
      itemBuilder: (_, i) => _RouteCard(route: routes[i], onTap: () => onTap(routes[i])),
    );
  }
}

// ─── Lista de borradores ──────────────────────────────────────────────────────
class _DraftList extends StatelessWidget {
  final List<Map<String, dynamic>> drafts;
  final Function(Map<String, dynamic>) onTap;
  final VoidCallback onNew;

  const _DraftList({required this.drafts, required this.onTap, required this.onNew});

  @override
  Widget build(BuildContext context) {
    if (drafts.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.edit_note_outlined, color: AppColors.greyDark, size: 64),
          const SizedBox(height: 16),
          const Text('No tienes borradores.\nLas rutas generadas aparecen aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Generar ruta'),
          ),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: drafts.length,
      itemBuilder: (_, i) => _RouteCard(
        route: drafts[i],
        onTap: () => onTap(drafts[i]),
        isDraft: true,
      ),
    );
  }
}

// ─── Lista de rutas recibidas ─────────────────────────────────────────────────
class _ReceivedList extends StatelessWidget {
  final List<Map<String, dynamic>> routes;
  final Function(Map<String, dynamic>) onTap;

  const _ReceivedList({required this.routes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.mail_outline, color: AppColors.greyDark, size: 64),
          SizedBox(height: 16),
          Text('No has recibido ninguna ruta aún.\nCuando un amigo comparta contigo aparecerá aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: routes.length,
      itemBuilder: (_, i) => _RouteCard(
        route: routes[i],
        onTap: () => onTap(routes[i]),
        isReceived: true,
      ),
    );
  }
}

// ─── Tarjeta de ruta ──────────────────────────────────────────────────────────
class _RouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  final VoidCallback onTap;
  final bool isDraft;
  final bool isReceived;

  const _RouteCard({
    required this.route,
    required this.onTap,
    this.isDraft    = false,
    this.isReceived = false,
  });

  Color get _statusColor {
    if (isDraft)    return AppColors.gold;
    if (isReceived) return AppColors.orange;
    switch (route['visibility']) {
      case 'public':  return AppColors.orange;
      case 'friends': return AppColors.cyan;
      default:        return AppColors.grey;
    }
  }

  String get _statusLabel {
    if (isDraft)    return '📝 Borrador';
    if (isReceived) return '📨 Recibida';
    switch (route['visibility']) {
      case 'public':  return '🌍 Pública';
      case 'friends': return '👥 Amigos';
      default:        return '🔒 Privada';
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
            color: isDraft ? AppColors.gold.withOpacity(0.3) : AppColors.greyDark,
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

          // Creador (si es recibida)
          if (isReceived && route['owner_name'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                const Icon(Icons.person_outline, color: AppColors.orange, size: 14),
                const SizedBox(width: 5),
                Text(
                  '${route['owner_name']}'
                  '${route['owner_nick'] != null ? ' @${route['owner_nick']}' : ''}',
                  style: const TextStyle(
                      color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ]),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(route['title'] ?? 'Sin título',
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
              Row(children: [
                _Chip(Icons.route,       '${route['distance_km'] ?? '?'} km', AppColors.orange),
                const SizedBox(width: 8),
                _Chip(Icons.access_time,
                    '${(((route['duration_minutes'] ?? 0) as num) / 60).toStringAsFixed(1)} h',
                    AppColors.cyan),
                const SizedBox(width: 8),
                _Chip(Icons.terrain, route['difficulty'] ?? '', AppColors.gold),
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/rider_avatar.dart';
import '../providers/route_share_service.dart';

class RouteDetailScreen extends StatefulWidget {
  final int routeId;
  const RouteDetailScreen({super.key, required this.routeId});

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  Map<String, dynamic>? _route;
  List<Map<String, dynamic>> _participants = [];
  bool _loading   = true;
  bool _isOwner   = false;
  bool _isJoined  = false;
  int  _count     = 0;
  bool _joining   = false;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      RouteShareService.getRoute(widget.routeId),
      RouteShareService.getParticipants(widget.routeId),
    ]);
    if (!mounted) return;
    setState(() {
      _route        = results[0]['route'];
      _isOwner      = results[0]['route']?['is_owner'] ?? false;
      _isJoined     = results[1]['is_joined'] ?? false;
      _count        = results[1]['count'] ?? 0;
      _participants = List<Map<String, dynamic>>.from(results[1]['participants'] ?? []);
      _loading      = false;
    });
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    final result = await RouteShareService.join(widget.routeId);
    if (!mounted) return;
    setState(() => _joining = false);
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? '¡Te has apuntado!'), backgroundColor: Colors.green));
      _loadRoute();
    }
  }

  Future<void> _leave() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Desapuntarse', style: TextStyle(color: AppColors.white)),
        content: const Text('¿Seguro que quieres desapuntarte de esta ruta?',
            style: TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desapuntarme', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    await RouteShareService.leave(widget.routeId);
    _loadRoute();
  }

  Future<void> _openMaps() async {
    final url = _route?['google_maps_url'];
    if (url == null) return;
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
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
          onPressed: () => context.pop(),
        ),
        title: Text(_route?['title'] ?? 'Ruta',
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.grey), onPressed: _loadRoute),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _route == null
              ? const Center(child: Text('Ruta no encontrada.', style: TextStyle(color: AppColors.grey)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          AppColors.orange.withOpacity(0.2),
                          AppColors.surface,
                        ]),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.orange.withOpacity(0.3)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_route!['title'] ?? '',
                            style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        if (_route!['description'] != null)
                          Text(_route!['description'],
                              style: const TextStyle(color: AppColors.grey, fontSize: 13, height: 1.5)),
                        const SizedBox(height: 12),
                        Row(children: [
                          _InfoChip(Icons.route, '${_route!['distance_km']} km', AppColors.orange),
                          const SizedBox(width: 8),
                          _InfoChip(Icons.access_time,
                              '${((_route!['duration_minutes'] ?? 0) / 60).toStringAsFixed(1)} h',
                              AppColors.cyan),
                          const SizedBox(width: 8),
                          _InfoChip(Icons.terrain, _route!['difficulty'] ?? '', AppColors.gold),
                        ]),
                      ]),
                    ),

                    const SizedBox(height: 20),

                    // Creador
                    if (_route!['owner'] != null) ...[
                      const Text('Creador', style: TextStyle(color: AppColors.grey, fontSize: 13)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.greyDark),
                        ),
                        child: Row(children: [
                          RiderAvatar(
                            avatarUrl: _route!['owner']['avatar_url'],
                            level: _route!['owner']['experience_level'] ?? 'novato',
                            size: 44,
                          ),
                          const SizedBox(width: 12),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              '${_route!['owner']['first_name'] ?? ''} ${_route!['owner']['last_name'] ?? ''}'.trim(),
                              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
                            ),
                            if (_route!['owner']['nickname'] != null)
                              Text('@${_route!['owner']['nickname']}',
                                  style: const TextStyle(color: AppColors.orange, fontSize: 12)),
                          ]),
                          if (_isOwner) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Tú', style: TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Detalles
                    if (_route!['departure_date'] != null || _route!['departure_time'] != null) ...[
                      const Text('Salida', style: TextStyle(color: AppColors.grey, fontSize: 13)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.greyDark),
                        ),
                        child: Row(children: [
                          const Icon(Icons.calendar_today, color: AppColors.cyan, size: 20),
                          const SizedBox(width: 12),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (_route!['departure_date'] != null)
                              Text(_route!['departure_date'],
                                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                            if (_route!['departure_time'] != null)
                              Text('Salida: ${_route!['departure_time']}',
                                  style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Participantes
                    Row(children: [
                      const Icon(Icons.people_outlined, color: AppColors.cyan, size: 18),
                      const SizedBox(width: 8),
                      Text('Participantes ($_count)',
                          style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 12),

                    if (_participants.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.greyDark),
                        ),
                        child: const Center(
                          child: Text('Nadie se ha apuntado todavía.',
                              style: TextStyle(color: AppColors.grey)),
                        ),
                      )
                    else
                      ...(_participants.map((p) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.greyDark),
                        ),
                        child: Row(children: [
                          RiderAvatar(
                            avatarUrl: p['avatar_url'],
                            level: p['experience_level'] ?? 'novato',
                            size: 40,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim(),
                              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            if (p['nickname'] != null)
                              Text('@${p['nickname']}',
                                  style: const TextStyle(color: AppColors.orange, fontSize: 11)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('✅ Apuntado',
                                style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ))),

                    const SizedBox(height: 24),

                    // Botón Google Maps
                    ElevatedButton(
                      onPressed: _openMaps,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.map, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Abrir en Google Maps',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ]),
                    ),

                    const SizedBox(height: 12),

                    // Botón apuntarse / desapuntarse (solo si no es el creador)
                    if (!_isOwner)
                      ElevatedButton(
                        onPressed: _joining ? null : (_isJoined ? _leave : _join),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isJoined ? AppColors.error : AppColors.orange,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _joining
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(_isJoined ? Icons.person_remove_outlined : Icons.person_add_outlined,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(_isJoined ? 'Desapuntarme' : '¡Apuntarme a esta ruta!',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              ]),
                      ),

                    const SizedBox(height: 32),
                  ]),
                ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

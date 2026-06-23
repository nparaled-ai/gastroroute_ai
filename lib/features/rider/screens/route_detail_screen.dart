import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/rider_avatar.dart';
import '../../../widgets/route_waypoints_view.dart';
import '../providers/route_service.dart';
import '../providers/route_share_service.dart';
import '../providers/friendship_service.dart';

class RouteDetailScreen extends StatefulWidget {
  final int routeId;
  const RouteDetailScreen({super.key, required this.routeId});

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  Map<String, dynamic>? _route;
  List<Map<String, dynamic>> _confirmed = [];
  List<Map<String, dynamic>> _pending   = [];
  List<Map<String, dynamic>> _declined  = [];
  int  _count      = 0;
  bool _loading    = true;
  bool _isOwner    = false;
  bool _isJoined   = false;
  bool _isDeclined = false;
  bool _joining    = false;
  bool _refreshingWeather = false;
  bool _publishing = false;
  Map<String, dynamic>? _currentWeather;

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
      _route      = results[0]['route'];
      _isOwner    = results[1]['is_owner']   ?? results[0]['route']?['is_owner'] ?? false;
      _isJoined   = results[1]['is_joined']  ?? false;
      _isDeclined = results[1]['is_declined'] ?? false;
      _count      = results[1]['count']      ?? 0;
      _confirmed  = List<Map<String, dynamic>>.from(results[1]['confirmed'] ?? []);
      _declined   = List<Map<String, dynamic>>.from(results[1]['declined']  ?? []);
      _pending    = List<Map<String, dynamic>>.from(results[1]['pending']   ?? []);
      _loading    = false;
    });
  }

  Future<void> _repeatRoute() async {
    String? date;
    String time = '09:00';

    await showDialog(
      context: context,
      builder: (ctx) {
        final dateCtrl = TextEditingController();
        final timeCtrl = TextEditingController(text: '09:00');
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.replay, color: AppColors.cyan, size: 22),
              SizedBox(width: 8),
              Text('Repetir ruta', style: TextStyle(color: AppColors.white, fontSize: 18)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Elige la nueva fecha y hora de salida:',
                  style: TextStyle(color: AppColors.grey, fontSize: 13)),
              const SizedBox(height: 20),
              // Fecha
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    date = picked.toIso8601String().split('T')[0];
                    dateCtrl.text = date!;
                    setS(() {});
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: dateCtrl.text.isEmpty
                        ? AppColors.greyDark : AppColors.cyan),
                  ),
                  child: Row(children: [
                    const Icon(Icons.event, color: AppColors.cyan, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      dateCtrl.text.isEmpty ? 'Selecciona fecha' : dateCtrl.text,
                      style: TextStyle(
                        color: dateCtrl.text.isEmpty ? AppColors.grey : AppColors.cyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              // Hora
              GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: const TimeOfDay(hour: 9, minute: 0),
                  );
                  if (picked != null) {
                    time = '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}';
                    timeCtrl.text = time;
                    setS(() {});
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.greyDark),
                  ),
                  child: Row(children: [
                    const Icon(Icons.schedule, color: AppColors.orange, size: 18),
                    const SizedBox(width: 10),
                    Text(timeCtrl.text,
                        style: const TextStyle(
                            color: AppColors.orange, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: AppColors.grey)),
              ),
              ElevatedButton(
                onPressed: date == null ? null : () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
                child: const Text('Guardar', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );

    if (date == null || !mounted) return;

    // Preparar datos de la copia
    final saveData = Map<String, dynamic>.from(_route!);
    saveData['departure_date'] = date;
    saveData['departure_time'] = time;
    saveData.remove('id');
    saveData.remove('status');
    saveData.remove('visibility');
    saveData.remove('created_at');
    saveData.remove('updated_at');

    // Guardar primero como saved
    setState(() => _loading = true);
    final result = await RouteService.saveRoute(saveData);
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
      return;
    }

    final newRouteId = result['route']?['id'];

    // Mostrar opciones de compartir
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _RepeatShareBottomSheet(
        onSaveOnly: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ruta guardada en Previstas.'),
                backgroundColor: Colors.green));
          context.pop();
        },
        onShareFriends: (ids) async {
          if (newRouteId != null) {
            await RouteShareService.share(newRouteId, visibility: 'friends', friendIds: ids);
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ruta guardada y compartida con amigos.'),
                backgroundColor: Colors.green));
          context.pop();
        },
        onSharePublic: () async {
          if (newRouteId != null) {
            await RouteShareService.share(newRouteId, visibility: 'public');
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ruta guardada y publicada.'),
                backgroundColor: Colors.green));
          context.pop();
        },
      ),
    );
  }

  Future<void> _dismiss() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Olvidar ruta', style: TextStyle(color: AppColors.white)),
        content: const Text('No volverás a ver esta ruta en tus notificaciones.',
            style: TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Olvidar', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    final result = await RouteShareService.dismiss(widget.routeId);
    if (!mounted) return;
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
    } else {
      context.pop(); // volver a la lista
      // my_routes_screen recarga al volver gracias al await en onTap
    }
  }

  Future<void> _decline() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('No puedo ir', style: TextStyle(color: AppColors.white)),
        content: const Text('¿Seguro que quieres indicar que no puedes ir?',
            style: TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('No puedo ir', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    final result = await RouteShareService.decline(widget.routeId);
    if (!mounted) return;
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Has indicado que no puedes ir.'),
            backgroundColor: AppColors.grey));
      _loadRoute();
    }
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
        SnackBar(content: Text(result['message'] ?? '¡Te has apuntado!'),
            backgroundColor: Colors.green));
      _loadRoute();
    }
  }

  Future<void> _leave() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Desapuntarse', style: TextStyle(color: AppColors.white)),
        content: const Text('¿Seguro que quieres desapuntarte?',
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
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _refreshWeather() async {
    final lat  = _route?['origin_lat'];
    final lng  = _route?['origin_lng'];
    final date = _route?['departure_date'];
    if (lat == null || lng == null) return;
    setState(() => _refreshingWeather = true);
    final result = await RouteService.refreshWeather(lat, lng, date: date);
    if (!mounted) return;
    setState(() {
      _refreshingWeather = false;
      if (result['weather'] != null) _currentWeather = result['weather'];
    });
    if (result['weather']?['is_forecast'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Previsión meteorológica para la fecha de la ruta'),
        backgroundColor: AppColors.cyan,
        duration: Duration(seconds: 2),
      ));
    }
  }

  void _showShareDialog({bool friendsOnly = false}) {
    final excludeIds = [
      ..._pending.map((p) => p['user_id'] as int),
      ..._confirmed.map((p) => p['user_id'] as int),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ShareBottomSheet(
        onShareFriends: (ids) => _shareWithFriends(ids),
        onSharePublic:  () => _sharePublic(),
        excludeUserIds: friendsOnly ? excludeIds : [],
        friendsOnly:    friendsOnly,
      ),
    );
  }

  Future<void> _shareWithFriends(List<int> friendIds) async {
    setState(() => _publishing = true);
    final result = await RouteShareService.share(
        _route!['id'], visibility: 'friends', friendIds: friendIds);
    if (!mounted) return;
    setState(() => _publishing = false);
    _handleShareResult(result);
  }

  Future<void> _sharePublic() async {
    setState(() => _publishing = true);
    final result = await RouteShareService.share(_route!['id'], visibility: 'public');
    if (!mounted) return;
    setState(() => _publishing = false);
    _handleShareResult(result);
  }

  void _handleShareResult(Map<String, dynamic> result) {
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: AppColors.error));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? '¡Ruta compartida!'),
            backgroundColor: Colors.green));
      setState(() { _route = null; _loading = true; });
      _loadRoute();
    }
  }

  Map<String, dynamic>? get _weather {
    if (_currentWeather != null) return _currentWeather;
    final ws = _route?['weather_summary'];
    if (ws == null) return null;
    if (ws is Map) return Map<String, dynamic>.from(ws['current'] ?? ws);
    return null;
  }

  int? get _fuelRangeKm => _route?['fuel_range_km'] as int?;

  bool get _isFuture =>
      _route?['departure_date'] != null &&
      DateTime.tryParse(_route!['departure_date'])?.isAfter(DateTime.now()) == true;

  bool get _isPast =>
      _route?['departure_date'] != null &&
      DateTime.tryParse(_route!['departure_date'])?.isBefore(DateTime.now()) == true;

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
          IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.grey),
              onPressed: _loadRoute),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _route == null
              ? const Center(
                  child: Text('Ruta no encontrada.',
                      style: TextStyle(color: AppColors.grey)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                    // ── Header ────────────────────────────────────────
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
                            style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        if (_route!['description'] != null) ...[
                          const SizedBox(height: 6),
                          Text(_route!['description'],
                              style: const TextStyle(
                                  color: AppColors.grey, fontSize: 13, height: 1.5)),
                        ],
                        const SizedBox(height: 12),
                        Row(children: [
                          _Chip(Icons.route, '${_route!['distance_km']} km',
                              AppColors.orange),
                          const SizedBox(width: 8),
                          _Chip(
                              Icons.access_time,
                              '${((_route!['duration_minutes'] ?? 0) / 60).toStringAsFixed(1)} h',
                              AppColors.cyan),
                          const SizedBox(width: 8),
                          _Chip(Icons.terrain, _route!['difficulty'] ?? '',
                              AppColors.gold),
                        ]),
                      ]),
                    ),

                    const SizedBox(height: 16),

                    // ── Creador ───────────────────────────────────────
                    if (_route!['owner'] != null) _buildOwner(),

                    // ── Fecha/hora ────────────────────────────────────
                    if (_route!['departure_date'] != null ||
                        _route!['departure_time'] != null)
                      _buildDeparture(),

                    // ── Clima ─────────────────────────────────────────
                    if (_weather != null) _buildWeather(),

                    // ── Autonomía ─────────────────────────────────────
                    if (_fuelRangeKm != null) _buildFuel(),

                    // ── Waypoints ─────────────────────────────────────
                    const Text('Waypoints de la ruta',
                        style: TextStyle(
                            color: AppColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    RouteWaypointsView(
                      route: _route!,
                      weather: _weather,
                      aiSummary: null,
                    ),

                    // ── Participantes (solo si no es privada) ─────────
                    // Amigos: todos los invitados ven todo
                    // Pública: todos ven confirmados, solo creador ve declinados
                    if (_route!['visibility'] == 'friends' ||
                        _route!['visibility'] == 'public') ...[  
                      const SizedBox(height: 8),
                      _buildParticipants(),
                    ],

                    const SizedBox(height: 20),

                    // ── Botón Google Maps ─────────────────────────────
                    ElevatedButton(
                      onPressed: _openMaps,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Abrir en Google Maps',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ]),
                    ),

                    // ── Botones invitado: Apuntarme / No puedo ir / Olvidar ──
                    if (!_isOwner) ...[  
                      const SizedBox(height: 12),
                      if (_isDeclined)
                        // Ya declinó
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.grey.withOpacity(0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.cancel_outlined, color: AppColors.grey, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('Has indicado que no puedes ir',
                                style: TextStyle(color: AppColors.grey))),
                            TextButton(
                              onPressed: _join,
                              child: const Text('Cambiar de idea',
                                  style: TextStyle(color: AppColors.cyan, fontSize: 12)),
                            ),
                          ]),
                        )
                      else
                        Row(children: [
                          // Botón apuntarme (si no está apuntado)
                          if (!_isJoined)
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _joining ? null : _join,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.orange,
                                  minimumSize: const Size(0, 52),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _joining
                                    ? const SizedBox(width: 20, height: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2))
                                    : const Text('¡Apuntarme!',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                              ),
                            ),
                          // Si está apuntado en ruta de amigos → "No puedo ir"
                          if (_isJoined && _route!['visibility'] == 'friends')
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _decline,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 52),
                                  side: const BorderSide(color: AppColors.error),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('No puedo ir',
                                    style: TextStyle(
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          // "No puedo ir" para rutas de amigos no apuntado
                          if (!_isJoined && _route!['visibility'] == 'friends') ...[  
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: _decline,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 52),
                                side: const BorderSide(color: AppColors.grey),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                              ),
                              child: const Text('No puedo ir',
                                  style: TextStyle(
                                      color: AppColors.grey, fontSize: 13)),
                            ),
                          ],
                          // "Olvidar" solo en rutas públicas no apuntado
                          if (!_isJoined && _route!['visibility'] == 'public') ...[  
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: _dismiss,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 52),
                                side: const BorderSide(color: AppColors.grey),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                              ),
                              child: const Text('Olvidar',
                                  style: TextStyle(
                                      color: AppColors.grey, fontSize: 13)),
                            ),
                          ],
                        ]),
                    ],

                    // ── Compartir (previstas privadas propias) ────────
                    if (_isOwner &&
                        _route!['visibility'] == 'private' &&
                        _isFuture) ...[
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _publishing ? null : _showShareDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _publishing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                    Icon(Icons.share_outlined,
                                        color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text('Compartir ruta',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                                  ]),
                      ),
                    ],

                    // ── Repetir (históricas propias) ──────────────────
                    if (_isOwner && _isPast) ...[  
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _repeatRoute,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          side: const BorderSide(color: AppColors.cyan),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.replay,
                                  color: AppColors.cyan, size: 20),
                              SizedBox(width: 8),
                              Text('Repetir esta ruta',
                                  style: TextStyle(
                                      color: AppColors.cyan,
                                      fontWeight: FontWeight.w700)),
                            ]),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ]),
                ),
    );
  }

  Widget _buildOwner() {
    final owner = _route!['owner'];
    final name = '${owner['first_name'] ?? ''} ${owner['last_name'] ?? ''}'.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              avatarUrl: owner['avatar_url'],
              level: owner['experience_level'] ?? 'novato',
              size: 44),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isNotEmpty ? name : owner['nickname'] ?? '',
                style: const TextStyle(
                    color: AppColors.white, fontWeight: FontWeight.w700)),
            if (owner['nickname'] != null)
              Text('@${owner['nickname']}',
                  style: const TextStyle(color: AppColors.orange, fontSize: 12)),
          ])),
          if (_isOwner)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Tú',
                  style: TextStyle(
                      color: AppColors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildDeparture() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cyan.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.event, color: AppColors.cyan, size: 16),
          const SizedBox(width: 8),
          if (_route!['departure_date'] != null)
            Text(_formatDate(_route!['departure_date']),
                style: const TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          if (_route!['departure_time'] != null) ...[
            const SizedBox(width: 12),
            const Icon(Icons.schedule, color: AppColors.cyan, size: 14),
            const SizedBox(width: 4),
            Text('Salida: ${_route!['departure_time']}',
                style: const TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildWeather() {
    final w = _weather!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.greyDark),
        ),
        child: Row(children: [
          const Icon(Icons.wb_sunny_outlined, color: AppColors.gold, size: 24),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${(w['temp'] as num?)?.toStringAsFixed(0)}°C · ${w['description'] ?? ''}',
                style: const TextStyle(
                    color: AppColors.white, fontWeight: FontWeight.w600)),
            Row(children: [
              Text(
                w['is_forecast'] == true ? 'Previsión · ' : 'Ahora · ',
                style: TextStyle(
                  color: w['is_forecast'] == true
                      ? AppColors.cyan
                      : AppColors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                w['humidity'] != null
                    ? 'Viento ${w['wind_speed']} m/s · Humedad ${w['humidity']}%'
                    : 'Viento ${w['wind_speed']} m/s',
                style: const TextStyle(color: AppColors.grey, fontSize: 11),
              ),
            ]),
          ])),
          // Botón refrescar clima (solo en rutas futuras)
          if (_isFuture)
            GestureDetector(
              onTap: _refreshingWeather ? null : _refreshWeather,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                ),
                child: _refreshingWeather
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: AppColors.cyan, strokeWidth: 2))
                    : const Icon(Icons.refresh,
                        color: AppColors.cyan, size: 18),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildFuel() {
    final dist = ((_route!['distance_km'] ?? 0) as num).toDouble();
    final needsFuel = dist > _fuelRangeKm!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: needsFuel
                  ? AppColors.error.withOpacity(0.4)
                  : AppColors.greyDark),
        ),
        child: Row(children: [
          Icon(Icons.local_gas_station,
              color: needsFuel ? AppColors.error : AppColors.grey, size: 22),
          const SizedBox(width: 12),
          Text('Autonomía: $_fuelRangeKm km',
              style: const TextStyle(
                  color: AppColors.white, fontWeight: FontWeight.w600)),
          if (needsFuel) ...[
            const SizedBox(width: 8),
            const Text('Necesitas repostar',
                style: TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildParticipants() {
    final isPublic = _route!['visibility'] == 'public';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Confirmados ───────────────────────────────────────
      Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
        const SizedBox(width: 8),
        Text('Confirmados ($_count)',
            style: const TextStyle(
                color: AppColors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        if (_isOwner &&
            _route!['visibility'] == 'friends' &&
            _pending.isEmpty)
          _inviteButton(),
      ]),
      const SizedBox(height: 12),
      if (_confirmed.isEmpty)
        _emptyBox('Nadie confirmado todavía.')
      else
        ..._confirmed.map((p) => _ParticipantRow(p: p)),

      // ── Pendientes ────────────────────────────────────────
      if (!isPublic && _pending.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.schedule, color: AppColors.gold, size: 18),
          const SizedBox(width: 8),
          Text('Invitados pendientes (${_pending.length})',
              style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_isOwner && _route!['visibility'] == 'friends')
            _inviteButton(label: 'Añadir'),
        ]),
        const SizedBox(height: 12),
        ..._pending.map((p) => _ParticipantRow(p: p)),
      ],

      // ── Declinados ────────────────────────────────────────
      if ((!isPublic || _isOwner) && _declined.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.cancel_outlined, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Text('No pueden ir (${_declined.length})',
              style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        ..._declined.map((p) => _ParticipantRow(p: p)),
      ],

      const SizedBox(height: 8),
    ]);
  }

  Widget _inviteButton({String label = 'Invitar'}) {
    return GestureDetector(
      onTap: () => _showShareDialog(friendsOnly: true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.cyan.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.person_add_outlined, color: AppColors.cyan, size: 14),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: AppColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _emptyBox(String text) => Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.greyDark),
        ),
        child:
            Center(child: Text(text, style: const TextStyle(color: AppColors.grey))),
      );

  String _formatDate(String? date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date);
      const days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
      const months = [
        'ene', 'feb', 'mar', 'abr', 'may', 'jun',
        'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
      ];
      return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return date;
    }
  }
}

// ─── Chip info ────────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(this.icon, this.label, this.color);

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
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─── Fila participante ────────────────────────────────────────────────────────
class _ParticipantRow extends StatelessWidget {
  final Map<String, dynamic> p;
  const _ParticipantRow({required this.p});

  @override
  Widget build(BuildContext context) {
    final name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    final status = p['status'] ?? 'pending';
    final Color badgeColor;
    final String badgeText;
    switch (status) {
      case 'confirmed':
        badgeColor = Colors.green;
        badgeText = '✅ Apuntado';
        break;
      case 'declined':
        badgeColor = AppColors.error;
        badgeText = '❌ No puede ir';
        break;
      default:
        badgeColor = AppColors.gold;
        badgeText = '⏳ Pendiente';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withOpacity(0.25)),
      ),
      child: Row(children: [
        RiderAvatar(
            avatarUrl: p['avatar_url'],
            level: p['experience_level'] ?? 'novato',
            size: 40),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isNotEmpty ? name : p['nickname'] ?? '',
              style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          if (p['nickname'] != null)
            Text('@${p['nickname']}',
                style: const TextStyle(color: AppColors.orange, fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: badgeColor.withOpacity(0.3)),
          ),
          child: Text(badgeText,
              style: TextStyle(
                  color: badgeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─── Bottom sheet compartir ───────────────────────────────────────────────────
class _ShareBottomSheet extends StatefulWidget {
  final Function(List<int>) onShareFriends;
  final VoidCallback onSharePublic;
  final List<int> excludeUserIds;
  final bool friendsOnly;

  const _ShareBottomSheet({
    required this.onShareFriends,
    required this.onSharePublic,
    this.excludeUserIds = const [],
    this.friendsOnly = false,
  });

  @override
  State<_ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<_ShareBottomSheet> {
  int _step = 0;
  List<Map<String, dynamic>> _friends = [];
  Set<int> _selected = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.friendsOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFriends());
    }
  }

  Future<void> _loadFriends() async {
    setState(() => _loading = true);
    final result = await FriendshipService.getFriends();
    if (!mounted) return;
    setState(() {
      _friends = List<Map<String, dynamic>>.from(result['friends'] ?? [])
          .where((f) => !widget.excludeUserIds.contains(f['user_id']))
          .toList();
      _loading = false;
      _step = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.greyDark,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          if (_step == 0) ..._buildMenu(),
          if (_step == 1) ..._buildFriendSelector(),
        ]),
      ),
    );
  }

  List<Widget> _buildMenu() => [
        const Text('¿Cómo quieres compartir esta ruta?',
            style: TextStyle(
                color: AppColors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        _OptionTile(
          icon: Icons.people_outlined,
          color: AppColors.cyan,
          title: 'Con amigos',
          desc: 'Elige qué amigos pueden verla y apuntarse.',
          onTap: _loadFriends,
          trailing: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: AppColors.cyan, strokeWidth: 2))
              : const Icon(Icons.arrow_forward_ios,
                  color: AppColors.cyan, size: 14),
        ),
        const SizedBox(height: 12),
        _OptionTile(
          icon: Icons.public,
          color: AppColors.orange,
          title: 'Pública (zona)',
          desc: 'Cualquier motero de tu zona puede verla y apuntarse.',
          onTap: () {
            Navigator.pop(context);
            widget.onSharePublic();
          },
        ),
        const SizedBox(height: 8),
      ];

  List<Widget> _buildFriendSelector() => [
        Row(children: [
          if (!widget.friendsOnly)
            GestureDetector(
              onTap: () => setState(() => _step = 0),
              child: const Icon(Icons.arrow_back_ios,
                  color: AppColors.grey, size: 18),
            ),
          const SizedBox(width: 8),
          const Text('Selecciona amigos',
              style: TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_friends.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                if (_selected.length == _friends.length)
                  _selected.clear();
                else
                  _selected =
                      _friends.map((f) => f['user_id'] as int).toSet();
              }),
              child: Text(
                  _selected.length == _friends.length
                      ? 'Quitar todos'
                      : 'Todos',
                  style:
                      const TextStyle(color: AppColors.grey, fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 16),
        if (_friends.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.excludeUserIds.isNotEmpty
                  ? 'Todos tus amigos ya han sido invitados.'
                  : 'No tienes amigos aún.',
              style: const TextStyle(color: AppColors.grey),
            ),
          )
        else
          SizedBox(
            height: 280,
            child: ListView.builder(
              itemCount: _friends.length,
              itemBuilder: (ctx, i) {
                final f = _friends[i];
                final uid = f['user_id'] as int;
                final chk = _selected.contains(uid);
                final name =
                    '${f['first_name'] ?? ''} ${f['last_name'] ?? ''}'
                        .trim();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: RiderAvatar(
                      avatarUrl: f['avatar_url'],
                      level: f['experience_level'] ?? 'novato',
                      size: 44),
                  title: Text(name.isNotEmpty ? name : f['nickname'] ?? '',
                      style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600)),
                  subtitle: f['nickname'] != null
                      ? Text('@${f['nickname']}',
                          style: const TextStyle(
                              color: AppColors.orange, fontSize: 12))
                      : null,
                  trailing: Checkbox(
                    value: chk,
                    activeColor: AppColors.cyan,
                    side: const BorderSide(color: AppColors.grey),
                    onChanged: (_) => setState(() {
                      if (chk)
                        _selected.remove(uid);
                      else
                        _selected.add(uid);
                    }),
                  ),
                  onTap: () => setState(() {
                    if (chk)
                      _selected.remove(uid);
                    else
                      _selected.add(uid);
                  }),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final ids = _selected.toList();
                  Navigator.pop(context);
                  widget.onShareFriends(ids);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyan,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            _selected.isEmpty
                ? 'Selecciona al menos un amigo'
                : 'Compartir con ${_selected.length} amigo${_selected.length > 1 ? 's' : ''}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
      ];
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final VoidCallback onTap;
  final Widget? trailing;

  const _OptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text(title,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(height: 3),
            Text(desc,
                style: const TextStyle(
                    color: AppColors.grey, fontSize: 12, height: 1.3)),
          ])),
          const SizedBox(width: 8),
          trailing ?? Icon(Icons.arrow_forward_ios, color: color, size: 14),
        ]),
      ),
    );
  }
}

// ─── Bottom sheet para repetir ruta (con opción guardar/compartir) ───────────────────────
class _RepeatShareBottomSheet extends StatefulWidget {
  final VoidCallback onSaveOnly;
  final Function(List<int>) onShareFriends;
  final VoidCallback onSharePublic;
  const _RepeatShareBottomSheet({
    required this.onSaveOnly,
    required this.onShareFriends,
    required this.onSharePublic,
  });

  @override
  State<_RepeatShareBottomSheet> createState() => _RepeatShareBottomSheetState();
}

class _RepeatShareBottomSheetState extends State<_RepeatShareBottomSheet> {
  int _step = 0;
  List<Map<String, dynamic>> _friends = [];
  bool _loading = false;
  Set<int> _selected = {};

  Future<void> _loadFriends() async {
    setState(() => _loading = true);
    final result = await FriendshipService.getFriends();
    if (!mounted) return;
    setState(() {
      _friends = List<Map<String, dynamic>>.from(result['friends'] ?? []);
      _loading = false;
      _step = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.greyDark, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            if (_step == 0) ..._buildMenu(),
            if (_step == 1) ..._buildFriendSelector(),
          ]),
      ),
    );
  }

  List<Widget> _buildMenu() => [
    const Text('¿Qué quieres hacer con esta ruta?',
        style: TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
    const SizedBox(height: 20),
    _OptionTile(
      icon: Icons.lock_outline, color: AppColors.grey,
      title: 'Guardar para mí', desc: 'Solo tú puedes verla. Aparecerá en Mis Rutas.',
      onTap: () { Navigator.pop(context); widget.onSaveOnly(); },
    ),
    const SizedBox(height: 12),
    _OptionTile(
      icon: Icons.people_outlined, color: AppColors.cyan,
      title: 'Compartir con amigos', desc: 'Elige qué amigos pueden verla y apuntarse.',
      onTap: _loadFriends,
      trailing: _loading
          ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2))
          : const Icon(Icons.arrow_forward_ios, color: AppColors.cyan, size: 14),
    ),
    const SizedBox(height: 12),
    _OptionTile(
      icon: Icons.public, color: AppColors.orange,
      title: 'Publicar para todos', desc: 'Cualquier motero de tu zona puede verla y apuntarse.',
      onTap: () { Navigator.pop(context); widget.onSharePublic(); },
    ),
    const SizedBox(height: 8),
  ];

  List<Widget> _buildFriendSelector() => [
    Row(children: [
      GestureDetector(
        onTap: () => setState(() => _step = 0),
        child: const Icon(Icons.arrow_back_ios, color: AppColors.grey, size: 18)),
      const SizedBox(width: 8),
      const Text('Selecciona amigos',
          style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      const Spacer(),
      if (_friends.isNotEmpty)
        GestureDetector(
          onTap: () => setState(() {
            if (_selected.length == _friends.length) _selected.clear();
            else _selected = _friends.map((f) => f['user_id'] as int).toSet();
          }),
          child: Text(_selected.length == _friends.length ? 'Quitar todos' : 'Todos',
              style: const TextStyle(color: AppColors.grey, fontSize: 12)),
        ),
    ]),
    const SizedBox(height: 16),
    if (_friends.isEmpty)
      const Padding(padding: EdgeInsets.all(16),
          child: Text('No tienes amigos aún.', style: TextStyle(color: AppColors.grey)))
    else
      SizedBox(
        height: 260,
        child: ListView.builder(
          itemCount: _friends.length,
          itemBuilder: (ctx, i) {
            final f = _friends[i];
            final uid = f['user_id'] as int;
            final chk = _selected.contains(uid);
            final name = '${f['first_name'] ?? ''} ${f['last_name'] ?? ''}'.trim();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: RiderAvatar(avatarUrl: f['avatar_url'],
                  level: f['experience_level'] ?? 'novato', size: 44),
              title: Text(name.isNotEmpty ? name : f['nickname'] ?? '',
                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
              subtitle: f['nickname'] != null
                  ? Text('@${f['nickname']}', style: const TextStyle(color: AppColors.orange, fontSize: 12))
                  : null,
              trailing: Checkbox(
                value: chk, activeColor: AppColors.cyan,
                side: const BorderSide(color: AppColors.grey),
                onChanged: (_) => setState(() {
                  if (chk) _selected.remove(uid); else _selected.add(uid);
                }),
              ),
              onTap: () => setState(() {
                if (chk) _selected.remove(uid); else _selected.add(uid);
              }),
            );
          },
        ),
      ),
    const SizedBox(height: 12),
    ElevatedButton(
      onPressed: _selected.isEmpty ? null : () {
        final ids = _selected.toList();
        Navigator.pop(context);
        widget.onShareFriends(ids);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.cyan,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        _selected.isEmpty ? 'Selecciona al menos un amigo'
            : 'Compartir con ${_selected.length} amigo${_selected.length > 1 ? 's' : ''}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ),
    const SizedBox(height: 8),
  ];
}

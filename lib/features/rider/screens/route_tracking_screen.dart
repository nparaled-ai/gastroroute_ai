import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/route_tracking_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/route_tracking_service.dart';

/// Pantalla "Ruta en curso".
///
/// Muestra km, tiempo y velocidad media en vivo, y detecta la llegada al
/// destino para ofrecer finalizar. El destino siempre es un punto fijo
/// guardado en la ruta, sea circular o con destino.
class RouteTrackingScreen extends StatefulWidget {
  final Map<String, dynamic> tracking;

  const RouteTrackingScreen({super.key, required this.tracking});

  @override
  State<RouteTrackingScreen> createState() => _RouteTrackingScreenState();
}

class _RouteTrackingScreenState extends State<RouteTrackingScreen> {
  /// Radio alrededor del destino para considerar que se ha llegado.
  static const double _arrivalRadiusM = 500;

  /// Tiempo dentro del radio antes de preguntar. Evita el falso positivo de
  /// pasar cerca del destino sin haber terminado.
  static const Duration _arrivalDwell = Duration(minutes: 3);

  /// En rutas circulares el origen es el destino, así que además se exige
  /// haber consumido este porcentaje del tiempo estimado.
  static const double _circularMinProgress = 0.8;

  late final StreamSubscription<TrackingState> _sub;
  Timer? _ticker;

  TrackingState _state = const TrackingState();
  DateTime? _insideSince;
  bool _arrivalAsked = false;
  bool _finishing = false;

  Map<String, dynamic> get _route =>
      Map<String, dynamic>.from(widget.tracking['route'] ?? {});

  @override
  void initState() {
    super.initState();
    _state = RouteTrackingManager.instance.state;

    _sub = RouteTrackingManager.instance.stream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      _checkArrival(s);
    });

    // El tiempo transcurrido cambia aunque no lleguen posiciones nuevas.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Detección de llegada
  // ---------------------------------------------------------------------

  void _checkArrival(TrackingState s) {
    if (_arrivalAsked || _finishing || s.lastPoint == null) return;

    final destLat = (_route['destination_lat'] as num?)?.toDouble();
    final destLng = (_route['destination_lng'] as num?)?.toDouble();
    if (destLat == null || destLng == null) return;

    final distance = RouteTrackingManager.haversine(
      s.lastPoint![0].toDouble(), s.lastPoint![1].toDouble(),
      destLat, destLng,
    );

    if (distance > _arrivalRadiusM) {
      _insideSince = null;
      return;
    }

    // En circular, el destino coincide con el origen: sin este freno saltaría
    // nada más arrancar.
    if (_route['route_type'] == 'circular' && !_pastCircularThreshold()) {
      return;
    }

    _insideSince ??= DateTime.now();

    if (DateTime.now().difference(_insideSince!) >= _arrivalDwell) {
      _arrivalAsked = true;
      _askArrival();
    }
  }

  bool _pastCircularThreshold() {
    final estimated = (_route['duration_minutes'] as num?)?.toInt();
    if (estimated == null || estimated <= 0) return true;

    final elapsedMin = _state.elapsed.inMinutes;
    return elapsedMin >= estimated * _circularMinProgress;
  }

  Future<void> _askArrival() async {
    final finish = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('tracking.arrival_title'.tr(),
            style: const TextStyle(color: AppColors.white)),
        content: Text('tracking.arrival_body'.tr(),
            style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('tracking.keep_going'.tr(),
                style: const TextStyle(color: AppColors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('tracking.finish'.tr()),
          ),
        ],
      ),
    );

    if (finish == true) {
      await _finish();
    } else {
      // Si decide seguir, no se vuelve a preguntar hasta que salga del radio.
      _insideSince = null;
      _arrivalAsked = false;
    }
  }

  // ---------------------------------------------------------------------
  // Finalizar / descartar
  // ---------------------------------------------------------------------

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    final trackingId = widget.tracking['id'] as int;
    final track = await RouteTrackingManager.instance.stop();

    if (track.length < 2) {
      await RouteTrackingService.discard(trackingId);
      if (!mounted) return;
      _showMessage('tracking.too_short'.tr());
      context.go('/rider/home');
      return;
    }

    final result = await RouteTrackingService.finish(trackingId, track);
    if (!mounted) return;

    if (result['error'] != null) {
      setState(() => _finishing = false);
      _showMessage(result['error']);
      return;
    }

    // Al resumen, que es donde se ven los km reales y los POIs detectados.
    context.go('/rider/summary', extra: result['tracking']);
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('tracking.discard_title'.tr(),
            style: const TextStyle(color: AppColors.white)),
        content: Text('tracking.discard_body'.tr(),
            style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr(),
                style: const TextStyle(color: AppColors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('tracking.discard'.tr()),
          ),
        ],
      ),
    );

    if (discard != true) return;

    await RouteTrackingManager.instance.stop();
    await RouteTrackingService.discard(widget.tracking['id'] as int);

    if (!mounted) return;
    context.go('/rider/home');
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.surface),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Salir con "atrás" no debe cortar el tracking: sigue rodando.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text('tracking.in_progress'.tr(),
              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.grey),
              tooltip: 'tracking.discard'.tr(),
              onPressed: _finishing ? null : _confirmDiscard,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_route['title'] ?? '',
                  style: const TextStyle(
                      color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.circle, color: AppColors.orange, size: 10),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('tracking.recording'.tr(),
                      style: const TextStyle(color: AppColors.orange, fontSize: 12)),
                ),
              ]),

              const SizedBox(height: 28),

              // Kilómetros: el dato protagonista
              Center(
                child: Column(children: [
                  Text(_state.distanceKm.toStringAsFixed(1),
                      style: const TextStyle(
                          color: AppColors.orange, fontSize: 64, fontWeight: FontWeight.w700, height: 1)),
                  Text('tracking.km'.tr(),
                      style: const TextStyle(color: AppColors.grey, fontSize: 14)),
                ]),
              ),

              const SizedBox(height: 28),

              Row(children: [
                _Stat(
                  label: 'tracking.time'.tr(),
                  value: _formatDuration(_state.elapsed),
                ),
                const SizedBox(width: 12),
                _Stat(
                  label: 'tracking.avg_speed'.tr(),
                  value: '${_state.avgSpeedKmh.toStringAsFixed(0)} km/h',
                ),
                const SizedBox(width: 12),
                _Stat(
                  label: 'tracking.points'.tr(),
                  value: '${_state.pointsCount}',
                ),
              ]),

              const SizedBox(height: 20),

              if (_state.pointsCount == 0)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.greyDark),
                  ),
                  child: Row(children: [
                    const Icon(Icons.satellite_alt, color: AppColors.grey, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('tracking.waiting_gps'.tr(),
                          style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4)),
                    ),
                  ]),
                ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _finishing ? null : _finish,
                  icon: _finishing
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                      : const Icon(Icons.flag),
                  label: Text('tracking.finish_route'.tr()),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    backgroundColor: AppColors.orange,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Text('tracking.background_hint'.tr(),
                  style: const TextStyle(color: AppColors.grey, fontSize: 11, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.greyDark),
        ),
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 11)),
        ]),
      ),
    );
  }
}

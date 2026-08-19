
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/route_map_image.dart';
import '../providers/route_tracking_service.dart';
import '../providers/achievement_service.dart';

/// Resumen de ruta, al finalizar el tracking.
///
/// Muestra los kilómetros reales, el tiempo, el mapa con el recorrido y los
/// POIs detectados. Deliberadamente NO menciona los logros desbloqueados: la
/// pantalla de celebración es el momento del descubrimiento, y adelantarlo
/// aquí lo dejaría sin efecto.
class RouteSummaryScreen extends StatefulWidget {
  final Map<String, dynamic> tracking;

  /// true cuando se abre desde el historial: entonces es solo consulta, no
  /// encadena con la celebración y el botón vuelve atrás en vez de ir a inicio.
  final bool fromHistory;

  const RouteSummaryScreen({
    super.key,
    required this.tracking,
    this.fromHistory = false,
  });

  @override
  State<RouteSummaryScreen> createState() => _RouteSummaryScreenState();
}

class _RouteSummaryScreenState extends State<RouteSummaryScreen> {

  late List<Map<String, dynamic>> _visited;
  late List<Map<String, dynamic>> _suggested;
  final Set<int> _working = {};

  int get _trackingId => widget.tracking['id'] as int;

  Map<String, dynamic> get _route =>
      Map<String, dynamic>.from(widget.tracking['route'] ?? {});

  @override
  void initState() {
    super.initState();

    _visited = List<Map<String, dynamic>>.from(
        (widget.tracking['visited_pois'] as List?) ?? []);
    _suggested = List<Map<String, dynamic>>.from(
        (widget.tracking['suggested_pois'] as List?) ?? []);

  }


  /// Mueve un POI de sugeridos a visitados.
  Future<void> _addPoi(Map<String, dynamic> poi) async {
    final poiId = poi['poi_id'] as int;
    setState(() => _working.add(poiId));

    final visit = await RouteTrackingService.confirmPoi(_trackingId, poiId);
    if (!mounted) return;

    setState(() {
      _working.remove(poiId);
      if (visit != null) {
        _suggested.removeWhere((p) => p['poi_id'] == poiId);
        _visited.add(visit);
      }
    });
  }

  /// Deshace un POI marcado a mano.
  Future<void> _removePoi(Map<String, dynamic> visit) async {
    final poiId = visit['poi_id'] as int;
    setState(() => _working.add(poiId));

    final ok = await RouteTrackingService.removePoi(_trackingId, poiId);
    if (!mounted) return;

    setState(() {
      _working.remove(poiId);
      if (ok) {
        _visited.removeWhere((p) => p['poi_id'] == poiId);
        _suggested.add(visit);
      }
    });
  }

  /// Al cerrar el resumen, encadena con la celebración si esta ruta ha
  /// desbloqueado logros. El resumen no los menciona a propósito: la
  /// celebración es el momento del descubrimiento.
  Future<void> _finish() async {
    // Desde el historial es una consulta: se vuelve por donde se vino.
    if (widget.fromHistory) {
      context.canPop() ? context.pop() : context.go('/rider/home');
      return;
    }

    final pending = await AchievementService.pending();
    if (!mounted) return;

    if (pending.isEmpty) {
      context.go('/rider/home');
      return;
    }

    context.go('/rider/celebration', extra: pending);
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    final km = (widget.tracking['distance_km'] as num?)?.toDouble() ?? 0;
    final seconds = (widget.tracking['duration_seconds'] as num?)?.toInt() ?? 0;
    final speed = (widget.tracking['avg_speed_kmh'] as num?)?.toDouble() ?? 0;
    final gaps = (widget.tracking['gps_gaps'] as num?)?.toInt() ?? 0;
    final rejected = widget.tracking['rejected_reason'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text('summary.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_route['title'] ?? '',
                style: const TextStyle(
                    color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w700)),

            const SizedBox(height: 20),

            // Kilómetros reales, el dato protagonista
            Center(
              child: Column(children: [
                Text(km.toStringAsFixed(1),
                    style: const TextStyle(
                        color: AppColors.orange,
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        height: 1)),
                Text('summary.km_real'.tr(),
                    style: const TextStyle(color: AppColors.grey, fontSize: 13)),
              ]),
            ),

            const SizedBox(height: 24),

            Row(children: [
              _Stat(label: 'summary.time'.tr(), value: _formatDuration(seconds)),
              const SizedBox(width: 12),
              _Stat(label: 'summary.avg_speed'.tr(), value: '${speed.toStringAsFixed(0)} km/h'),
            ]),

            if (rejected != null) ...[
              const SizedBox(height: 16),
              _Notice(
                icon: Icons.report_problem_outlined,
                color: AppColors.error,
                text: 'summary.rejected'.tr(namedArgs: {'reason': rejected.toString()}),
              ),
            ],

            if (gaps > 0) ...[
              const SizedBox(height: 12),
              _Notice(
                icon: Icons.signal_cellular_connected_no_internet_0_bar,
                color: AppColors.grey,
                text: 'summary.gps_gaps'.plural(gaps),
              ),
            ],

            const SizedBox(height: 24),

            // Mapa con el recorrido real grabado
            RouteMapImage(
              title: 'summary.route_map'.tr(),
              loader: () => RouteTrackingService.mapImage(_trackingId),
            ),

            const SizedBox(height: 24),

            // POIs detectados
            Text('summary.visited_pois'.tr(),
                style: const TextStyle(
                    color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('summary.visited_pois_desc'.tr(),
                style: const TextStyle(color: AppColors.grey, fontSize: 11, height: 1.4)),
            const SizedBox(height: 10),

            if (_visited.isEmpty)
              _Notice(
                icon: Icons.place_outlined,
                color: AppColors.grey,
                text: 'summary.no_pois'.tr(),
              )
            else
              // map_label lo calcula el servidor, el mismo código que dibuja
              // los marcadores. Viene a null en los POIs que el mapa omite por
              // caer encima de otro: esos salen en la lista pero sin número.
              ..._visited.map((poi) => _PoiTile(
                    poi: poi,
                    visited: true,
                    label: poi['map_label'] as String?,
                    busy: _working.contains(poi['poi_id']),
                    // Solo se puede deshacer lo marcado a mano: lo detectado
                    // por GPS no se toca.
                    onAction: poi['confirmed_manually'] == true
                        ? () => _removePoi(poi)
                        : null,
                  )),

            // POIs sugeridos
            if (_suggested.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('summary.suggested_pois'.tr(),
                  style: const TextStyle(
                      color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('summary.suggested_pois_desc'.tr(),
                  style: const TextStyle(color: AppColors.grey, fontSize: 11, height: 1.4)),
              const SizedBox(height: 10),
              ..._suggested.map((poi) => _PoiTile(
                    poi: poi,
                    visited: false,
                    busy: _working.contains(poi['poi_id']),
                    onAction: () => _addPoi(poi),
                  )),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),

      // El botón va fijo abajo, fuera del scroll: así no hay que bajar hasta
      // el final para terminar, y SafeArea evita que la barra de navegación
      // de Android se lo coma.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _finish,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 52),
              backgroundColor: AppColors.orange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('summary.done'.tr(),
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.greyDark),
        ),
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 11)),
        ]),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(color: color, fontSize: 12, height: 1.4)),
        ),
      ]),
    );
  }
}

class _PoiTile extends StatelessWidget {
  final Map<String, dynamic> poi;
  final bool visited;
  final bool busy;
  final String? label;
  final VoidCallback? onAction;

  const _PoiTile({
    required this.poi,
    required this.visited,
    required this.busy,
    this.label,
    this.onAction,
  });

  static const _icons = {
    'puerto_montana':    Icons.terrain,
    'mirador':           Icons.visibility_outlined,
    'monumento':         Icons.account_balance_outlined,
    'monumento_natural': Icons.landscape_outlined,
    'parque_natural':    Icons.park_outlined,
    'desfiladero':       Icons.filter_hdr,
    'embalse':           Icons.water_outlined,
    'pueblo_historico':  Icons.location_city_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final color = visited ? AppColors.orange : AppColors.grey;
    final distance = (poi['closest_distance_m'] as num?)?.toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: visited ? AppColors.orange.withValues(alpha: 0.4) : AppColors.greyDark),
      ),
      child: Row(children: [
        // Número que casa con el marcador del mapa
        if (label != null) ...[
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.cyan,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(label!,
                style: const TextStyle(
                    color: AppColors.background,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
        ],
        Icon(_icons[poi['category']] ?? Icons.place_outlined, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(poi['name']?.toString() ?? '',
                style: const TextStyle(
                    color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              [
                if (poi['region'] != null) poi['region'].toString(),
                if (distance != null) 'summary.at_distance'.tr(namedArgs: {'m': '$distance'}),
              ].join(' · '),
              style: const TextStyle(color: AppColors.grey, fontSize: 11),
            ),
          ]),
        ),
        if (busy)
          const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange))
        else if (onAction != null)
          IconButton(
            icon: Icon(visited ? Icons.close : Icons.add_circle_outline, color: color, size: 20),
            onPressed: onAction,
            tooltip: visited ? 'summary.remove'.tr() : 'summary.add'.tr(),
          )
        else
          const Icon(Icons.check_circle, color: AppColors.orange, size: 20),
      ]),
    );
  }
}

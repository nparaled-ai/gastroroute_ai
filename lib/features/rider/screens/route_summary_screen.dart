
import 'package:gastroroute_ai/core/labels.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/route_map_image.dart';
import '../../../widgets/route_publication_block.dart';
import '../providers/route_tracking_service.dart';
import '../providers/achievement_service.dart';
import '../providers/route_service.dart';

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

  /// Las tarjetas de valorar, para poder enviar lo marcado al pulsar «Listo».
  final Map<String, GlobalKey<_EateryRatingCardState>> _ratingKeys = {};

  /// Lo que ya valoró en esta ruta, por sitio.
  Map<int, Map<String, dynamic>> get _myRatings => {
        for (final r in ((widget.tracking['my_ratings'] as List?) ?? const []))
          (r['eatery_id'] as num).toInt(): Map<String, dynamic>.from(r as Map),
      };

  /// Los sitios de comer que ya valoró en esta ruta.
  Set<int> get _ratedIds => ((widget.tracking['rated_eatery_ids'] as List?) ?? const [])
      .map((e) => (e as num).toInt())
      .toSet();

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
    for (final k in _ratingKeys.values) {
      await k.currentState?.sendIfPending();
    }
    if (!mounted) return;

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

    // Tiempo rodando de verdad, sin las paradas. Es lo que sustituye al botón
    // de pausa: el motero no pulsa nada y el servidor separa los dos tiempos.
    //
    // Puede venir null en trackings anteriores a este campo: en ese caso se
    // enseña solo el tiempo total, en vez de un "0h 00m" que parecería un error.
    final movingSeconds = (widget.tracking['moving_seconds'] as num?)?.toInt();
    final speed = (widget.tracking['avg_speed_kmh'] as num?)?.toDouble() ?? 0;

    // La media se calcula sobre el tiempo EN MOVIMIENTO, igual que en la
    // pestaña de rodadas: con el tiempo total, una parada larga para comer
    // la hunde y deja de contar cómo se rodó. El tiempo parado no se esconde,
    // se ve restando "En movimiento" del "Tiempo" que hay al lado.
    //
    // Si el tracking es anterior a moving_seconds se usa la media que ya
    // calculó el servidor, para no inventar un número distinto.
    final effectiveSeconds = movingSeconds ?? seconds;
    final speedKmh =
        effectiveSeconds > 0 ? km / (effectiveSeconds / 3600) : speed;

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
                Text(dec1(context, km),
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
              if (movingSeconds != null) ...[
                _Stat(
                  label: 'summary.moving_time'.tr(),
                  value: _formatDuration(movingSeconds),
                ),
                const SizedBox(width: 12),
              ],
              _Stat(
                  label: 'summary.avg_speed'.tr(),
                  value: '${speedKmh.toStringAsFixed(0)} km/h'),
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

            // La rodada no llega al 60 % de los km: no se puede publicar y se explica por que
            if (rejected == null && _route['publish_blocked_short'] == true) ...[
              const SizedBox(height: 16),
              _Notice(
                icon: Icons.landscape_outlined,
                color: AppColors.grey,
                text: 'catalog.publish_need_60'.tr(),
              ),
            ],

            // Publicar la ruta en Rutas moteras: el momento natural es al acabar de rodarla
            if (rejected == null && _route['can_publish'] == true) ...[
              const SizedBox(height: 20),
              RoutePublicationBlock(
                routeId: (_route['id'] as num).toInt(),
                status: _route['publication_status'] as String?,
                reason: _route['publication_reason'] as String?,
                catalogRouteId: (_route['catalog_route_id'] as num?)?.toInt(),
              ),
            ],

            const SizedBox(height: 24),

            // Mapa con el recorrido real grabado
            // Sin puntos GPS grabados (p. ej. se perdió la señal todo el rato) no hay nada que dibujar:
            // se dice claramente en vez de enseñar un error de carga.
            if (((widget.tracking['points_count'] as num?)?.toInt() ?? 2) < 2) ...[
              Text('summary.route_map'.tr(),
                  style: const TextStyle(
                      color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _Notice(
                icon: Icons.location_off_outlined,
                color: AppColors.grey,
                text: 'summary.no_track'.tr(),
              ),
            ] else
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

            // ¿Qué tal se comió? (norma 21): solo al terminar, no al consultar el historial.
            // También desde el historial, mientras no lo haya valorado ya.
            // Si ya lo valoró, se enseña lo que puso, sin poder tocarlo.
            for (final campo in const ['lunch_stop', 'dinner_stop'])
              if (_route[campo] is Map &&
                  _route[campo]['eatery'] is Map &&
                  _ratedIds.contains((_route[campo]['eatery']['id'] as num).toInt())) ...[
                const SizedBox(height: 24),
                _EateryRatedCard(
                  eatery: Map<String, dynamic>.from(_route[campo]['eatery'] as Map),
                  rating: _myRatings[(_route[campo]['eatery']['id'] as num).toInt()] ?? const {},
                ),
              ],
            for (final campo in const ['lunch_stop', 'dinner_stop'])
              if (_route[campo] is Map &&
                  _route[campo]['eatery'] is Map &&
                  !_ratedIds.contains((_route[campo]['eatery']['id'] as num).toInt())) ...[
                  const SizedBox(height: 24),
                  _EateryRatingCard(
                    key: _ratingKeys.putIfAbsent(
                        campo, () => GlobalKey<_EateryRatingCardState>()),
                    routeId: (_route['id'] as num).toInt(),
                    eatery: Map<String, dynamic>.from(_route[campo]['eatery'] as Map),
                    title: campo == 'lunch_stop'
                        ? 'route_result.lunch_stop'.tr()
                        : 'route_result.dinner_stop'.tr(),
                  ),
                ],

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


/// La pregunta de la norma 21 al cerrar la ruta: qué tal se comió, si se pudo
/// aparcar la moto, y si el sitio ya no existe. Todo opcional: se manda lo que
/// haya contestado.
class _EateryRatingCard extends StatefulWidget {
  final int routeId;
  final Map<String, dynamic> eatery;
  final String title;

  const _EateryRatingCard({
    super.key,
    required this.routeId,
    required this.eatery,
    required this.title,
  });

  @override
  State<_EateryRatingCard> createState() => _EateryRatingCardState();
}

class _EateryRatingCardState extends State<_EateryRatingCard> {
  int _stars = 0;
  bool? _parked;
  bool _closed = false;
  bool _sending = false;
  bool _sent = false;
  bool _pending = false;
  final _comment = TextEditingController();

  /// Al pulsar «Listo» se envía lo que haya marcado aunque no haya pulsado
  /// «Enviar»: antes se perdía y la tarjeta volvía a salir.
  Future<void> sendIfPending() async {
    if (_hasAnswer && !_sent && !_sending) await _send();
  }

  bool get _hasAnswer =>
      _stars > 0 || _parked != null || _closed || _comment.text.trim().isNotEmpty;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final result = await RouteService.rateEatery(
      (widget.eatery['id'] as num).toInt(),
      widget.routeId,
      stars: _stars > 0 ? _stars : null,
      parked: _parked,
      closed: _closed,
      comment: _comment.text,
    );
    if (!mounted) return;
    final ok = result != null;
    setState(() {
      _sending = false;
      _sent = ok;
      _pending = result == 'pending';
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('rating.error'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyDark),
      ),
      child: _sent
          ? Row(children: [
              const Icon(Icons.check_circle_outline, color: AppColors.cyan, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text((_pending ? 'rating.thanks_pending' : 'rating.thanks').tr(),
                    style: const TextStyle(color: AppColors.white, fontSize: 13)),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('rating.title'.tr(namedArgs: {'name': '${widget.eatery['name']}'}),
                  style: const TextStyle(
                      color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(widget.title,
                  style: const TextStyle(color: AppColors.grey, fontSize: 11)),
              const SizedBox(height: 10),
              Row(children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: _closed ? null : () => setState(() => _stars = i),
                    icon: Icon(
                      i <= _stars ? Icons.star : Icons.star_border,
                      color: AppColors.gold,
                      size: 30,
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Text('rating.parking'.tr(),
                  style: const TextStyle(color: AppColors.white, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: Text('rating.yes'.tr()),
                  selected: _parked == true,
                  onSelected: (v) => setState(() => _parked = v ? true : null),
                ),
                ChoiceChip(
                  label: Text('rating.no'.tr()),
                  selected: _parked == false,
                  onSelected: (v) => setState(() => _parked = v ? false : null),
                ),
              ]),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _closed,
                onChanged: (v) => setState(() {
                  _closed = v ?? false;
                  if (_closed) _stars = 0;
                }),
                title: Text('rating.closed'.tr(),
                    style: const TextStyle(color: AppColors.white, fontSize: 13)),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _comment,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(color: AppColors.white, fontSize: 13),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'rating.comment_hint'.tr(),
                  hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
                  isDense: true,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: _hasAnswer && !_sending ? _send : null,
                  child: _sending
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('rating.send'.tr()),
                ),
              ),
            ]),
    );
  }
}


/// Lo que ya valoró de un sitio de comer, sin poder tocarlo, con el estado de su
/// comentario (pendiente de revisar, publicado o no publicado).
class _EateryRatedCard extends StatelessWidget {
  final Map<String, dynamic> eatery;
  final Map<String, dynamic> rating;

  const _EateryRatedCard({required this.eatery, required this.rating});

  @override
  Widget build(BuildContext context) {
    final stars = (rating['stars'] as num?)?.toInt() ?? 0;
    final parked = rating['parked'];
    final comment = '${rating['comment'] ?? ''}'.trim();
    final status = rating['status'] as String?;

    final (Color color, String statusKey) = switch (status) {
      'approved' => (const Color(0xFF7BE0A1), 'rating.status_approved'),
      'rejected' => (const Color(0xFFFF9A9A), 'rating.status_rejected'),
      'annulled' => (const Color(0xFFFF9A9A), 'rating.status_annulled'),
      _ => (const Color(0xFFFFD77A), 'rating.status_pending'),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyDark),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.check_circle_outline, color: AppColors.cyan, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('rating.your_rating'.tr(namedArgs: {'name': '${eatery['name']}'}),
                style: const TextStyle(
                    color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (stars > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 1; i <= 5; i++)
              Icon(i <= stars ? Icons.star : Icons.star_border, color: AppColors.gold, size: 22),
          ]),
        ],
        if (parked != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.two_wheeler, color: AppColors.cyan, size: 16),
            const SizedBox(width: 6),
            Text((parked == true ? 'rating.parked_yes' : 'rating.parked_no').tr(),
                style: const TextStyle(color: AppColors.white, fontSize: 13)),
          ]),
        ],
        if (rating['closed'] == true) ...[
          const SizedBox(height: 8),
          Text('rating.reported_closed'.tr(),
              style: const TextStyle(color: AppColors.white, fontSize: 13)),
        ],
        if (status == 'annulled') ...[
          const SizedBox(height: 10),
          Text('rating.status_annulled'.tr(),
              style: const TextStyle(
                  color: Color(0xFFFF9A9A), fontSize: 12, fontWeight: FontWeight.w700)),
        ],
        if (comment.isNotEmpty && status != 'annulled') ...[
          const SizedBox(height: 10),
          Text('“$comment”',
              style: const TextStyle(
                  color: AppColors.white, fontSize: 13, height: 1.4, fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Text(statusKey.tr(),
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }
}

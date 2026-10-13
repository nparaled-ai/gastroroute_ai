import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
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
  late final StreamSubscription<TrackingState> _sub;
  Timer? _ticker;

  TrackingState _state = const TrackingState();
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

  /// La detección vive en RouteTrackingManager, no aquí.
  ///
  /// Antes esta pantalla tenía la suya propia, y tenía dos problemas: solo
  /// funcionaba con la pantalla abierta —justo cuando menos falta hace, porque
  /// el motero va conduciendo con el móvil guardado— y leía las coordenadas
  /// con `as num?`, que sobre el texto que manda el servidor daba siempre null.
  /// En circulares, además, no hay destino, así que no detectaba nada nunca.
  void _checkArrival(TrackingState s) {
    if (!s.arrived || _arrivalAsked || _finishing) return;
    _arrivalAsked = true;
    _askArrival();
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
    }
    // Si decide seguir, no se le vuelve a preguntar: el gestor solo marca la
    // llegada una vez por ruta, y volver a insistir mientras aparca sería
    // molesto. Le queda el botón de finalizar.
  }

  // ---------------------------------------------------------------------
  // Finalizar / descartar
  // ---------------------------------------------------------------------

  /// Finaliza la ruta.
  ///
  /// El track NO se borra hasta que el servidor lo confirma. Antes se llamaba
  /// a stop(), que lo borraba todo, antes de subir: si la subida fallaba —sin
  /// cobertura al final de una ruta de montaña, lo más probable del mundo—
  /// el motero reintentaba con un track ya vacío, caía en "demasiado corta",
  /// se descartaba, y perdía la ruta entera con sus POIs y sus logros.
  ///
  /// Ahora un fallo deja todo como estaba y el reintento sube el mismo track.
  /// Si la app muere entre medias, el track sigue en disco y se recupera al
  /// volver a abrirla.
  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    final trackingId = widget.tracking['id'] as int;
    final track = await RouteTrackingManager.instance.pauseRecording();

    // Sin recorrido que guardar: se descarta en vez de finalizar.
    if (track.length < 2) {
      final error = await RouteTrackingService.discard(trackingId);
      if (!mounted) return;

      if (error != null) {
        // El motero pulsó Finalizar, no Descartar: el mensaje no puede hablar
        // de descartar, que es lo que la app decide por dentro al no haber
        // recorrido. Leer "no se pudo descartar tu ruta" tras darle a finalizar
        // asusta, porque parece que se la van a borrar.
        debugPrint('[tracking] descarte por ruta corta falló: $error');
        setState(() => _finishing = false);
        _showMessage('tracking.too_short_failed'.tr());
        return;
      }

      await RouteTrackingManager.instance.clear();
      if (!mounted) return;
      _showMessage('tracking.too_short'.tr());
      context.go('/rider/home');
      return;
    }

    final result = await RouteTrackingService.finish(trackingId, track);
    if (!mounted) return;

    if (result['error'] != null) {
      // El detalle técnico va al log, no a la pantalla: al motero no le sirve
      // "Error de conexión." cuando el mensaje ya le dice que es la cobertura.
      debugPrint('[tracking] finalizar falló: ${result['error']}');
      setState(() => _finishing = false);
      _showMessage('tracking.finish_failed'.tr());
      return;
    }

    // Solo ahora, con la ruta ya en el servidor, se borra la copia local.
    await RouteTrackingManager.instance.clear();
    if (!mounted) return;

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

    // Mismo criterio que al finalizar: no se borra nada hasta que el servidor
    // confirma. Antes se ignoraba el resultado y, si la petición no llegaba,
    // la app daba la ruta por descartada mientras el servidor la seguía
    // teniendo abierta.
    await RouteTrackingManager.instance.pauseRecording();
    final error = await RouteTrackingService.discard(widget.tracking['id'] as int);
    if (!mounted) return;

    if (error != null) {
      debugPrint('[tracking] descartar falló: $error');
      _showMessage('tracking.discard_failed'.tr());
      return;
    }

    await RouteTrackingManager.instance.clear();
    if (!mounted) return;
    context.go('/rider/home');
  }

  /// Mensaje emergente.
  ///
  /// El color lo pone el tema (ver snackBarTheme): las pantallas ya no fijan
  /// el fondo, porque hacerlo dejaba el texto oscuro sobre oscuro.
  ///
  /// Seis segundos en vez de los cuatro por defecto: los avisos de aquí son
  /// instrucciones de dos líneas —qué ha pasado y qué hacer— y con el móvil en
  /// la mano, en marcha, cuatro segundos no dan para leerlas.
  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 6)),
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
    // Salir de esta pantalla no corta el tracking: sigue grabando, y la barra
    // inferior (ActiveTrackingBar) deja volver desde cualquier sitio con un
    // toque.
    //
    // Antes el "atrás" estaba bloqueado con PopScope(canPop: false) y no había
    // flecha: la única salida era la X de arriba, que descarta la ruta. Se
    // entraba aquí por el salto automático, así que tenía cierta lógica, pero
    // con la barra ya no: cerrar una pantalla no puede significar tirar la ruta
    // a la basura. La X se ha quitado y descartar está abajo, en su sitio,
    // escrito con palabras.
    return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.white),
            // Si no hay nada debajo —se ha entrado desde una notificación, que
            // abre esta pantalla directa— la flecha no puede quedarse muerta:
            // lleva a Inicio, donde ya está la barra para volver.
            onPressed: () => Navigator.of(context).canPop()
                ? Navigator.of(context).pop()
                : context.go('/rider/home'),
          ),
          title: Text('tracking.in_progress'.tr(),
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

              // Kilómetros: el dato protagonista.
              //
              // En depuración, una pulsación larga sobre la cifra fuerza el
              // aviso de llegada: probarlo de verdad son horas de ruta. En
              // release el gesto no existe (kDebugMode lo resuelve el
              // compilador).
              Center(
                child: GestureDetector(
                  onLongPress: kDebugMode
                      ? () => RouteTrackingManager.instance.debugForceArrival()
                      : null,
                  child: Column(children: [
                    Text(_state.distanceKm.toStringAsFixed(1),
                        style: const TextStyle(
                            color: AppColors.orange, fontSize: 64, fontWeight: FontWeight.w700, height: 1)),
                    Text('tracking.km'.tr(),
                        style: const TextStyle(color: AppColors.grey, fontSize: 14)),
                  ]),
                ),
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

              const SizedBox(height: 8),

              // Descartar: en texto y en segundo plano visual, no como un
              // icono en la esquina. Es la acción que tira el recorrido, y
              // tiene que costar más leerla que pulsarla por error.
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _finishing ? null : _confirmDiscard,
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.grey, size: 18),
                  label: Text('tracking.discard'.tr(),
                      style: const TextStyle(color: AppColors.grey)),
                ),
              ),

              const SizedBox(height: 4),

              Text('tracking.background_hint'.tr(),
                  style: const TextStyle(color: AppColors.grey, fontSize: 11, height: 1.5)),
            ],
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

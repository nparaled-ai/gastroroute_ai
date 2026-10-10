import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/router.dart';
import '../core/services/route_tracking_manager.dart';
import '../core/theme/app_theme.dart';

/// Franja fija en la parte inferior mientras se graba una ruta.
///
/// Sustituye al salto automático a la pantalla de ruta en curso. Ese salto
/// tenía un problema: durante una ruta el motero abre la app para cualquier
/// cosa —y en la moto basta con que arranque sola la app del fabricante para
/// que la nuestra pase a segundo plano y haya que volver a entrar— y se le
/// empujaba a la ruta en curso, de la que encima tenía que salir.
///
/// Con la barra el acceso sigue estando a un toque desde cualquier pantalla,
/// pero sin robarle la navegación. El salto automático se reserva para cuando
/// hay algo que decidir: que ya se haya detectado la llegada al destino.
///
/// Va montada en el `builder` de MaterialApp, encima del Navigator, para que
/// no haya que acordarse de ponerla en cada una de las pantallas.
class ActiveTrackingBar extends StatefulWidget {
  const ActiveTrackingBar({super.key});

  @override
  State<ActiveTrackingBar> createState() => _ActiveTrackingBarState();
}

class _ActiveTrackingBarState extends State<ActiveTrackingBar> {
  /// Pantallas donde la barra no pinta nada.
  ///
  /// En la propia ruta en curso sería un botón para ir a donde ya estás, y en
  /// las de login/registro no hay ninguna ruta que pueda estar grabándose.
  static const _hiddenOn = {
    '/rider/tracking',
    '/splash',
    '/login',
    '/register',
    '/verify-email',
    '/select-role',
    '/forgot-password',
    '/reset-password',
  };

  StreamSubscription<TrackingState>? _sub;
  Timer? _ticker;

  TrackingState _state = const TrackingState();

  @override
  void initState() {
    super.initState();
    _state = RouteTrackingManager.instance.state;

    _sub = RouteTrackingManager.instance.stream.listen((s) {
      if (mounted) setState(() => _state = s);
    });

    // El tiempo corre aunque no lleguen posiciones nuevas: paradas, túneles,
    // o simplemente el móvil guardado en el bolsillo sin moverse.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state.isActive) setState(() {});
    });

    // La barra se esconde en según qué pantallas, así que tiene que repintarse
    // al navegar. GoRouterState.of() no sirve aquí: este widget vive por
    // encima del Navigator, no dentro de él.
    router.routerDelegate.addListener(_onNavigate);
  }

  @override
  void dispose() {
    router.routerDelegate.removeListener(_onNavigate);
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _onNavigate() {
    if (mounted) setState(() {});
  }

  String get _currentPath {
    try {
      return router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return '';
    }
  }

  void _open() {
    // Si falta el tracking guardado se abre la ruta, que es lo más parecido:
    // desde ahí se puede finalizar igual. Mejor eso que un toque que no hace
    // nada.
    final data = RouteTrackingManager.instance.data;
    if (data != null) {
      router.push('/rider/tracking', extra: data);
      return;
    }

    final routeId = RouteTrackingManager.instance.routeId;
    if (routeId != null) router.push('/rider/routes/$routeId');
  }

  String _elapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    if (!_state.isActive) return const SizedBox.shrink();
    if (_hiddenOn.contains(_currentPath)) return const SizedBox.shrink();

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: _open,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.orange, width: 2)),
          ),
          // El hueco de la barra de navegación del sistema va DENTRO de la
          // franja: así el naranja llega hasta el borde y el texto no queda
          // debajo de los botones del móvil.
          padding: EdgeInsets.fromLTRB(
            16, 10, 12, 10 + MediaQuery.of(context).padding.bottom,
          ),
          child: Row(children: [
            const Icon(Icons.fiber_manual_record, color: AppColors.orange, size: 12),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'tracking.in_progress'.tr(),
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${_state.distanceKm.toStringAsFixed(1)} km · '
                    '${_elapsed(_state.elapsed)}',
                    style: const TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.grey),
          ]),
        ),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Imagen del recorrido de una ruta.
///
/// Se usa en tres sitios —detalle de ruta, resultado al generar y resumen de
/// una ruta rodada— que obtienen la imagen de endpoints distintos. Por eso
/// recibe un cargador en lugar de un id: lo único que comparten es cómo se
/// muestra mientras carga y qué enseñar si falla.
///
/// La imagen se pide como bytes y no con Image.network porque los endpoints
/// requieren el token que inyecta el interceptor de Dio.
class RouteMapImage extends StatefulWidget {
  final Future<Uint8List?> Function() loader;
  final String? title;

  const RouteMapImage({super.key, required this.loader, this.title});

  @override
  State<RouteMapImage> createState() => _RouteMapImageState();
}

class _RouteMapImageState extends State<RouteMapImage> {
  Uint8List? _image;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RouteMapImage old) {
    super.didUpdateWidget(old);
    if (old.loader != widget.loader) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final image = await widget.loader();
    if (!mounted) return;
    setState(() {
      _image = image;
      _loading = false;
    });
  }

  /// Abre la imagen a pantalla completa, con zoom de pellizco.
  ///
  /// Es una imagen fija, así que ampliar mucho la pixela: sirve para verla
  /// más grande, no para descubrir detalle que no está. Para eso está el
  /// botón de abrir en Google Maps que ya tiene la pantalla.
  void _openFullScreen() {
    final image = _image;
    if (image == null) return;

    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _FullScreenMap(image: image),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null) ...[
          Text(widget.title!,
              style: const TextStyle(
                  color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Container(
              color: AppColors.surface,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.orange))
                  : _image != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_image!, fit: BoxFit.cover),
                            // Toda la imagen es pulsable, pero sin el icono no
                            // se adivina que se puede ampliar.
                            Material(
                              color: Colors.transparent,
                              child: InkWell(onTap: _openFullScreen),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: IgnorePointer(
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.background.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.zoom_out_map,
                                      color: AppColors.white, size: 18),
                                ),
                              ),
                            ),
                          ],
                        )
                      : _unavailable(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _unavailable() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, color: AppColors.grey, size: 36),
          const SizedBox(height: 8),
          Text('summary.map_unavailable'.tr(),
              style: const TextStyle(color: AppColors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _load,
            child: Text('common.retry'.tr(),
                style: const TextStyle(color: AppColors.orange, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Visor a pantalla completa del mapa, con zoom de pellizco y desplazamiento.
class _FullScreenMap extends StatelessWidget {
  final Uint8List image;

  const _FullScreenMap({required this.image});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tocar fuera de la imagen cierra el visor.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
            ),
          ),
          Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.memory(image, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: AppColors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

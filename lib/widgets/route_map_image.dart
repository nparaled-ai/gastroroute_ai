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
                      ? Image.memory(_image!, fit: BoxFit.cover)
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

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/rider/providers/route_service.dart';

/// «Publicar en Rutas moteras» de una ruta rodada: el botón, el estado (pendiente / publicada / rechazada) y el
/// aviso de que ya hay rutas parecidas antes de pedirlo.
///
/// Se usa en el resumen de la rodada (el momento natural para publicar, con la ruta recién hecha). La ficha
/// de la ruta tiene el mismo flujo en su propio código.
class RoutePublicationBlock extends StatefulWidget {
  final int routeId;

  /// null | pending | approved | rejected
  final String? status;
  final String? reason;

  /// Si la ruta viene del catálogo, ya está allí: no se vuelve a publicar.
  final int? catalogRouteId;

  const RoutePublicationBlock({
    super.key,
    required this.routeId,
    this.status,
    this.reason,
    this.catalogRouteId,
  });

  @override
  State<RoutePublicationBlock> createState() => _RoutePublicationBlockState();
}

class _RoutePublicationBlockState extends State<RoutePublicationBlock> {
  late String? _status = widget.status;
  bool _publishing = false;

  Future<void> _request() async {
    setState(() => _publishing = true);

    // ¿Ya hay en Rutas moteras alguna parecida? Se avisa; publicar sigue siendo posible.
    final parecidas = await RouteService.similarForPublish(widget.routeId);
    if (!mounted) return;
    if (parecidas.isNotEmpty) {
      setState(() => _publishing = false);
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('catalog.pub_similar_title'.tr(),
              style: const TextStyle(color: AppColors.white, fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('catalog.pub_similar_body'.tr(),
                  style: const TextStyle(color: AppColors.greyText, fontSize: 14)),
              const SizedBox(height: 12),
              for (final s in parecidas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => context.push('/rider/catalog/${s['id']}'),
                    child: Row(children: [
                      const Icon(Icons.alt_route, color: AppColors.cyan, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s['name']} · ${'catalog.km_short'.tr(namedArgs: {'km': '${s['km']}'})} · '
                          '${'catalog.sim_pct'.tr(namedArgs: {'pct': '${s['similarity']}'})}',
                          style: const TextStyle(color: AppColors.white, fontSize: 13),
                        ),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text('common.cancel'.tr())),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('catalog.pub_similar_confirm'.tr(),
                    style: const TextStyle(color: AppColors.orange))),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
      setState(() => _publishing = true);
    }

    final result = await RouteService.publishRoute(widget.routeId, 'public');
    if (!mounted) return;
    setState(() => _publishing = false);

    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result['error']}'), backgroundColor: AppColors.error));
      return;
    }
    final r = Map<String, dynamic>.from(result['route'] as Map? ?? {});
    setState(() => _status = '${r['publication_status'] ?? 'pending'}');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('catalog.publish_pending'.tr())));
  }

  Widget _box(Color color, IconData icon, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    // Una ruta guardada desde «Rutas moteras» ya está en el catálogo: se valora en su ficha.
    if (widget.catalogRouteId != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _box(AppColors.cyan, Icons.landscape_outlined, 'catalog.already_in_catalog'.tr()),
        TextButton(
          onPressed: () => context.push('/rider/catalog/${widget.catalogRouteId}'),
          child: Text('catalog.see_in_catalog'.tr()),
        ),
      ]);
    }

    if (_status == 'pending') {
      return _box(AppColors.gold, Icons.hourglass_top, 'catalog.publish_pending'.tr());
    }
    if (_status == 'approved') {
      return _box(AppColors.cyan, Icons.verified_outlined, 'catalog.publish_published'.tr());
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_status == 'rejected')
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'catalog.publish_rejected'.tr() +
                ((widget.reason ?? '').isNotEmpty
                    ? '\n${'catalog.publish_rejected_reason'.tr(namedArgs: {'reason': widget.reason!})}'
                    : ''),
            style: const TextStyle(color: AppColors.error, fontSize: 13, height: 1.4),
          ),
        ),
      OutlinedButton.icon(
        onPressed: _publishing ? null : _request,
        icon: _publishing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.landscape_outlined, color: AppColors.cyan),
        label: Text('catalog.publish'.tr(), style: const TextStyle(color: AppColors.cyan)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          side: const BorderSide(color: AppColors.cyan),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('catalog.publish_help'.tr(),
            style: const TextStyle(color: AppColors.greyText, fontSize: 12, height: 1.4)),
      ),
    ]);
  }
}

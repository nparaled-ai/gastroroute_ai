import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/route_overlay_map.dart';
import '../../rider/screens/catalog_screen.dart' show categoryColor;
import '../providers/moderation_service.dart';

/// Compara una ruta pendiente de publicar con las rutas parecidas que ya hay en Rutas moteras:
/// un mapa con las dos superpuestas (naranja = la que se revisa, azul = la del catálogo) y, debajo,
/// la lista con km, sinuosidad, carreteras, puertos y estrellas de cada una.
class SimilarRoutesScreen extends StatefulWidget {
  final int routeId;
  final String title;

  const SimilarRoutesScreen({super.key, required this.routeId, required this.title});

  @override
  State<SimilarRoutesScreen> createState() => _SimilarRoutesScreenState();
}

class _SimilarRoutesScreenState extends State<SimilarRoutesScreen> {
  Map<String, dynamic>? _data;
  bool _error = false;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ModerationService.similar(widget.routeId);
    if (!mounted) return;
    setState(() {
      _data = r;
      _error = r == null;
    });
  }

  List<Map<String, dynamic>> get _similar => List<Map<String, dynamic>>.from(
      ((_data?['similar'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));

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
        title: Text('catalog.sim_title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error) {
      return Center(child: TextButton(onPressed: _load, child: Text('moderation.retry'.tr())));
    }
    if (_data == null) return const Center(child: CircularProgressIndicator());

    final list = _similar;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('catalog.sim_none'.tr(),
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.greyText)),
        ),
      );
    }
    final sel = list[_selected.clamp(0, list.length - 1)];
    final mine = Map<String, dynamic>.from(_data!['mine'] as Map);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: RouteOverlayMap(mine: mine['polyline'] as String?, other: sel['polyline'] as String?),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          _legend(AppColors.orange, 'catalog.sim_legend_mine'.tr()),
          const SizedBox(width: 16),
          _legend(AppColors.cyan, 'catalog.sim_legend_other'.tr()),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 24 + MediaQuery.of(context).padding.bottom),
          itemCount: list.length,
          itemBuilder: (_, i) => _card(list[i], mine, i == _selected, () => setState(() => _selected = i)),
        ),
      ),
    ]);
  }

  Widget _legend(Color c, String t) => Row(children: [
        Container(width: 18, height: 5, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
      ]);

  Widget _card(Map<String, dynamic> s, Map<String, dynamic> mine, bool on, VoidCallback onTap) {
    final high = s['level'] == 'high';
    final roads = List<String>.from((s['shared_roads'] as List?) ?? const []);
    final passes = List<String>.from((s['shared_passes'] as List?) ?? const []);
    final cat = s['category'] as String?;

    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: on ? AppColors.cyan : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${s['name']}',
                    style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (high ? AppColors.error : AppColors.gold).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('catalog.sim_pct'.tr(namedArgs: {'pct': '${s['similarity']}'}),
                    style: TextStyle(
                        color: high ? AppColors.error : AppColors.gold,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
            ]),
            if (s['contained'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('catalog.sim_contained'.tr(),
                    style: const TextStyle(color: AppColors.gold, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            // Lado a lado: la que se revisa y la del catálogo
            Row(children: [
              Expanded(child: _col('catalog.sim_legend_mine'.tr(), [
                'catalog.km_short'.tr(namedArgs: {'km': '${mine['km'] ?? '?'}'}),
              ], AppColors.orange)),
              Expanded(
                child: _col('catalog.sim_legend_other'.tr(), [
                  'catalog.km_short'.tr(namedArgs: {'km': '${s['km']}'}),
                  if (cat != null) '${s['score']} · ${s['category_label'] ?? cat}',
                  if (s['rating'] != null) '★ ${s['rating']} (${s['votes']})',
                ], AppColors.cyan, color2: cat != null ? categoryColor(cat) : null),
              ),
            ]),
            if (roads.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('catalog.sim_shared_roads'.tr(namedArgs: {'roads': roads.join(', ')}),
                    style: const TextStyle(color: AppColors.white, fontSize: 13)),
              ),
            if (passes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('catalog.sim_shared_passes'.tr(namedArgs: {'passes': passes.join(', ')}),
                    style: const TextStyle(color: AppColors.white, fontSize: 13)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _col(String head, List<String> lines, Color c, {Color? color2}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(head, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
          for (var i = 0; i < lines.length; i++)
            Text(lines[i],
                style: TextStyle(
                    color: (i == 1 && color2 != null) ? color2 : AppColors.white, fontSize: 13)),
        ],
      );
}

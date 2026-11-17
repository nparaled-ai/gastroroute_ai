import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/moderation_service.dart';

/// Comentarios de las rutas del catálogo pendientes de aprobar.
///
/// Todo comentario espera aquí. La IA solo deja una sugerencia; decide la persona.
class ModerationCatalogCommentsScreen extends StatefulWidget {
  const ModerationCatalogCommentsScreen({super.key});

  @override
  State<ModerationCatalogCommentsScreen> createState() =>
      _ModerationCatalogCommentsScreenState();
}

class _ModerationCatalogCommentsScreenState extends State<ModerationCatalogCommentsScreen> {
  List<Map<String, dynamic>>? _items;
  bool _error = false;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ModerationService.catalogComments();
    if (!mounted) return;
    setState(() {
      _items = r;
      _error = r == null;
    });
  }

  Future<void> _decide(Map<String, dynamic> c, String decision) async {
    final id = (c['id'] as num).toInt();
    setState(() => _busy.add(id));
    final ok = await ModerationService.decideCatalogComment(id, decision);
    if (!mounted) return;
    setState(() => _busy.remove(id));

    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('moderation.error'.tr())));
      return;
    }
    _load();
  }

  String _suggestion(String? s) {
    switch (s) {
      case 'approve':
        return 'moderation.ia_approve'.tr();
      case 'reject':
        return 'moderation.ia_reject'.tr();
      case 'unsure':
        return 'moderation.ia_unsure'.tr();
    }
    return '';
  }

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
        title: Text('catalog.mod_comments'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error) {
      return Center(
        child: TextButton(onPressed: _load, child: Text('moderation.retry'.tr())),
      );
    }
    if (_items == null) return const Center(child: CircularProgressIndicator());
    if (_items!.isEmpty) {
      return Center(
        child: Text('catalog.mod_empty_comments'.tr(),
            style: const TextStyle(color: AppColors.greyText)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(14, 14, 14, 28 + MediaQuery.of(context).padding.bottom),
        itemCount: _items!.length,
        itemBuilder: (_, i) {
          final c = _items![i];
          final id = (c['id'] as num).toInt();
          final busy = _busy.contains(id);
          final stars = (c['stars'] as num?)?.toInt();
          final tip = _suggestion(c['suggestion'] as String?);

          return Card(
            color: AppColors.card,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${c['route'] ?? ''}',
                    style: const TextStyle(
                        color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Row(children: [
                  Text('${c['nickname'] ?? ''}',
                      style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                  const Spacer(),
                  if (stars != null)
                    for (var s = 1; s <= 5; s++)
                      Icon(s <= stars ? Icons.star : Icons.star_border,
                          size: 15, color: AppColors.gold),
                ]),
                const SizedBox(height: 8),
                Text('${c['comment']}',
                    style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.4)),
                if (tip.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(tip + (c['reason'] != null ? ' · ${c['reason']}' : ''),
                      style: const TextStyle(color: AppColors.gold, fontSize: 12)),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  ElevatedButton(
                    onPressed: busy ? null : () => _decide(c, 'approved'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
                    child: Text('moderation.approve'.tr(),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => _decide(c, 'rejected'),
                    child: Text('moderation.reject_comment'.tr()),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => _decide(c, 'annulled'),
                    child: Text('moderation.annul'.tr(),
                        style: const TextStyle(color: AppColors.error)),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}

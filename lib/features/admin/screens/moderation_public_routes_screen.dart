import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/route_overlay_map.dart';
import '../providers/moderation_service.dart';

/// Rutas publicadas PARA TODOS («Publicar para todos»): se publican al momento si cumplen los mínimos, sin revisión
/// previa. El moderador las ve aquí, solo lectura, con su autor, y puede bloquear la cuenta de quien abuse.
class ModerationPublicRoutesScreen extends StatefulWidget {
  const ModerationPublicRoutesScreen({super.key});

  @override
  State<ModerationPublicRoutesScreen> createState() => _ModerationPublicRoutesScreenState();
}

class _ModerationPublicRoutesScreenState extends State<ModerationPublicRoutesScreen> {
  List<Map<String, dynamic>>? _routes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ModerationService.publicRoutes();
    if (!mounted) return;
    setState(() {
      _routes = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('moderation.public_routes'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _routes == null
              ? Center(
                  child: Text('common.connection_error'.tr(), style: const TextStyle(color: AppColors.greyText)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _routes!.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text('moderation.public_routes_empty'.tr(),
                                style: const TextStyle(color: AppColors.greyText)),
                          ),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _routes!.length,
                          itemBuilder: (context, i) {
                            final r = _routes![i];
                            final author = Map<String, dynamic>.from(r['author'] as Map);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () async {
                                  await context.push('/admin/moderation/public-routes/${r['id']}');
                                  _load();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.greyDark),
                                  ),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${r['title']}',
                                        style: const TextStyle(
                                            color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    Text('${r['origin'] ?? ''} · ${r['km']} km',
                                        style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      const Icon(Icons.person_outline, size: 15, color: AppColors.cyan),
                                      const SizedBox(width: 4),
                                      Text('@${author['nickname'] ?? '—'}',
                                          style: const TextStyle(color: AppColors.cyan, fontSize: 13)),
                                    ]),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

/// Una ruta publicada, de solo lectura, con el autor y el botón de bloquear su cuenta.
class ModerationPublicRouteDetailScreen extends StatefulWidget {
  final int routeId;
  const ModerationPublicRouteDetailScreen({super.key, required this.routeId});

  @override
  State<ModerationPublicRouteDetailScreen> createState() => _ModerationPublicRouteDetailScreenState();
}

class _ModerationPublicRouteDetailScreenState extends State<ModerationPublicRouteDetailScreen> {
  Map<String, dynamic>? _r;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ModerationService.publicRoute(widget.routeId);
    if (!mounted) return;
    setState(() {
      _r = r;
      _loading = false;
    });
  }

  Future<void> _block() async {
    final author = Map<String, dynamic>.from(_r!['author'] as Map);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('moderation.block_title'.tr(namedArgs: {'nick': '${author['nickname']}'})),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('moderation.block_body'.tr(),
              style: const TextStyle(color: AppColors.greyText, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            maxLength: 150,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(labelText: 'moderation.block_reason'.tr()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('common.cancel'.tr())),
          TextButton(
            onPressed: () => Navigator.pop(ctx, reason.text.trim().length >= 3),
            child: Text('moderation.block'.tr(), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final err = await ModerationService.blockUser(author['id'] as int, reason.text.trim());
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: AppColors.error));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('moderation.blocked_ok'.tr())));
    context.pop();
  }

  Future<void> _unblock() async {
    final author = Map<String, dynamic>.from(_r!['author'] as Map);
    final err = await ModerationService.unblockUser(author['id'] as int);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: AppColors.error));
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('moderation.public_route'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : r == null
              ? Center(
                  child: Text('common.connection_error'.tr(), style: const TextStyle(color: AppColors.greyText)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('${r['title']}',
                        style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('${r['origin'] ?? ''} · ${r['km']} km',
                        style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                    const SizedBox(height: 14),
                    if ((r['polyline'] ?? '').toString().isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: RouteOverlayMap(mine: r['polyline'] as String?, other: null, height: 220),
                      ),
                    const SizedBox(height: 14),
                    if ('${r['description'] ?? ''}'.isNotEmpty) ...[
                      Text('${r['description']}',
                          style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.5)),
                      const SizedBox(height: 14),
                    ],
                    for (final w in (r['waypoints'] as List? ?? const []))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.place_outlined, size: 16, color: AppColors.orange),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                '${w['name']}${(w['note'] ?? '').toString().isNotEmpty ? ' — ${w['note']}' : ''}',
                                style: const TextStyle(color: AppColors.greyText, fontSize: 13, height: 1.4)),
                          ),
                        ]),
                      ),
                    const Divider(color: AppColors.greyDark, height: 32),
                    _Author(author: Map<String, dynamic>.from(r['author'] as Map), onBlock: _block, onUnblock: _unblock),
                  ],
                ),
    );
  }
}

class _Author extends StatelessWidget {
  final Map<String, dynamic> author;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;
  const _Author({required this.author, required this.onBlock, required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    final blocked = author['blocked'] == true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blocked ? AppColors.error.withOpacity(0.5) : AppColors.greyDark),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('moderation.author'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text('@${author['nickname'] ?? '—'}',
            style: const TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        if ('${author['province'] ?? ''}'.isNotEmpty)
          Text('${author['province']}', style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
        const SizedBox(height: 4),
        Text('moderation.author_public_routes'.tr(namedArgs: {'n': '${author['public_routes'] ?? 0}'}),
            style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
        if (blocked) ...[
          const SizedBox(height: 10),
          Text('${'moderation.account_blocked'.tr()}${(author['blocked_reason'] ?? '').toString().isNotEmpty ? ': ${author['blocked_reason']}' : ''}',
              style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        blocked
            ? OutlinedButton.icon(
                onPressed: onUnblock,
                icon: const Icon(Icons.lock_open),
                label: Text('moderation.unblock'.tr()),
              )
            : OutlinedButton.icon(
                onPressed: onBlock,
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                icon: const Icon(Icons.block),
                label: Text('moderation.block_account'.tr()),
              ),
      ]),
    );
  }
}

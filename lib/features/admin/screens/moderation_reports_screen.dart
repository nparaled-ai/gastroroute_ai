import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/moderation_service.dart';

/// Denuncias de rutas de «Rutas moteras» y de sus comentarios, pendientes de decidir.
class ModerationReportsScreen extends StatefulWidget {
  const ModerationReportsScreen({super.key});

  @override
  State<ModerationReportsScreen> createState() => _ModerationReportsScreenState();
}

class _ModerationReportsScreenState extends State<ModerationReportsScreen> {
  List<Map<String, dynamic>>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ModerationService.reports();
    if (!mounted) return;
    setState(() {
      _items = r;
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
        title: Text('moderation.reports.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _items == null
              ? Center(child: Text('common.connection_error'.tr(), style: const TextStyle(color: AppColors.greyText)))
              : _items!.isEmpty
                  ? Center(child: Text('moderation.reports.empty'.tr(), style: const TextStyle(color: AppColors.greyText)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items!.length,
                        itemBuilder: (_, i) {
                          final r = _items![i];
                          final isRoute = r['target_type'] == 'catalog_route';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                await context.push('/admin/moderation/reports/${r['id']}');
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
                                  Row(children: [
                                    Icon(isRoute ? Icons.route : Icons.chat_bubble_outline,
                                        size: 16, color: AppColors.orange),
                                    const SizedBox(width: 6),
                                    Text(isRoute ? 'moderation.reports.type_route'.tr() : 'moderation.reports.type_comment'.tr(),
                                        style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w700)),
                                    const Spacer(),
                                    if ((r['same_target'] as num? ?? 1) > 1)
                                      Text('moderation.reports.same_target'.tr(namedArgs: {'n': '${r['same_target']}'}),
                                          style: const TextStyle(color: AppColors.error, fontSize: 12)),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text('${r['title']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text('report.reasons.${r['reason']}'.tr(),
                                      style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
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

/// Una denuncia: lo denunciado, quién y por qué, y las salidas del moderador.
class ModerationReportDetailScreen extends StatefulWidget {
  final int reportId;
  const ModerationReportDetailScreen({super.key, required this.reportId});

  @override
  State<ModerationReportDetailScreen> createState() => _ModerationReportDetailScreenState();
}

class _ModerationReportDetailScreenState extends State<ModerationReportDetailScreen> {
  Map<String, dynamic>? _r;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ModerationService.report(widget.reportId);
    if (!mounted) return;
    setState(() {
      _r = r;
      _loading = false;
    });
  }

  void _snack(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));

  Future<void> _finish(String decision, {String? reason}) async {
    setState(() => _busy = true);
    final err = await ModerationService.resolveReport(widget.reportId, decision, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _snack(err, error: true);
      return;
    }
    _snack('moderation.reports.resolved'.tr());
    context.pop();
  }

  /// Pide un texto (motivo o aviso). null si se cancela.
  Future<String?> _ask(String title, String body, String label, {int min = 3}) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(body, style: const TextStyle(color: AppColors.greyText, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            maxLength: 200,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(labelText: label),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('common.cancel'.tr())),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim().length >= min), child: Text('common.confirm'.tr())),
        ],
      ),
    );
    return ok == true ? c.text.trim() : null;
  }

  Future<void> _hide() async {
    final reason = await _ask('moderation.reports.hide_title'.tr(), 'moderation.reports.hide_body'.tr(),
        'moderation.reports.hide_reason'.tr());
    if (reason != null) _finish('hidden', reason: reason);
  }

  Future<void> _warn() async {
    final author = Map<String, dynamic>.from(_r!['author'] as Map);
    final text = await _ask('moderation.warn_title'.tr(namedArgs: {'nick': '${author['nickname']}'}),
        'moderation.warn_body'.tr(), 'moderation.warn_text'.tr(), min: 5);
    if (text == null) return;
    final err = await ModerationService.warnUser(author['id'] as int, message: text);
    if (!mounted) return;
    if (err != null) {
      _snack(err, error: true);
      return;
    }
    _snack('moderation.warn_sent'.tr());
    _finish('warned');
  }

  Future<void> _block() async {
    final author = Map<String, dynamic>.from(_r!['author'] as Map);
    final reason = await _ask('moderation.block_title'.tr(namedArgs: {'nick': '${author['nickname']}'}),
        'moderation.block_body'.tr(), 'moderation.block_reason'.tr());
    if (reason == null) return;
    final err = await ModerationService.blockUser(author['id'] as int, reason);
    if (!mounted) return;
    if (err != null) {
      _snack(err, error: true);
      return;
    }
    _snack('moderation.blocked_ok'.tr());
    _finish('blocked');
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(t, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('moderation.reports.detail_title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : r == null
              ? Center(child: Text('common.connection_error'.tr(), style: const TextStyle(color: AppColors.greyText)))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text(r['target_type'] == 'catalog_route'
                      ? 'moderation.reports.type_route'.tr()
                      : 'moderation.reports.type_comment'.tr(),
                      style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${(r['target'] as Map)['title']}',
                      style: const TextStyle(color: AppColors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                  if ('${(r['target'] as Map)['text']}'.isNotEmpty && r['target_type'] != 'catalog_comment')
                    Text('${(r['target'] as Map)['text']}', style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                  if (r['target_type'] == 'catalog_comment') ...[
                    _label('moderation.reports.content'.tr()),
                    Text('${(r['target'] as Map)['text']}',
                        style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.45)),
                  ],
                  if ((r['target'] as Map)['hidden'] == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('moderation.reports.already_hidden'.tr(),
                          style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ),
                  _label('moderation.author'.tr()),
                  Text(
                      (r['author'] as Map)['id'] == null
                          ? 'moderation.reports.curated'.tr()
                          : '@${(r['author'] as Map)['nickname'] ?? '—'}',
                      style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const Divider(color: AppColors.greyDark, height: 28),
                  _label('report.reason_label'.tr()),
                  Text('report.reasons.${r['reason']}'.tr(),
                      style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  _label('moderation.reports.details'.tr()),
                  Text('${r['details']}', style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.45)),
                  _label('moderation.reports.reporter'.tr(namedArgs: {'nick': '${(r['reporter'] as Map)['nickname'] ?? '—'}'})),
                  Text(
                      'moderation.reports.reporter_stats'.tr(namedArgs: {
                        'total': '${(r['reporter'] as Map)['total']}',
                        'dismissed': '${(r['reporter'] as Map)['dismissed']}',
                      }),
                      style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                  if ((r['same_target'] as num? ?? 1) > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('moderation.reports.same_target'.tr(namedArgs: {'n': '${r['same_target']}'}),
                          style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ),
                  const SizedBox(height: 22),
                  if (r['status'] == 'pending') ...[
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _finish('dismissed'),
                      icon: const Icon(Icons.check),
                      label: Text('moderation.reports.dismiss'.tr()),
                    ),
                    const SizedBox(height: 8),
                    if ((r['target'] as Map)['hidden'] != true)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _hide,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.orange, side: const BorderSide(color: AppColors.orange)),
                        icon: const Icon(Icons.visibility_off_outlined),
                        label: Text('moderation.reports.hide'.tr()),
                      ),
                    if ((r['author'] as Map)['id'] != null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _warn,
                        icon: const Icon(Icons.campaign_outlined),
                        label: Text('moderation.warn_author'.tr()),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _block,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                        icon: const Icon(Icons.block),
                        label: Text('moderation.block_account'.tr()),
                      ),
                    ],
                  ] else
                    Text('moderation.reports.resolved'.tr(), style: const TextStyle(color: AppColors.greyText)),
                ]),
    );
  }
}

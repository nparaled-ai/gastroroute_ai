import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';


import '../../../core/theme/app_theme.dart';
import '../providers/moderation_service.dart';

/// La cola de comentarios de los sitios de comer.
///
/// Cada uno lleva la sugerencia del filtro de IA (aprobar, rechazar, dudosa),
/// pero la IA no decide: lo publica o lo rechaza el administrador. Lo ya decidido
/// se puede revertir desde la pestaña «Revisados».
class ModerationCommentsScreen extends StatefulWidget {
  const ModerationCommentsScreen({super.key});

  @override
  State<ModerationCommentsScreen> createState() => _ModerationCommentsScreenState();
}

class _ModerationCommentsScreenState extends State<ModerationCommentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('moderation.comments'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFFB9A2FF),
          labelColor: AppColors.white,
          unselectedLabelColor: AppColors.greyText,
          tabs: [
            Tab(text: 'moderation.tab_pending'.tr()),
            Tab(text: 'moderation.tab_reviewed'.tr()),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _CommentList(reviewed: false),
          _CommentList(reviewed: true),
        ],
      ),
    );
  }
}

class _CommentList extends StatefulWidget {
  final bool reviewed;
  const _CommentList({required this.reviewed});

  @override
  State<_CommentList> createState() => _CommentListState();
}

class _CommentListState extends State<_CommentList>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _items;
  bool _error = false;
  final Set<int> _busy = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ModerationService.comments(reviewed: widget.reviewed);
    if (!mounted) return;
    setState(() {
      _items = r;
      _error = r == null;
    });
  }

  Future<void> _decide(Map<String, dynamic> c, String decision) async {
    final id = (c['id'] as num).toInt();
    setState(() => _busy.add(id));
    final ok = await ModerationService.decide(id, decision);
    if (!mounted) return;
    setState(() => _busy.remove(id));

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('moderation.error'.tr())),
      );
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_items == null && !_error) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: Text('moderation.retry'.tr()),
        ),
      );
    }
    if (_items!.isEmpty) {
      return Center(
        child: Text(
          widget.reviewed ? 'moderation.empty_reviewed'.tr() : 'moderation.empty_pending'.tr(),
          style: const TextStyle(color: AppColors.greyText),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        // Con margen abajo para que la última tarjeta no quede tapada por la barra
        // de navegación del móvil.
        padding: EdgeInsets.fromLTRB(14, 14, 14, 28 + MediaQuery.of(context).padding.bottom),
        itemCount: _items!.length,
        itemBuilder: (_, i) => _CommentCard(
          c: _items![i],
          busy: _busy.contains((_items![i]['id'] as num).toInt()),
          onDecide: (d) => _decide(_items![i], d),
        ),
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  final Map<String, dynamic> c;
  final bool busy;
  final void Function(String decision) onDecide;

  const _CommentCard({required this.c, required this.busy, required this.onDecide});

  @override
  Widget build(BuildContext context) {
    final status = '${c['status']}';
    final suggestion = c['suggestion'] as String?;
    final stars = (c['stars'] as num?)?.toInt() ?? 0;
    final place = [c['eatery'], c['locality']]
        .where((e) => e != null && '$e'.isNotEmpty)
        .join(' · ');

    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (status == 'pending' && suggestion != null)
              _SuggestionChip(suggestion: suggestion, reason: c['reason'] as String?),
            // Son dos decisiones distintas: la valoración (estrellas y aparcamiento)
            // y el texto del comentario.
            if (status != 'pending') ...[
              _DecisionLine(
                label: 'moderation.decision_rating'.tr(),
                ok: status != 'annulled',
                okText: 'moderation.decision_rating_ok'.tr(),
                noText: 'moderation.decision_rating_no'.tr(),
              ),
              const SizedBox(height: 2),
              _DecisionLine(
                label: 'moderation.decision_comment'.tr(),
                ok: status == 'approved',
                okText: 'moderation.decision_comment_ok'.tr(),
                noText: 'moderation.decision_comment_no'.tr(),
              ),
            ],
            const SizedBox(height: 6),
            Text(place,
                style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
            Text('@${c['nickname'] ?? ''}',
                style: const TextStyle(color: AppColors.orange, fontSize: 12)),
            // Cuándo estuvo allí y cuándo lo escribió: para comprobarlo.
            if (c['visited_on'] != null || c['date'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [
                    if (c['visited_on'] != null)
                      'moderation.visited_on'.tr(namedArgs: {'date': _fecha(context, '${c['visited_on']}')}),
                    if (c['date'] != null)
                      'moderation.commented_on'.tr(namedArgs: {'date': _fecha(context, '${c['date']}')}),
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.greyText, fontSize: 11),
                ),
              ),
            if (stars > 0) ...[
              const SizedBox(height: 4),
              Row(children: [
                for (var i = 1; i <= 5; i++)
                  Icon(i <= stars ? Icons.star : Icons.star_border,
                      color: AppColors.gold, size: 16),
              ]),
            ],
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.two_wheeler, color: AppColors.cyan, size: 16),
              const SizedBox(width: 6),
              Text(
                (c['parked'] == true
                        ? 'moderation.parking_yes'
                        : c['parked'] == false
                            ? 'moderation.parking_no'
                            : 'moderation.parking_unknown')
                    .tr(),
                style: const TextStyle(color: AppColors.white, fontSize: 12),
              ),
            ]),
            if (c['closed'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('moderation.says_closed'.tr(),
                    style: const TextStyle(color: Color(0xFFFFD77A), fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Text('${c['comment']}',
                style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.4)),
            if (c['translation'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('moderation.translation'.tr(namedArgs: {'text': '${c['translation']}'}),
                    style: const TextStyle(
                        color: Color(0xFFB9A2FF), fontSize: 13, height: 1.4, fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 12),
            if (busy)
              const Center(
                  child: SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            else if (status != 'pending') ...[
              // Ya revisado: dos interruptores, con el actual marcado.
              _Toggle(
                label: 'moderation.decision_rating'.tr(),
                leftText: 'moderation.decision_rating_ok'.tr(),
                rightText: 'moderation.decision_rating_no'.tr(),
                leftSelected: status != 'annulled',
                // Válida: se conserva y el comentario queda rechazado hasta que lo apruebes.
                onLeft: () => status == 'annulled' ? onDecide('rejected') : null,
                onRight: () => status == 'annulled' ? null : onDecide('annulled'),
              ),
              const SizedBox(height: 8),
              _Toggle(
                label: 'moderation.decision_comment'.tr(),
                leftText: 'moderation.decision_comment_ok'.tr(),
                rightText: 'moderation.decision_comment_no'.tr(),
                leftSelected: status == 'approved',
                // Un voto anulado no tiene comentario que aprobar: primero se restaura.
                onLeft: () => status == 'approved' ? null : onDecide('approved'),
                onRight: () => status == 'approved' ? onDecide('rejected') : null,
              ),
            ] else ...[
              // Qué se puede hacer según cómo esté el voto: aprobar el comentario,
              // rechazar solo el comentario (la valoración se queda) o anular todo.
              Row(children: [
                if (status != 'approved')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onDecide('approved'),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text((status == 'annulled' ? 'moderation.restore' : 'moderation.approve').tr()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7BE0A1),
                        side: const BorderSide(color: Color(0xFF2F6A48)),
                      ),
                    ),
                  ),
                if (status != 'approved' && status != 'annulled' && status != 'rejected')
                  const SizedBox(width: 8),
                if (status == 'pending' || status == 'approved')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onDecide('rejected'),
                      icon: const Icon(Icons.comments_disabled_outlined, size: 18),
                      label: Text('moderation.reject_comment'.tr(),
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFFD77A),
                        side: const BorderSide(color: Color(0xFF6A5A2A)),
                      ),
                    ),
                  ),
              ]),
              if (status != 'annulled') ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => onDecide('annulled'),
                    icon: const Icon(Icons.close, size: 18),
                    label: Text('moderation.annul'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF9A9A),
                      side: const BorderSide(color: Color(0xFF7A3A3A)),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String suggestion;
  final String? reason;
  const _SuggestionChip({required this.suggestion, this.reason});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, String key) = switch (suggestion) {
      'approve' => (const Color(0xFF1F3A2A), const Color(0xFF7BE0A1), 'moderation.ia_approve'),
      'reject' => (const Color(0xFF4A2222), const Color(0xFFFF9A9A), 'moderation.ia_reject'),
      _ => (const Color(0xFF40361A), const Color(0xFFFFD77A), 'moderation.ia_unsure'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text(key.tr(), style: TextStyle(color: fg, fontSize: 12)),
        ),
        if (reason != null && reason!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(reason!,
                style: const TextStyle(color: AppColors.greyText, fontSize: 11)),
          ),
      ],
    );
  }
}

class _DecisionLine extends StatelessWidget {
  final String label, okText, noText;
  final bool ok;
  const _DecisionLine(
      {required this.label, required this.ok, required this.okText, required this.noText});

  @override
  Widget build(BuildContext context) {
    final color = ok ? const Color(0xFF7BE0A1) : const Color(0xFFFF9A9A);
    return Text.rich(TextSpan(children: [
      TextSpan(text: '$label: ', style: const TextStyle(color: AppColors.greyText)),
      TextSpan(text: ok ? okText : noText, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    ]), style: const TextStyle(fontSize: 12));
  }
}

/// Una fecha `2026-11-02` escrita como la escribe quien la lee, en su idioma.
String _fecha(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat.yMMMd(context.locale.toString()).format(d);
}

/// Dos opciones excluyentes con la actual marcada.
class _Toggle extends StatelessWidget {
  final String label, leftText, rightText;
  final bool leftSelected;
  final VoidCallback onLeft, onRight;
  const _Toggle({
    required this.label,
    required this.leftText,
    required this.rightText,
    required this.leftSelected,
    required this.onLeft,
    required this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    Widget opt(String text, bool selected, Color color, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: selected ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.22) : Colors.transparent,
                border: Border.all(color: selected ? color : AppColors.greyDark),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(text,
                  style: TextStyle(
                      color: selected ? color : AppColors.greyText,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
            ),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.greyText, fontSize: 11)),
      const SizedBox(height: 4),
      Row(children: [
        opt(leftText, leftSelected, const Color(0xFF7BE0A1), onLeft),
        const SizedBox(width: 8),
        opt(rightText, !leftSelected, const Color(0xFFFF9A9A), onRight),
      ]),
    ]);
  }
}

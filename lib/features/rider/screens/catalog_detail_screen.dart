import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/report_dialog.dart';
import '../providers/catalog_service.dart';
import 'catalog_screen.dart' show categoryColor, seasonColor;

/// La ficha de una ruta del catálogo: qué es, cuándo se puede hacer, qué dicen los
/// moteros, y lo que se puede hacer con ella (abrirla en Google Maps, hacerla desde
/// donde estás, valorarla si se ha rodado).
class CatalogDetailScreen extends StatefulWidget {
  final int id;
  const CatalogDetailScreen({super.key, required this.id});

  @override
  State<CatalogDetailScreen> createState() => _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends State<CatalogDetailScreen> {
  Map<String, dynamic>? _route;
  bool _error = false;

  final List<Map<String, dynamic>> _comments = [];
  int _commentPage = 1;
  bool _moreComments = false;
  bool _loadingComments = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await CatalogService.detail(widget.id);
    if (!mounted) return;
    if (r == null) {
      setState(() => _error = true);
      return;
    }
    setState(() {
      _route = r;
      _error = false;
    });
    _loadComments();
  }

  Future<void> _loadComments({bool more = false}) async {
    if (_loadingComments) return;
    setState(() => _loadingComments = true);
    final page = more ? _commentPage + 1 : 1;
    final r = await CatalogService.ratings(widget.id, page: page);
    if (!mounted) return;
    setState(() {
      _loadingComments = false;
      if (r == null) return;
      if (!more) _comments.clear();
      _commentPage = page;
      _comments.addAll(List<Map<String, dynamic>>.from(
          (r['comments'] as List).map((e) => Map<String, dynamic>.from(e as Map))));
      _moreComments = r['has_more'] == true;
      // La media y los votos pueden haber cambiado desde la lista.
      _route = {..._route!, 'rating': r['rating'], 'votes': r['votes']};
    });
  }

  Future<void> _openMaps() async {
    final url = _route?['google_maps_url'] as String?;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  String _month(int m) =>
      DateFormat.MMMM(context.locale.toString()).format(DateTime(2024, m));

  Future<void> _rate() async {
    final mine = Map<String, dynamic>.from(_route!['mine'] as Map);
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _RateSheet(
        catalogId: widget.id,
        routeId: (mine['route_id'] as num).toInt(),
        initialStars: (mine['stars'] as num?)?.toInt(),
        initialComment: mine['comment'] as String?,
        commentOnly: mine['is_author'] == true,
      ),
    );
    if (done == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _route;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.white),
          onPressed: () => context.canPop() ? context.pop() : context.go('/rider/catalog'),
        ),
        title: Text('catalog.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          // Denunciar: discreto, en el menú de tres puntos (no si la ruta es tuya).
          if (r != null && (r['mine'] as Map? ?? const {})['is_author'] != true)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.grey),
              color: AppColors.surface,
              onSelected: (_) => showReportDialog(context, targetType: 'catalog_route', targetId: widget.id),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'report',
                  child: Row(children: [
                    const Icon(Icons.outlined_flag, size: 18, color: AppColors.grey),
                    const SizedBox(width: 8),
                    Text('report.route_title'.tr(), style: const TextStyle(color: AppColors.white)),
                  ]),
                ),
              ],
            ),
        ],
      ),
      body: r == null
          ? Center(
              child: _error
                  ? TextButton(onPressed: _load, child: Text('catalog.load_error'.tr()))
                  : const CircularProgressIndicator())
          : _content(r),
    );
  }

  Widget _content(Map<String, dynamic> r) {
    final cat = r['category'] as String?;
    final rating = (r['rating'] as num?)?.toDouble();
    final votes = (r['votes'] as num?)?.toInt() ?? 0;
    final passes = List<String>.from((r['passes'] as List?) ?? const []);
    final season = r['season'] as Map?;
    final mine = r['mine'] as Map? ?? const {};
    final place = [r['region'], r['countries_label'] ?? r['country_name']]
        .where((e) => e != null && '$e'.isNotEmpty)
        .join(' · ');

    return ListView(
      padding: EdgeInsets.fromLTRB(18, 16, 18, 32 + MediaQuery.of(context).padding.bottom),
      children: [
        Text('${r['name']}',
            style: const TextStyle(
                color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(place, style: const TextStyle(color: AppColors.greyText, fontSize: 14)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _Pill('${r['category_label']}', categoryColor(cat)),
          _Pill('${r['kind_label']}', AppColors.cyan),
          _Pill(
              'catalog.km_short'.tr(namedArgs: {'km': '${(r['km'] as num).round()}'}),
              AppColors.greyText),
          _Pill('${r['season_label']}', seasonColor(r['season_state'] as String?)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          const Icon(Icons.star, color: AppColors.gold, size: 20),
          const SizedBox(width: 6),
          Text(
            rating == null
                ? 'catalog.no_rating'.tr()
                : '${rating.toStringAsFixed(1)} · ${'catalog.votes'.tr(namedArgs: {'n': '$votes'})}',
            style: const TextStyle(color: AppColors.white, fontSize: 15),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.verified_outlined,
              size: 16, color: r['source'] == 'community' ? AppColors.cyan : AppColors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${r['source_label']}'
                '${r['verified_label'] != null ? ' · ${r['verified_label']}' : ''}',
                style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 16),
        Text('${r['description']}',
            style: const TextStyle(color: AppColors.white, fontSize: 15, height: 1.45)),
        const SizedBox(height: 6),
        Text('${r['category_description']}',
            style: const TextStyle(color: AppColors.greyText, fontSize: 14, height: 1.45)),
        if (r['noisy_note'] != null) ...[
          const SizedBox(height: 6),
          Text('${r['noisy_note']}',
              style: const TextStyle(color: AppColors.greyText, fontSize: 12, height: 1.4)),
        ],
        if (passes.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Line(Icons.landscape_outlined,
              'catalog.passes'.tr(namedArgs: {'names': passes.join(', ')})),
        ],
        if ((r['road_codes'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          _Line(Icons.add_road,
              'catalog.roads'.tr(namedArgs: {'roads': '${r['road_codes']}'.replaceAll('|', ' · ')})),
        ],
        if (season != null && season['opens'] != null && season['closes'] != null) ...[
          const SizedBox(height: 8),
          _Line(
              Icons.calendar_month_outlined,
              'catalog.season_range'.tr(namedArgs: {
                'from': _month((season['opens'] as num).toInt()),
                'to': _month((season['closes'] as num).toInt()),
              })),
        ],
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => context.push('/rider/catalog/${widget.id}/plan', extra: r),
          icon: const Icon(Icons.two_wheeler, color: Colors.white),
          label: Text('catalog.do_route'.tr(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openMaps,
          icon: const Icon(Icons.map_outlined, color: AppColors.cyan),
          label: Text('catalog.open_maps'.tr(), style: const TextStyle(color: AppColors.cyan)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: AppColors.cyan),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 26),
        Row(children: [
          Expanded(
            child: Text('catalog.ratings'.tr(),
                style: const TextStyle(
                    color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          if (mine['ridden'] == true)
            TextButton.icon(
              onPressed: _rate,
              icon: const Icon(Icons.star_outline, color: AppColors.gold),
              label: Text(
                  mine['stars'] != null ? 'catalog.your_rating'.tr() : 'catalog.rate'.tr(),
                  style: const TextStyle(color: AppColors.gold)),
            ),
        ]),
        if (mine['ridden'] != true || mine['is_author'] == true)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
                mine['is_author'] == true
                    ? 'catalog.rate_author'.tr()
                    : (mine['ridden_short'] == true
                        ? 'catalog.rate_not_enough'.tr()
                        : 'catalog.rate_only_ridden'.tr()),
                style: const TextStyle(color: AppColors.greyText, fontSize: 12, height: 1.4)),
          ),
        if (_comments.isEmpty && !_loadingComments)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('catalog.no_comments'.tr(),
                style: const TextStyle(color: AppColors.greyText)),
          ),
        for (final c in _comments) _CommentTile(c),
        if (_moreComments)
          TextButton(
            onPressed: _loadingComments ? null : () => _loadComments(more: true),
            child: Text('catalog.more'.tr()),
          ),
        if (_loadingComments)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: AppColors.greyText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.4)),
        ),
      ]);
}

class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> c;
  const _CommentTile(this.c);

  @override
  Widget build(BuildContext context) {
    final stars = (c['stars'] as num?)?.toInt();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${c['nickname'] ?? ''}',
              style: const TextStyle(
                  color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          const Spacer(),
          if (stars != null)
            Row(children: [
              for (var i = 1; i <= 5; i++)
                Icon(i <= stars ? Icons.star : Icons.star_border,
                    size: 14, color: AppColors.gold),
            ]),
        ]),
        const SizedBox(height: 6),
        Text('${c['comment']}',
            style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.4)),
        if (c['is_mine'] != true && c['id'] != null)
          Align(
            alignment: Alignment.centerRight,
            child: ReportLink(targetType: 'catalog_comment', targetId: (c['id'] as num).toInt()),
          ),
      ]),
    );
  }
}

/// Hoja para valorar una ruta rodada: estrellas, ¿estaba abierta?, ¿obras? y comentario.
class _RateSheet extends StatefulWidget {
  final int catalogId;
  final int routeId;
  final int? initialStars;
  final String? initialComment;
  /// El autor de la ruta solo puede comentarla, no puntuarla.
  final bool commentOnly;
  const _RateSheet({
    required this.catalogId,
    required this.routeId,
    this.initialStars,
    this.initialComment,
    this.commentOnly = false,
  });

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  late int? _stars = widget.initialStars;
  late final _comment = TextEditingController(text: widget.initialComment ?? '');
  bool? _wasOpen;
  bool? _roadworks;
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final r = await CatalogService.rate(
      widget.catalogId,
      routeId: widget.routeId,
      stars: widget.commentOnly ? null : _stars,
      wasOpen: widget.commentOnly ? null : _wasOpen,
      roadworks: widget.commentOnly ? null : _roadworks,
      comment: _comment.text,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    final msg = (r['error'] ?? r['message'] ?? 'catalog.thanks'.tr()).toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (r['error'] == null) Navigator.pop(context, true);
  }

  Widget _yesNo(String label, bool? value, ValueChanged<bool?> onChange) => Row(children: [
        Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.white, fontSize: 14))),
        ChoiceChip(
            label: Text('common.yes'.tr()),
            selected: value == true,
            onSelected: (v) => onChange(v ? true : null)),
        const SizedBox(width: 6),
        ChoiceChip(
            label: Text('common.no'.tr()),
            selected: value == false,
            onSelected: (v) => onChange(v ? false : null)),
      ]);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            18, 16, 18, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('catalog.rate'.tr(),
                style: const TextStyle(
                    color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (!widget.commentOnly) Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 36,
                  onPressed: () => setState(() => _stars = i),
                  icon: Icon((_stars ?? 0) >= i ? Icons.star : Icons.star_border,
                      color: AppColors.gold),
                ),
            ]),
            if (!widget.commentOnly) ...[
              _yesNo('catalog.was_open'.tr(), _wasOpen, (v) => setState(() => _wasOpen = v)),
              _yesNo('catalog.roadworks'.tr(), _roadworks, (v) => setState(() => _roadworks = v)),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _comment,
              maxLines: 3,
              maxLength: 500,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'catalog.comment_hint'.tr(),
                hintStyle: const TextStyle(color: AppColors.greyText),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange, minimumSize: const Size.fromHeight(48)),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('catalog.send'.tr(),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

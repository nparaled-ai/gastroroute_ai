import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../widgets/profile_menu_button.dart';
import '../providers/moderation_service.dart';

/// Inicio de Moderación: lo pendiente de cada tipo.
///
/// Nada de lo que escriben los moteros se publica sin que lo apruebe el
/// administrador. Solo llega aquí quien tiene el perfil de administrador o de
/// moderador, que se asigna únicamente desde la base de datos.
class ModerationHomeScreen extends StatefulWidget {
  const ModerationHomeScreen({super.key});

  @override
  State<ModerationHomeScreen> createState() => _ModerationHomeScreenState();
}

class _ModerationHomeScreenState extends State<ModerationHomeScreen> {
  Map<String, int>? _counts;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    if (PushNotificationService.consumePendingModeration()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push('/admin/moderation/comments');
      });
    }
  }

  Future<void> _load() async {
    final c = await ModerationService.summary();
    if (!mounted) return;
    setState(() {
      _counts = c;
      _loading = false;
    });
  }

  int get _total => (_counts ?? const {}).values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final c = _counts ?? const <String, int>{};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('moderation.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w800)),
        actions: const [ProfileMenuButton()],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 32 + MediaQuery.of(context).padding.bottom),
          children: [
            Text('moderation.pending_title'.tr(),
                style: const TextStyle(
                    color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _loading
                  ? ''
                  : (_total == 0
                      ? 'moderation.nothing_pending'.tr()
                      : 'moderation.pending_total'.tr(namedArgs: {'n': '$_total'})),
              style: const TextStyle(color: AppColors.greyText, fontSize: 14),
            ),
            const SizedBox(height: 18),
            _Tile(
              icon: Icons.chat_bubble_outline,
              label: 'moderation.comments'.tr(),
              count: c['comments'] ?? 0,
              onTap: () async {
                await context.push('/admin/moderation/comments');
                _load();
              },
            ),
            _Tile(
              icon: Icons.route,
              label: 'moderation.routes'.tr(),
              count: c['routes'] ?? 0,
              onTap: () async {
                await context.push('/admin/moderation/routes');
                _load();
              },
            ),
            _Tile(
              icon: Icons.rate_review_outlined,
              label: 'catalog.mod_comments'.tr(),
              count: c['catalog_comments'] ?? 0,
              onTap: () async {
                await context.push('/admin/moderation/catalog-comments');
                _load();
              },
            ),
            _Tile(
              icon: Icons.storefront_outlined,
              label: 'moderation.partners'.tr(),
              count: c['partners'] ?? 0,
              soon: true,
            ),
            _Tile(
              icon: Icons.place_outlined,
              label: 'moderation.points'.tr(),
              count: c['points'] ?? 0,
              soon: true,
            ),
            _Tile(
              icon: Icons.door_front_door_outlined,
              label: 'moderation.closed'.tr(),
              count: c['closed'] ?? 0,
              soon: true,
            ),
            const SizedBox(height: 16),
            Text('moderation.footer'.tr(),
                style: const TextStyle(color: AppColors.greyText, fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool soon;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.label,
    required this.count,
    this.soon = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const violeta = Color(0xFFB9A2FF);

    return Opacity(
      opacity: soon ? 0.55 : 1,
      child: Card(
        color: AppColors.card,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(icon, color: violeta),
          title: Text(label, style: const TextStyle(color: AppColors.white)),
          subtitle: soon
              ? Text('moderation.soon'.tr(),
                  style: const TextStyle(color: AppColors.greyText, fontSize: 12))
              : null,
          trailing: count > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count',
                      style: const TextStyle(
                          color: AppColors.background,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                )
              : null,
          onTap: soon ? null : onTap,
        ),
      ),
    );
  }
}

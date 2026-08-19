import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/achievement_service.dart';
import '../widgets/achievement_style.dart';

/// Pantalla de logros del motero.
///
/// Muestra el catálogo completo, también lo bloqueado: ver lo que queda por
/// conseguir es parte de lo que engancha. El orden de las categorías es fijo.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await AchievementService.getAll();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  void _openDetail(Map<String, dynamic> category) {
    _openSheet(_CategoryDetailSheet(category: category));
  }

  void _openSpecialDetail(Map<String, dynamic> special) {
    _openSheet(_SpecialDetailSheet(special: special));
  }

  void _openSheet(Widget child) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => child,
    );
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
          onPressed: () => context.go('/rider/home'),
        ),
        title: Text('achievements.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _data == null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _load, child: Text('common.retry'.tr())),
                  ]),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final total = (_data!['total'] as num?)?.toInt() ?? 0;
    final unlocked = (_data!['unlocked'] as num?)?.toInt() ?? 0;
    final progressive = List<Map<String, dynamic>>.from(_data!['progressive'] ?? []);
    final special = List<Map<String, dynamic>>.from(_data!['special'] ?? []);

    final percent = total > 0 ? (unlocked / total) : 0.0;

    return RefreshIndicator(
      color: AppColors.orange,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Cabecera con el progreso global: da sensación de avance desde el
          // primer vistazo, aunque no se haya desbloqueado casi nada.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.orange),
            ),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('achievements.progress'.tr(namedArgs: {
                        'unlocked': '$unlocked',
                        'total': '$total',
                      }), style: const TextStyle(
                          color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('achievements.progress_desc'.tr(),
                          style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                    ]),
                  ),
                  Text('${(percent * 100).round()}%',
                      style: const TextStyle(
                          color: AppColors.orange, fontSize: 24, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 10),
              _Bar(value: percent, color: AppColors.orange),
            ]),
          ),

          // Banner de bienvenida mientras no haya ningún logro
          if (unlocked == 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.emoji_events_outlined, color: AppColors.orange, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('achievements.empty_hint'.tr(),
                      style: const TextStyle(color: AppColors.white, fontSize: 12, height: 1.4)),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 24),
          Text('achievements.progressive'.tr(),
              style: const TextStyle(
                  color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          ...progressive.map((c) => _CategoryCard(
                category: c,
                onTap: () => _openDetail(c),
              )),

          const SizedBox(height: 24),
          Text('achievements.special'.tr(),
              style: const TextStyle(
                  color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: special
                .map((s) => _SpecialBadge(
                      special: s,
                      onTap: () => _openSpecialDetail(s),
                    ))
                .toList(),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final Color color;

  const _Bar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 6,
        backgroundColor: AppColors.greyDark,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final Map<String, dynamic> category;
  final VoidCallback onTap;

  const _CategoryCard({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = category['category'] as String;
    final currentTier = category['current_tier'] as String?;
    final nextTier = category['next_tier'] as String?;
    final value = (category['value'] as num?)?.toInt() ?? 0;
    final threshold = (category['next_threshold'] as num?)?.toInt();
    final remaining = (category['remaining'] as num?)?.toInt() ?? 0;
    final progress = (category['progress'] as num?)?.toDouble() ?? 0;

    final locked = currentTier == null;
    final color = locked
        ? AppColors.grey
        : AchievementStyle.tierColor(currentTier);

    return Opacity(
      // Bloqueados atenuados pero visibles: se ve lo que hay por conseguir.
      opacity: locked ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.greyDark),
          ),
          child: Column(children: [
            Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(AchievementStyle.categoryIcon(name), color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AchievementStyle.categoryLabel(name).tr(),
                          style: const TextStyle(
                              color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      _TierPill(tier: currentTier),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    threshold == null
                        ? 'achievements.max_tier'.tr()
                        : 'achievements.progress_line'.tr(namedArgs: {
                            'value': '$value',
                            'threshold': '$threshold',
                            'remaining': '$remaining',
                          }),
                    style: const TextStyle(color: AppColors.grey, fontSize: 11),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            _Bar(
              value: progress,
              color: nextTier != null
                  ? AchievementStyle.tierColor(nextTier)
                  : AchievementStyle.platino,
            ),
          ]),
        ),
      ),
    );
  }
}

class _TierPill extends StatelessWidget {
  final String? tier;

  const _TierPill({required this.tier});

  @override
  Widget build(BuildContext context) {
    final locked = tier == null;
    final color = AchievementStyle.tierColor(tier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: locked ? AppColors.card : color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        locked
            ? 'achievements.locked'.tr().toUpperCase()
            : 'achievements.tier_$tier'.tr().toUpperCase(),
        style: TextStyle(
          color: locked ? AppColors.grey : AchievementStyle.tierTextColor(tier),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SpecialBadge extends StatelessWidget {
  final Map<String, dynamic> special;
  final VoidCallback onTap;

  const _SpecialBadge({required this.special, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unlocked = special['unlocked'] == true;
    final code = special['code'] as String?;
    final color = unlocked ? AppColors.orange : AppColors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        // Bloqueados atenuados, pero no tanto que no se puedan leer: hay que
        // poder ver qué son para querer conseguirlos.
        opacity: unlocked ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: unlocked ? AppColors.orange.withValues(alpha: 0.5) : AppColors.greyDark),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AchievementStyle.specialIcon(code), color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                AchievementStyle.specialLabel(code).tr(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.white, fontSize: 9, height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detalle de un logro especial: qué hay que hacer para conseguirlo.
///
/// Sin esto, la rejilla solo muestra un icono y un nombre. "Coleccionista" no
/// dice nada por sí solo, y en los bloqueados es peor: se ve que falta algo
/// pero no qué hay que hacer.
class _SpecialDetailSheet extends StatelessWidget {
  final Map<String, dynamic> special;

  const _SpecialDetailSheet({required this.special});

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final date = DateTime.tryParse(iso);
    return date == null ? '' : DateFormat.yMMMMd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = special['unlocked'] == true;
    final code = special['code'] as String?;
    final color = unlocked ? AppColors.orange : AppColors.grey;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(AchievementStyle.specialIcon(code), color: color, size: 36),
            ),
            const SizedBox(height: 14),

            Text(AchievementStyle.specialLabel(code).tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.white, fontSize: 19, fontWeight: FontWeight.w700)),

            const SizedBox(height: 10),

            // Lo importante: qué hay que hacer para conseguirlo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                Text('achievements.how_to'.tr(),
                    style: const TextStyle(
                        color: AppColors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('achievements.special_desc_$code'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.white, fontSize: 13, height: 1.5)),
              ]),
            ),

            const SizedBox(height: 14),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(unlocked ? Icons.check_circle : Icons.lock_outline,
                    color: color, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    unlocked
                        ? 'achievements.unlocked_on'.tr(namedArgs: {
                            'date': _formatDate(special['unlocked_at'] as String?),
                          })
                        : 'achievements.not_yet'.tr(),
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Detalle de una categoría: los cuatro niveles, con fecha de consecución.
class _CategoryDetailSheet extends StatelessWidget {
  final Map<String, dynamic> category;

  const _CategoryDetailSheet({required this.category});

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final date = DateTime.tryParse(iso);
    if (date == null) return '';
    return DateFormat.yMMMMd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    final name = category['category'] as String;
    final currentTier = category['current_tier'] as String?;
    final nextTier = category['next_tier'] as String?;
    final value = (category['value'] as num?)?.toInt() ?? 0;
    final threshold = (category['next_threshold'] as num?)?.toInt();
    final remaining = (category['remaining'] as num?)?.toInt() ?? 0;
    final progress = (category['progress'] as num?)?.toDouble() ?? 0;
    final tiers = List<Map<String, dynamic>>.from(category['tiers'] ?? []);

    final color = AchievementStyle.tierColor(currentTier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(AchievementStyle.categoryIcon(name), color: color, size: 34),
                ),
                const SizedBox(height: 12),
                Text(
                  currentTier == null
                      ? AchievementStyle.categoryLabel(name).tr()
                      : 'achievements.tier_level'.tr(namedArgs: {
                          'tier': 'achievements.tier_$currentTier'.tr(),
                        }),
                  style: const TextStyle(
                      color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text('achievements.desc_$name'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.5)),
              ]),
            ),

            const SizedBox(height: 20),

            if (threshold != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('achievements.next_tier'.tr(namedArgs: {
                        'tier': 'achievements.tier_$nextTier'.tr(),
                      }), style: const TextStyle(
                          color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('$value / $threshold',
                          style: TextStyle(
                              color: AchievementStyle.tierColor(nextTier),
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _Bar(value: progress, color: AchievementStyle.tierColor(nextTier)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('achievements.remaining'.tr(namedArgs: {'n': '$remaining'}),
                        style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
            ],

            Text('achievements.levels'.tr(),
                style: const TextStyle(
                    color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),

            ...tiers.map((t) {
              final tier = t['tier'] as String?;
              final done = t['unlocked'] == true;
              final isCurrent = tier == currentTier;
              final tierColor = AchievementStyle.tierColor(tier);

              return Opacity(
                opacity: done ? 1 : 0.4,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isCurrent ? tierColor : Colors.transparent),
                  ),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(done ? Icons.check : Icons.lock_outline,
                          color: done ? tierColor : AppColors.grey, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('achievements.tier_$tier'.tr(),
                            style: const TextStyle(
                                color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('${t['threshold']}',
                            style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                        if (done)
                          Text(
                            'achievements.unlocked_on'.tr(
                                namedArgs: {'date': _formatDate(t['unlocked_at'] as String?)}),
                            style: TextStyle(color: tierColor, fontSize: 10),
                          ),
                      ]),
                    ),
                  ]),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

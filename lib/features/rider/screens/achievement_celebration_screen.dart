import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/achievement_service.dart';
import '../widgets/achievement_style.dart';

/// Pantalla de celebración al desbloquear logros.
///
/// Es el momento del descubrimiento: el resumen de ruta no los menciona a
/// propósito. Si se desbloquean varios a la vez se muestran todos en UNA sola
/// pantalla, no una por logro.
class AchievementCelebrationScreen extends StatefulWidget {
  final List<Map<String, dynamic>> achievements;

  /// A dónde ir al cerrar. Viniendo de una ruta se vuelve a la principal;
  /// viniendo de la tarjeta de Logros, a la lista, que es lo que se iba a ver.
  final String nextRoute;

  const AchievementCelebrationScreen({
    super.key,
    required this.achievements,
    this.nextRoute = '/rider/home',
  });

  @override
  State<AchievementCelebrationScreen> createState() =>
      _AchievementCelebrationScreenState();
}

class _AchievementCelebrationScreenState extends State<AchievementCelebrationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Rebote al aparecer: la insignia entra con un pequeño exceso y se asienta.
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    // Marcar como celebrados antes de salir: si no, volverían a aparecer.
    final ids = widget.achievements
        .map((a) => a['id'])
        .whereType<int>()
        .toList();

    await AchievementService.markCelebrated(ids);

    if (!mounted) return;
    context.go(widget.nextRoute);
  }

  /// Nombre del logro: los progresivos llevan categoría y nivel; los
  /// especiales, su propio nombre.
  String _nameOf(Map<String, dynamic> achievement) {
    final category = achievement['category'] as String?;
    final tier = achievement['tier'] as String?;

    if (category == 'special' || tier == null) {
      return AchievementStyle.specialLabel(achievement['code'] as String?).tr();
    }

    return '${AchievementStyle.categoryLabel(category!).tr()} · '
        '${'achievements.tier_$tier'.tr()}';
  }

  IconData _iconOf(Map<String, dynamic> achievement) {
    final category = achievement['category'] as String?;
    return (category == null || category == 'special')
        ? AchievementStyle.specialIcon(achievement['code'] as String?)
        : AchievementStyle.categoryIcon(category);
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.achievements.length > 1;

    return PopScope(
      // Debe salirse por el botón, para que se marquen como celebrados.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),

                FadeTransition(
                  opacity: _fade,
                  child: Column(children: [
                    Text('achievements.celebration_title'.plural(widget.achievements.length),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.orange,
                            fontSize: 26,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('achievements.celebration_subtitle'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.grey, fontSize: 13, height: 1.5)),
                  ]),
                ),

                const SizedBox(height: 36),

                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: widget.achievements.map((achievement) {
                        final tier = achievement['tier'] as String?;
                        final color = tier != null
                            ? AchievementStyle.tierColor(tier)
                            : AppColors.orange;

                        return ScaleTransition(
                          scale: _scale,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: EdgeInsets.all(many ? 16 : 24),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: color, width: 2),
                            ),
                            child: Column(children: [
                              Container(
                                width: many ? 60 : 92,
                                height: many ? 60 : 92,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(_iconOf(achievement),
                                    color: color, size: many ? 30 : 46),
                              ),
                              SizedBox(height: many ? 10 : 16),
                              Text(_nameOf(achievement),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColors.white,
                                      fontSize: many ? 15 : 19,
                                      fontWeight: FontWeight.w700)),
                              if (achievement['value_at_unlock'] != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'achievements.reached_with'.tr(namedArgs: {
                                    'value': '${achievement['value_at_unlock']}',
                                  }),
                                  style: TextStyle(color: color, fontSize: 12),
                                ),
                              ],
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _close,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      backgroundColor: AppColors.orange,
                    ),
                    child: Text('achievements.celebration_button'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

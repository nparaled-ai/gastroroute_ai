import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class PlannerSelectionScreen extends StatelessWidget {
  const PlannerSelectionScreen({super.key});

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
        title: Text('planner.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // Header IA
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.orange.withOpacity(0.2),
                  AppColors.cyan.withOpacity(0.1),
                ]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.orange, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('planner.ai_generated'.tr(),
                            style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('planner.what_plan'.tr(),
                            style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Text('planner.what_plan'.tr(),
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),

            const SizedBox(height: 20),

            // Opción Ruta
            _PlanOption(
              icon: Icons.explore_outlined,
              emoji: '🏍️',
              title: 'planner.route'.tr(),
              desc: 'planner.route_desc'.tr(),
              color: AppColors.orange,
              available: true,
              onTap: () => context.go('/rider/route-generator'),
            ),

            const SizedBox(height: 16),

            // Opción Viaje
            _PlanOption(
              icon: Icons.map_outlined,
              emoji: '🗺️',
              title: 'planner.trip'.tr(),
              desc: 'planner.trip_desc'.tr(),
              color: AppColors.cyan,
              available: false,
              badge: 'planner.trip_coming_soon'.tr(),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  final IconData icon;
  final String emoji;
  final String title;
  final String desc;
  final Color color;
  final bool available;
  final String? badge;
  final VoidCallback onTap;

  const _PlanOption({
    required this.icon,
    required this.emoji,
    required this.title,
    required this.desc,
    required this.color,
    required this.available,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: available ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: available ? color.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: available ? color.withOpacity(0.5) : AppColors.greyDark,
            width: available ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icono grande
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: available
                    ? color.withOpacity(0.15)
                    : AppColors.greyDark.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 36)),
              ),
            ),

            const SizedBox(width: 20),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: available ? color : AppColors.greyDark,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.greyDark.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                                color: AppColors.grey,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    desc,
                    style: TextStyle(
                      color: available ? AppColors.grey : AppColors.greyDark,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            if (available)
              Icon(Icons.arrow_forward_ios, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

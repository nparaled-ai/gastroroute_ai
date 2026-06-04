import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/auth_service.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            children: [
              TextSpan(text: 'GAS', style: TextStyle(color: AppColors.orange)),
              TextSpan(text: 'troroute', style: TextStyle(color: AppColors.white)),
              TextSpan(text: 'AI', style: TextStyle(color: AppColors.cyan)),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outlined, color: AppColors.white),
            onPressed: () => context.go('/rider/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.grey),
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text('home.welcome'.tr(),
                style: const TextStyle(color: AppColors.white, fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('home.subtitle'.tr(),
                style: const TextStyle(color: AppColors.grey, fontSize: 14)),
            const SizedBox(height: 32),

            _QuickAccessCard(
              icon: Icons.person_outlined,
              title: 'home.my_profile'.tr(),
              desc: 'home.my_profile_desc'.tr(),
              color: AppColors.orange,
              onTap: () => context.go('/rider/profile'),
            ),
            const SizedBox(height: 16),
            _QuickAccessCard(
              icon: Icons.map_outlined,
              title: 'home.planner'.tr(),
              desc: 'home.planner_desc'.tr(),
              color: AppColors.cyan,
              onTap: () => context.go('/rider/planner'),
            ),
            const SizedBox(height: 16),
            _QuickAccessCard(
              icon: Icons.restaurant_outlined,
              title: 'home.gastronomy'.tr(),
              desc: 'home.gastronomy_desc'.tr(),
              color: AppColors.gold,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  final VoidCallback onTap;

  const _QuickAccessCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.greyDark),
        ),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(desc, style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: AppColors.grey, size: 16),
          ],
        ),
      ),
    );
  }
}

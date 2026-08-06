import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/rider_profile_service.dart';

class CreateRouteScreen extends StatefulWidget {
  const CreateRouteScreen({super.key});

  @override
  State<CreateRouteScreen> createState() => _CreateRouteScreenState();
}

class _CreateRouteScreenState extends State<CreateRouteScreen> {
  List<dynamic> _motos = [];
  bool _loadingMotos = true;

  @override
  void initState() {
    super.initState();
    _loadMotos();
  }

  Future<void> _loadMotos() async {
    final result = await RiderProfileService.getMotos();
    if (!mounted) return;
    setState(() {
      _motos = result['motos'] ?? [];
      _loadingMotos = false;
    });
  }

  void _requireMoto(VoidCallback onHasMoto) {
    if (_loadingMotos) return;
    if (_motos.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('create_route.no_moto_title'.tr(),
              style: const TextStyle(color: AppColors.white)),
          content: Text('create_route.no_moto_body'.tr(),
              style: const TextStyle(color: AppColors.grey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/rider/motos');
              },
              child: Text('create_route.add_moto'.tr()),
            ),
          ],
        ),
      );
      return;
    }
    onHasMoto();
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
        title: Text('create_route.title'.tr(),
            style: const TextStyle(
                color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          Text('create_route.how'.tr(),
              style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('create_route.subtitle'.tr(),
              style: const TextStyle(
                  color: AppColors.grey, fontSize: 14, height: 1.5)),
          const SizedBox(height: 32),

          _OptionCard(
            emoji: '✨',
            color: AppColors.orange,
            title: 'create_route.ai_title'.tr(),
            desc: 'create_route.ai_desc'.tr(),
            tags: ['create_route.ai_tag1'.tr(), 'create_route.ai_tag2'.tr()],
            onTap: () => _requireMoto(() => context.push('/rider/route-generator')),
          ),
          const SizedBox(height: 16),

          _OptionCard(
            emoji: '🗺️',
            color: const Color(0xFF4285F4),
            title: 'create_route.maps_title'.tr(),
            desc: 'create_route.maps_desc'.tr(),
            tags: ['create_route.maps_tag1'.tr(), 'create_route.maps_tag2'.tr()],
            onTap: () => _requireMoto(() => context.push('/rider/route-import')),
          ),
          const SizedBox(height: 16),

          _OptionCard(
            emoji: '📂',
            color: AppColors.cyan,
            title: 'create_route.gpx_title'.tr(),
            desc: 'create_route.gpx_desc'.tr(),
            tags: ['Wikiloc', 'Komoot', 'Garmin'],
            onTap: () => _requireMoto(() => context.push('/rider/route-import-gpx')),
          ),
          const SizedBox(height: 16),

          _OptionCard(
            emoji: '🏕️',
            color: AppColors.gold,
            title: 'create_route.multiday_title'.tr(),
            desc: 'create_route.multiday_desc'.tr(),
            tags: ['create_route.multiday_tag1'.tr(), 'create_route.multiday_tag2'.tr()],
            comingSoon: true,
            onTap: () {},
          ),

          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String emoji;
  final Color color;
  final String title;
  final String desc;
  final List<String> tags;
  final bool comingSoon;
  final VoidCallback onTap;

  const _OptionCard({
    required this.emoji,
    required this.color,
    required this.title,
    required this.desc,
    required this.tags,
    required this.onTap,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: comingSoon ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: comingSoon
                ? AppColors.greyDark
                : color.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Emoji icono
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: comingSoon
                  ? AppColors.greyDark
                  : color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 16),

          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title,
                    style: TextStyle(
                        color: comingSoon ? AppColors.grey : AppColors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                if (comingSoon) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.greyDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('create_route.coming_soon'.tr(),
                        style: const TextStyle(
                            color: AppColors.grey,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
              const SizedBox(height: 6),
              Text(desc,
                  style: const TextStyle(
                      color: AppColors.grey, fontSize: 13, height: 1.4)),
              const SizedBox(height: 10),
              // Tags
              Wrap(spacing: 6, runSpacing: 6, children: tags.map((tag) =>
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: comingSoon
                        ? AppColors.greyDark.withOpacity(0.5)
                        : color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: comingSoon
                            ? AppColors.greyDark
                            : color.withOpacity(0.3)),
                  ),
                  child: Text(tag,
                      style: TextStyle(
                          color: comingSoon ? AppColors.grey : color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ).toList()),
            ]),
          ),

          // Flecha o lock
          const SizedBox(width: 8),
          Icon(
            comingSoon ? Icons.lock_outline : Icons.arrow_forward_ios,
            color: comingSoon ? AppColors.greyDark : color,
            size: 16,
          ),
        ]),
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/rider_avatar.dart';
import '../providers/rider_profile_service.dart';

class RiderProfileScreen extends StatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() { _loading = true; _error = null; });
    final result = await RiderProfileService.getProfile();
    if (!mounted) return;
    if (result['error'] != null) {
      setState(() { _loading = false; _error = result['error']; });
      return;
    }
    setState(() { _loading = false; _profile = result['profile']; });
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
        title: Text('profile.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.orange),
            onPressed: _profile == null ? null : () async {
              await context.push('/rider/edit-profile', extra: _profile);
              _loadProfile();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: AppColors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadProfile, child: Text('common.retry'.tr())),
                    ],
                  ),
                )
              : _buildProfile(),
    );
  }

  Widget _buildProfile() {
    final profile = _profile!;
    final motos   = List<Map<String, dynamic>>.from(profile['motos'] ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + nickname
          Center(
            child: Column(
              children: [
                RiderAvatar(
                  avatarUrl: profile['avatar_url'],
                  level: profile['experience_level'] ?? 'novato',
                  size: 90,
                ),
                const SizedBox(height: 12),
                Text(profile['nickname'] ?? '',
                    style: const TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LevelBadge(level: profile['experience_level'] ?? 'novato'),
                    const SizedBox(width: 8),
                    _LanguageFlag(language: profile['language'] ?? 'es'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Stats
          Row(
            children: [
              _StatCard(label: 'profile.stats_km'.tr(),     value: '${profile['total_km'] ?? 0}'),
              const SizedBox(width: 12),
              _StatCard(label: 'profile.stats_routes'.tr(), value: '${profile['routes_completed'] ?? 0}'),
              const SizedBox(width: 12),
              _StatCard(label: 'profile.stats_lunches'.tr(), value: '${profile['lunches_completed'] ?? 0}'),
            ],
          ),

          const SizedBox(height: 24),

          // Bio
          if (profile['bio'] != null && profile['bio'].toString().isNotEmpty) ...[
            _SectionTitle('profile.about_me'.tr()),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.greyDark),
              ),
              child: Text(profile['bio'], style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5)),
            ),
            const SizedBox(height: 24),
          ],

          // Ubicación
          if (profile['province'] != null) ...[
            _SectionTitle('profile.location'.tr()),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.greyDark),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: AppColors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text('${profile['province']}, ${profile['country'] ?? 'ES'}',
                      style: const TextStyle(color: AppColors.white, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Motos
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionTitle('profile.my_motos'.tr()),
              GestureDetector(
                onTap: () => context.go('/rider/motos'),
                child: Text('profile.manage_motos'.tr(),
                    style: const TextStyle(color: AppColors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (motos.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.greyDark),
              ),
              child: Column(
                children: [
                  const Icon(Icons.two_wheeler, color: AppColors.grey, size: 40),
                  const SizedBox(height: 8),
                  Text('profile.no_motos'.tr(), style: const TextStyle(color: AppColors.grey)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.go('/rider/motos'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(160, 44)),
                    child: Text('profile.add_moto'.tr()),
                  ),
                ],
              ),
            )
          else
            ...motos.map((moto) => _MotoCard(moto: moto)),
        ],
      ),
    );
  }
}

class _LanguageFlag extends StatelessWidget {
  final String language;
  const _LanguageFlag({required this.language});

  String get _flag {
    switch (language) {
      case 'en': return '🇬🇧';
      case 'fr': return '🇫🇷';
      case 'de': return '🇩🇪';
      case 'it': return '🇮🇹';
      case 'pt': return '🇵🇹';
      default:   return '🇪🇸';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.greyDark),
      ),
      child: Text(_flag, style: const TextStyle(fontSize: 14)),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  final String level;
  const _LevelBadge({required this.level});

  Color get _color {
    switch (level) {
      case 'experto':    return AppColors.gold;
      case 'intermedio': return AppColors.cyan;
      default:           return AppColors.grey;
    }
  }

  String _label(BuildContext context) {
    switch (level) {
      case 'experto':    return 'profile.level_expert'.tr();
      case 'intermedio': return 'profile.level_intermediate'.tr();
      default:           return 'profile.level_novice'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(_label(context),
          style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.greyDark),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: AppColors.orange, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700));
  }
}

class _MotoCard extends StatelessWidget {
  final Map<String, dynamic> moto;
  const _MotoCard({required this.moto});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: moto['is_primary'] == true ? AppColors.orange : AppColors.greyDark),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.two_wheeler, color: AppColors.orange, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(moto['alias'] ?? '${moto['brand']} ${moto['model']}',
                        style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    if (moto['is_primary'] == true) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('motos.primary'.tr(),
                            style: const TextStyle(color: AppColors.orange, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text('${moto['brand'] ?? ''} ${moto['model'] ?? ''} · ${moto['year'] ?? ''} · ${moto['engine_cc'] ?? ''}cc',
                    style: const TextStyle(color: AppColors.grey, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

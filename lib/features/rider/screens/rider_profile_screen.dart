import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/auth_service.dart';
import '../../../core/theme/app_theme.dart';
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
        title: const Text(
          'Mi Perfil',
          style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.orange),
            onPressed: _profile == null ? null : () {
              context.go('/rider/edit-profile', extra: _profile);
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
                      ElevatedButton(
                        onPressed: _loadProfile,
                        child: const Text('Reintentar'),
                      ),
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
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.orange, width: 2),
                  ),
                  child: const Icon(Icons.person, color: AppColors.grey, size: 48),
                ),
                const SizedBox(height: 12),
                Text(
                  profile['nickname'] ?? '',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                _LevelBadge(level: profile['experience_level'] ?? 'novato'),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Stats
          Row(
            children: [
              _StatCard(label: 'Km totales',  value: '${profile['total_km'] ?? 0}'),
              const SizedBox(width: 12),
              _StatCard(label: 'Rutas',       value: '${profile['routes_completed'] ?? 0}'),
              const SizedBox(width: 12),
              _StatCard(label: 'Comidas',     value: '${profile['lunches_completed'] ?? 0}'),
            ],
          ),

          const SizedBox(height: 24),

          // Bio
          if (profile['bio'] != null && profile['bio'].toString().isNotEmpty) ...[
            _SectionTitle('Sobre mí'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.greyDark),
              ),
              child: Text(
                profile['bio'],
                style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Ubicación
          if (profile['province'] != null) ...[
            _SectionTitle('Ubicación'),
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
                  Text(
                    '${profile['province']}, ${profile['country'] ?? 'ES'}',
                    style: const TextStyle(color: AppColors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Motos
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionTitle('Mis Motos'),
              GestureDetector(
                onTap: () => context.go('/rider/motos'),
                child: const Text(
                  'Gestionar',
                  style: TextStyle(color: AppColors.orange, fontSize: 13, fontWeight: FontWeight.w600),
                ),
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
                  const Text(
                    'No tienes motos añadidas',
                    style: TextStyle(color: AppColors.grey),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.go('/rider/motos'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(160, 44),
                    ),
                    child: const Text('AÑADIR MOTO'),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(
        level.toUpperCase(),
        style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
      ),
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
            Text(
              value,
              style: const TextStyle(
                color: AppColors.orange,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: AppColors.grey, fontSize: 11),
            ),
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
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
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
        border: Border.all(
          color: moto['is_primary'] == true ? AppColors.orange : AppColors.greyDark,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.two_wheeler, color: AppColors.orange, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      moto['alias'] ?? '${moto['brand']} ${moto['model']}',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (moto['is_primary'] == true) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Principal',
                          style: TextStyle(color: AppColors.orange, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${moto['brand'] ?? ''} ${moto['model'] ?? ''} · ${moto['year'] ?? ''} · ${moto['engine_cc'] ?? ''}cc',
                  style: const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
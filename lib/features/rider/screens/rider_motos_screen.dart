import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/rider_profile_service.dart';

class RiderMotosScreen extends StatefulWidget {
  const RiderMotosScreen({super.key});

  @override
  State<RiderMotosScreen> createState() => _RiderMotosScreenState();
}

class _RiderMotosScreenState extends State<RiderMotosScreen> {
  List<Map<String, dynamic>> _motos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMotos();
  }

  Future<void> _loadMotos() async {
    setState(() { _loading = true; _error = null; });
    final result = await RiderProfileService.getMotos();
    if (!mounted) return;
    if (result['error'] != null) {
      setState(() { _loading = false; _error = result['error']; });
      return;
    }
    setState(() { _loading = false; _motos = List<Map<String, dynamic>>.from(result['motos']); });
  }

  Future<void> _deleteMoto(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('motos.edit_title'.tr(), style: const TextStyle(color: AppColors.white)),
        content: Text('motos.delete_confirm'.tr(), style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr(), style: const TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('common.delete'.tr(), style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    await RiderProfileService.deleteMoto(id);
    _loadMotos();
  }

  Future<void> _setPrimary(int id) async {
    await RiderProfileService.setPrimaryMoto(id);
    _loadMotos();
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
          onPressed: () => context.go('/rider/profile'),
        ),
        title: Text('motos.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.orange),
            onPressed: () async {
              await context.push('/rider/motos/add');
              _loadMotos();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.grey)))
              : _motos.isEmpty ? _buildEmpty() : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.two_wheeler, color: AppColors.grey, size: 64),
          const SizedBox(height: 16),
          Text('profile.no_motos'.tr(), style: const TextStyle(color: AppColors.grey)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async { await context.push('/rider/motos/add'); _loadMotos(); },
            style: ElevatedButton.styleFrom(minimumSize: const Size(180, 48)),
            child: Text('profile.add_moto'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _motos.length,
      itemBuilder: (context, index) {
        final moto      = _motos[index];
        final isPrimary = moto['is_primary'] == true;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isPrimary ? AppColors.orange : AppColors.greyDark, width: isPrimary ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.two_wheeler, color: AppColors.orange, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(moto['alias'] ?? '${moto['brand']} ${moto['model']}',
                                style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                            if (isPrimary) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!isPrimary) ...[
                    _ActionButton(label: 'motos.set_primary'.tr(), icon: Icons.star_outline, color: AppColors.gold, onTap: () => _setPrimary(moto['id'])),
                    const SizedBox(width: 8),
                  ],
                  _ActionButton(
                    label: 'common.edit'.tr(), icon: Icons.edit_outlined, color: AppColors.cyan,
                    onTap: () async { await context.push('/rider/motos/edit', extra: moto); _loadMotos(); },
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(label: 'common.delete'.tr(), icon: Icons.delete_outline, color: AppColors.error, onTap: () => _deleteMoto(moto['id'])),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

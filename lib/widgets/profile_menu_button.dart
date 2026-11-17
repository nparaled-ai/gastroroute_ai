import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api/auth_service.dart';
import '../core/role_home.dart';
import '../core/services/push_notification_service.dart';
import '../core/services/route_tracking_manager.dart';
import '../core/storage/auth_storage.dart';
import '../core/theme/app_theme.dart';

/// El botón de perfil de la barra superior: un avatar que abre el menú de la
/// persona.
///
/// Sustituye al icono de perfil y al de salir. Decidido el 10-11-2026: cambiar de
/// perfil es un toque, sin cerrar sesión ni escribir la contraseña, porque la
/// persona ya está autenticada y sabe que tiene ese perfil.
///
/// El menú trae: su nombre, «Mi perfil» (solo con el perfil de motero), la lista
/// de sus perfiles cuando tiene más de uno —con lo pendiente en cada uno— y
/// «Cerrar sesión».
class ProfileMenuButton extends StatelessWidget {
  /// Apodo del motero, si ya se conoce. Sin él se usa el email.
  final String? nickname;

  const ProfileMenuButton({super.key, this.nickname});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: AuthStorage.getEmail(),
      builder: (context, snap) {
        final fuente = (nickname != null && nickname!.trim().isNotEmpty)
            ? nickname!.trim()
            : (snap.data ?? '').trim();
        final initial = fuente.isNotEmpty ? fuente[0].toUpperCase() : '•';
        return _avatar(context, initial);
      },
    );
  }

  Widget _avatar(BuildContext context, String initial) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 14),
      child: GestureDetector(
        onTap: () => _open(context),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.orange,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: const TextStyle(
              color: AppColors.background,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final role = await AuthStorage.getRole();
    final email = await AuthStorage.getEmail();
    final profiles = await AuthService.profiles();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => _Menu(
        activeRole: role,
        name: nickname != null && nickname!.isNotEmpty ? '@$nickname' : (email ?? ''),
        profiles: profiles,
        parent: context,
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  final String? activeRole;
  final String name;
  final List<Map<String, dynamic>> profiles;
  final BuildContext parent;

  const _Menu({
    required this.activeRole,
    required this.name,
    required this.profiles,
    required this.parent,
  });

  /// Los perfiles que ya tienen pantallas: de partner todavía no.
  List<Map<String, dynamic>> get _switchable =>
      profiles.where((p) => homeForRole('${p['role']}') != null).toList();

  static IconData _icon(String role) {
    switch (role) {
      case 'admin':
      case 'moderator':
        return Icons.shield_outlined;
      case 'partner':
        return Icons.storefront_outlined;
      default:
        return Icons.two_wheeler;
    }
  }

  static Color _color(String role) {
    switch (role) {
      case 'admin':
      case 'moderator':
        return const Color(0xFFB9A2FF);
      case 'partner':
        return AppColors.cyan;
      default:
        return AppColors.orange;
    }
  }

  Future<void> _switchTo(BuildContext sheet, String role) async {
    // Mientras se graba una ruta no se cambia de perfil: la grabación habla con
    // el servidor como motero y con otro perfil sus llamadas dejarían de valer.
    if (RouteTrackingManager.instance.isTracking) {
      Navigator.pop(sheet);
      ScaffoldMessenger.of(parent).showSnackBar(
        SnackBar(content: Text('profile_menu.recording'.tr())),
      );
      return;
    }

    final result = await AuthService.switchRole(role);
    if (!sheet.mounted) return;
    Navigator.pop(sheet);

    if (result['success'] == true) {
      // El registro del móvil para avisos es de motero: al volver a ese perfil se renueva.
      if (role == 'rider') PushNotificationService.registerToken();
      final home = homeForRole(role);
      if (home != null && parent.mounted) parent.go(home);
    } else if (parent.mounted) {
      ScaffoldMessenger.of(parent).showSnackBar(
        SnackBar(content: Text('${result['error']}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfiles = _switchable;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(
                name,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (activeRole == 'rider')
              ListTile(
                leading: const Icon(Icons.person_outline, color: AppColors.white),
                title: Text('home.my_profile'.tr(),
                    style: const TextStyle(color: AppColors.white)),
                onTap: () {
                  Navigator.pop(context);
                  parent.go('/rider/profile');
                },
              ),
            if (perfiles.length > 1) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text('profile_menu.switch'.tr(),
                    style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
              ),
              for (final p in perfiles)
                ListTile(
                  leading: Icon(_icon('${p['role']}'), color: _color('${p['role']}')),
                  title: Text('profile_menu.role_${p['role']}'.tr(),
                      style: const TextStyle(color: AppColors.white)),
                  subtitle: p['active'] == true
                      ? Text('profile_menu.active'.tr(),
                          style: const TextStyle(color: AppColors.greyText, fontSize: 12))
                      : null,
                  trailing: p['active'] == true
                      ? Icon(Icons.check, color: _color('${p['role']}'))
                      : ((p['pending'] ?? 0) > 0
                          ? _Badge(count: (p['pending'] as num).toInt(), color: _color('${p['role']}'))
                          : null),
                  onTap: p['active'] == true ? null : () => _switchTo(context, '${p['role']}'),
                ),
            ],
            const Divider(color: AppColors.greyDark, height: 20),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.grey),
              title: Text('profile_menu.logout'.tr(),
                  style: const TextStyle(color: AppColors.white)),
              onTap: () async {
                Navigator.pop(context);
                await AuthService.logout();
                if (parent.mounted) parent.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  final Color color;
  const _Badge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: AppColors.background,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

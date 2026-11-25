import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/account_service.dart';
import '../../../core/api/api_client.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';

/// Cuenta y privacidad: cambiar la contraseña, eliminar la cuenta y leer los términos y la política de privacidad.
///
/// Lo exigen la ley (RGPD: derecho de supresión, información) y las tiendas de aplicaciones (borrar la cuenta
/// desde la propia app).
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _changePassword(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('account.password_changed'.tr())));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (deleted == true && context.mounted) {
      await ApiClient.deleteToken();
      await AuthStorage.clear();
      await AuthStorage.clearCredentials();   // y el correo recordado: la cuenta ya no existe
      if (context.mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('account.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Tile(
            icon: Icons.lock_reset,
            title: 'account.change_password'.tr(),
            subtitle: 'account.change_password_desc'.tr(),
            onTap: () => _changePassword(context),
          ),
          _Tile(
            icon: Icons.description_outlined,
            title: 'legal.terms'.tr(),
            onTap: () => context.push('/legal/terms'),
          ),
          _Tile(
            icon: Icons.privacy_tip_outlined,
            title: 'legal.privacy'.tr(),
            onTap: () => context.push('/legal/privacy'),
          ),
          const SizedBox(height: 24),
          _Tile(
            icon: Icons.delete_forever_outlined,
            title: 'account.delete'.tr(),
            subtitle: 'account.delete_desc'.tr(),
            danger: true,
            onTap: () => _deleteAccount(context),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.title, this.subtitle, this.danger = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: danger ? AppColors.error.withOpacity(0.4) : AppColors.greyDark),
          ),
          child: Row(children: [
            Icon(icon, color: danger ? AppColors.error : AppColors.orange),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: const TextStyle(color: AppColors.grey, fontSize: 12.5, height: 1.35)),
                ],
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppColors.grey),
          ]),
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_new.text.length < 8) {
      setState(() => _error = 'account.password_short'.tr());
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'account.password_mismatch'.tr());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await AccountService.changePassword(
        current: _current.text, password: _new.text, confirmation: _confirm.text);
    if (!mounted) return;
    if (r['error'] != null) {
      setState(() {
        _busy = false;
        _error = '${r['error']}';
      });
      return;
    }
    Navigator.pop(context, true);
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: true,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('account.change_password'.tr()),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('account.change_password_note'.tr(),
              style: const TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4)),
          const SizedBox(height: 14),
          _field(_current, 'account.current_password'.tr()),
          _field(_new, 'account.new_password'.tr()),
          _field(_confirm, 'account.repeat_password'.tr()),
          if (_error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text('common.cancel'.tr())),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('account.change'.tr()),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    // Cuenta de Google: no tiene contraseña, se confirma escribiendo la palabra.
    final googleAccount = _password.text.trim().toUpperCase() == 'ELIMINAR' ||
        _password.text.trim().toUpperCase() == 'DELETE';
    final r = googleAccount
        ? await AccountService.deleteAccount(confirm: _password.text.trim().toUpperCase())
        : await AccountService.deleteAccount(password: _password.text);
    if (!mounted) return;
    if (r['error'] != null) {
      setState(() {
        _busy = false;
        _error = '${r['error']}';
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('account.delete'.tr(), style: const TextStyle(color: AppColors.error)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('account.delete_warning'.tr(), style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.45)),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: true,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(labelText: 'account.delete_confirm_password'.tr()),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text('common.cancel'.tr())),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('account.delete_final'.tr(), style: const TextStyle(color: AppColors.error)),
        ),
      ],
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/account_service.dart';
import '../../core/api/api_client.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';

/// Volver a aceptar los términos y la política: para cuentas anteriores al registro de consentimientos o cuando
/// cambian los textos. Sin aceptar no se entra; la aceptación queda guardada en el servidor como prueba (RGPD art. 7.1).
class ConsentScreen extends StatefulWidget {
  final String next;
  const ConsentScreen({super.key, required this.next});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _accepted = false;
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    if (!_accepted) {
      setState(() => _error = 'legal.reaccept_must'.tr());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await AccountService.acceptTerms();
    if (!mounted) return;
    if (r['error'] != null) {
      setState(() {
        _busy = false;
        _error = '${r['error']}';
      });
      return;
    }
    context.go(widget.next);
  }

  Future<void> _decline() async {
    await ApiClient.deleteToken();
    await AuthStorage.clear();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.gavel_outlined, color: AppColors.orange, size: 44),
              const SizedBox(height: 16),
              Text('legal.reaccept_title'.tr(),
                  style: const TextStyle(color: AppColors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text('legal.reaccept_body'.tr(),
                  style: const TextStyle(color: AppColors.greyText, fontSize: 14.5, height: 1.5)),
              const SizedBox(height: 20),
              InkWell(
                onTap: () => setState(() => _accepted = !_accepted),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Checkbox(
                    value: _accepted,
                    onChanged: (v) => setState(() => _accepted = v ?? false),
                    activeColor: AppColors.orange,
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text.rich(TextSpan(
                        style: const TextStyle(color: AppColors.greyText, fontSize: 13, height: 1.4),
                        children: [
                          TextSpan(text: 'legal.accept_prefix'.tr()),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: () => context.push('/legal/terms'),
                              child: Text(' ${'legal.terms'.tr()}',
                                  style: const TextStyle(
                                      color: AppColors.cyan, fontSize: 13, decoration: TextDecoration.underline)),
                            ),
                          ),
                          TextSpan(text: ' ${'legal.and'.tr()} '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: () => context.push('/legal/privacy'),
                              child: Text('legal.privacy'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.cyan, fontSize: 13, decoration: TextDecoration.underline)),
                            ),
                          ),
                          TextSpan(text: 'legal.accept_suffix'.tr()),
                        ],
                      )),
                    ),
                  ),
                ]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : _accept,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('legal.reaccept_button'.tr()),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _decline,
                child: Text('legal.reaccept_decline'.tr(), style: const TextStyle(color: AppColors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

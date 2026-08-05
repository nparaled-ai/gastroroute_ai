import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/auth_service.dart';
import '../../../core/theme/app_theme.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _sending  = false;
  String? _msg;
  bool _isError  = false;

  Future<void> _resend() async {
    setState(() { _sending = true; _msg = null; });
    final result = await AuthService.resendVerification(widget.email);
    if (!mounted) return;
    setState(() {
      _sending  = false;
      _isError  = result['error'] != null;
      _msg      = result['error'] ?? result['message'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                  color: AppColors.orange.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_unread_outlined,
                    color: AppColors.orange, size: 48),
              ),
              const SizedBox(height: 32),
              Text(
                'verify_email.title'.tr(),
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(color: AppColors.grey, fontSize: 15, height: 1.5),
                  children: [
                    TextSpan(text: '${'verify_email.sent_to'.tr()}\n'),
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(
                          color: AppColors.orange, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: '\n\n${'verify_email.instruction'.tr()}'),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              if (_msg != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_isError ? AppColors.error : AppColors.cyan).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (_isError ? AppColors.error : AppColors.cyan).withOpacity(0.3),
                    ),
                  ),
                  child: Text(_msg!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _isError ? AppColors.error : AppColors.cyan,
                          fontSize: 13)),
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _sending ? null : _resend,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.orange, strokeWidth: 2))
                      : Text('verify_email.resend'.tr(),
                          style: const TextStyle(color: AppColors.orange, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text('verify_email.back_to_login'.tr(),
                    style: const TextStyle(color: AppColors.grey, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

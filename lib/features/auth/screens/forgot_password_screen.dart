import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/password_reset_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent    = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'forgot_password.email_empty'.tr());
      return;
    }
    setState(() { _loading = true; _error = null; });
    final result = await PasswordResetService.forgotPassword(email);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['error'] != null) {
      setState(() => _error = result['error']);
    } else {
      setState(() => _sent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _sent ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      const Text('🔑', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 16),
      Text('forgot_password.title'.tr(),
          style: const TextStyle(color: AppColors.white, fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Text('forgot_password.subtitle'.tr(),
          style: const TextStyle(color: AppColors.grey, fontSize: 15, height: 1.5)),
      const SizedBox(height: 40),
      TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        style: const TextStyle(color: AppColors.white),
        decoration: InputDecoration(
          labelText: 'auth.email'.tr(),
          prefixIcon: const Icon(Icons.email_outlined, color: AppColors.grey),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.error.withOpacity(0.4)),
          ),
          child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ),
      ],
      const SizedBox(height: 28),
      ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _loading
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text('forgot_password.send_button'.tr(),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    ]);
  }

  Widget _buildSuccess() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      const Text('📧', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 16),
      Text('forgot_password.sent_title'.tr(),
          style: const TextStyle(color: AppColors.white, fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Text(
        'forgot_password.sent_body'.tr(namedArgs: {'email': _emailController.text.trim()}),
        style: const TextStyle(color: AppColors.grey, fontSize: 15, height: 1.5),
      ),
      const SizedBox(height: 28),
      ElevatedButton(
        onPressed: () => context.push('/reset-password',
            extra: {'email': _emailController.text.trim()}),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text('forgot_password.have_code'.tr(),
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => setState(() => _sent = false),
        child: Text('forgot_password.resend'.tr(),
            style: const TextStyle(color: AppColors.grey)),
      ),
    ]);
  }
}

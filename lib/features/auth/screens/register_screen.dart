import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/auth_service.dart';
import '../../../core/theme/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _loading  = false;
  bool _obscure  = true;
  // Terminos, politica de privacidad y edad minima: sin marcarla no se crea la cuenta (RGPD arts. 7 y 8).
  bool _accepted = false;
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()..onTap = () => context.push('/legal/terms');
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()..onTap = () => context.push('/legal/privacy');
  String? _error;
  String? _success;

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_accepted) {
      setState(() => _error = 'legal.must_accept'.tr());
      return;
    }
    setState(() { _loading = true; _error = null; _success = null; });

    final result = await AuthService.registerRider(
      email:    _emailController.text.trim(),
      password: _passwordController.text,
      nickname: _nicknameController.text.trim(),
      acceptTerms: _accepted,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['error'] != null) {
      setState(() => _error = result['error']);
      return;
    }

    if (!mounted) return;
    final email = result['email'] ?? _emailController.text.trim();
    context.go('/verify-email', extra: {'email': email});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              IconButton(
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.arrow_back_ios, color: AppColors.white),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),

              Center(
                child: Column(
                  children: [
                    Image.asset('assets/images/logo.png', width: 70),
                    const SizedBox(height: 12),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                        children: [
                          TextSpan(text: 'GAS', style: TextStyle(color: AppColors.orange)),
                          TextSpan(text: 'troRoute', style: TextStyle(color: AppColors.white)),
                          TextSpan(text: 'AI', style: TextStyle(color: AppColors.cyan)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              Text('auth.join_community'.tr(),
                  style: const TextStyle(color: AppColors.white, fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('auth.register_subtitle'.tr(),
                  style: const TextStyle(color: AppColors.grey, fontSize: 14)),

              const SizedBox(height: 32),

              TextFormField(
                controller: _nicknameController,
                style: const TextStyle(color: AppColors.white),
                decoration: InputDecoration(
                  labelText: 'auth.nickname'.tr(),
                  prefixIcon: const Icon(Icons.person_outlined, color: AppColors.grey),
                  hintText: 'auth.nickname_hint'.tr(),
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppColors.white),
                decoration: InputDecoration(
                  labelText: 'auth.email'.tr(),
                  prefixIcon: const Icon(Icons.email_outlined, color: AppColors.grey),
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                obscureText: _obscure,
                style: const TextStyle(color: AppColors.white),
                decoration: InputDecoration(
                  labelText: 'auth.password'.tr(),
                  prefixIcon: const Icon(Icons.lock_outlined, color: AppColors.grey),
                  hintText: 'auth.min_chars'.tr(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AppColors.grey,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              // Casilla de aceptacion: terminos + politica + edad minima, con enlaces a los textos.
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
                      // Un solo parrafo, con los dos enlaces dentro: el texto fluye y la coma no queda suelta.
                      child: Text.rich(TextSpan(
                        style: const TextStyle(color: AppColors.greyText, fontSize: 13, height: 1.4),
                        children: [
                          TextSpan(text: '${'legal.accept_prefix'.tr()} '),
                          TextSpan(
                            text: 'legal.terms'.tr(),
                            style: const TextStyle(color: AppColors.cyan, decoration: TextDecoration.underline),
                            recognizer: _termsTap,
                          ),
                          TextSpan(text: 'legal.and'.tr().endsWith('’') ? ' ${'legal.and'.tr()}' : ' ${'legal.and'.tr()} '),
                          TextSpan(
                            text: 'legal.privacy'.tr(),
                            style: const TextStyle(color: AppColors.cyan, decoration: TextDecoration.underline),
                            recognizer: _privacyTap,
                          ),
                          TextSpan(text: 'legal.accept_suffix'.tr()),
                        ],
                      )),
                    ),
                  ),
                ]),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                    ],
                  ),
                ),
              ],

              if (_success != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_success!, style: const TextStyle(color: Colors.green, fontSize: 13))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/login'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: Text('auth.login_link'.tr().toUpperCase()),
                ),
              ],

              if (_success == null) ...[
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _loading ? null : _register,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('auth.create_account'.tr()),
                ),
              ],

              const SizedBox(height: 24),

              Center(
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14),
                      children: [
                        TextSpan(text: 'auth.already_account'.tr(),
                            style: const TextStyle(color: AppColors.grey)),
                        const TextSpan(text: ' '),
                        TextSpan(text: 'auth.login_link'.tr(),
                            style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

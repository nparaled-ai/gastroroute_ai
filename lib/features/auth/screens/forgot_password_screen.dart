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
  String? _debugToken;

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Introduce tu email.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final result = await PasswordResetService.forgotPassword(email);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _debugToken = result['debug_token']; // solo en desarrollo
    });
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
      const Text('¿Olvidaste tu contraseña?',
          style: TextStyle(color: AppColors.white, fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      const Text('Introduce tu email y te enviaremos un código para restablecerla.',
          style: TextStyle(color: AppColors.grey, fontSize: 15, height: 1.5)),
      const SizedBox(height: 40),
      TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        style: const TextStyle(color: AppColors.white),
        decoration: const InputDecoration(
          labelText: 'Email',
          prefixIcon: Icon(Icons.email_outlined, color: AppColors.grey),
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
            : const Text('Enviar enlace',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    ]);
  }

  Widget _buildSuccess() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      const Text('📧', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 16),
      const Text('¡Email enviado!',
          style: TextStyle(color: AppColors.white, fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Text(
        'Hemos enviado un enlace a ${_emailController.text.trim()}.\n\nRevisa tu bandeja de entrada y sigue las instrucciones.',
        style: const TextStyle(color: AppColors.grey, fontSize: 15, height: 1.5),
      ),
      const SizedBox(height: 12),
      Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
      color: AppColors.cyan.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('💡 Modo desarrollo', style: TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
        if (_debugToken != null) ...[  
            const Text('Tu código es:', style: TextStyle(color: AppColors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(
                _debugToken!.substring(0, 6).toUpperCase(),
                style: const TextStyle(
                  color: AppColors.orange, fontSize: 28,
                  fontWeight: FontWeight.w900, letterSpacing: 8,
                ),
              ),
            ] else
              const Text('El código aparece en laravel.log',
                  style: TextStyle(color: AppColors.grey, fontSize: 12)),
          ]),
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
        child: const Text('Tengo el código',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => setState(() => _sent = false),
        child: const Text('Reenviar email', style: TextStyle(color: AppColors.grey)),
      ),
    ]);
  }
}

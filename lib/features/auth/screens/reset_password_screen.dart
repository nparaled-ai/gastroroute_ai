import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/password_reset_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _tokenController    = TextEditingController();
  final _passController     = TextEditingController();
  final _confirmController  = TextEditingController();
  bool _loading  = false;
  bool _success  = false;
  bool _showPass = false;
  String? _error;

  Future<void> _submit() async {
    final token    = _tokenController.text.trim();
    final password = _passController.text;
    final confirm  = _confirmController.text;

    if (token.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Rellena todos los campos.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'La contraseña debe tener al menos 8 caracteres.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final result = await PasswordResetService.resetPassword(
        widget.email, token, password, confirm);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['error'] != null) {
      setState(() => _error = result['error']);
    } else {
      setState(() => _success = true);
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
          child: _success ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        const Text('🔐', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        const Text('Nueva contraseña',
            style: TextStyle(color: AppColors.white, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Email: ${widget.email}',
            style: const TextStyle(color: AppColors.grey, fontSize: 13)),
        const SizedBox(height: 32),

        // Código
        TextFormField(
          controller: _tokenController,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: AppColors.white, letterSpacing: 4, fontSize: 20),
          textAlign: TextAlign.center,
          onChanged: (v) {
            final upper = v.toUpperCase();
            if (upper != v) {
              _tokenController.value = _tokenController.value.copyWith(
                text: upper,
                selection: TextSelection.collapsed(offset: upper.length),
              );
            }
          },
          decoration: const InputDecoration(
            labelText: 'Código de verificación',
            hintText: 'XXXXXX',
            prefixIcon: Icon(Icons.key_outlined, color: AppColors.orange),
          ),
        ),
        const SizedBox(height: 16),

        // Nueva contraseña
        TextFormField(
          controller: _passController,
          obscureText: !_showPass,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            labelText: 'Nueva contraseña',
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.grey),
            suffixIcon: IconButton(
              icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.grey),
              onPressed: () => setState(() => _showPass = !_showPass),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Confirmar
        TextFormField(
          controller: _confirmController,
          obscureText: !_showPass,
          style: const TextStyle(color: AppColors.white),
          decoration: const InputDecoration(
            labelText: 'Confirmar contraseña',
            prefixIcon: Icon(Icons.lock_outline, color: AppColors.grey),
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
              : const Text('Restablecer contraseña',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildSuccess() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      const Text('✅', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 16),
      const Text('¡Contraseña cambiada!',
          style: TextStyle(color: AppColors.white, fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      const Text('Tu contraseña se ha restablecido correctamente. Ya puedes iniciar sesión.',
          style: TextStyle(color: AppColors.grey, fontSize: 15, height: 1.5)),
      const SizedBox(height: 40),
      ElevatedButton(
        onPressed: () => context.go('/login'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Iniciar sesión',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

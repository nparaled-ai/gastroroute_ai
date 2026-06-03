import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/auth_service.dart';
import '../../../core/theme/app_theme.dart';

class SelectRoleScreen extends StatefulWidget {
  final int userId;
  final List<String> roles;
  final String password;

  const SelectRoleScreen({
    super.key,
    required this.userId,
    required this.roles,
    required this.password,
  });

  @override
  State<SelectRoleScreen> createState() => _SelectRoleScreenState();
}

class _SelectRoleScreenState extends State<SelectRoleScreen> {
  String? _selectedRole;
  bool _loading = false;
  String? _error;

  final _roleConfig = {
    'rider': {
      'label': 'Motero',
      'icon':  Icons.two_wheeler,
      'desc':  'Rutas, comunidad y aventura',
      'color': AppColors.orange,
    },
    'partner': {
      'label': 'Partner',
      'icon':  Icons.store_outlined,
      'desc':  'Gestiona tu negocio',
      'color': AppColors.cyan,
    },
    'admin': {
      'label': 'Administrador',
      'icon':  Icons.admin_panel_settings_outlined,
      'desc':  'Panel de control',
      'color': AppColors.gold,
    },
  };

  Future<void> _confirm() async {
    if (_selectedRole == null) return;

    setState(() { _loading = true; _error = null; });

    final result = await AuthService.selectRole(
      userId:   widget.userId,
      role:     _selectedRole!,
      password: widget.password,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['error'] != null) {
      setState(() => _error = result['error']);
      return;
    }

    if (result['success'] == true) {
      final role = result['role'];
      if (role == 'rider')   context.go('/rider/home');
      if (role == 'partner') context.go('/login'); // próximamente
      if (role == 'admin')   context.go('/login'); // próximamente
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),

              // Logo
              Center(
                child: Image.asset('assets/images/logo.png', width: 70),
              ),

              const SizedBox(height: 32),

              const Text(
                '¿Con qué rol quieres entrar?',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tienes varios perfiles disponibles',
                style: TextStyle(color: AppColors.grey, fontSize: 14),
              ),

              const SizedBox(height: 32),

              // Roles
              ...widget.roles.map((role) {
                final config = _roleConfig[role]!;
                final isSelected = _selectedRole == role;
                final color = config['color'] as Color;

                return GestureDetector(
                  onTap: () => setState(() => _selectedRole = role),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withOpacity(0.15)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? color : AppColors.greyDark,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            config['icon'] as IconData,
                            color: color,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                config['label'] as String,
                                style: TextStyle(
                                  color: isSelected ? color : AppColors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                config['desc'] as String,
                                style: const TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle, color: color, size: 24),
                      ],
                    ),
                  ),
                );
              }),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ],

              const Spacer(),

              ElevatedButton(
                onPressed: (_selectedRole == null || _loading) ? null : _confirm,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('ENTRAR'),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
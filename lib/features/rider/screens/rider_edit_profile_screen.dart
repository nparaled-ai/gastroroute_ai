import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/rider_avatar.dart';
import '../providers/avatar_service.dart';
import '../providers/rider_profile_service.dart';

class RiderEditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;

  const RiderEditProfileScreen({super.key, required this.profile});

  @override
  State<RiderEditProfileScreen> createState() => _RiderEditProfileScreenState();
}

class _RiderEditProfileScreenState extends State<RiderEditProfileScreen> {
  late TextEditingController _nicknameController;
  late TextEditingController _bioController;
  late TextEditingController _provinceController;
  String? _experienceLevel;
  String  _language = 'es';
  bool _loading = false;
  bool _uploadingAvatar = false;
  String? _error;
  String? _avatarUrl;
  File? _localAvatar;

  final _levels = ['novato', 'intermedio', 'experto'];

  final _languages = [
    {'code': 'es', 'flag': '🇪🇸', 'name': 'Español'},
    {'code': 'en', 'flag': '🇬🇧', 'name': 'English'},
    {'code': 'fr', 'flag': '🇫🇷', 'name': 'Français'},
    {'code': 'de', 'flag': '🇩🇪', 'name': 'Deutsch'},
    {'code': 'it', 'flag': '🇮🇹', 'name': 'Italiano'},
    {'code': 'pt', 'flag': '🇵🇹', 'name': 'Português'},
  ];

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.profile['nickname']);
    _bioController      = TextEditingController(text: widget.profile['bio'] ?? '');
    _provinceController = TextEditingController(text: widget.profile['province'] ?? '');
    _experienceLevel    = widget.profile['experience_level'] ?? 'novato';
    _language           = widget.profile['language'] ?? 'es';
    _avatarUrl          = widget.profile['avatar_url'];
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    _provinceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 800);
    if (picked == null) return;

    final file = File(picked.path);
    setState(() { _uploadingAvatar = true; _localAvatar = file; });

    final result = await AvatarService.uploadAvatar(file);
    if (!mounted) return;
    setState(() => _uploadingAvatar = false);

    if (result['error'] != null) {
      setState(() => _error = result['error']);
    } else {
      setState(() => _avatarUrl = result['avatar_url']);
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.orange),
              title: const Text('Hacer foto', style: TextStyle(color: AppColors.white)),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.cyan),
              title: const Text('Elegir de galería', style: TextStyle(color: AppColors.white)),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
            ),
            if (_avatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Eliminar foto', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() { _avatarUrl = null; _localAvatar = null; });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() { _loading = true; _error = null; });

    final result = await RiderProfileService.updateProfile({
      'nickname':         _nicknameController.text.trim(),
      'bio':              _bioController.text.trim(),
      'province':         _provinceController.text.trim(),
      'experience_level': _experienceLevel,
      'language':         _language,
    });

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['error'] != null) {
      setState(() => _error = result['error']);
      return;
    }

    // Guardar idioma localmente y cambiar en la app
    await AuthStorage.saveLanguage(_language);
    await context.setLocale(Locale(_language));
    if (!mounted) return;
    context.pop();
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
          onPressed: () => context.pop(),
        ),
        title: Text(
          'profile.edit_title'.tr(),
          style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2),
                  )
                : Text(
                    'common.save'.tr(),
                    style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Center(
              child: GestureDetector(
                onTap: _showImageSourceDialog,
                child: Stack(
                  children: [
                    _uploadingAvatar
                        ? Container(
                            width: 90, height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surface,
                              border: Border.all(color: AppColors.orange, width: 2),
                            ),
                            child: const Center(child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2)),
                          )
                        : _localAvatar != null
                            ? Container(
                                width: 90, height: 90,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.orange, width: 2),
                                  image: DecorationImage(
                                    image: FileImage(_localAvatar!),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              )
                            : RiderAvatar(
                                avatarUrl: _avatarUrl,
                                level: _experienceLevel ?? 'novato',
                                size: 90,
                              ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 28, height: 28,
                        decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Nickname
            const Text('Nickname', style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nicknameController,
              style: const TextStyle(color: AppColors.white),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outlined, color: AppColors.grey),
              ),
            ),

            const SizedBox(height: 20),

            // Bio
            const Text('Bio', style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bioController,
              style: const TextStyle(color: AppColors.white),
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'profile.about_me'.tr(),
                counterStyle: const TextStyle(color: AppColors.grey),
              ),
            ),

            const SizedBox(height: 20),

            // Provincia
            Text('profile.location'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _provinceController,
              style: const TextStyle(color: AppColors.white),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.grey),
              ),
            ),

            const SizedBox(height: 20),

            // Nivel de experiencia
            const Text('Nivel', style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: _levels.map((level) {
                final isSelected = _experienceLevel == level;
                Color color;
                switch (level) {
                  case 'experto':    color = AppColors.gold; break;
                  case 'intermedio': color = AppColors.cyan; break;
                  default:           color = AppColors.grey;
                }
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _experienceLevel = level),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withOpacity(0.15) : AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isSelected ? color : AppColors.greyDark, width: isSelected ? 2 : 1),
                      ),
                      child: Text(
                        level[0].toUpperCase() + level.substring(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? color : AppColors.grey,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Idioma
            Text('profile.language'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _languages.map((lang) {
                final isSelected = _language == lang['code'];
                return GestureDetector(
                  onTap: () => setState(() => _language = lang['code']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.orange.withOpacity(0.15) : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.orange : AppColors.greyDark,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(lang['flag']!, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          lang['name']!,
                          style: TextStyle(
                            color: isSelected ? AppColors.orange : AppColors.grey,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 20),
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

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

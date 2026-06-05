import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/api_client.dart';
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
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _nicknameController;
  late TextEditingController _bioController;
  late TextEditingController _provinceController;
  String? _experienceLevel;
  String  _language = 'es';
  String? _gender;
  bool _loading = false;
  bool _uploadingAvatar = false;
  String? _error;
  String? _avatarUrl;
  File? _localAvatar;

  List<Map<String, dynamic>> _locationSuggestions = [];
  bool _loadingLocation = false;
  bool _locationValidated = false;
  bool _detectingLocation = false;
  final _locationFocusNode = FocusNode();

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
    _firstNameController = TextEditingController(text: widget.profile['first_name'] ?? '');
    _lastNameController  = TextEditingController(text: widget.profile['last_name'] ?? '');
    _nicknameController  = TextEditingController(text: widget.profile['nickname']);
    _bioController      = TextEditingController(text: widget.profile['bio'] ?? '');
    _provinceController = TextEditingController(text: widget.profile['province'] ?? '');
    _experienceLevel    = widget.profile['experience_level'] ?? 'novato';
    _language           = widget.profile['language'] ?? 'es';
    _gender             = widget.profile['gender'];
    _avatarUrl          = widget.profile['avatar_url'];
    // Si ya tiene ubicación guardada se considera validada
    _locationValidated  = (widget.profile['province'] ?? '').isNotEmpty;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _nicknameController.dispose();
    _bioController.dispose();
    _provinceController.dispose();
    _locationFocusNode.dispose();
    super.dispose();
  }

  Future<void> _detectCurrentLocation() async {
    setState(() => _detectingLocation = true);
    try {
      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _detectingLocation = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Activa los permisos de ubicación en ajustes.'),
            backgroundColor: AppColors.error,
          ));
        }
        setState(() => _detectingLocation = false);
        return;
      }

      // Obtener posición
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      // Geocodificación inversa via backend
      final response = await ApiClient.dio.get('/location/search', queryParameters: {
        'q':    '${position.latitude},${position.longitude}',
        'lang': _language,
        'reverse': '1',
      });

      final List data = response.data as List? ?? [];
      if (data.isNotEmpty) {
        setState(() {
          _provinceController.text = data[0]['description'] as String;
          _locationValidated = true;
          _locationSuggestions = [];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo obtener la ubicación actual.'),
          backgroundColor: AppColors.error,
        ));
      }
    }
    if (mounted) setState(() => _detectingLocation = false);
  }

  Future<void> _searchLocation(String query) async {
    setState(() { _locationValidated = false; _locationSuggestions = []; });
    if (query.length < 3) return;
    setState(() => _loadingLocation = true);
    try {
      final response = await ApiClient.dio.get('/location/search', queryParameters: {
        'q':    query,
        'lang': _language,
      });
      final List data = response.data as List? ?? [];
      if (data.isNotEmpty) {
        setState(() {
          _locationSuggestions = data.map<Map<String, dynamic>>((p) => {
            'description': p['description'] as String,
            'place_id':    p['place_id'] as String,
          }).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingLocation = false);
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                onTap: () { Navigator.pop(ctx); setState(() { _avatarUrl = null; _localAvatar = null; }); },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_firstNameController.text.trim().isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    if (_lastNameController.text.trim().isEmpty) {
      setState(() => _error = 'Los apellidos son obligatorios.');
      return;
    }
    if (_provinceController.text.trim().isEmpty) {
      setState(() => _error = 'La ubicación es obligatoria.');
      return;
    }
    if (_provinceController.text.trim().isNotEmpty && !_locationValidated) {
      setState(() => _error = 'Selecciona una ubicación de la lista de sugerencias.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final result = await RiderProfileService.updateProfile({
      'first_name':       _firstNameController.text.trim(),
      'last_name':        _lastNameController.text.trim(),
      'nickname':         _nicknameController.text.trim(),
      'bio':              _bioController.text.trim(),
      'province':         _provinceController.text.trim(),
      'experience_level': _experienceLevel,
      'language':         _language,
      'gender':           _gender,
    });
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['error'] != null) {
      setState(() => _error = result['error']);
      return;
    }
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
        title: Text('profile.edit_title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2))
                : Text('common.save'.tr(),
                    style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
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
                child: Stack(children: [
                  _uploadingAvatar
                      ? Container(width: 90, height: 90,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface,
                              border: Border.all(color: AppColors.orange, width: 2)),
                          child: const Center(child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2)))
                      : _localAvatar != null
                          ? Container(width: 90, height: 90,
                              decoration: BoxDecoration(shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.orange, width: 2),
                                  image: DecorationImage(image: FileImage(_localAvatar!), fit: BoxFit.cover)))
                          : RiderAvatar(avatarUrl: _avatarUrl, level: _experienceLevel ?? 'novato', size: 90),
                  Positioned(bottom: 0, right: 0,
                    child: Container(width: 28, height: 28,
                      decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 16))),
                ]),
              ),
            ),

            const SizedBox(height: 32),

            // Email (inmodificable)
            const Text('Email', style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.greyDark.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.greyDark),
              ),
              child: Row(children: [
                const Icon(Icons.email_outlined, color: AppColors.grey, size: 18),
                const SizedBox(width: 12),
                Text(
                  widget.profile['email'] ?? '',
                  style: const TextStyle(color: AppColors.grey, fontSize: 14),
                ),
                const Spacer(),
                const Icon(Icons.lock_outline, color: AppColors.greyDark, size: 16),
              ]),
            ),

            const SizedBox(height: 20),

            // Nombre
            Row(children: [
              const Text('Nombre', style: TextStyle(color: AppColors.grey, fontSize: 13)),
              const SizedBox(width: 4),
              const Text('*', style: TextStyle(color: AppColors.error, fontSize: 13)),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              controller: _firstNameController,
              style: const TextStyle(color: AppColors.white),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outlined, color: AppColors.grey),
                hintText: 'Tu nombre',
              ),
            ),

            const SizedBox(height: 16),

            // Apellidos
            Row(children: [
              const Text('Apellidos', style: TextStyle(color: AppColors.grey, fontSize: 13)),
              const SizedBox(width: 4),
              const Text('*', style: TextStyle(color: AppColors.error, fontSize: 13)),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              controller: _lastNameController,
              style: const TextStyle(color: AppColors.white),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outlined, color: AppColors.grey),
                hintText: 'Tus apellidos',
              ),
            ),

            const SizedBox(height: 20),

            // Nickname
            const Text('Nickname', style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nicknameController,
              style: const TextStyle(color: AppColors.white),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outlined, color: AppColors.grey)),
            ),

            const SizedBox(height: 20),

            // Bio
            const Text('Bio', style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bioController,
              style: const TextStyle(color: AppColors.white),
              maxLines: 3, maxLength: 500,
              decoration: InputDecoration(
                  hintText: 'profile.about_me'.tr(),
                  counterStyle: const TextStyle(color: AppColors.grey)),
            ),

            const SizedBox(height: 20),

            // Ubicación con autocompletado
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('profile.location'.tr(),
                    style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                GestureDetector(
                  onTap: _detectingLocation ? null : _detectCurrentLocation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.cyan.withOpacity(0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _detectingLocation
                          ? const SizedBox(width: 12, height: 12,
                              child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2))
                          : const Icon(Icons.my_location, color: AppColors.cyan, size: 13),
                      const SizedBox(width: 4),
                      const Text('Usar mi ubicación',
                          style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _provinceController,
              focusNode: _locationFocusNode,
              style: const TextStyle(color: AppColors.white),
              onChanged: _searchLocation,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.grey),
                suffixIcon: _loadingLocation
                    ? const SizedBox(width: 16, height: 16,
                        child: Padding(padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2)))
                    : _provinceController.text.isNotEmpty
                        ? _locationValidated
                            ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                            : IconButton(
                                icon: const Icon(Icons.clear, color: AppColors.grey, size: 18),
                                onPressed: () => setState(() {
                                  _provinceController.clear();
                                  _locationSuggestions = [];
                                  _locationValidated = false;
                                }))
                        : null,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _provinceController.text.isNotEmpty && !_locationValidated
                        ? AppColors.error
                        : AppColors.greyDark,
                  ),
                ),
              ),
            ),
            if (_locationSuggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.greyDark)),
                child: Column(
                  children: _locationSuggestions.map((s) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_city, color: AppColors.grey, size: 18),
                    title: Text(s['description'],
                        style: const TextStyle(color: AppColors.white, fontSize: 13)),
                    onTap: () {
                      setState(() {
                        _provinceController.text = s['description'];
                        _locationSuggestions = [];
                        _locationValidated = true; // validado por Google
                      });
                      _locationFocusNode.unfocus();
                    },
                  )).toList(),
                ),
              ),

            const SizedBox(height: 20),

            // Género
            const Text('Soy...', style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              _GenderChip(
                label: 'Motero',
                emoji: '🔵',
                icon: Icons.two_wheeler,
                selected: _gender == 'motero',
                color: AppColors.cyan,
                onTap: () => setState(() => _gender = _gender == 'motero' ? null : 'motero'),
              ),
              const SizedBox(width: 12),
              _GenderChip(
                label: 'Motera',
                emoji: '🟠',
                icon: Icons.two_wheeler,
                selected: _gender == 'motera',
                color: AppColors.orange,
                onTap: () => setState(() => _gender = _gender == 'motera' ? null : 'motera'),
              ),
            ]),

            const SizedBox(height: 20),

            // Nivel
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
                      child: Text(level[0].toUpperCase() + level.substring(1),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: isSelected ? color : AppColors.grey,
                              fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
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
              spacing: 8, runSpacing: 8,
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
                      border: Border.all(color: isSelected ? AppColors.orange : AppColors.greyDark, width: isSelected ? 2 : 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(lang['flag']!, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(lang['name']!,
                          style: TextStyle(color: isSelected ? AppColors.orange : AppColors.grey,
                              fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
                    ]),
                  ),
                );
              }).toList(),
            ),

            if (_error != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                ]),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final String emoji;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _GenderChip({
    required this.label,
    required this.emoji,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : AppColors.greyDark, width: selected ? 2 : 1),
            boxShadow: selected ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 8, spreadRadius: 1)] : null,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(selected ? 0.2 : 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: selected ? color : AppColors.greyDark, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: selected ? color : AppColors.grey,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.normal)),
            if (selected) ...[  
              const SizedBox(height: 4),
              Icon(Icons.check_circle, color: color, size: 16),
            ],
          ]),
        ),
      ),
    );
  }
}

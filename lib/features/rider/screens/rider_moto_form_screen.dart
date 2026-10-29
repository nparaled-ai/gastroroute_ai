import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/moto_photo_service.dart';
import '../providers/rider_profile_service.dart';

class RiderMotoFormScreen extends StatefulWidget {
  final Map<String, dynamic>? moto;
  const RiderMotoFormScreen({super.key, this.moto});

  @override
  State<RiderMotoFormScreen> createState() => _RiderMotoFormScreenState();
}

class _RiderMotoFormScreenState extends State<RiderMotoFormScreen> {
  late TextEditingController _aliasController;
  late TextEditingController _brandController;
  late TextEditingController _modelController;
  late TextEditingController _yearController;
  late TextEditingController _engineController;
  late TextEditingController _fuelCapacityController;
  late TextEditingController _consumptionController;
  String? _motoType;
  bool _loading = false;
  bool _uploadingPhoto = false;
  bool _photoRemoved = false;
  String? _photoUrl;
  File?   _localPhoto;
  int?    _savedMotoId;

  bool get _isEditing => widget.moto != null;

  final _types = ['trail', 'custom', 'sport', 'touring', 'naked', 'scooter', 'otro'];

  final _brands = [
    'Aprilia', 'Benelli', 'Beta', 'BMW', 'Bultaco', 'Buell', 'Cagiva',
    'CFMoto', 'Daelim', 'Derbi', 'Ducati', 'Energica', 'Fantic', 'Gas Gas',
    'Gilera', 'Harley-Davidson', 'Honda', 'Husqvarna', 'Hyosung', 'Indian',
    'Kawasaki', 'Keeway', 'KTM', 'Kymco', 'Lambretta', 'Mash', 'Moto Guzzi',
    'MV Agusta', 'Norton', 'Peugeot', 'Piaggio', 'Rieju', 'Royal Enfield',
    'Suzuki', 'SWM', 'Sym', 'Triumph', 'Ural', 'Vespa', 'Voge',
    'Yamaha', 'Zero', 'Otra',
  ];

  @override
  void initState() {
    super.initState();
    final m = widget.moto;
    _aliasController        = TextEditingController(text: m?['alias'] ?? '');
    _brandController        = TextEditingController(text: m?['brand'] ?? '');
    _modelController        = TextEditingController(text: m?['model'] ?? '');
    _yearController         = TextEditingController(text: m?['year']?.toString() ?? '');
    _engineController       = TextEditingController(text: m?['engine_cc']?.toString() ?? '');
    _fuelCapacityController = TextEditingController(text: m?['fuel_capacity']?.toString() ?? '');
    _consumptionController  = TextEditingController(text: m?['consumption_per_100km']?.toString() ?? '');
    _motoType               = m?['moto_type'];
    _photoUrl               = m?['photo_url'];
    _savedMotoId            = m?['id'];
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _engineController.dispose();
    _fuelCapacityController.dispose();
    _consumptionController.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _save() async {
    if (_aliasController.text.trim().isEmpty) {
      _showError('motos.alias_required'.tr());
      return;
    }
    if (_brandController.text.trim().isEmpty) {
      _showError('motos.brand_required'.tr());
      return;
    }
    if (_motoType == null) {
      _showError('motos.type_required'.tr());
      return;
    }

    setState(() => _loading = true);

    final data = {
      'alias':                 _aliasController.text.trim(),
      'brand':                 _brandController.text.trim(),
      'model':                 _modelController.text.trim(),
      'year':                  int.tryParse(_yearController.text.trim()),
      'engine_cc':             int.tryParse(_engineController.text.trim()),
      'moto_type':             _motoType,
      'fuel_capacity':         double.tryParse(_fuelCapacityController.text.trim()),
      'consumption_per_100km': double.tryParse(_consumptionController.text.trim()),
    };

    Map<String, dynamic> result;
    if (_isEditing) {
      result = await RiderProfileService.updateMoto(widget.moto!['id'], data);
    } else {
      result = await RiderProfileService.addMoto(data);
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['error'] != null) {
      _showError(result['error']);
      return;
    }

    final motoId = _isEditing
        ? widget.moto!['id'] as int
        : result['moto']?['id'] as int?;

    if (motoId != null) {
      if (_photoRemoved) {
        await MotoPhotoService.deletePhoto(motoId);
      } else if (_localPhoto != null && !_isEditing) {
        await _uploadPhoto(motoId);
      }
    }

    if (!mounted) return;
    context.pop();
  }

  Future<void> _uploadPhoto(int motoId) async {
    if (_localPhoto == null) return;
    setState(() => _uploadingPhoto = true);
    final res = await MotoPhotoService.uploadPhoto(motoId, _localPhoto!);
    if (!mounted) return;
    setState(() {
      _uploadingPhoto = false;
      if (res['photo_url'] != null) _photoUrl = res['photo_url'];
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1200);
    if (picked == null) return;
    final file = File(picked.path);
    setState(() { _localPhoto = file; });

    // Si estamos editando, subir de inmediato
    if (_isEditing) {
      setState(() => _uploadingPhoto = true);
      final res = await MotoPhotoService.uploadPhoto(widget.moto!['id'] as int, file);
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        if (res['photo_url'] != null) _photoUrl = res['photo_url'];
        if (res['error'] != null) _showError(res['error']);
      });
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.greyDark, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.orange),
                title: Text('motos.photo_camera'.tr(), style: const TextStyle(color: AppColors.white)),
                onTap: () { Navigator.pop(ctx); _pickPhoto(ImageSource.camera); },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.cyan),
                title: Text('motos.photo_gallery'.tr(), style: const TextStyle(color: AppColors.white)),
                onTap: () { Navigator.pop(ctx); _pickPhoto(ImageSource.gallery); },
              ),
              if (_photoUrl != null || _localPhoto != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.error),
                  title: Text('motos.photo_remove'.tr(), style: const TextStyle(color: AppColors.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() { _photoUrl = null; _localPhoto = null; _photoRemoved = true; });
                  },
                ),
            ],
          ),
        ),
      ),
    );
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
        title: Text(_isEditing ? 'motos.edit_title'.tr() : 'motos.add_title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2))
                : Text('common.save'.tr(), style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Foto de la moto ──────────────────────────────
            Center(
              child: GestureDetector(
                onTap: _showPhotoOptions,
                child: Stack(
                  children: [
                    Container(
                      width: 160, height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.greyDark, width: 1.5),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: _uploadingPhoto
                          ? const Center(child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2))
                          : _localPhoto != null
                              ? Image.file(_localPhoto!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                              : _photoUrl != null
                                  ? Image.network(_photoUrl!, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                                      errorBuilder: (_, __, ___) => _photoPlaceholder())
                                  : _photoPlaceholder(),
                    ),
                    Positioned(
                      bottom: 8, right: 8,
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.background, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 20),
                child: Text('motos.photo_tap'.tr(),
                    style: const TextStyle(color: AppColors.grey, fontSize: 12)),
              ),
            ),

            _field('motos.alias'.tr(), _aliasController, hint: 'motos.alias_hint'.tr()),
            const SizedBox(height: 16),

            // Marca con autocompletado
            Text('motos.brand'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _brandController.text),
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return _brands;
                return _brands.where((b) => b.toLowerCase().contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (val) => setState(() => _brandController.text = val),
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                controller.text = _brandController.text;
                controller.addListener(() => _brandController.text = controller.text);
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(hintText: 'motos.brand_hint'.tr()),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            title: Text(option, style: const TextStyle(color: AppColors.white)),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),
            _field('motos.model'.tr(), _modelController, hint: 'motos.model_hint'.tr()),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _field('motos.year'.tr(), _yearController, hint: '2022', keyboard: TextInputType.number)),
                const SizedBox(width: 16),
                Expanded(child: _field('motos.cc'.tr(), _engineController, hint: '888', keyboard: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _field('motos.tank'.tr(), _fuelCapacityController, hint: '20', keyboard: TextInputType.number)),
                const SizedBox(width: 16),
                Expanded(child: _field('motos.consumption'.tr(), _consumptionController, hint: '5.5', keyboard: const TextInputType.numberWithOptions(decimal: true))),
              ],
            ),

            const SizedBox(height: 20),
            Text('motos.type'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _types.map((type) {
                final isSelected = _motoType == type;
                return GestureDetector(
                  onTap: () => setState(() => _motoType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.orange.withOpacity(0.15) : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? AppColors.orange : AppColors.greyDark, width: isSelected ? 2 : 1),
                    ),
                    child: Text(type[0].toUpperCase() + type.substring(1),
                        style: TextStyle(color: isSelected ? AppColors.orange : AppColors.grey,
                            fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.two_wheeler, color: AppColors.greyDark, size: 40),
      const SizedBox(height: 8),
      Text('motos.photo_add'.tr(),
          style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
    ]);
  }

  Widget _field(String label, TextEditingController controller, {String? hint, TextInputType? keyboard}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 13)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboard,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

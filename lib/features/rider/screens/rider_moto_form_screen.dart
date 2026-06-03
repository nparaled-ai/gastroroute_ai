import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
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
  String? _error;

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

  Future<void> _save() async {
    if (_aliasController.text.trim().isEmpty) {
      setState(() => _error = 'motos.alias_required'.tr());
      return;
    }
    if (_brandController.text.trim().isEmpty) {
      setState(() => _error = 'motos.brand_required'.tr());
      return;
    }
    if (_motoType == null) {
      setState(() => _error = 'motos.type_required'.tr());
      return;
    }

    setState(() { _loading = true; _error = null; });

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
      setState(() => _error = result['error']);
      return;
    }
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

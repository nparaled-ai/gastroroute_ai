import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/rider_profile_service.dart';
import '../providers/route_service.dart';

class RouteGeneratorScreen extends StatefulWidget {
  const RouteGeneratorScreen({super.key});

  @override
  State<RouteGeneratorScreen> createState() => _RouteGeneratorScreenState();
}

class _RouteGeneratorScreenState extends State<RouteGeneratorScreen> {
  final _originController       = TextEditingController();
  final _destinationController  = TextEditingController();
  final _departureTimeController = TextEditingController();
  final _lunchTimeController    = TextEditingController();
  final _dinnerTimeController   = TextEditingController();
  final List<TextEditingController> _customPointControllers = [];

  List<Map<String, dynamic>> _motos = [];
  Map<String, dynamic>? _selectedMoto;
  int? _selectedMotoId;
  String _preference = 'mixto';
  String _difficulty = 'moderada';
  bool _circular    = true;
  int  _hours       = 4;
  int  _days        = 1;
  bool _loading     = false;
  bool _loadingMotos = true;
  String? _error;
  int? _routesRemaining;

  // Nuevas opciones
  bool _suggestGasStations = true;
  bool _suggestLunch       = false;
  bool _suggestDinner      = false;
  bool _suggestHotels      = false; // solo rutas multi-día

  bool get _motoHasFuelData {
    if (_selectedMoto == null) return false;
    return _selectedMoto!['fuel_capacity'] != null &&
           _selectedMoto!['consumption_per_100km'] != null;
  }

  @override
  void initState() {
    super.initState();
    _loadMotos();
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _departureTimeController.dispose();
    _lunchTimeController.dispose();
    _dinnerTimeController.dispose();
    for (final c in _customPointControllers) c.dispose();
    super.dispose();
  }

  Future<void> _loadMotos() async {
    final result = await RiderProfileService.getMotos();
    if (!mounted) return;
    if (result['error'] == null) {
      final motos = List<Map<String, dynamic>>.from(result['motos']);
      setState(() {
        _motos        = motos;
        _loadingMotos = false;
        if (motos.isNotEmpty) {
          final primary = motos.firstWhere(
            (m) => m['is_primary'] == true,
            orElse: () => motos.first,
          );
          _selectedMotoId = primary['id'];
          _selectedMoto   = primary;
        }
      });
    } else {
      setState(() => _loadingMotos = false);
    }
  }

  Future<void> _generate() async {
    if (_originController.text.trim().isEmpty) {
      setState(() => _error = 'planner.origin_required'.tr());
      return;
    }
    if (!_circular && _destinationController.text.trim().isEmpty) {
      setState(() => _error = 'planner.destination_required'.tr());
      return;
    }
    if (_selectedMotoId == null) {
      setState(() => _error = 'planner.moto_required'.tr());
      return;
    }

    setState(() { _loading = true; _error = null; });

    final customPoints = _customPointControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final data = {
      'origin':              _originController.text.trim(),
      'moto_id':             _selectedMotoId,
      'circular':            _circular,
      'preference':          _preference,
      'difficulty':          _difficulty,
      if (_days > 1) 'days': _days else 'hours': _hours,
      if (customPoints.isNotEmpty) 'custom_points': customPoints,
      if (_departureTimeController.text.trim().isNotEmpty)
        'departure_time': _departureTimeController.text.trim(),
      if (!_circular && _destinationController.text.trim().isNotEmpty)
        'destination': _destinationController.text.trim(),
      'suggest_gas_stations': _motoHasFuelData && _suggestGasStations,
      'suggest_lunch':        _suggestLunch,
      'lunch_time':           _suggestLunch ? _lunchTimeController.text.trim() : null,
      'suggest_dinner':       _suggestDinner,
      'dinner_time':          _suggestDinner ? _dinnerTimeController.text.trim() : null,
      if (_days > 1) 'suggest_hotels': _suggestHotels,
    };

    final result = await RouteService.generateRoute(data);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['error'] != null) {
      setState(() => _error = result['error']);
      return;
    }

    context.go('/rider/route-result', extra: result['result']);
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
          onPressed: () => context.go('/rider/home'),
        ),
        title: Text('planner.title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: _loadingMotos
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header IA
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        AppColors.orange.withOpacity(0.2),
                        AppColors.cyan.withOpacity(0.1),
                      ]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: AppColors.orange, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('planner.ai_generated'.tr(),
                                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                              if (_routesRemaining != null)
                                Text('planner.routes_remaining'.tr(args: ['$_routesRemaining']),
                                    style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 1. Moto
                  Text('planner.moto'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (_motos.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.greyDark),
                      ),
                      child: Text('profile.no_motos'.tr(), style: const TextStyle(color: AppColors.grey)),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: _selectedMotoId,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(color: AppColors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.greyDark)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.greyDark)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.orange, width: 2)),
                      ),
                      items: _motos.map((moto) => DropdownMenuItem<int>(
                        value: moto['id'],
                        child: Text(moto['alias'] ?? '${moto['brand']} ${moto['model']}',
                            style: const TextStyle(color: AppColors.white)),
                      )).toList(),
                      onChanged: (val) => setState(() {
                        _selectedMotoId = val;
                        _selectedMoto   = _motos.firstWhere((m) => m['id'] == val);
                      }),
                    ),

                  const SizedBox(height: 20),

                  // 2. Punto de origen
                  Text('planner.origin'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _originController,
                    style: const TextStyle(color: AppColors.white),
                    decoration: InputDecoration(
                      hintText: 'planner.origin_hint'.tr(),
                      prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.orange),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. Hora de salida (opcional)
                  Row(children: [
                    Text('planner.departure_time_optional'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                    const SizedBox(width: 8),
                    Text('planner.ai_calculates'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                  ]),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _departureTimeController,
                    style: const TextStyle(color: AppColors.white),
                    keyboardType: TextInputType.datetime,
                    decoration: InputDecoration(
                      hintText: 'planner.departure_time_hint'.tr(),
                      prefixIcon: const Icon(Icons.schedule, color: AppColors.grey),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 4. Tipo de ruta
                  Text('planner.route_type'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _OptionChip(label: 'planner.circular'.tr(), selected: _circular, onTap: () => setState(() => _circular = true)),
                    const SizedBox(width: 8),
                    _OptionChip(label: 'planner.with_destination'.tr(), selected: !_circular, onTap: () => setState(() => _circular = false)),
                  ]),

                  // 5. Destino
                  if (!_circular) ...[
                    const SizedBox(height: 16),
                    Text('planner.destination'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _destinationController,
                      style: const TextStyle(color: AppColors.white),
                      decoration: InputDecoration(
                        hintText: 'planner.destination_hint'.tr(),
                        prefixIcon: const Icon(Icons.flag_outlined, color: AppColors.cyan),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // 6. Puntos obligatorios
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('planner.mandatory_points'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                      if (_customPointControllers.length < 5)
                        GestureDetector(
                          onTap: () => setState(() => _customPointControllers.add(TextEditingController())),
                          child: Row(children: [
                            const Icon(Icons.add_circle_outline, color: AppColors.orange, size: 18),
                            const SizedBox(width: 4),
                            Text('common.add'.tr(), style: const TextStyle(color: AppColors.orange, fontSize: 13)),
                          ]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._customPointControllers.asMap().entries.map((entry) {
                    final i = entry.key;
                    final ctrl = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.orange.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.orange),
                          ),
                          child: Center(child: Text('${i + 1}',
                              style: const TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.w700))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: ctrl,
                            style: const TextStyle(color: AppColors.white),
                            decoration: InputDecoration(
                              hintText: 'planner.point_hint'.tr(),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() {
                            ctrl.dispose();
                            _customPointControllers.removeAt(i);
                          }),
                          child: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
                        ),
                      ]),
                    );
                  }),

                  const SizedBox(height: 20),

                  // 7. Duración
                  Text('planner.duration'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _OptionChip(label: 'planner.route'.tr(), selected: _days == 1, onTap: () => setState(() => _days = 1)),
                    const SizedBox(width: 8),
                    _OptionChip(label: '2 ${"planner.trip".tr()}', selected: _days == 2, onTap: () => setState(() => _days = 2)),
                    const SizedBox(width: 8),
                    _OptionChip(label: '3+ ${"planner.trip".tr()}', selected: _days >= 3, onTap: () => setState(() => _days = 3)),
                  ]),
                  if (_days == 1) ...[
                    const SizedBox(height: 12),
                    Text('planner.hours_available'.tr(args: ['$_hours']),
                        style: const TextStyle(color: AppColors.white, fontSize: 13)),
                    Slider(
                      value: _hours.toDouble(), min: 2, max: 12, divisions: 10,
                      activeColor: AppColors.orange, inactiveColor: AppColors.greyDark,
                      label: '$_hours h',
                      onChanged: (val) => setState(() => _hours = val.round()),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // 8. Preferencia
                  Text('planner.preference'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _OptionChip(label: 'planner.curves'.tr(),    selected: _preference == 'curvas',  onTap: () => setState(() => _preference = 'curvas')),
                    const SizedBox(width: 8),
                    _OptionChip(label: 'planner.landscape'.tr(), selected: _preference == 'paisaje', onTap: () => setState(() => _preference = 'paisaje')),
                    const SizedBox(width: 8),
                    _OptionChip(label: 'planner.mixed'.tr(),     selected: _preference == 'mixto',   onTap: () => setState(() => _preference = 'mixto')),
                  ]),

                  const SizedBox(height: 20),

                  // 9. Dificultad
                  Text('planner.difficulty'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _OptionChip(label: 'planner.easy'.tr(),     selected: _difficulty == 'tranquila', onTap: () => setState(() => _difficulty = 'tranquila')),
                    const SizedBox(width: 8),
                    _OptionChip(label: 'planner.moderate'.tr(), selected: _difficulty == 'moderada',  onTap: () => setState(() => _difficulty = 'moderada')),
                    const SizedBox(width: 8),
                    _OptionChip(label: 'planner.hard'.tr(),     selected: _difficulty == 'exigente',  onTap: () => setState(() => _difficulty = 'exigente')),
                  ]),

                  const SizedBox(height: 24),

                  // 10. Sugerencias adicionales
                  Text('planner.extra_suggestions'.tr(), style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),

                  _ToggleOption(
                    icon: Icons.local_gas_station,
                    label: 'planner.gas_stations'.tr(),
                    subtitle: _motoHasFuelData ? 'planner.gas_stations_desc'.tr() : 'planner.gas_stations_no_data'.tr(),
                    value: _motoHasFuelData && _suggestGasStations,
                    enabled: _motoHasFuelData,
                    color: AppColors.gold,
                    onChanged: (val) => setState(() => _suggestGasStations = val),
                  ),

                  const SizedBox(height: 8),

                  _ToggleOption(
                    icon: Icons.restaurant_outlined,
                    label: 'planner.lunch_stop'.tr(),
                    subtitle: 'planner.lunch_desc'.tr(),
                    value: _suggestLunch,
                    enabled: true,
                    color: AppColors.orange,
                    onChanged: (val) => setState(() => _suggestLunch = val),
                  ),
                  if (_suggestLunch) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _lunchTimeController,
                      style: const TextStyle(color: AppColors.white),
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        hintText: 'planner.time_approx_hint'.tr(args: ['14:00']),
                        prefixIcon: const Icon(Icons.schedule, color: AppColors.orange),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  _ToggleOption(
                    icon: Icons.dinner_dining,
                    label: 'planner.dinner_stop'.tr(),
                    subtitle: 'planner.dinner_desc'.tr(),
                    value: _suggestDinner,
                    enabled: true,
                    color: AppColors.cyan,
                    onChanged: (val) => setState(() => _suggestDinner = val),
                  ),
                  if (_suggestDinner) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _dinnerTimeController,
                      style: const TextStyle(color: AppColors.white),
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        hintText: 'planner.time_approx_hint'.tr(args: ['21:00']),
                        prefixIcon: const Icon(Icons.schedule, color: AppColors.cyan),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],

                  if (_days > 1) ...[
                    const SizedBox(height: 8),
                    _ToggleOption(
                      icon: Icons.hotel_outlined,
                      label: 'planner.hotels'.tr(),
                      subtitle: 'planner.hotels_desc'.tr(),
                      value: _suggestHotels,
                      enabled: true,
                      color: AppColors.gold,
                      onChanged: (val) => setState(() => _suggestHotels = val),
                    ),
                  ],

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
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 32),

                  ElevatedButton(
                    onPressed: (_loading || _motos.isEmpty) ? null : _generate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                              const SizedBox(width: 12),
                              Text('planner.generating'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text('planner.generate_button'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                            ],
                          ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

// Widget toggle reutilizable
class _ToggleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final bool enabled;
  final Color color;
  final ValueChanged<bool> onChanged;

  const _ToggleOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: value ? color.withOpacity(0.1) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value ? color.withOpacity(0.4) : AppColors.greyDark),
      ),
      child: Row(children: [
        Icon(icon, color: enabled ? color : AppColors.greyDark, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                color: enabled ? AppColors.white : AppColors.greyDark,
                fontSize: 14, fontWeight: FontWeight.w600,
              )),
              Text(subtitle, style: TextStyle(
                color: enabled ? AppColors.grey : AppColors.greyDark,
                fontSize: 11,
              )),
            ],
          ),
        ),
        Switch(
          value: value && enabled,
          onChanged: enabled ? onChanged : null,
          activeColor: color,
          inactiveThumbColor: AppColors.greyDark,
          inactiveTrackColor: AppColors.surface,
        ),
      ]),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.orange.withOpacity(0.15) : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.orange : AppColors.greyDark,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppColors.orange : AppColors.grey,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

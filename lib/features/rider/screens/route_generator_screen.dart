import 'dart:async';
import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/rider_profile_service.dart';
import '../providers/route_service.dart';
import 'poi_picker_screen.dart';

class RouteGeneratorScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const RouteGeneratorScreen({super.key, this.initialData});

  @override
  State<RouteGeneratorScreen> createState() => _RouteGeneratorScreenState();
}

class _RouteGeneratorScreenState extends State<RouteGeneratorScreen> {
  final _originController        = TextEditingController();
  final _destinationController   = TextEditingController();
  final _departureTimeController = TextEditingController();
  final _lunchTimeController     = TextEditingController();
  final _dinnerTimeController    = TextEditingController();
  final List<TextEditingController> _customPointControllers = [];

  List<Map<String, dynamic>> _motos = [];
  Map<String, dynamic>? _selectedMoto;
  int? _selectedMotoId;
  String _preference  = 'mixto';
  String _difficulty  = 'moderada';

  /// Cuántas paradas con desvío acepta: ninguna, pocas o muchas.
  ///
  /// "Pocas" por defecto: quien no toca esto quiere rodar, con un par de
  /// sitios que merezcan la pena, no una visita guiada. Los puertos y
  /// desfiladeros no cuentan aquí — se visitan al pasar.
  String _poiStops    = 'pocas';

  /// POIs de nuestra tabla que el motero ha elegido a mano. Obligatorios.
  ///
  /// Se guardan enteros, no solo los ids, para poder enseñar sus nombres aquí
  /// y para que el selector pueda listarlos aunque el filtro activo los deje
  /// fuera al volver a entrar.
  List<Map<String, dynamic>> _selectedPois = [];

  /// Filtros del selector, para encontrarlo como lo dejaste.
  String? _poiCategory;
  String? _poiQuery;
  int? _poiRadiusKm;

  List<int> get _selectedPoiIds =>
      _selectedPois.map((p) => p['id'] as int).toList();
  bool   _circular    = true;
  bool   _avoidHighways = true;
  int    _hours       = 4;
  int    _km          = 200;
  String _durationMode = 'ai'; // 'ai', 'hours', 'km'
  DateTime? _departureDate;
  bool _loading      = false;
  bool _loadingMotos = true;
  bool _detectingLocation = false;
  bool _originValidated   = false;
  bool _destinationValidated = false;
  List<Map<String, dynamic>> _originSuggestions = [];
  List<Map<String, dynamic>> _destinationSuggestions = [];
  List<List<Map<String, dynamic>>> _pointSuggestions = [];
  List<bool> _pointValidated = [];
  List<Map<String, double>?> _pointCoords = []; // lat/lng de cada punto
  double? _originLat;
  double? _originLng;
  String? _error;
  int? _routesRemaining;

  bool _suggestGasStations = true;
  bool _suggestLunch       = false;
  bool _suggestDinner      = false;

  bool get _motoHasFuelData {
    if (_selectedMoto == null) return false;
    return _selectedMoto!['fuel_capacity'] != null &&
           _selectedMoto!['consumption_per_100km'] != null;
  }

  @override
  void initState() {
    super.initState();
    _loadMotos().then((_) {
      if (widget.initialData != null) _restoreFormData(widget.initialData!);
    });
  }

  void _restoreFormData(Map<String, dynamic> data) {
    setState(() {
      _originController.text      = data['origin'] ?? '';
      _originValidated            = (data['origin'] ?? '').isNotEmpty;
      _destinationController.text = data['destination'] ?? '';
      _destinationValidated       = (data['destination'] ?? '').isNotEmpty;
      _circular           = data['circular'] ?? true;
      _avoidHighways      = data['avoid_highways'] ?? true;
      _preference         = data['preference'] ?? 'mixto';
      _poiStops           = data['poi_stops'] ?? 'pocas';
      _selectedPois       = List<Map<String, dynamic>>.from(data['pois_elegidos'] ?? []);
      _difficulty         = data['difficulty'] ?? 'moderada';
      _durationMode       = data['duration_mode'] ?? 'hours';
      _hours              = (data['hours'] ?? 4) is double
          ? (data['hours'] as double).round()
          : (data['hours'] ?? 4) as int;
      _km                 = (data['km'] ?? 200) is double
          ? (data['km'] as double).round()
          : (data['km'] ?? 200) as int;
      _suggestLunch       = data['suggest_lunch'] ?? false;
      _suggestDinner      = data['suggest_dinner'] ?? false;
      _suggestGasStations = data['suggest_gas'] ?? false;

      if ((data['departure_time'] ?? '').toString().isNotEmpty)
        _departureTimeController.text = data['departure_time'];
      if ((data['lunch_time'] ?? '').toString().isNotEmpty)
        _lunchTimeController.text = data['lunch_time'];
      if ((data['dinner_time'] ?? '').toString().isNotEmpty)
        _dinnerTimeController.text = data['dinner_time'];

      // Restaurar fecha
      if (data['departure_date'] != null) {
        try { _departureDate = DateTime.parse(data['departure_date']); } catch (_) {}
      }

      // Restaurar moto
      if (data['moto_id'] != null && _motos.isNotEmpty) {
        final moto = _motos.firstWhere(
          (m) => m['id'] == data['moto_id'],
          orElse: () => _motos.first,
        );
        _selectedMotoId = moto['id'];
        _selectedMoto   = moto;
      }

      // Restaurar puntos obligatorios
      for (final c in _customPointControllers) c.dispose();
      _customPointControllers.clear();
      _pointSuggestions.clear();
      _pointValidated.clear();
      _pointCoords.clear();
      final points = (data['custom_points'] as List? ?? []);
      for (final p in points) {
        _customPointControllers.add(TextEditingController(text: p.toString()));
        _pointSuggestions.add([]);
        _pointValidated.add(true); // ya validados previamente
        _pointCoords.add(null);
      }
    });
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _departureTimeController.dispose();
    _lunchTimeController.dispose();
    _dinnerTimeController.dispose();
    for (final c in _customPointControllers) c.dispose();
    for (final t in _searchDebounce.values) t.cancel();
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

    // Cargar ubicación del perfil como origen por defecto
    if (_originController.text.isEmpty) {
      final profileResult = await RiderProfileService.getProfile();
      if (!mounted) return;
      final profile  = profileResult['profile'];
      final province = profile?['province'];
      if (province != null && province.toString().isNotEmpty) {
        setState(() {
          _originController.text = province;
          _originValidated = true;
        });
        // Intentar obtener coordenadas del perfil (province_lat/lng)
        final lat = (profile?['province_lat'] as num?)?.toDouble();
        final lng = (profile?['province_lng'] as num?)?.toDouble();
        if (lat != null && lng != null && lat != 0 && lng != 0) {
          setState(() { _originLat = lat; _originLng = lng; });
        } else {
          // Geocodificar el nombre
          try {
            final response = await ApiClient.dio.get('/location/search', queryParameters: {
              'q': province, 'lang': 'es',
            });
            final List data = response.data as List? ?? [];
            if (data.isNotEmpty && mounted) {
              setState(() {
                _originLat = (data[0]['lat'] as num?)?.toDouble();
                _originLng = (data[0]['lng'] as num?)?.toDouble();
              });
            }
          } catch (_) {}
        }
      }
    }

    // Hora de salida por defecto: 09:00
    if (_departureTimeController.text.isEmpty) {
      setState(() => _departureTimeController.text = '09:00');
    }
  }

  void _searchOrigin(String query) {
    if (_originValidated) {
      setState(() => _originValidated = false);
    }

    if (query.length < 3) {
      if (_originSuggestions.isNotEmpty) {
        setState(() => _originSuggestions = []);
      }
      return;
    }

    _debounced('origin', () => _fetchOrigin(query));
  }

  Future<void> _fetchOrigin(String query) async {
    try {
      final response = await ApiClient.dio.get('/location/search', queryParameters: {
        'q': query, 'lang': 'es',
      });
      final List data = response.data as List? ?? [];
      if (data.isNotEmpty && mounted) {
        setState(() {
          _originSuggestions = data.map<Map<String, dynamic>>((p) => {
            'description': p['description'] as String,
            'place_id':    p['place_id'] as String,
            'lat':         (p['lat'] as num?)?.toDouble() ?? 0.0,
            'lng':         (p['lng'] as num?)?.toDouble() ?? 0.0,
          }).toList();
        });
      }
    } catch (_) {}
  }

  /// Temporizadores de los buscadores de lugares, uno por campo.
  ///
  /// Sin esto se pedían sugerencias a Google EN CADA TECLA: escribir
  /// "Santander" eran siete llamadas, cada una ida y vuelta al servidor. Se
  /// notaba al escribir y además Places Autocomplete es de lo más caro de la
  /// API. Ahora se espera a que el motero pare.
  final Map<String, Timer> _searchDebounce = {};

  void _debounced(String field, VoidCallback action) {
    _searchDebounce[field]?.cancel();
    _searchDebounce[field] =
        Timer(const Duration(milliseconds: 400), action);
  }

  /// El reseteo es inmediato y solo se retrasa la llamada: así el campo
  /// responde al instante aunque la búsqueda tarde.
  /// Al teclear NO se repinta nada: ni se borran las sugerencias ni se toca
  /// el estado.
  ///
  /// Cada `setState` aquí reconstruye la pantalla entera, que pasa de 1.500
  /// líneas de widgets, y eso es lo que hacía que el teclado fuera a tirones.
  /// El primer intento —borrar sugerencias solo si las había— no arregló gran
  /// cosa: en cuanto aparecen, cada tecla siguiente las borraba otra vez.
  ///
  /// Así que se dejan a la vista hasta que llegan las nuevas. Además de ser
  /// más rápido se ve mejor: la lista no parpadea entre letra y letra.
  void _searchDestination(String query) {
    if (_destinationValidated) {
      setState(() => _destinationValidated = false);
    }

    if (query.length < 3) {
      if (_destinationSuggestions.isNotEmpty) {
        setState(() => _destinationSuggestions = []);
      }
      return;
    }

    _debounced('destination', () => _fetchDestination(query));
  }

  Future<void> _fetchDestination(String query) async {
    try {
      final response = await ApiClient.dio.get('/location/search', queryParameters: {
        'q': query, 'lang': 'es',
      });
      final List data = response.data as List? ?? [];
      if (data.isNotEmpty && mounted) {
        setState(() {
          _destinationSuggestions = data.map<Map<String, dynamic>>((p) => {
            'description': p['description'] as String,
            'place_id':    p['place_id'] as String,
          }).toList();
        });
      }
    } catch (_) {}
  }

  double? _distanceToOrigin(Map<String, double>? coords) {
    if (coords == null || _originLat == null || _originLng == null) return null;
    const r = 6371.0;
    final dLat = _toRad(coords['lat']! - _originLat!);
    final dLng = _toRad(coords['lng']! - _originLng!);
    final a = sin(dLat/2)*sin(dLat/2) +
        cos(_toRad(_originLat!)) * cos(_toRad(coords['lat']!)) *
        sin(dLng/2)*sin(dLng/2);
    return r * 2 * atan2(sqrt(a), sqrt(1-a));
  }

  double _toRad(double deg) => deg * pi / 180;

  void _searchPoint(int index, String query) {
    if (index >= _pointSuggestions.length) return;

    if (_pointValidated[index] || _pointCoords[index] != null) {
      setState(() {
        _pointValidated[index] = false;
        _pointCoords[index] = null;
      });
    }

    if (query.length < 3) {
      if (_pointSuggestions[index].isNotEmpty) {
        setState(() => _pointSuggestions[index] = []);
      }
      return;
    }

    _debounced('point$index', () => _fetchPoint(index, query));
  }

  Future<void> _fetchPoint(int index, String query) async {
    if (index >= _pointSuggestions.length) return;
    try {
      final response = await ApiClient.dio.get('/location/search', queryParameters: {
        'q': query, 'lang': 'es', 'poi': '1',
      });
      final List data = response.data as List? ?? [];
      if (data.isNotEmpty && mounted) {
        setState(() {
          _pointSuggestions[index] = data.map<Map<String, dynamic>>((p) => {
            'description': p['description'] as String,
            'place_id':    p['place_id'] as String,
            'lat':         (p['lat'] as num?)?.toDouble() ?? 0.0,
            'lng':         (p['lng'] as num?)?.toDouble() ?? 0.0,
          }).toList();
        });
      }
    } catch (_) {}
  }

  void _movePointUp(int i) {
    if (i == 0) return;
    setState(() {
      final ctrl = _customPointControllers.removeAt(i);
      _customPointControllers.insert(i - 1, ctrl);
      final sugg = _pointSuggestions.removeAt(i);
      _pointSuggestions.insert(i - 1, sugg);
      final val = _pointValidated.removeAt(i);
      _pointValidated.insert(i - 1, val);
      final coord = _pointCoords.removeAt(i);
      _pointCoords.insert(i - 1, coord);
    });
  }

  void _movePointDown(int i) {
    if (i >= _customPointControllers.length - 1) return;
    setState(() {
      final ctrl = _customPointControllers.removeAt(i);
      _customPointControllers.insert(i + 1, ctrl);
      final sugg = _pointSuggestions.removeAt(i);
      _pointSuggestions.insert(i + 1, sugg);
      final val = _pointValidated.removeAt(i);
      _pointValidated.insert(i + 1, val);
      final coord = _pointCoords.removeAt(i);
      _pointCoords.insert(i + 1, coord);
    });
  }

  Future<void> _detectOriginLocation() async {
    setState(() => _detectingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) { setState(() => _detectingLocation = false); return; }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Activa los permisos de ubicación en ajustes.'), backgroundColor: AppColors.error));
        setState(() => _detectingLocation = false); return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      final response = await ApiClient.dio.get('/location/search', queryParameters: {
        'q': '${position.latitude},${position.longitude}', 'lang': 'es', 'reverse': '1',
      });
      final List data = response.data as List? ?? [];
      if (data.isNotEmpty && mounted) {
        setState(() {
          _originController.text = data[0]['description'] as String;
          _originValidated = true;
          _originSuggestions = [];
        });
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo obtener la ubicación.'), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() => _detectingLocation = false);
  }

  // Aviso si hay puntos obligatorios que pueden sobrepasar el límite
  void _checkDurationWarning() {
    if (_customPointControllers.isEmpty) return;
    if (_durationMode == 'ai') return;

    final pointCount = _customPointControllers.where((c) => c.text.trim().isNotEmpty).length;
    if (pointCount == 0) return;

    String? warning;
    if (_durationMode == 'hours' && _hours <= 4 && pointCount >= 2) {
      warning = '⚠️ Tienes $_hours horas y $pointCount puntos obligatorios. La ruta puede sobrepasar el tiempo disponible. Considera ampliar las horas o dejar que la IA calcule.';
    } else if (_durationMode == 'hours' && _hours <= 6 && pointCount >= 3) {
      warning = '⚠️ Con $pointCount puntos obligatorios y $_hours horas disponibles la ruta puede ser ajustada. La IA intentará optimizarla.';
    } else if (_durationMode == 'km' && _km <= 150 && pointCount >= 2) {
      warning = '⚠️ Tienes $_km km y $pointCount puntos obligatorios. La distancia puede ser insuficiente. Considera ampliar los km o dejar que la IA calcule.';
    }

    if (warning != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(warning),
        backgroundColor: AppColors.gold,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Dejar a la IA',
          textColor: AppColors.background,
          onPressed: () => setState(() => _durationMode = 'ai'),
        ),
      ));
    }
  }

  Future<void> _pickDate() async {
    final now  = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _departureDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.orange, surface: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (date != null) {
      setState(() => _departureDate = date);
      final diff = date.difference(DateTime.now()).inDays;
      if (diff > 5 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('planner.weather_forecast_notice'.tr()),
          backgroundColor: AppColors.gold,
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  Future<void> _pickTime(TextEditingController controller, {Color color = AppColors.orange}) async {
    final now = const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: controller.text.isNotEmpty
          ? TimeOfDay(
              hour: int.tryParse(controller.text.split(':')[0]) ?? now.hour,
              minute: int.tryParse(controller.text.split(':')[1]) ?? 0,
            )
          : now,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: color, surface: AppColors.surface),
          timePickerTheme: TimePickerThemeData(
            backgroundColor: AppColors.surface,
            hourMinuteColor: AppColors.background,
            hourMinuteTextColor: color,
            dialHandColor: color,
            dialBackgroundColor: AppColors.background,
            entryModeIconColor: color,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      setState(() => controller.text = '$h:$m');
    }
  }

  /// Abre el selector de POIs de nuestra base de datos.
  ///
  /// Hace falta el origen: sin él no hay desde dónde medir distancias, y es
  /// mejor decirlo que abrir una pantalla vacía.
  Future<void> _openPoiPicker() async {
    final origin = _originController.text.trim();
    final destination = _destinationController.text.trim();

    if (origin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('poi_picker.need_origin'.tr()),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    // En una ruta con destino los puntos no están en un círculo alrededor de
    // la salida, sino a lo largo del trayecto. Sin saber adónde vas no hay
    // trayecto, así que no hay nada que enseñar.
    if (!_circular && destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('poi_picker.need_destination'.tr()),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => PoiPickerScreen(
          origin: origin,
          destination: _circular ? null : destination,
          // Solo se pasan los km si el motero eligió ese modo: así el servidor
          // acota el radio a lo que de verdad cabe en su ruta.
          km: _durationMode == 'km' ? _km : null,
          circular: _circular,
          selected: _selectedPois,
          initialCategory: _poiCategory,
          initialQuery: _poiQuery,
          initialRadiusKm: _poiRadiusKm,
        ),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedPois =
          List<Map<String, dynamic>>.from(result['pois'] ?? const []);
      _poiCategory = result['category'];
      _poiQuery = result['query'];
      _poiRadiusKm = result['radius_km'];
    });
  }

  Future<void> _generate() async {
    if (_selectedMotoId == null) {
      setState(() => _error = 'planner.moto_required'.tr());
      return;
    }
    if (_originController.text.trim().isEmpty) {
      setState(() => _error = 'planner.origin_required'.tr());
      return;
    }
    if (_departureDate == null) {
      setState(() => _error = 'planner.date_required'.tr());
      return;
    }
    if (_departureTimeController.text.trim().isEmpty) {
      setState(() => _error = 'planner.time_required'.tr());
      return;
    }
    if (!_circular && _destinationController.text.trim().isEmpty) {
      setState(() => _error = 'planner.destination_required'.tr());
      return;
    }
    if (_suggestLunch && _lunchTimeController.text.trim().isEmpty) {
      setState(() => _error = 'planner.lunch_time_required'.tr());
      return;
    }
    if (_suggestDinner && _dinnerTimeController.text.trim().isEmpty) {
      setState(() => _error = 'planner.dinner_time_required'.tr());
      return;
    }

    // Validar mínimo 4 horas entre almuerzo y comida
    if (_suggestLunch && _suggestDinner &&
        _lunchTimeController.text.isNotEmpty &&
        _dinnerTimeController.text.isNotEmpty) {
      final lParts = _lunchTimeController.text.split(':');
      final dParts = _dinnerTimeController.text.split(':');
      if (lParts.length == 2 && dParts.length == 2) {
        final lMins = int.parse(lParts[0]) * 60 + int.parse(lParts[1]);
        final dMins = int.parse(dParts[0]) * 60 + int.parse(dParts[1]);
        if (dMins - lMins < 240) {
          final suggested = TimeOfDay(
            hour: (lMins + 240) ~/ 60,
            minute: (lMins + 240) % 60,
          );
          final h = suggested.hour.toString().padLeft(2, '0');
          final m = suggested.minute.toString().padLeft(2, '0');
          setState(() => _error = 'Debe haber al menos 4 horas entre almuerzo y comida. Hora de comida mínima: $h:$m');
          return;
        }
      }
    }

    // Validar que los puntos obligatorios no estén vacíos
    for (int i = 0; i < _customPointControllers.length; i++) {
      if (_customPointControllers[i].text.trim().isEmpty) {
        setState(() => _error = 'El punto ${i + 1} está vacío. Rellénalo o elimínalo.');
        return;
      }
      if (i < _pointValidated.length && !_pointValidated[i]) {
        setState(() => _error = 'El punto ${i + 1} no está validado. Selecciónalo de la lista de sugerencias.');
        return;
      }
    }

    setState(() { _loading = true; _error = null; });

    final customPoints = _customPointControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final data = {
      'origin':               _originController.text.trim(),
      'moto_id':              _selectedMotoId,
      'circular':             _circular,
      'avoid_highways':       _avoidHighways,
      'preference':           _preference,
      'difficulty':           _difficulty,
      'poi_stops':            _poiStops,
      if (_selectedPoiIds.isNotEmpty) 'poi_ids': _selectedPoiIds,
      'duration_mode':        _durationMode,
      'hours':                _durationMode == 'hours' ? _hours : null,
      'km':                   _durationMode == 'km'    ? _km    : null,
      if (customPoints.isNotEmpty) 'custom_points': customPoints,
      if (_departureTimeController.text.trim().isNotEmpty)
        'departure_time': _departureTimeController.text.trim(),
      if (_departureDate != null)
        'departure_date': '${_departureDate!.year}-${_departureDate!.month.toString().padLeft(2, '0')}-${_departureDate!.day.toString().padLeft(2, '0')}',
      if (!_circular && _destinationController.text.trim().isNotEmpty)
        'destination': _destinationController.text.trim(),
      'suggest_gas_stations': _motoHasFuelData && _suggestGasStations,
      'suggest_lunch':        _suggestLunch,
      'lunch_time':           _suggestLunch ? _lunchTimeController.text.trim() : null,
      'suggest_dinner':       _suggestDinner,
      'dinner_time':          _suggestDinner ? _dinnerTimeController.text.trim() : null,
    };

    final result = await RouteService.generateRoute(data);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['error'] != null) {
      setState(() => _error = result['error']);
      return;
    }

    // Pasar también los datos del formulario para poder restaurarlos al volver
    final formData = {
      'origin':         _originController.text.trim(),
      'destination':    _destinationController.text.trim(),
      'moto_id':        _selectedMotoId,
      'circular':       _circular,
      'avoid_highways': _avoidHighways,
      'preference':     _preference,
      'difficulty':     _difficulty,
      'poi_stops':      _poiStops,
      'poi_ids':        _selectedPoiIds,
      'duration_mode':  _durationMode,
      'hours':          _hours,
      'km':             _km,
      'departure_date': _departureDate != null
          ? '${_departureDate!.year}-${_departureDate!.month.toString().padLeft(2, '0')}-${_departureDate!.day.toString().padLeft(2, '0')}'
          : null,
      'departure_time': _departureTimeController.text.trim(),
      'suggest_lunch':  _suggestLunch,
      'lunch_time':     _lunchTimeController.text.trim(),
      'suggest_dinner': _suggestDinner,
      'dinner_time':    _dinnerTimeController.text.trim(),
      'suggest_gas':    _suggestGasStations,
      'custom_points':  _customPointControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    };

    context.push('/rider/route-result', extra: {
      ...result['result'] as Map<String, dynamic>,
      'form_data': formData,
    });
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
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/rider/home');
            }
          },
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
                    child: Row(children: [
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
                    ]),
                  ),

                  const SizedBox(height: 24),

                  // 1. Moto
                  Text('planner.moto'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (_motos.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.greyDark)),
                      child: Text('profile.no_motos'.tr(), style: const TextStyle(color: AppColors.grey)),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: _selectedMotoId,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(color: AppColors.white),
                      decoration: InputDecoration(
                        filled: true, fillColor: AppColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.greyDark)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.greyDark)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.orange, width: 2)),
                      ),
                      items: _motos.map((moto) => DropdownMenuItem<int>(
                        value: moto['id'],
                        child: Text(moto['alias'] ?? '${moto['brand']} ${moto['model'] ?? ''}'.trim(), style: const TextStyle(color: AppColors.white)),
                      )).toList(),
                      onChanged: (val) => setState(() {
                        _selectedMotoId = val;
                        _selectedMoto   = _motos.firstWhere((m) => m['id'] == val);
                      }),
                    ),

                  const SizedBox(height: 20),

                  // 2. Origen
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('planner.origin'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                      GestureDetector(
                        onTap: _detectingLocation ? null : _detectOriginLocation,
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
                    controller: _originController,
                    style: const TextStyle(color: AppColors.white),
                    onChanged: _searchOrigin,
                    decoration: InputDecoration(
                      hintText: 'planner.origin_hint'.tr(),
                      prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.orange),
                      suffixIcon: _originController.text.isNotEmpty
                          ? _originValidated
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                              : IconButton(
                                  icon: const Icon(Icons.clear, color: AppColors.grey, size: 18),
                                  onPressed: () => setState(() {
                                    _originController.clear();
                                    _originSuggestions = [];
                                    _originValidated = false;
                                  }))
                          : null,
                    ),
                  ),
                  if (_originSuggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.greyDark),
                      ),
                      child: Column(
                        children: _originSuggestions.map((s) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_city, color: AppColors.grey, size: 18),
                          title: Text(s['description'],
                              style: const TextStyle(color: AppColors.white, fontSize: 13)),
                          onTap: () => setState(() {
                            _originController.text = s['description'];
                            _originValidated = true;
                            _originSuggestions = [];
                            _originLat = (s['lat'] as num?)?.toDouble();
                            _originLng = (s['lng'] as num?)?.toDouble();
                          }),
                        )).toList(),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // 3. Fecha de salida
                  Text('planner.departure_date'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _departureDate != null ? AppColors.orange : AppColors.greyDark,
                          width: _departureDate != null ? 2 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today,
                            color: _departureDate != null ? AppColors.orange : AppColors.grey, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          _departureDate != null
                              ? '${_departureDate!.day.toString().padLeft(2, '0')}/${_departureDate!.month.toString().padLeft(2, '0')}/${_departureDate!.year}'
                              : 'planner.departure_date'.tr(),
                          style: TextStyle(
                            color: _departureDate != null ? AppColors.white : AppColors.grey,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        if (_departureDate != null)
                          GestureDetector(
                            onTap: () => setState(() => _departureDate = null),
                            child: const Icon(Icons.clear, color: AppColors.grey, size: 18),
                          ),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 4. Hora de salida (obligatoria)
                  Row(children: [
                    Text('planner.departure_time_optional'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                    const SizedBox(width: 4),
                    const Text('*', style: TextStyle(color: AppColors.error, fontSize: 13)),
                    const SizedBox(width: 8),
                    Text('planner.ai_calculates'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                  ]),
                  const SizedBox(height: 8),
                  _TimePickerButton(
                    controller: _departureTimeController,
                    color: AppColors.orange,
                    hint: 'planner.departure_time_hint'.tr(),
                    onTap: () => _pickTime(_departureTimeController, color: AppColors.orange),
                  ),

                  const SizedBox(height: 20),

                  // 5. Tipo de ruta
                  Text('planner.route_type'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _OptionChip(label: 'planner.circular'.tr(), selected: _circular, onTap: () => setState(() => _circular = true)),
                    const SizedBox(width: 8),
                    _OptionChip(label: 'planner.with_destination'.tr(), selected: !_circular, onTap: () => setState(() => _circular = false)),
                  ]),

                  if (!_circular) ...[
                    const SizedBox(height: 16),
                    Text('planner.destination'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _destinationController,
                      style: const TextStyle(color: AppColors.white),
                      onChanged: _searchDestination,
                      decoration: InputDecoration(
                        hintText: 'planner.destination_hint'.tr(),
                        prefixIcon: const Icon(Icons.flag_outlined, color: AppColors.cyan),
                        suffixIcon: _destinationController.text.isNotEmpty
                            ? _destinationValidated
                                ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                                : IconButton(
                                    icon: const Icon(Icons.clear, color: AppColors.grey, size: 18),
                                    onPressed: () => setState(() {
                                      _destinationController.clear();
                                      _destinationSuggestions = [];
                                      _destinationValidated = false;
                                    }))
                            : null,
                      ),
                    ),
                    if (_destinationSuggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.greyDark),
                        ),
                        child: Column(
                          children: _destinationSuggestions.map((s) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_city, color: AppColors.grey, size: 18),
                            title: Text(s['description'],
                                style: const TextStyle(color: AppColors.white, fontSize: 13)),
                            onTap: () => setState(() {
                              _destinationController.text = s['description'];
                              _destinationValidated = true;
                              _destinationSuggestions = [];
                            }),
                          )).toList(),
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
                          onTap: () => setState(() {
                            _customPointControllers.add(TextEditingController());
                            _pointSuggestions.add([]);
                            _pointValidated.add(false);
                            _pointCoords.add(null);
                          }),
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
                    final i    = entry.key;
                    final ctrl = entry.value;
                    final total = _customPointControllers.length;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          Row(children: [
                            // Número
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
                            // Campo
                            Expanded(
                              child: TextFormField(
                                controller: ctrl,
                                style: const TextStyle(color: AppColors.white),
                                onChanged: (q) => _searchPoint(i, q),
                                decoration: InputDecoration(
                                  hintText: 'planner.point_hint'.tr(),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  suffixIcon: ctrl.text.isNotEmpty
                                      ? (i < _pointValidated.length && _pointValidated[i])
                                          ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                                          : null
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Botones orden
                            if (total > 1) Column(mainAxisSize: MainAxisSize.min, children: [
                              GestureDetector(
                                onTap: i > 0 ? () => _movePointUp(i) : null,
                                child: Icon(Icons.keyboard_arrow_up,
                                    color: i > 0 ? AppColors.cyan : AppColors.greyDark, size: 20),
                              ),
                              GestureDetector(
                                onTap: i < total - 1 ? () => _movePointDown(i) : null,
                                child: Icon(Icons.keyboard_arrow_down,
                                    color: i < total - 1 ? AppColors.cyan : AppColors.greyDark, size: 20),
                              ),
                            ]),
                            const SizedBox(width: 4),
                            // Eliminar
                            GestureDetector(
                              onTap: () => setState(() {
                                ctrl.dispose();
                                _customPointControllers.removeAt(i);
                                if (i < _pointSuggestions.length) _pointSuggestions.removeAt(i);
                                if (i < _pointValidated.length)   _pointValidated.removeAt(i);
                                if (i < _pointCoords.length)      _pointCoords.removeAt(i);
                              }),
                              child: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
                            ),
                          ]),
                          // Desplegable sugerencias
                          if (i < _pointSuggestions.length && _pointSuggestions[i].isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4, left: 32),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.greyDark),
                              ),
                              child: Column(
                                children: _pointSuggestions[i].map((s) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.location_city, color: AppColors.grey, size: 18),
                                  title: Text(s['description'],
                                      style: const TextStyle(color: AppColors.white, fontSize: 13)),
                                  onTap: () => setState(() {
                                    ctrl.text = s['description'];
                                    _pointValidated[i] = true;
                                    _pointSuggestions[i] = [];
                                    if (i < _pointCoords.length) {
                                      _pointCoords[i] = {
                                        'lat': (s['lat'] as num?)?.toDouble() ?? 0.0,
                                        'lng': (s['lng'] as num?)?.toDouble() ?? 0.0,
                                      };
                                    }
                                  }),
                                )).toList(),
                              ),
                            ),
                          // Badge distancia al origen
                          if (i < _pointValidated.length && _pointValidated[i] &&
                              i < _pointCoords.length && _pointCoords[i] != null)
                            Builder(builder: (context) {
                              final dist = _distanceToOrigin(_pointCoords[i]);
                              if (dist == null) return const SizedBox.shrink();
                              final isWarning  = dist > 300;
                              final isCritical = dist > 500;
                              final color = isCritical ? AppColors.error : isWarning ? AppColors.gold : Colors.green;
                              final icon  = isCritical ? '⛔' : isWarning ? '⚠️' : '✅';
                              final msg   = isCritical
                                  ? 'Muy lejos del origen — puede generar ruta incorrecta'
                                  : isWarning ? 'Lejos del origen — la ruta será larga' : null;
                              return Container(
                                margin: const EdgeInsets.only(top: 4, left: 32),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: color.withOpacity(0.4)),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Text(icon, style: const TextStyle(fontSize: 12)),
                                    const SizedBox(width: 6),
                                    Text('${dist.toInt()} km del origen',
                                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                                  ]),
                                  if (msg != null)
                                    Text(msg, style: TextStyle(color: color, fontSize: 11)),
                                ]),
                              );
                            }),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 20),

                  // 7. Duración
                  Text('planner.duration'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 8),

                  // Selector de modo
                  Row(children: [
                    _DurationModeChip(
                      icon: Icons.auto_awesome,
                      label: 'La IA decide',
                      selected: _durationMode == 'ai',
                      color: AppColors.gold,
                      onTap: () => setState(() => _durationMode = 'ai'),
                    ),
                    const SizedBox(width: 8),
                    _DurationModeChip(
                      icon: Icons.access_time,
                      label: 'Por horas',
                      selected: _durationMode == 'hours',
                      color: AppColors.orange,
                      onTap: () {
                        setState(() => _durationMode = 'hours');
                        _checkDurationWarning();
                      },
                    ),
                    const SizedBox(width: 8),
                    _DurationModeChip(
                      icon: Icons.speed,
                      label: 'Por km',
                      selected: _durationMode == 'km',
                      color: AppColors.cyan,
                      onTap: () {
                        setState(() => _durationMode = 'km');
                        _checkDurationWarning();
                      },
                    ),
                  ]),

                  // Slider según modo
                  if (_durationMode == 'hours') ...[
                    const SizedBox(height: 8),
                    Text('planner.hours_available'.tr(args: ['$_hours']),
                        style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    Slider(
                      value: _hours.toDouble(), min: 2, max: 12, divisions: 10,
                      activeColor: AppColors.orange, inactiveColor: AppColors.greyDark,
                      label: '$_hours h',
                      onChanged: (val) {
                        setState(() => _hours = val.round());
                        _checkDurationWarning();
                      },
                    ),
                  ],

                  if (_durationMode == 'km') ...[
                    const SizedBox(height: 8),
                    Text('📏 Distancia objetivo: $_km km',
                        style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    Slider(
                      value: _km.toDouble(), min: 50, max: 600, divisions: 22,
                      activeColor: AppColors.cyan, inactiveColor: AppColors.greyDark,
                      label: '$_km km',
                      onChanged: (val) {
                        setState(() => _km = (val / 25).round() * 25);
                        _checkDurationWarning();
                      },
                    ),
                  ],

                  if (_durationMode == 'ai')
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.auto_awesome, color: AppColors.gold, size: 16),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'La IA calculará la duración óptima según tus puntos, moto y preferencias.',
                            style: TextStyle(color: AppColors.gold, fontSize: 12),
                          ),
                        ),
                      ]),
                    ),

                  const SizedBox(height: 12),

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

                  const SizedBox(height: 20),

                  // 9a. Paradas de interés
                  //
                  // Los puertos, desfiladeros y parques naturales NO cuentan
                  // aquí: se visitan al pasar, sin desviarse ni parar. Esto
                  // regula solo las paradas de verdad — miradores, monumentos,
                  // pueblos — que son las que cuestan kilómetros y tiempo.
                  Text('planner.poi_stops'.tr(),
                      style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('planner.poi_stops_help'.tr(),
                      style: const TextStyle(color: AppColors.grey, fontSize: 11, height: 1.3)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _OptionChip(
                        label: 'planner.poi_stops_none'.tr(),
                        selected: _poiStops == 'ninguna',
                        onTap: () => setState(() => _poiStops = 'ninguna')),
                    const SizedBox(width: 8),
                    _OptionChip(
                        label: 'planner.poi_stops_few'.tr(),
                        selected: _poiStops == 'pocas',
                        onTap: () => setState(() => _poiStops = 'pocas')),
                    const SizedBox(width: 8),
                    _OptionChip(
                        label: 'planner.poi_stops_many'.tr(),
                        selected: _poiStops == 'muchas',
                        onTap: () => setState(() => _poiStops = 'muchas')),
                  ]),

                  const SizedBox(height: 12),

                  // Elegir POIs concretos de nuestra base de datos.
                  //
                  // Va justo debajo del selector de paradas porque son lo
                  // mismo visto de otra forma: ahí dices CUÁNTAS quieres, aquí
                  // CUÁLES. Y los que elijas a mano son obligatorios.
                  OutlinedButton.icon(
                    onPressed: _openPoiPicker,
                    icon: const Icon(Icons.place_outlined,
                        color: AppColors.cyan, size: 18),
                    label: Text(
                      _selectedPois.isEmpty
                          ? 'poi_picker.choose'.tr()
                          : 'poi_picker.chosen'.plural(_selectedPois.length),
                      style: const TextStyle(color: AppColors.cyan),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      side: const BorderSide(color: AppColors.cyan),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  // Los nombres de los elegidos, debajo del botón.
                  //
                  // "3 puntos elegidos" no dice nada: desde esta pantalla no
                  // hay forma de saber cuáles son sin volver a entrar. Cada
                  // uno se puede quitar aquí mismo.
                  if (_selectedPois.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedPois.map((poi) {
                        return GestureDetector(
                          onTap: () => setState(() => _selectedPois.remove(poi)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('${poi['name']}',
                                  style: const TextStyle(
                                      color: AppColors.cyan, fontSize: 11)),
                              const SizedBox(width: 6),
                              const Icon(Icons.close,
                                  color: AppColors.cyan, size: 13),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    // Que se vea POR QUÉ la ruta no traerá sitios de propina:
                    // elegir a mano desactiva los que añade la IA.
                    Text('poi_picker.manual_note'.tr(),
                        style: const TextStyle(
                            color: AppColors.grey, fontSize: 12, height: 1.3)),
                  ],

                  const SizedBox(height: 20),

                  // 9b. Evitar autovías/autopistas
                  _ToggleOption(
                    icon: Icons.alt_route,
                    label: 'planner.avoid_highways'.tr(),
                    subtitle: 'planner.avoid_highways_desc'.tr(),
                    value: _avoidHighways, enabled: true, color: AppColors.cyan,
                    onChanged: (val) => setState(() => _avoidHighways = val),
                  ),

                  const SizedBox(height: 24),

                  // 10. Sugerencias adicionales
                  Text('planner.extra_suggestions'.tr(), style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),

                  _ToggleOption(
                    icon: Icons.local_gas_station,
                    label: 'planner.gas_stations'.tr(),
                    subtitle: (_motoHasFuelData
                        ? 'planner.gas_stations_desc'.tr()
                        : 'planner.gas_stations_no_data'.tr()) + ' (parada ~15 min)',
                    value: _motoHasFuelData && _suggestGasStations,
                    enabled: _motoHasFuelData,
                    color: AppColors.gold,
                    onChanged: (val) => setState(() => _suggestGasStations = val),
                  ),
                  const SizedBox(height: 8),
                  _ToggleOption(
                    icon: Icons.restaurant_outlined,
                    label: 'planner.lunch_stop'.tr(),
                    subtitle: 'planner.lunch_desc'.tr() + ' (parada ~30 min)',
                    value: _suggestLunch, enabled: true, color: AppColors.orange,
                    onChanged: (val) => setState(() => _suggestLunch = val),
                  ),
                  if (_suggestLunch) ...[
                    const SizedBox(height: 8),
                    _TimePickerButton(
                      controller: _lunchTimeController,
                      color: AppColors.orange,
                      hint: 'planner.time_approx_hint'.tr(args: ['14:00']),
                      onTap: () => _pickTime(_lunchTimeController, color: AppColors.orange),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _ToggleOption(
                    icon: Icons.dinner_dining,
                    label: 'planner.dinner_stop'.tr(),
                    subtitle: 'planner.dinner_desc'.tr() + ' (parada ~1 hora)',
                    value: _suggestDinner, enabled: true, color: AppColors.cyan,
                    onChanged: (val) => setState(() => _suggestDinner = val),
                  ),
                  if (_suggestDinner) ...[
                    const SizedBox(height: 8),
                    _TimePickerButton(
                      controller: _dinnerTimeController,
                      color: AppColors.cyan,
                      hint: 'planner.time_approx_hint'.tr(args: ['15:00']),
                      onTap: () => _pickTime(_dinnerTimeController, color: AppColors.cyan),
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
                        ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                            const SizedBox(width: 12),
                            Text('planner.generating'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ])
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text('planner.generate_button'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                          ]),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _DurationModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _DurationModeChip({
    required this.icon, required this.label, required this.selected,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? color : AppColors.greyDark, width: selected ? 2 : 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: selected ? color : AppColors.grey, size: 18),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center,
                style: TextStyle(color: selected ? color : AppColors.grey,
                    fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }
}

class _TimePickerButton extends StatefulWidget {
  final TextEditingController controller;
  final Color color;
  final String hint;
  final VoidCallback onTap;

  const _TimePickerButton({
    required this.controller,
    required this.color,
    required this.hint,
    required this.onTap,
  });

  @override
  State<_TimePickerButton> createState() => _TimePickerButtonState();
}

class _TimePickerButtonState extends State<_TimePickerButton> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.controller.text.isNotEmpty;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasValue ? widget.color : AppColors.greyDark,
            width: hasValue ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Icon(Icons.schedule, color: hasValue ? widget.color : AppColors.grey, size: 20),
          const SizedBox(width: 12),
          Text(
            hasValue ? widget.controller.text : widget.hint,
            style: TextStyle(
              color: hasValue ? AppColors.white : AppColors.grey,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          if (hasValue)
            Icon(Icons.edit_outlined, color: widget.color, size: 16),
        ]),
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final bool enabled;
  final Color color;
  final ValueChanged<bool> onChanged;

  const _ToggleOption({required this.icon, required this.label, required this.subtitle,
      required this.value, required this.enabled, required this.color, required this.onChanged});

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
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: enabled ? AppColors.white : AppColors.greyText, fontSize: 14, fontWeight: FontWeight.w600)),
          Text(subtitle, style: TextStyle(color: enabled ? AppColors.grey : AppColors.greyText, fontSize: 11)),
        ])),
        Switch(value: value && enabled, onChanged: enabled ? onChanged : null,
            activeColor: color, inactiveThumbColor: AppColors.greyDark, inactiveTrackColor: AppColors.surface),
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
            border: Border.all(color: selected ? AppColors.orange : AppColors.greyDark, width: selected ? 2 : 1),
          ),
          child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(color: selected ? AppColors.orange : AppColors.grey,
                fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
        ),
      ),
    );
  }
}

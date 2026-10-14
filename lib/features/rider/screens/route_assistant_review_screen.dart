import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/route_service.dart';

/// Segunda pantalla del asistente: lo que he entendido, antes de generar.
///
/// Lo que decide si esto funciona es la separación en dos bloques: **lo que el
/// motero dijo** y **lo que se ha supuesto por él**. Un resumen de siete líneas
/// iguales se lee en diagonal; separándolas, la vista se va sola a lo que no
/// eligió, que es justo donde puede estar el error.
///
/// Lo que falta no se adivina: se pide arriba y el botón de generar está
/// apagado hasta completarlo. El origen nunca se inventa.
class RouteAssistantReviewScreen extends StatefulWidget {
  /// La frase original. Se guarda con la ruta y viaja a la IA como contexto.
  final String request;

  final Map<String, dynamic> interpretation;

  const RouteAssistantReviewScreen({
    super.key,
    required this.request,
    required this.interpretation,
  });

  @override
  State<RouteAssistantReviewScreen> createState() =>
      _RouteAssistantReviewScreenState();
}

class _RouteAssistantReviewScreenState
    extends State<RouteAssistantReviewScreen> {
  late Map<String, dynamic> _fields =
      Map<String, dynamic>.from(widget.interpretation['fields'] ?? {});
  late List<String> _said =
      List<String>.from(widget.interpretation['said'] ?? []);
  late List<String> _assumed =
      List<String>.from(widget.interpretation['assumed'] ?? []);

  bool _generating = false;

  /// Campos que no se enseñan: o son detalle interno, o se deciden solos.
  static const _hidden = {
    'days', 'suggest_gas_stations', 'moto', 'understood', 'multi_day',
  };

  /// Orden en el que se leen bien, no el que trae el JSON.
  static const _order = [
    'origin', 'destination', 'circular', 'departure_date', 'departure_time',
    'km', 'hours', 'duration_mode', 'zone_hint', 'preference', 'difficulty',
    'avoid_highways', 'suggest_lunch', 'suggest_dinner', 'moto_id',
  ];

  List<String> get _missing =>
      List<String>.from(widget.interpretation['missing'] ?? [])
          .where((k) => _isEmpty(_fields[k]))
          .toList();

  bool _isEmpty(dynamic v) => v == null || v == '' || v == false;

  List<String> _visible(List<String> keys) {
    final shown = keys
        .where((k) => !_hidden.contains(k) && !_isEmpty(_fields[k]))
        .toSet();

    return _order.where(shown.contains).toList();
  }

  /// Al corregir un campo pasa de "supuesto" a "dicho": ya no lo decidió la
  /// app, lo decidió el motero.
  void _set(String key, dynamic value) {
    setState(() {
      _fields[key] = value;
      _assumed.remove(key);
      if (!_said.contains(key)) _said.add(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final said = _visible(_said);
    final assumed = _visible(_assumed);
    final missing = _missing;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          // Volver atrás devuelve a la frase, con lo escrito, para retocarla.
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Text('assistant.review_title'.tr(),
            style: const TextStyle(
                color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          if (missing.isNotEmpty) ...[
            for (final key in missing) _buildMissing(key),
            const SizedBox(height: 14),
          ],

          if (said.isNotEmpty) ...[
            _label('assistant.said'.tr()),
            _group(said),
            const SizedBox(height: 14),
          ],

          if (assumed.isNotEmpty) ...[
            _label('assistant.assumed'.tr(), hint: 'assistant.assumed_hint'.tr()),
            _group(assumed, assumed: true),
            const SizedBox(height: 14),
          ],

          // Lo fino va detrás de esto, no al mismo nivel que los kilómetros.
          TextButton.icon(
            onPressed: _openFullForm,
            icon: const Icon(Icons.tune, color: AppColors.cyan, size: 17),
            label: Text('assistant.more'.tr(),
                style: const TextStyle(color: AppColors.cyan, fontSize: 12)),
          ),

          const SizedBox(height: 6),

          ElevatedButton(
            onPressed: (missing.isEmpty && !_generating) ? _generate : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              disabledBackgroundColor: AppColors.greyDark,
              minimumSize: const Size(double.infinity, 52),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text('assistant.generate'.tr(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
          ),

          if (missing.isNotEmpty) ...[
            const SizedBox(height: 6),
            Center(
              child: Text('assistant.generate_blocked'.tr(),
                  style: const TextStyle(color: AppColors.grey, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Row(children: [
          Text(text,
              style: const TextStyle(
                  color: AppColors.grey,
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600)),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Text(hint,
                style: const TextStyle(color: AppColors.greyDark, fontSize: 10.5)),
          ],
        ]),
      );

  Widget _group(List<String> keys, {bool assumed = false}) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          // La barra lateral marca el bloque de lo supuesto de un vistazo.
          border: assumed
              ? const Border(
                  left: BorderSide(color: AppColors.greyDark, width: 3))
              : null,
        ),
        child: Column(
          children: [
            for (var i = 0; i < keys.length; i++)
              _row(keys[i], assumed: assumed, last: i == keys.length - 1),
          ],
        ),
      );

  Widget _row(String key, {required bool assumed, required bool last}) {
    return InkWell(
      onTap: () => _edit(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(
                  bottom: BorderSide(color: AppColors.greyDark, width: 0.5)),
        ),
        child: Row(children: [
          Icon(_iconFor(key), color: AppColors.grey, size: 17),
          const SizedBox(width: 11),
          Expanded(
            child: Text(_valueFor(key),
                style: TextStyle(
                    color: assumed ? AppColors.grey : AppColors.white,
                    fontSize: 13)),
          ),
          const Icon(Icons.edit_outlined, color: AppColors.greyDark, size: 16),
        ]),
      ),
    );
  }

  Widget _buildMissing(String key) => GestureDetector(
        onTap: () => _edit(key),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            const Icon(Icons.error_outline, color: AppColors.orange, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'assistant.missing'.tr(namedArgs: {
                  'what': 'assistant.f_$key'.tr().toLowerCase(),
                }),
                style: const TextStyle(
                    color: AppColors.orange, fontSize: 12, height: 1.4),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.orange, size: 18),
          ]),
        ),
      );

  // ─── Cómo se lee cada campo ──────────────────────────────────────────

  IconData _iconFor(String key) => switch (key) {
        'origin' => Icons.my_location,
        'destination' => Icons.flag_outlined,
        'circular' => Icons.loop,
        'departure_date' => Icons.calendar_today_outlined,
        'departure_time' => Icons.schedule,
        'km' || 'hours' || 'duration_mode' => Icons.straighten,
        'preference' => Icons.terrain_outlined,
        'difficulty' => Icons.speed_outlined,
        'avoid_highways' => Icons.alt_route,
        'suggest_lunch' || 'suggest_dinner' => Icons.restaurant_outlined,
        'moto_id' => Icons.two_wheeler,
        'zone_hint' => Icons.map_outlined,
        _ => Icons.circle_outlined,
      };

  String _valueFor(String key) {
    final v = _fields[key];

    return switch (key) {
      'circular' => v == true
          ? 'assistant.v_circular'.tr()
          : 'assistant.v_destination'.tr(),
      'avoid_highways' => v == true
          ? 'assistant.v_avoid'.tr()
          : 'assistant.v_highways'.tr(),
      'suggest_lunch' => 'assistant.v_lunch'.tr(),
      'suggest_dinner' => 'assistant.v_dinner'.tr(),
      'km' => '$v km',
      'hours' => '$v h',
      'duration_mode' => '${'assistant.f_hours'.tr()}: $v',
      'preference' => 'planner.${_prefKey(v)}'.tr(),
      'difficulty' => 'planner.${_diffKey(v)}'.tr(),
      'moto_id' => _motoName ?? 'assistant.f_moto_id'.tr(),
      _ => '$v',
    };
  }

  String _prefKey(dynamic v) => switch (v) {
        'curvas' => 'curves',
        'paisaje' => 'landscape',
        _ => 'mixed',
      };

  String _diffKey(dynamic v) => switch (v) {
        'tranquila' => 'easy',
        'exigente' => 'hard',
        _ => 'moderate',
      };

  String? _motoName;

  // ─── Corregir ────────────────────────────────────────────────────────

  /// El origen tiene su propia hoja: no es solo "mi ubicación".
  ///
  /// En una ruta en grupo se queda en un sitio concreto —una gasolinera, el bar
  /// de siempre— y de ahí se sale todos juntos. Por eso se busca con `poi=1`,
  /// que devuelve también negocios y no solo pueblos.
  Future<void> _edit(String key) async {
    switch (key) {
      case 'origin':
      case 'destination':
        await _editPlace(key);
      case 'departure_date':
        await _editDate();
      case 'departure_time':
        await _editTime();
      case 'circular':
        _set('circular', !(_fields['circular'] == true));
      case 'avoid_highways':
        _set('avoid_highways', !(_fields['avoid_highways'] == true));
      case 'suggest_lunch':
        _set('suggest_lunch', !(_fields['suggest_lunch'] == true));
      case 'suggest_dinner':
        _set('suggest_dinner', !(_fields['suggest_dinner'] == true));
      case 'preference':
        await _editChoice(key, const ['curvas', 'paisaje', 'mixto'],
            (v) => 'planner.${_prefKey(v)}'.tr());
      case 'difficulty':
        await _editChoice(key, const ['tranquila', 'moderada', 'exigente'],
            (v) => 'planner.${_diffKey(v)}'.tr());
      default:
        // Lo que no tiene editor propio se corrige en el formulario completo,
        // que ya los tiene todos. Mejor eso que catorce pantallas nuevas.
        await _openFullForm();
    }
  }

  Future<void> _editPlace(String key) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _PlaceSheet(title: 'assistant.f_$key'.tr()),
    );

    if (result != null) _set(key, result['description']);
  }

  Future<void> _editDate() async {
    final current = DateTime.tryParse('${_fields['departure_date']}');
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      _set('departure_date',
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _editTime() async {
    final parts = '${_fields['departure_time'] ?? '09:00'}'.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 9,
        minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
      ),
    );

    if (picked != null) {
      _set('departure_time',
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _editChoice(
      String key, List<String> options, String Function(String) label) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((o) => ListTile(
                    title: Text(label(o),
                        style: const TextStyle(color: AppColors.white)),
                    trailing: _fields[key] == o
                        ? const Icon(Icons.check, color: AppColors.orange)
                        : null,
                    onTap: () => Navigator.pop(ctx, o),
                  ))
              .toList(),
        ),
      ),
    );

    if (picked != null) _set(key, picked);
  }

  /// El formulario de siempre, relleno con lo entendido.
  Future<void> _openFullForm() async {
    if (!mounted) return;
    context.pushReplacement('/rider/route-generator', extra: {
      ..._fields,
      'ai_request': widget.request,
    });
  }

  // ─── Generar ─────────────────────────────────────────────────────────

  Future<void> _generate() async {
    setState(() => _generating = true);

    final payload = Map<String, dynamic>.from(_fields)
      ..removeWhere((k, v) => v == null || _hidden.contains(k) && k != 'days')
      // La frase viaja con la petición: se guarda con la ruta y le da a la IA
      // el contexto que no cabe en ningún campo ("por el Pirineo").
      ..['ai_request'] = widget.request;

    final result = await RouteService.generateRoute(payload);
    if (!mounted) return;

    setState(() => _generating = false);

    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['error']),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    context.pushReplacement('/rider/route-result', extra: result['result']);
  }
}

/// Hoja para elegir un lugar: mi ubicación, o buscar uno concreto.
class _PlaceSheet extends StatefulWidget {
  final String title;

  const _PlaceSheet({required this.title});

  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  final _controller = TextEditingController();

  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 3) return;
    setState(() => _loading = true);

    try {
      // poi=1 para que devuelva también gasolineras y bares: en una ruta en
      // grupo se queda en un sitio concreto, no en "Jaca".
      final response = await ApiClient.dio.get('/location/search',
          queryParameters: {'q': query, 'lang': 'es', 'poi': '1'});

      if (!mounted) return;
      setState(() {
        _loading = false;
        _results = List<Map<String, dynamic>>.from(
            (response.data as List? ?? []).map((p) => {
                  'description': p['description'],
                  'lat': p['lat'],
                  'lng': p['lng'],
                }));
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useMyLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      final response = await ApiClient.dio.get('/location/search',
          queryParameters: {
            'q': '${position.latitude},${position.longitude}',
            'reverse': '1',
            'lang': 'es',
          });

      final data = response.data as List? ?? [];
      if (!mounted || data.isEmpty) return;

      Navigator.pop(context, {'description': data.first['description']});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),

            ListTile(
              leading: const Icon(Icons.my_location, color: AppColors.cyan),
              title: Text('planner.use_my_location'.tr(),
                  style: const TextStyle(color: AppColors.cyan, fontSize: 14)),
              onTap: _useMyLocation,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onSubmitted: _search,
                onChanged: (q) {
                  if (q.trim().length >= 3) _search(q);
                },
                style: const TextStyle(color: AppColors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'planner.search_place'.tr(),
                  hintStyle:
                      const TextStyle(color: AppColors.grey, fontSize: 13),
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.grey, size: 19),
                  filled: true,
                  fillColor: AppColors.background,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: AppColors.orange),
              ),

            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                children: _results
                    .map((r) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined,
                              color: AppColors.grey, size: 18),
                          title: Text('${r['description']}',
                              style: const TextStyle(
                                  color: AppColors.white, fontSize: 13)),
                          onTap: () => Navigator.pop(context, r),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

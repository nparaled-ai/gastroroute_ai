import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/catalog_service.dart';
import '../../../widgets/highways_maps_notice.dart';
import 'map_point_picker_screen.dart';

/// "Hacer esta ruta": el motero no sale del inicio de la ruta sino de donde está.
///
/// Aquí dice desde dónde sale (por defecto, su ubicación), dónde acaba el día, cuándo
/// sale y si quiere autovía para llegar. El servidor devuelve el viaje por tramos
/// (acercamiento + ruta + regreso) con los avisos que importan: lejos, puerto cerrado
/// en esa fecha, día demasiado largo. Después se guarda como cualquier ruta.
class CatalogPlanScreen extends StatefulWidget {
  final int id;
  final Map<String, dynamic> route;
  const CatalogPlanScreen({super.key, required this.id, required this.route});

  @override
  State<CatalogPlanScreen> createState() => _CatalogPlanScreenState();
}

class _CatalogPlanScreenState extends State<CatalogPlanScreen> {
  // Salida
  double? _lat, _lng;
  String _originName = '';
  bool _locating = true;

  // Final
  String _finish = 'home'; // home | end | place
  double? _finishLat, _finishLng;
  String _finishName = '';

  String _entry = 'nearest';
  bool _useHighways = false;
  DateTime? _date;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);

  // Paradas para comer: se PREGUNTA al motero si las quiere (por defecto, no) y, si las
  // quiere, a qué hora. Sin hora elegida, el servidor usa la habitual del país.
  bool _wantLunch = false;
  bool _wantDinner = false;
  String _lunchKind = 'almuerzo'; // cafe | almuerzo
  TimeOfDay? _lunchTime;
  TimeOfDay? _dinnerTime;

  bool _calculating = false;

  // Para llevar al motero al resultado cuando termina de calcular (se quedaba arriba).
  final _scroll = ScrollController();
  final _resultKey = GlobalKey();

  /// Se pone a true al intentar calcular con algo sin rellenar: marca en rojo lo que falta.
  bool _showMissing = false;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        throw Exception('denied');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _originName = 'catalog.my_location'.tr();
        _locating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _locating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('catalog.location_denied'.tr())));
    }
  }

  Future<Map<String, dynamic>?> _pick(String title, double? lat, double? lng) {
    return Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPointPickerScreen(
          title: title,
          initial: lat != null && lng != null ? LatLng(lat, lng) : null,
        ),
      ),
    );
  }

  Future<void> _pickOrigin() async {
    final r = await _pick('catalog.plan_from'.tr(), _lat, _lng);
    if (r == null || !mounted) return;
    setState(() {
      _lat = (r['lat'] as num).toDouble();
      _lng = (r['lng'] as num).toDouble();
      _originName = '${r['description']}';
      _result = null;
    });
  }

  Future<void> _pickFinish() async {
    final r = await _pick('catalog.finish_place_pick'.tr(), _finishLat ?? _lat, _finishLng ?? _lng);
    if (r == null || !mounted) return;
    setState(() {
      _finish = 'place';
      _finishLat = (r['lat'] as num).toDouble();
      _finishLng = (r['lng'] as num).toDouble();
      _finishName = '${r['description']}';
      _result = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null && mounted) setState(() { _date = d; _result = null; });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null && mounted) setState(() { _time = t; _result = null; });
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _time2(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}min' : '${m}min';
  }

  /// Todos los datos son obligatorios antes de calcular y guardar: salida, fecha y hora, y
  /// el sitio donde acaba si no vuelve a casa ni acaba donde acaba la ruta.
  bool _validate() {
    String? falta;
    if (_lat == null || _lng == null) {
      falta = 'catalog.location_denied'.tr();
    } else if (_date == null) {
      falta = 'catalog.date_required'.tr();
    } else if (_finish == 'place' && _finishLat == null) {
      falta = 'catalog.finish_required'.tr();
    }
    if (falta == null) return true;

    setState(() => _showMissing = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(falta)));
    return false;
  }

  Future<void> _calculate() async {
    if (_lat == null || _lng == null) await _locate();
    if (!_validate()) return;

    setState(() {
      _calculating = true;
      _result = null;
    });

    final r = await CatalogService.prepare(widget.id, {
      'origin_lat': _lat,
      'origin_lng': _lng,
      'origin_name': _originName,
      'use_highways': _useHighways,
      'entry': _entry,
      'finish': _finish,
      if (_finish == 'place') ...{
        'finish_lat': _finishLat,
        'finish_lng': _finishLng,
        'finish_name': _finishName,
      },
      if (_date != null) 'departure_date': DateFormat('yyyy-MM-dd').format(_date!),
      'departure_time': _hhmm(_time),
      if (_wantLunch) ...{
        'suggest_lunch': true,
        'lunch_kind': _lunchKind,
        if (_lunchTime != null) 'lunch_time': _hhmm(_lunchTime!),
      },
      if (_wantDinner) ...{
        'suggest_dinner': true,
        if (_dinnerTime != null) 'dinner_time': _hhmm(_dinnerTime!),
      },
    });
    if (!mounted) return;

    setState(() => _calculating = false);

    if (r['error'] != null) {
      final msg = '${r['error']}'.isEmpty ? 'catalog.plan_error'.tr() : '${r['error']}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    setState(() => _result = r);

    // Al calcular, el resultado sale debajo del botón: se baja hasta él.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _resultKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 450), curve: Curves.easeOut, alignment: 0.0);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
        title: Text('catalog.plan_title'.tr(),
            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        controller: _scroll,
        // Que el resultado esté ya construido aunque quede lejos de la pantalla: hace falta
        // para poder bajar hasta él.
        cacheExtent: 4000,
        padding: EdgeInsets.fromLTRB(18, 16, 18, 32 + MediaQuery.of(context).padding.bottom),
        children: [
          Text('${widget.route['name']}',
              style: const TextStyle(
                  color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),

          _Section('catalog.plan_from'.tr()),
          _Tile(
            icon: _locating ? Icons.hourglass_top : Icons.my_location,
            text: _locating
                ? 'catalog.locating'.tr()
                : (_originName.isEmpty ? 'catalog.my_location'.tr() : _originName),
            trailing: TextButton(
              onPressed: _pickOrigin,
              child: Text('catalog.pick_on_map'.tr()),
            ),
          ),

          _Section('catalog.plan_finish'.tr()),
          _Radio(
              value: 'home',
              group: _finish,
              label: 'catalog.finish_home'.tr(),
              onChanged: (v) => setState(() { _finish = v; _result = null; })),
          _Radio(
              value: 'end',
              group: _finish,
              label: 'catalog.finish_end'.tr(),
              onChanged: (v) => setState(() { _finish = v; _result = null; })),
          _Radio(
              value: 'place',
              group: _finish,
              label: _finish == 'place' && _finishName.isNotEmpty
                  ? _finishName
                  : 'catalog.finish_place'.tr(),
              onChanged: (_) => _pickFinish()),

          _Section('catalog.plan_entry'.tr()),
          for (final e in const ['nearest', 'start', 'end'])
            _Radio(
                value: e,
                group: _entry,
                label: 'catalog.entry_$e'.tr(),
                onChanged: (v) => setState(() { _entry = v; _result = null; })),

          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('catalog.use_highways'.tr(),
                style: const TextStyle(color: AppColors.white, fontSize: 14)),
            subtitle: Text('catalog.use_highways_hint'.tr(),
                style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
            value: _useHighways,
            onChanged: (v) => setState(() { _useHighways = v; _result = null; }),
          ),
          if (_useHighways) const HighwaysMapsNotice(),

          _Section('catalog.plan_when'.tr()),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: Icon(Icons.calendar_today_outlined,
                    size: 18,
                    color: _showMissing && _date == null ? AppColors.error : null),
                label: Text(
                  _date == null
                      ? '${'catalog.pick_date'.tr()} *'
                      : DateFormat.yMMMd(context.locale.toString()).format(_date!),
                  style: TextStyle(
                      color: _showMissing && _date == null ? AppColors.error : null),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: _showMissing && _date == null
                          ? AppColors.error
                          : AppColors.greyDark),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(_hhmm(_time)),
            ),
          ]),

          _Section('catalog.meals_ask'.tr()),
          _mealOption(
            label: 'catalog.want_lunch'.tr(),
            on: _wantLunch,
            time: _lunchTime,
            onToggle: (v) => setState(() { _wantLunch = v; _result = null; }),
            onTime: (t) => setState(() { _lunchTime = t; _result = null; }),
            initial: const TimeOfDay(hour: 11, minute: 0),
          ),
          if (_wantLunch)
            Wrap(spacing: 8, children: [
              for (final k in const ['almuerzo', 'cafe'])
                ChoiceChip(
                  label: Text('assistant.lunch_kind_$k'.tr()),
                  selected: _lunchKind == k,
                  onSelected: (_) => setState(() { _lunchKind = k; _result = null; }),
                ),
            ]),
          _mealOption(
            label: 'catalog.want_dinner'.tr(),
            on: _wantDinner,
            time: _dinnerTime,
            onToggle: (v) => setState(() { _wantDinner = v; _result = null; }),
            onTime: (t) => setState(() { _dinnerTime = t; _result = null; }),
            initial: const TimeOfDay(hour: 14, minute: 0),
          ),

          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _calculating || _locating ? null : _calculate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _calculating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('catalog.calculate'.tr(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),

          if (_result != null) ..._resultWidgets(_result!),
        ],
      ),
    );
  }

  List<Widget> _resultWidgets(Map<String, dynamic> r) {
    final trip = Map<String, dynamic>.from(r['trip'] as Map);
    final parts = List<Map<String, dynamic>>.from(
        (trip['parts'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final route = Map<String, dynamic>.from(r['route'] as Map);
    final warnings = List<Map<String, dynamic>>.from(
        (r['warnings'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final summary = Map<String, dynamic>.from(r['ai_summary'] as Map? ?? {});
    final fuel = List<dynamic>.from(summary['fuel_stops'] as List? ?? const []);
    final lunch = route['lunch_stop'] as Map?;
    final dinner = route['dinner_stop'] as Map?;
    final weather = r['weather'] as Map?;

    return [
      SizedBox(key: _resultKey, height: 22),
      for (final w in warnings) _warning(w),
      Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(14),
        decoration:
            BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final p in parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Icon(
                  p['type'] == 'route' ? Icons.two_wheeler : Icons.arrow_forward,
                  size: 18,
                  color: p['type'] == 'route' ? AppColors.orange : AppColors.greyText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('catalog.part_${p['type']}'.tr(),
                      style: TextStyle(
                          color: AppColors.white,
                          fontWeight:
                              p['type'] == 'route' ? FontWeight.w800 : FontWeight.w500)),
                ),
                Text(
                    'catalog.part_line'.tr(namedArgs: {
                      'km': '${p['km']}',
                      'time': _time2((p['minutes'] as num).toInt()),
                    }),
                    style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
              ]),
            ),
          const Divider(color: AppColors.greyDark),
          Text(
              'catalog.total'.tr(namedArgs: {
                'km': '${route['distance_km']}',
                'time': _time2((route['duration_minutes'] as num).toInt()),
              }),
              style: const TextStyle(
                  color: AppColors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          if (weather != null) ...[
            const SizedBox(height: 8),
            Text(
                '${weather['temp'] ?? ''}° · ${weather['description'] ?? ''}',
                style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
            if (r['weather_alert'] != null)
              Text('${r['weather_alert']}',
                  style: const TextStyle(color: AppColors.orange, fontSize: 13)),
          ],
        ]),
      ),
      if (lunch != null || dinner != null || summary['lunch_skipped'] != null || summary['dinner_skipped'] != null) ...[
        _Section('catalog.meals'.tr()),
        if (lunch != null) _mealTile('catalog.meal_lunch'.tr(), lunch),
        if (dinner != null) _mealTile('catalog.meal_dinner'.tr(), dinner),
        if (lunch == null && dinner == null)
          Text('catalog.meal_none'.tr(),
              style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
      ],
      if (fuel.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final km in fuel)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              const Icon(Icons.local_gas_station_outlined,
                  size: 16, color: AppColors.greyText),
              const SizedBox(width: 8),
              Text('catalog.fuel'.tr(namedArgs: {'km': '$km'}),
                  style: const TextStyle(color: AppColors.white, fontSize: 13)),
            ]),
          ),
      ],
      const SizedBox(height: 18),
      ElevatedButton(
        onPressed: () => context.push('/rider/route-result', extra: r),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text('catalog.continue'.tr(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
    ];
  }

  /// Un interruptor de parada para comer; si está activo, deja elegir la hora.
  Widget _mealOption({
    required String label,
    required bool on,
    required TimeOfDay? time,
    required ValueChanged<bool> onToggle,
    required ValueChanged<TimeOfDay> onTime,
    required TimeOfDay initial,
  }) {
    return Column(children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(color: AppColors.white, fontSize: 14)),
        value: on,
        onChanged: onToggle,
      ),
      if (on)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: time ?? initial);
              if (t != null) onTime(t);
            },
            icon: const Icon(Icons.schedule, size: 18),
            label: Text(time == null
                ? 'catalog.meal_default_time'.tr()
                : 'catalog.meal_at'.tr(namedArgs: {'time': _hhmm(time)})),
          ),
        ),
    ]);
  }

  Widget _mealTile(String label, Map meal) {
    final eatery = meal['eatery'] as Map?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.restaurant_outlined, size: 17, color: AppColors.gold),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label · ${meal['estimated_time'] ?? ''} · ${meal['location'] ?? ''}'
            '${eatery != null ? ' — ${eatery['name']}' : ''}',
            style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.35),
          ),
        ),
      ]),
    );
  }

  Widget _warning(Map<String, dynamic> w) {
    String text;
    Color color = AppColors.orange;
    Widget? action;

    switch (w['type']) {
      case 'far':
        text = 'catalog.warn_far'.tr(namedArgs: {
          'km': '${w['km']}',
          'time': _time2((w['minutes'] as num).toInt()),
        });
        break;
      case 'closed_on_date':
        text = 'catalog.warn_closed_on_date'.tr(namedArgs: {
          'km': '${w['km']}',
          'route_km': '${w['route_km']}',
        });
        color = AppColors.error;
        break;
      case 'same_road':
        text = 'catalog.warn_same_road'.tr(namedArgs: {'pct': '${w['overlap']}'});
        color = AppColors.gold;
        break;
      case 'season':
        final closed = w['state'] == 'closed';
        text = (closed ? 'catalog.warn_season_closed' : 'catalog.warn_season_maybe').tr();
        color = closed ? AppColors.error : AppColors.gold;
        break;
      case 'long_day':
        text = 'catalog.warn_long_day'.tr(namedArgs: {
          'time': _time2((w['minutes'] as num).toInt()),
        });
        if (_finish != 'end') {
          action = TextButton(
            onPressed: () {
              setState(() => _finish = 'end');
              _calculate();
            },
            child: Text('catalog.use_end_finish'.tr()),
          );
        }
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.45)),
          ),
        ]),
        if (action != null) Align(alignment: Alignment.centerLeft, child: action),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.white, fontWeight: FontWeight.w800, fontSize: 15)),
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? trailing;
  const _Tile({required this.icon, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration:
            BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, color: AppColors.cyan, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: AppColors.white, fontSize: 14))),
          if (trailing != null) trailing!,
        ]),
      );
}

class _Radio extends StatelessWidget {
  final String value;
  final String group;
  final String label;
  final ValueChanged<String> onChanged;
  const _Radio({
    required this.value,
    required this.group,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == group;

    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.orange : AppColors.greyText, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: AppColors.white, fontSize: 14))),
        ]),
      ),
    );
  }
}

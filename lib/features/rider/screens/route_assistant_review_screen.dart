import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/rider_profile_service.dart';
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

  /// Todo lo que se enseña, en el orden en que se lee bien.
  ///
  /// La lista es FIJA: nada aparece ni desaparece al tocar algo. Antes se
  /// ocultaban los campos vacíos y eso descolocaba la pantalla a cada cambio —
  /// y en el peor caso te dejaba sin la fila que acababas de tocar.
  static const _order = [
    'origin', 'destination', 'circular', 'departure_date', 'departure_time',
    'duration', 'preference', 'difficulty', 'avoid_highways',
    'suggest_lunch', 'suggest_dinner', 'moto_id', 'zone_hint',
  ];

  /// Las motos del motero, para poder cambiarla sin salir de aquí.
  List<Map<String, dynamic>> _motos = [];

  /// Lo que falta, recalculado en cada pintada.
  ///
  /// Antes se tomaba tal cual la lista que mandó el servidor al interpretar la
  /// frase, y eso se rompía en cuanto el motero tocaba algo: al cambiar a "con
  /// destino", el destino no se pedía —no estaba en aquella lista— y se podía
  /// generar una ruta con destino sin destino, con el botón activado y sin que
  /// la fila apareciera siquiera, porque estaba vacía.
  List<String> get _missing {
    final required = <String>[
      'origin',
      'moto_id',
      if (_fields['circular'] != true) 'destination',
    ];

    return required.where((k) => _isEmpty(_fields[k])).toList();
  }

  /// Campos donde `false` SIGNIFICA algo y hay que enseñarlo igual.
  ///
  /// `circular: false` es "con destino" y `avoid_highways: false` es "autovías
  /// permitidas": dos cosas que el motero ha elegido, no huecos. En cambio
  /// `suggest_lunch: false` es que no para a comer, y de eso no hay nada que
  /// decir.
  ///
  /// Tratarlos a todos igual hacía que la fila de circular DESAPARECIERA al
  /// cambiarla a "con destino", dejándote sin forma de volver atrás.
  static const _falseIsMeaningful = {'circular', 'avoid_highways'};

  bool _isEmptyFor(String key, dynamic v) =>
      v == null || v == '' || (v == false && !_falseIsMeaningful.contains(key));

  bool _isEmpty(dynamic v) => v == null || v == '';

  @override
  void initState() {
    super.initState();
    _loadMotos();
  }

  Future<void> _loadMotos() async {
    final result = await RiderProfileService.getMotos();
    if (!mounted || result['motos'] == null) return;
    setState(() => _motos = List<Map<String, dynamic>>.from(result['motos']));
  }

  /// Si la fila tiene sentido en esta ruta.
  ///
  /// Lo único que se esconde es lo que no aplica: el destino en una circular, y
  /// la zona solo si la mencionó. Todo lo demás está siempre, con valor o sin
  /// él.
  bool _applies(String key) => switch (key) {
        'destination' => _fields['circular'] != true,
        'zone_hint' => !_isEmpty(_fields['zone_hint']),
        _ => !_hidden.contains(key),
      };

  /// Las filas que van en cada bloque.
  ///
  /// Lo que falta va arriba del todo; el resto se reparte entre lo que dijo el
  /// motero y lo que se supuso por él.
  List<String> _rowsOf(String block) {
    return _order.where((k) {
      if (!_applies(k)) return false;

      final missing = _missing.contains(k);
      if (block == 'missing') return missing;
      if (missing) return false;

      final said = _said.contains(k) || (k == 'duration' && _durationSaid);
      return block == 'said' ? said : !said;
    }).toList();
  }

  /// La duración es una fila que resume tres campos (modo, km y horas), así
  /// que su origen se mira en los tres.
  bool get _durationSaid =>
      _said.contains('km') ||
      _said.contains('hours') ||
      _said.contains('duration_mode');

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
    final said = _rowsOf('said');
    final assumed = _rowsOf('assumed');
    final missing = _rowsOf('missing');

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
            const SizedBox(height: 6),
            _group(missing, missing: true),
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

  Widget _group(List<String> keys,
          {bool assumed = false, bool missing = false}) =>
      Container(
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
              _row(keys[i],
                  assumed: assumed,
                  missing: missing,
                  last: i == keys.length - 1),
          ],
        ),
      );

  Widget _row(String key,
      {required bool assumed, required bool last, bool missing = false}) {
    return InkWell(
      onTap: () => _edit(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // La etiqueta siempre visible: sin ella, "Circular" o "09:00"
                // sueltos no dicen de qué campo son.
                Text(_labelFor(key),
                    style: const TextStyle(
                        color: AppColors.grey, fontSize: 10.5)),
                const SizedBox(height: 2),
                Text(_valueFor(key),
                    style: TextStyle(
                        color: missing
                            ? AppColors.grey
                            : (assumed ? AppColors.grey : AppColors.white),
                        fontSize: 13,
                        fontStyle:
                            missing ? FontStyle.italic : FontStyle.normal)),
              ],
            ),
          ),
          // Verde si está resuelto, rojo si falta. De un vistazo se ve qué
          // queda por tocar sin leer una línea.
          Icon(
            missing ? Icons.cancel_outlined : Icons.check_circle_outline,
            color: missing ? AppColors.error : Colors.green,
            size: 18,
          ),
        ]),
      ),
    );
  }

  String _labelFor(String key) => switch (key) {
        'duration' => 'assistant.f_km'.tr(),
        _ => 'assistant.f_$key'.tr(),
      };

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
              // Una pregunta concreta por cada dato, no un genérico "falta un
              // dato: salida" — que se leía como la HORA de salida: el motero
              // ponía la hora, el aviso seguía ahí, y no había forma de
              // entender por qué.
              child: Text(
                _missingText(key),
                style: const TextStyle(
                    color: AppColors.orange, fontSize: 12, height: 1.4),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.orange, size: 18),
          ]),
        ),
      );

  /// El texto del aviso, con respaldo por si algún día falta un campo nuevo.
  String _missingText(String key) {
    final specific = 'assistant.missing_$key';
    final text = specific.tr();

    return text == specific
        ? 'assistant.missing'.tr(
            namedArgs: {'what': 'assistant.f_$key'.tr().toLowerCase()})
        : text;
  }

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

    if (key != 'duration' && _isEmptyFor(key, v) && _missing.contains(key)) {
      return 'assistant.undefined'.tr();
    }

    return switch (key) {
      'circular' => v == true
          ? 'assistant.v_circular'.tr()
          : 'assistant.v_destination'.tr(),
      'avoid_highways' => v == true
          ? 'assistant.v_avoid'.tr()
          : 'assistant.v_highways'.tr(),
      // Un "no" también se enseña: que NO pares a comer es una decisión, y si
      // la fila desapareciera no habría forma de activarla.
      'suggest_lunch' =>
        v == true ? 'assistant.v_lunch'.tr() : 'assistant.v_no_lunch'.tr(),
      'suggest_dinner' =>
        v == true ? 'assistant.v_dinner'.tr() : 'assistant.v_no_dinner'.tr(),
      'duration' => _durationText,
      'preference' => 'planner.${_prefKey(v)}'.tr(),
      'difficulty' => 'planner.${_diffKey(v)}'.tr(),
      'moto_id' => _motoName,
      _ => '$v',
    };
  }

  /// Una sola fila para los tres campos que dicen lo mismo.
  ///
  /// El motero piensa "cuánto quiero rodar", no "modo de duración más valor".
  String get _durationText {
    final mode = _fields['duration_mode'];

    if (mode == 'km' && _fields['km'] != null) return '${_fields['km']} km';
    if (mode == 'hours' && _fields['hours'] != null) {
      return '${_fields['hours']} h';
    }

    return 'assistant.v_duration_ai'.tr();
  }

  String get _motoName {
    final moto = _motos.firstWhere(
      (m) => m['id'] == _fields['moto_id'],
      orElse: () => const {},
    );

    if (moto.isEmpty) return 'assistant.undefined'.tr();
    return '${moto['brand'] ?? ''} ${moto['model'] ?? ''}'.trim();
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
        // Una hoja con las dos opciones a la vista, no un interruptor a
        // ciegas: tocar una fila y que cambie sola no deja ver entre qué
        // estás eligiendo, aunque solo haya dos cosas.
        final picked = await _editBool('circular',
            'assistant.v_circular'.tr(), 'assistant.v_destination'.tr());
        if (picked == null) return;

        final circular = picked;

        if (circular) {
          // Una circular no tiene destino: dejarlo puesto lo enseñaria en la
          // lista y se mandaria al servidor, que lo ignora. Confunde para nada.
          setState(() {
            _fields.remove('destination');
            _said.remove('destination');
            _assumed.remove('destination');
          });
        } else if (_isEmpty(_fields['destination'])) {
          // Acaba de decir que va a algun sitio: lo logico es preguntarle
          // adonde ahora, no dejarselo como un aviso mas que resolver luego.
          await _editPlace('destination');
        }
      case 'avoid_highways':
        await _editBool(key, 'assistant.v_avoid'.tr(),
            'assistant.v_highways'.tr(), apply: true);
      case 'suggest_lunch':
        await _editBool(key, 'assistant.v_lunch'.tr(),
            'assistant.v_no_lunch'.tr(), apply: true);
      case 'suggest_dinner':
        await _editBool(key, 'assistant.v_dinner'.tr(),
            'assistant.v_no_dinner'.tr(), apply: true);
      case 'preference':
        await _editChoice(key, const ['curvas', 'paisaje', 'mixto'],
            (v) => 'planner.${_prefKey(v)}'.tr());
      case 'difficulty':
        await _editChoice(key, const ['tranquila', 'moderada', 'exigente'],
            (v) => 'planner.${_diffKey(v)}'.tr());
      case 'duration':
        await _editDuration();
      case 'moto_id':
        await _editMoto();
      case 'zone_hint':
        await _editText(key);
    }
  }

  /// Límites que acepta el generador. Los mismos que valida el servidor: si
  /// aquí dejáramos pasar 4.000 km, el error llegaría al final y sin explicar.
  static const _minKm = 50;
  static const _maxKm = 800;
  static const _minHours = 1;
  static const _maxHours = 24;

  String _rangeHint(String mode) => mode == 'km'
      ? 'assistant.range_km'.tr(
          namedArgs: {'min': '$_minKm', 'max': '$_maxKm'})
      : 'assistant.range_hours'.tr(
          namedArgs: {'min': '$_minHours', 'max': '$_maxHours'});

  String? _rangeError(String mode, String text) {
    if (mode == 'ai') return null;

    final value = int.tryParse(text.trim());
    if (value == null) return 'assistant.range_needed'.tr();

    final min = mode == 'km' ? _minKm : _minHours;
    final max = mode == 'km' ? _maxKm : _maxHours;

    return (value < min || value > max) ? _rangeHint(mode) : null;
  }

  /// Elegir entre dos opciones, con las dos a la vista.
  ///
  /// Nada de interruptores silenciosos: tocar una fila y que cambie sola no
  /// deja ver entre qué estás eligiendo. Devuelve null si se cierra sin elegir.
  Future<bool?> _editBool(
    String key,
    String labelTrue,
    String labelFalse, {
    bool apply = false,
  }) async {
    final picked = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_labelFor(key),
                  style: const TextStyle(
                      color: AppColors.grey,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          for (final option in [true, false])
            ListTile(
              title: Text(option ? labelTrue : labelFalse,
                  style: const TextStyle(color: AppColors.white, fontSize: 14)),
              trailing: (_fields[key] == true) == option
                  ? const Icon(Icons.check, color: AppColors.orange)
                  : null,
              onTap: () => Navigator.pop(ctx, option),
            ),
        ]),
      ),
    );

    if (picked != null && apply) _set(key, picked);
    return picked;
  }

  /// Cuánto quiere rodar: por kilómetros, por horas, o que lo decida la IA.
  Future<void> _editDuration() async {
    final controller = TextEditingController(
      text: '${_fields['duration_mode'] == 'km' ? _fields['km'] ?? '' : _fields['hours'] ?? ''}',
    );
    var mode = '${_fields['duration_mode'] ?? 'ai'}';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  for (final m in const ['km', 'hours', 'ai'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setSheet(() => mode = m),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: mode == m
                                  ? AppColors.orange
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                  color: mode == m
                                      ? AppColors.orange
                                      : AppColors.greyDark),
                            ),
                            child: Text('assistant.d_$m'.tr(),
                                style: TextStyle(
                                    color: mode == m
                                        ? AppColors.background
                                        : AppColors.grey,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              if (mode != 'ai')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    onChanged: (_) => setSheet(() {}),
                    style: const TextStyle(
                        color: AppColors.white, fontSize: 15),
                    decoration: InputDecoration(
                      suffixText: mode == 'km' ? 'km' : 'h',
                      suffixStyle: const TextStyle(color: AppColors.grey),
                      // Los límites a la vista desde el principio: enterarse
                      // de que 4.000 km no vale al darle a generar, con un
                      // error del servidor, es la peor forma de saberlo.
                      helperText: _rangeHint(mode),
                      helperStyle:
                          const TextStyle(color: AppColors.grey, fontSize: 11),
                      errorText: _rangeError(mode, controller.text),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ElevatedButton(
                  onPressed: _rangeError(mode, controller.text) != null
                      ? null
                      : () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    minimumSize: const Size(double.infinity, 46),
                  ),
                  child: Text('common.save'.tr(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );

    if (saved != true) return;

    final value = int.tryParse(controller.text.trim());

    setState(() {
      _fields['duration_mode'] = mode;
      _fields['km'] = mode == 'km' ? value : null;
      _fields['hours'] = mode == 'hours' ? value : null;
    });

    // La fila de duración resume tres campos: basta con marcar uno.
    _set('duration_mode', mode);
  }

  Future<void> _editMoto() async {
    if (_motos.isEmpty) return;

    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _motos
              .map((m) => ListTile(
                    leading: const Icon(Icons.two_wheeler,
                        color: AppColors.grey, size: 20),
                    title: Text('${m['brand']} ${m['model']}',
                        style: const TextStyle(color: AppColors.white)),
                    trailing: _fields['moto_id'] == m['id']
                        ? const Icon(Icons.check, color: AppColors.orange)
                        : null,
                    onTap: () => Navigator.pop(ctx, m['id'] as int),
                  ))
              .toList(),
        ),
      ),
    );

    if (picked != null) _set('moto_id', picked);
  }

  Future<void> _editText(String key) async {
    final controller = TextEditingController(text: '${_fields[key] ?? ''}');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: AppColors.white, fontSize: 15),
                decoration: InputDecoration(
                  labelText: _labelFor(key),
                  labelStyle: const TextStyle(color: AppColors.grey),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  minimumSize: const Size(double.infinity, 46),
                ),
                child: Text('common.save'.tr(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );

    if (saved == true) _set(key, controller.text.trim());
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

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../core/theme/app_theme.dart';
import '../providers/rider_profile_service.dart';
import '../../../widgets/place_sheet.dart';
import 'route_assistant_refine_screen.dart';

/// Cómo está cada fila del resumen.
///
/// [said] lo dijo el motero, [assumed] lo puso la app por él, [missing] no lo
/// tiene nadie y sin ello no hay ruta.
enum _Mark { said, assumed, missing }

/// Segunda pantalla del asistente: la ruta, antes de afinarla.
///
/// Una sola lista en orden fijo con lo que define la ruta. Lo que la afina
/// —puntos de interés, paradas, autovías— va en la pantalla siguiente.
///
/// Lo que decide si esto funciona es la marca de cada fila: verde lo que dijo
/// el motero, ámbar lo que puso la app por él, rojo lo que falta. Antes eso se
/// resolvía repartiendo las filas en tres bloques, y el efecto era el
/// contrario: la misma fila saltaba de sitio según lo que hubieras escrito en
/// la frase, y el aviso de lo que faltaba vivía arriba, lejos de la fila que lo
/// causaba.
///
/// Lo que falta no se adivina ni se rellena solo: se pinta en rojo en su propia
/// fila y el botón no deja pasar. El origen nunca se inventa.
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
  late final Map<String, dynamic> _fields =
      Map<String, dynamic>.from(widget.interpretation['fields'] ?? {});
  late final List<String> _said =
      List<String>.from(widget.interpretation['said'] ?? []);
  late final List<String> _assumed =
      List<String>.from(widget.interpretation['assumed'] ?? []);


  /// Campos que no se enseñan aquí: o son detalle interno, o se deciden solos,
  /// o van en la pantalla siguiente (paradas, puntos de interés, autovías).
  static const _hidden = {
    'days', 'suggest_gas_stations', 'moto', 'understood', 'multi_day',
  };

  /// Lo que define la ruta, en el orden en que se lee bien.
  ///
  /// De dónde sales → qué forma tiene → cuándo → cuánto → cómo → con qué. Lo
  /// que la afina (puntos de interés, paradas, autovías) va en la pantalla
  /// siguiente: esto es lo que no puede faltar.
  ///
  /// La lista es FIJA y el orden no depende de lo que dijera la frase. Antes
  /// las filas se repartían en tres bloques según de dónde saliera el dato, así
  /// que la misma fila cambiaba de sitio según lo que escribieras — y una
  /// pantalla cuyo orden se mueve no se lee, se descifra.
  static const _order = [
    'origin', 'circular', 'destination', 'departure_date', 'departure_time',
    'duration', 'difficulty', 'preference', 'moto_id',
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
  ///
  /// La HORA estaba fuera de esta lista y ese olvido se veía en la pantalla:
  /// salía una fila "Hora: null" con el visto bueno verde. Que la marca salga
  /// de aquí y no de una lista aparte es lo que evita que vuelva a pasar.
  List<String> get _missing {
    final required = <String>[
      'origin',
      'departure_date',
      'departure_time',
      'moto_id',
      if (_fields['circular'] != true) 'destination',
    ];

    return required.where((k) => _isEmpty(_fields[k])).toList();
  }

  /// En qué estado está una fila. Son tres, no dos.
  ///
  /// Con solo "bien / falta", todo lo que la app decidió por su cuenta salía
  /// con el visto verde, como si lo hubiera elegido el motero. El ámbar dice
  /// "esto lo he puesto yo, míralo": es la diferencia entre un resumen que se
  /// revisa y uno que se pasa de largo.
  _Mark _markOf(String key) {
    if (_missing.contains(key)) return _Mark.missing;

    // Con una sola moto no hay nada que revisar: es la única que puede ser.
    // Pedirle al motero que compruebe un dato que no puede cambiar es ruido, y
    // el ámbar deja de significar algo si se reparte a campos sin alternativa.
    // Con varias, la propuesta va en ámbar aunque acierte: ahí sí hay elección.
    if (key == 'moto_id' && _motos.length == 1) return _Mark.said;

    final said = key == 'duration' ? _durationSaid : _said.contains(key);
    return said ? _Mark.said : _Mark.assumed;
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

  /// Las filas que se pintan, en el orden fijo de [_order].
  List<String> get _rows => _order.where(_applies).toList();

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
    final rows = _rows;
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('assistant.step_route'.tr(),
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            Text('assistant.step_of'.tr(namedArgs: {'n': '1'}),
                style: const TextStyle(color: AppColors.grey, fontSize: 10.5)),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          // Una sola tarjeta: el orden es el mismo pase lo que pase.
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  _row(rows[i], last: i == rows.length - 1),
              ],
            ),
          ),

          const SizedBox(height: 18),

          ElevatedButton(
            onPressed: missing.isEmpty ? _continue : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              disabledBackgroundColor: AppColors.greyDark,
              minimumSize: const Size(double.infinity, 52),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            // El botón apagado dice POR QUÉ lo está. Un botón gris y un aviso
            // lejos, arriba del todo, obligan a buscar la relación entre las
            // dos cosas.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (missing.isNotEmpty) ...[
                  const Icon(Icons.cancel_outlined,
                      color: AppColors.error, size: 17),
                  const SizedBox(width: 7),
                ],
                Text(
                  missing.isEmpty
                      ? 'assistant.continue'.tr()
                      : _blockedText(missing),
                  style: TextStyle(
                      color: missing.isEmpty ? Colors.white : AppColors.grey,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Por qué no se puede continuar. Con un solo dato se dice cuál es: "faltan
  /// datos" obliga a repasar la lista entera para encontrarlo.
  String _blockedText(List<String> missing) => missing.length == 1
      ? 'assistant.missing'.tr(
          namedArgs: {'what': _labelFor(missing.first).toLowerCase()})
      : 'assistant.blocked_many'.tr(
          namedArgs: {'n': '${missing.length}'});

  Widget _row(String key, {required bool last}) {
    final mark = _markOf(key);
    final missing = mark == _Mark.missing;

    final (markIcon, markColor) = switch (mark) {
      _Mark.said => (Icons.check_circle_outline, Colors.green),
      _Mark.assumed => (Icons.help_outline, AppColors.orange),
      _Mark.missing => (Icons.cancel_outlined, AppColors.error),
    };

    return InkWell(
      onTap: () => _edit(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          // La fila que falta se pinta entera, no solo su marca: es lo primero
          // que encuentra la vista al bajar por la lista.
          color: missing
              ? AppColors.error.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border(
            left: missing
                ? const BorderSide(color: AppColors.error, width: 3)
                : BorderSide.none,
            bottom: last
                ? BorderSide.none
                : const BorderSide(color: AppColors.greyDark, width: 0.5),
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(_iconFor(key),
              color: missing ? AppColors.error : AppColors.grey, size: 17),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // La etiqueta siempre visible: sin ella, "Circular" o "09:00"
                // sueltos no dicen de qué campo son.
                Text(_labelFor(key),
                    style: TextStyle(
                        color: missing ? AppColors.error : AppColors.grey,
                        fontSize: 10.5)),
                const SizedBox(height: 2),
                if (key == 'duration')
                  _durationChips()
                else ...[
                  Row(children: [
                    Flexible(
                      child: Text(_valueFor(key),
                          style: TextStyle(
                              color: switch (mark) {
                                _Mark.said => AppColors.white,
                                _Mark.assumed => AppColors.grey,
                                _Mark.missing => AppColors.error,
                              },
                              fontSize: 13)),
                    ),
                    // "supuesto" escrito, no solo un color: el color se ve de
                    // lejos, la palabra se entiende sin aprenderse el código.
                    if (mark == _Mark.assumed) ...[
                      const SizedBox(width: 6),
                      Text('· ${'assistant.tag_assumed'.tr()}',
                          style: const TextStyle(
                              color: AppColors.greyDark, fontSize: 10.5)),
                    ],
                  ]),

                  // La dirección completa del sitio elegido, debajo y en
                  // pequeño. El nombre corto no basta para saber si la
                  // gasolinera es la de la entrada del pueblo o la de la
                  // salida, y el punto de salida de una quedada tiene que
                  // quedar claro para todos.
                  if (_addressOf(key) != null) ...[
                    const SizedBox(height: 2),
                    Text(_addressOf(key)!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.greyDark,
                            fontSize: 10.5,
                            height: 1.25)),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(markIcon, color: markColor, size: 18),
        ]),
      ),
    );
  }

  /// Los tres modos de duración, a la vista y tocables.
  ///
  /// Eran tres campos sueltos (`duration_mode`, `km`, `hours`) y para enterarse
  /// de que existe "que lo decida la IA" había que abrir una hoja. Puestos en
  /// fila se ve en qué modo estás sin tocar nada.
  Widget _durationChips() {
    final mode = '${_fields['duration_mode'] ?? 'ai'}';

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          for (final m in const ['km', 'hours', 'ai'])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => _pickDurationMode(m),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: mode == m ? AppColors.orange : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color:
                            mode == m ? AppColors.orange : AppColors.greyDark),
                  ),
                  child: Text(
                    // El modo activo enseña su valor ("150 km"), los otros su
                    // nombre: así se lee de un vistazo cuánto vas a rodar.
                    mode == m ? _durationText : 'assistant.d_$m'.tr(),
                    style: TextStyle(
                        color: mode == m
                            ? AppColors.background
                            : AppColors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _labelFor(String key) => switch (key) {
        'duration' => 'assistant.f_duration'.tr(),
        _ => 'assistant.f_$key'.tr(),
      };

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

    // Lo que falta lo dice la propia fila, e invita a tocarla. Un "Sin definir"
    // suelto no dice que se pueda arreglar ahí mismo.
    if (key != 'duration' && _missing.contains(key)) {
      return 'assistant.row_missing'.tr();
    }

    // Red de seguridad: un campo vacío que no esté en la lista de obligatorios
    // imprimía literalmente "null" en la pantalla.
    if (_isEmptyFor(key, v) && v == null) return 'assistant.undefined'.tr();

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

        // Guardar la elección. Faltaba: la hoja se abría, elegías "con
        // destino", se cerraba y la fila seguía diciendo "Circular" — porque
        // `_editBool` solo aplica el valor cuando se le pide, y aquí no se le
        // pedía. Lo demás (quitar el destino, o preguntarlo) ya funcionaba, así
        // que parecía que la pantalla ignoraba el toque.
        _set('circular', circular);

        if (circular) {
          // Una circular no tiene destino: dejarlo puesto lo enseñaria en la
          // lista y se mandaria al servidor, que lo ignora. Confunde para nada.
          setState(() {
            _fields.remove('destination');
            _fields.remove('destination_lat');
            _fields.remove('destination_lng');
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

  /// Tocar un modo desde la propia fila.
  ///
  /// "Que decida la IA" no necesita teclear nada, así que se aplica y punto;
  /// los otros dos piden un número y abren la hoja ya en ese modo. Abrir una
  /// hoja para que te diga que no hay nada que rellenar sobra.
  Future<void> _pickDurationMode(String mode) async {
    if (mode == 'ai') {
      setState(() {
        _fields['duration_mode'] = 'ai';
        _fields['km'] = null;
        _fields['hours'] = null;
      });
      _set('duration_mode', 'ai');
      return;
    }

    await _editDuration(initialMode: mode);
  }

  /// Cuánto quiere rodar: por kilómetros, por horas, o que lo decida la IA.
  Future<void> _editDuration({String? initialMode}) async {
    var mode = initialMode ?? '${_fields['duration_mode'] ?? 'ai'}';

    final controller = TextEditingController(
      text: '${mode == 'km' ? _fields['km'] ?? '' : mode == 'hours' ? _fields['hours'] ?? '' : ''}',
    );

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
    final current = _coordsOf(key);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) =>
          PlaceSheet(title: 'assistant.f_$key'.tr(), initial: current),
    );

    if (result == null) return;

    // Guardar la coordenada, no solo el nombre. El servidor geocodifica el
    // texto cuando no le llegan coordenadas, así que mandar solo "Gasolinera
    // de Sariñena" tiraría el punto exacto que el motero acaba de elegir.
    //
    // Si el sitio viene sin coordenadas, se borran las que hubiera: dejarlas
    // puestas ataría el nombre nuevo al punto viejo, que es peor que no tener
    // ninguna.
    setState(() {
      _fields['${key}_lat'] = _toDouble(result['lat']);
      _fields['${key}_lng'] = _toDouble(result['lng']);
      // La dirección completa se guarda para enseñarla bajo el nombre. No
      // viaja al servidor: es solo para que el motero reconozca el sitio.
      _fields['${key}_address'] = result['address'];
    });

    _set(key, result['description']);
  }

  /// La dirección completa del sitio, si se eligió en el mapa o buscándolo.
  ///
  /// Solo para los dos campos de lugar: en los demás no significa nada.
  String? _addressOf(String key) {
    if (key != 'origin' && key != 'destination') return null;

    final v = _fields['${key}_address'];
    return (v is String && v.trim().isNotEmpty) ? v : null;
  }

  /// Las coordenadas guardadas de un campo de lugar, si las tiene.
  LatLng? _coordsOf(String key) {
    final lat = _toDouble(_fields['${key}_lat']);
    final lng = _toDouble(_fields['${key}_lng']);

    return (lat == null || lng == null) ? null : LatLng(lat, lng);
  }

  /// El servidor manda los números como `num` y la búsqueda a veces como
  /// cadena, según la fuente.
  double? _toDouble(dynamic v) => switch (v) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };

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

  // ─── Continuar ───────────────────────────────────────────────────────

  /// Pasa a afinar la ruta. Aquí no se genera nada.
  ///
  /// Se navega con `push`, no con `pushReplacement`: desde la pantalla de
  /// afinar se tiene que poder volver a corregir la hora o el destino sin
  /// perder lo escrito.
  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteAssistantRefineScreen(
          request: widget.request,
          fields: Map<String, dynamic>.from(_fields),
          // Lo que se toque allí se guarda aquí al volver. Si no, ir a
          // corregir la hora borraba la dirección y los puntos elegidos.
          onBack: (updated) {
            if (!mounted) return;
            setState(() => _fields.addAll(updated));
          },
        ),
      ),
    );
  }
}


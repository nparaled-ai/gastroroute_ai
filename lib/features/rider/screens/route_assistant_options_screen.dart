import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/route_assistant_service.dart';
import '../providers/route_service.dart';

/// Varias formas de hacer la misma ruta, para elegir antes de calcular nada.
///
/// Generar una ruta son hasta cinco intentos, cada uno con su llamada a la IA y
/// cinco o seis a Google, y tarda entre 20 y 90 segundos. Así que no se generan
/// tres: se piden tres TITULARES —una sola llamada, sin Google— y solo se
/// calcula la que el motero elija.
///
/// Sin esto, cuando una ruta no gusta solo queda darle a regenerar, que es una
/// lotería: no hay forma de decir "por ahí no, por el otro lado".
///
/// Pueden venir menos de tres. Una circular corta o una ruta con los puntos ya
/// elegidos a mano puede tener una sola manera sensata de trazarse, y sacarse
/// dos de la manga sería inventarlas.
class RouteAssistantOptionsScreen extends StatefulWidget {
  /// Todo lo que el motero ha ido decidiendo: sirve para pedir las propuestas
  /// y, con la elegida, para generar.
  final Map<String, dynamic> payload;

  /// La frase original, que viaja con la ruta hasta el final.
  final String request;

  const RouteAssistantOptionsScreen({
    super.key,
    required this.payload,
    required this.request,
  });

  @override
  State<RouteAssistantOptionsScreen> createState() =>
      _RouteAssistantOptionsScreenState();
}

class _RouteAssistantOptionsScreenState
    extends State<RouteAssistantOptionsScreen> {
  /// Un color por propuesta. El primero es el naranja de la app, que es el de
  /// la recomendada en la mayoría de los casos.
  static const _colors = [AppColors.orange, AppColors.cyan, Color(0xFFA8E05F)];

  List<Map<String, dynamic>> _options = const [];
  String? _note;
  String? _error;

  /// Dónde sale, para que el encuadre incluya la salida y no solo los hitos.
  LatLng? _origin;

  /// Y adónde va, cuando va a algún sitio. Las rutas directas no tienen hitos,
  /// así que su línea en el mapa es la que une la salida con la llegada.
  LatLng? _destination;

  bool _loading = true;
  bool _generating = false;

  /// Cuál está resaltada en el mapa. Arranca en la recomendada.
  int _highlighted = 0;

  /// Para poder subir la lista hasta el mapa.
  ///
  /// "Ver en el mapa" no hacía nada visible y el motivo era tonto: el mapa está
  /// fijo arriba, y cuando bajas a leer la segunda o la tercera tarjeta ya no
  /// está en pantalla. Se reencuadraba de verdad, pero nadie lo veía.
  final _scroll = ScrollController();

  GoogleMapController? _map;

  /// Las chinchetas numeradas, dibujadas una vez y reutilizadas.
  final Map<String, BitmapDescriptor> _pins = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _map?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await RouteAssistantService.options(widget.payload);
    if (!mounted) return;

    final options = List<Map<String, dynamic>>.from(
      result['options'] ?? const [],
    );

    // La recomendada primero: es la que se resalta y la que lleva el botón
    // encendido, así que tenerla arriba evita que el motero tenga que buscarla.
    options.sort(
      (a, b) =>
          (b['recommended'] == true ? 1 : 0) -
          (a['recommended'] == true ? 1 : 0),
    );

    await _buildPins(options.length);
    if (!mounted) return;

    final origin = result['origin'];
    final end = result['destination'];

    LatLng? asPoint(dynamic p) => p == null
        ? null
        : LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());

    setState(() {
      _options = options;
      _note = result['note'];
      _error = result['error'];
      _loading = false;
      _highlighted = 0;
      _origin = asPoint(origin);
      _destination = asPoint(end);
    });

    if (options.isNotEmpty) _frame(0);
  }

  /// Dibuja una chincheta numerada por cada posición y color.
  ///
  /// Los marcadores de Google no saben llevar un número dentro, así que se
  /// pintan a mano. Sin número, tres propuestas en el mismo mapa se convierten
  /// en una nube de puntos de la que no se saca el orden de la ruta.
  Future<void> _buildPins(int howMany) async {
    for (
      var option = 0;
      option < howMany && option < _colors.length;
      option++
    ) {
      for (var n = 1; n <= 9; n++) {
        final key = '$option-$n';
        if (_pins.containsKey(key)) continue;
        _pins[key] = await _pin('$n', _colors[option]);
      }
    }
  }

  /// Lo que mide la chincheta en pantalla, en puntos lógicos.
  ///
  /// El bitmap se dibuja multiplicado por la densidad del móvil y se le dice a
  /// Google a qué densidad corresponde. Sin eso, el dibujo se escala otra vez y
  /// en un móvil normal salen chinchetas del tamaño de un dedo: medido en el
  /// emulador, tapaban media provincia.
  static const _pinSize = 26.0;

  Future<BitmapDescriptor> _pin(String label, Color color) async {
    final dpr =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

    final size = _pinSize * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);

    canvas.drawCircle(center, size / 2 - dpr, Paint()..color = color);
    canvas.drawCircle(
      center,
      size / 2 - dpr,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = dpr,
    );

    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.black,
          fontSize: size * 0.56,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      Offset((size - painter.width) / 2, (size - painter.height) / 2),
    );

    final image = await recorder.endRecording().toImage(
      size.round(),
      size.round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: dpr,
    );
  }

  /// El mapa, en oscuro como el resto de la app.
  ///
  /// Un mapa en claro dentro de una pantalla negra no es solo feo: deslumbra de
  /// noche, que es justo cuando un motero mira el móvil con el casco puesto.
  static const _darkMap = '''
[{"elementType":"geometry","stylers":[{"color":"#242f3e"}]},
{"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
{"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#263c3f"}]},
{"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},
{"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212a37"}]},
{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},
{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#746855"}]},
{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1f2835"}]},
{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f3d19c"}]},
{"featureType":"transit","stylers":[{"visibility":"off"}]},
{"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]}]
''';

  // ─── El mapa ─────────────────────────────────────────────────────────

  List<LatLng> _pointsOf(int index) {
    final points =
        List<Map<String, dynamic>>.from(_options[index]['points'] ?? const [])
            .map(
              (p) => LatLng(
                (p['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble(),
              ),
            )
            .toList();

    // Una ruta directa no tiene hitos a propósito: su dibujo es la línea entre
    // la salida y la llegada. Sin esto, tocar "ver en el mapa" en la rápida no
    // enseñaría nada.
    if (points.isEmpty && _destination != null) return [_destination!];

    return points;
  }

  Set<Polyline> get _lines {
    final lines = <Polyline>{};

    final circular = widget.payload['circular'] != false;

    for (var i = 0; i < _options.length; i++) {
      // El trazo arranca y acaba donde arranca y acaba la ruta. En una circular
      // eso cierra el bucle; sin ello se veía una línea suelta entre dos
      // pueblos que no explicaba nada.
      final points = [
        ?_origin,
        ..._pointsOf(i),
        if (_origin != null && circular) _origin!,
      ];
      if (points.length < 2) continue;

      final on = i == _highlighted;

      lines.add(
        Polyline(
          polylineId: PolylineId('o$i'),
          points: points,
          color: _colors[i % _colors.length].withValues(alpha: on ? 1 : 0.4),
          width: on ? 5 : 3,
          // Puntos, no línea continua. Esto NO es el recorrido: es por dónde va
          // la idea. Con una línea maciza cualquiera la lee como la carretera, y
          // al ampliar el mapa el aviso escrito deja de bastar.
          patterns: [PatternItem.dash(26), PatternItem.gap(14)],
        ),
      );
    }

    return lines;
  }

  Set<Marker> get _markers {
    if (_options.isEmpty) return {};

    final points = _pointsOf(_highlighted);
    final markers = <Marker>{};

    for (var i = 0; i < points.length; i++) {
      final pin = _pins['${_highlighted % _colors.length}-${i + 1}'];

      markers.add(
        Marker(
          markerId: MarkerId('p$i'),
          position: points[i],
          icon: pin ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    return markers;
  }

  /// Encuadra la propuesta elegida.
  Future<void> _frame(int index) async {
    // La salida entra en el encuadre: es el primer sitio que se busca al mirar
    // el mapa, y dejándola fuera la ruta parecía empezar en mitad del campo.
    final points = [..._pointsOf(index), ?_origin];
    if (points.isEmpty || _map == null) return;

    var south = points.first.latitude, north = points.first.latitude;
    var west = points.first.longitude, east = points.first.longitude;

    for (final p in points) {
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }

    // Un margen mínimo: con dos puntos muy juntos, los límites quedan casi
    // degenerados y el mapa se va al zoom máximo, encima de un tejado.
    const pad = 0.08;

    await _map!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south - pad, west - pad),
          northeast: LatLng(north + pad, east + pad),
        ),
        48,
      ),
    );
  }

  /// Resalta una propuesta y la encuadra en el mapa.
  ///
  /// [subirAlMapa] solo cuando se pulsa el botón: sin eso el botón parecía
  /// roto, porque el mapa está fijo arriba y al leer la segunda tarjeta ya no
  /// se ve. Tocando la TARJETA no se sube: ahí el motero está leyendo, y
  /// moverle la lista bajo el dedo es peor que no enseñarle el mapa.
  void _highlight(int index, {bool subirAlMapa = false}) {
    setState(() => _highlighted = index);
    _frame(index);

    if (subirAlMapa && _scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }
  }

  // ─── Elegir ──────────────────────────────────────────────────────────

  /// Generar la ruta de la propuesta elegida.
  ///
  /// Sus hitos van como SUGERENCIA, no como obligación, y ahí está toda la
  /// diferencia. Al principio viajaban como puntos obligatorios y eso rompía el
  /// control de distancia del generador: lo obligatorio no se recorta nunca, y
  /// el recorte se quedaba sin margen. Medido — una circular de 250 km salía en
  /// 327 y 374 km, y un Zaragoza-Santander acababa en 678 km y 10,9 h cuando el
  /// tope de un día son 600 y 10.
  ///
  /// Lo que el motero eligió es una ZONA, no cada pueblo de la tarjeta: si uno
  /// obliga a pasarse de largo, es mejor dejarlo fuera que devolver una ruta
  /// que no cabe en el día.
  Future<void> _choose(int? index) async {
    setState(() => _generating = true);

    final option = index == null ? null : _options[index];
    final kind = '${option?['kind'] ?? 'scenic'}';

    // La rápida y la directa no pasan por la IA: ya las ha trazado Google.
    // Tardan un segundo en vez de minuto y medio y no gastan cupo.
    final result = kind == 'scenic'
        ? await _generateScenic(option)
        : await _generateDirect(kind);

    if (!mounted) return;

    setState(() => _generating = false);

    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    context.push('/rider/route-result', extra: result['result']);
  }

  /// La ruta corta: la traza Google y se guarda tal cual.
  Future<Map<String, dynamic>> _generateDirect(String kind) {
    final p = widget.payload;

    return RouteAssistantService.direct({
      'origin': p['origin'],
      'destination': p['destination'],
      'moto_id': p['moto_id'],
      // La rápida va por autopista; la otra, expresamente no.
      'avoid_highways': kind == 'roads',
      'title': _directTitle(kind),
      'description': 'assistant.direct_${kind}_desc'.tr(),
      if (p['difficulty'] != null) 'difficulty': p['difficulty'],
      if (p['departure_date'] != null) 'departure_date': p['departure_date'],
      if (p['departure_time'] != null) 'departure_time': p['departure_time'],
      'ai_request': widget.request,
    });
  }

  String _directTitle(String kind) => 'assistant.direct_${kind}_title'.tr(
    namedArgs: {
      'from': '${widget.payload['origin']}'.split(',').first.trim(),
      'to': '${widget.payload['destination']}'.split(',').first.trim(),
    },
  );

  Future<Map<String, dynamic>> _generateScenic(
    Map<String, dynamic>? option,
  ) async {
    final names = option == null
        ? const <String>[]
        : List<Map<String, dynamic>>.from(
            option['points'] ?? const [],
          ).map((p) => '${p['name']}').toList();

    final payload = Map<String, dynamic>.from(widget.payload)
      ..['ai_request'] = widget.request;

    if (names.isNotEmpty) payload['suggested_points'] = names;

    return RouteService.generateRoute(payload);
  }

  // ─── Pintar ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'assistant.options_title'.tr(),
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${'assistant.step_of'.tr(namedArgs: {'n': '3'})} · $_subtitle',
              style: const TextStyle(color: AppColors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
      body: _loading
          ? _busy('assistant.options_loading'.tr())
          : _generating
          ? _busy('assistant.options_generating'.tr())
          : _options.isEmpty
          ? _empty()
          : _list(),
    );
  }

  String get _subtitle {
    final km = widget.payload['km'];
    final circular = widget.payload['circular'] != false;

    final where = circular
        ? 'assistant.options_circular'.tr(
            namedArgs: {'from': '${widget.payload['origin']}'},
          )
        : 'assistant.options_to'.tr(
            namedArgs: {'to': '${widget.payload['destination']}'},
          );

    return km == null ? where : '$where · ~$km km';
  }

  Widget _busy(String text) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: AppColors.orange),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.grey, fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.map_outlined, color: AppColors.greyDark, size: 44),
          const SizedBox(height: 14),
          Text(
            _error ?? 'assistant.options_none'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.grey,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          // Que no haya propuestas no puede dejar al motero encerrado: la
          // ruta se genera igual, sin elegir zona.
          ElevatedButton(
            onPressed: () => _choose(null),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              minimumSize: const Size(220, 46),
            ),
            child: Text(
              'assistant.generate'.tr(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: _load,
            child: Text(
              'assistant.options_again'.tr(),
              style: const TextStyle(color: AppColors.cyan, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _list() => Column(
    children: [
      SizedBox(
        height: 212,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _pointsOf(0).first,
                zoom: 8,
              ),
              style: _darkMap,
              onMapCreated: (c) {
                _map = c;
                _frame(_highlighted);
              },
              polylines: _lines,
              markers: _markers,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
              // El mapa es para mirar, no para manejar: los gestos aquí
              // pelean con el scroll de la lista.
              scrollGesturesEnabled: false,
              rotateGesturesEnabled: false,
            ),

            // El aviso va SOBRE el mapa, no al pie de la pantalla: es
            // mirándolo cuando se confunde un trazo con una carretera.
            Positioned(
              left: 10,
              bottom: 9,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'assistant.options_sketch'.tr(),
                  style: const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),

      Expanded(
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(
            14,
            12,
            14,
            20 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            if (_note != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 2),
                child: Text(
                  _note!,
                  style: const TextStyle(
                    color: AppColors.grey,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],

            for (var i = 0; i < _options.length; i++) _card(i),

            const SizedBox(height: 2),

            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, color: AppColors.cyan, size: 16),
              label: Text(
                'assistant.options_again'.tr(),
                style: const TextStyle(color: AppColors.cyan, fontSize: 12.5),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.greyDark),
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _card(int index) {
    final option = _options[index];
    final color = _colors[index % _colors.length];
    final on = index == _highlighted;
    final recommended = option['recommended'] == true;

    // La rápida y la directa no las ha pensado la IA: las ha trazado Google.
    // Así que su nombre y su explicación los pone la app, en el idioma del
    // motero, y sus kilómetros son exactos en vez de aproximados.
    final kind = '${option['kind'] ?? 'scenic'}';
    final direct = kind != 'scenic';

    final title = direct ? _directTitle(kind) : '${option['name']}';

    final names = direct
        ? 'assistant.direct_${kind}_sub'.tr()
        : List<Map<String, dynamic>>.from(
            option['points'] ?? const [],
          ).map((p) => '${p['name']}').join(' · ');

    final hours = (option['minutes'] as num?) == null
        ? null
        : ((option['minutes'] as num) / 60).toStringAsFixed(1);

    // Tocar la tarjeta es lo mismo que "Ver en el mapa": es el gesto que sale
    // solo cuando estás comparando tres, y tener que apuntar al botón pequeño
    // para algo que no decide nada sobra.
    return GestureDetector(
      onTap: () => _highlight(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: on ? Border.all(color: color, width: 2) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                if (recommended) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'assistant.options_pick'.tr(),
                      style: const TextStyle(
                        color: AppColors.background,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),

            if (recommended) ...[
              const SizedBox(height: 5),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],

            const SizedBox(height: 3),
            Text(
              names,
              style: const TextStyle(color: AppColors.grey, fontSize: 12),
            ),

            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                _chip(
                  direct
                      ? '${option['approx_km']} km'
                      : '~${option['approx_km']} km',
                ),
                if (hours != null) _chip('$hours h'),
                for (final t in List<String>.from(option['traits'] ?? const []))
                  _chip(t),
              ],
            ),

            if (direct) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.greyDark, width: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'assistant.direct_${kind}_why'.tr(),
                      style: const TextStyle(
                        color: AppColors.grey,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),

                    // Lo que esta ruta se deja por el camino. Si el motero ha
                    // elegido sitios a mano y esta no pasa por ellos, hay que
                    // decírselo aquí: darle una ruta que ignora en silencio lo
                    // que acaba de pedir es lo único que no se puede hacer.
                    if ((option['skips'] as num? ?? 0) > 0) ...[
                      const SizedBox(height: 7),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppColors.orange,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'assistant.direct_skips'.tr(
                                namedArgs: {'n': '${option['skips']}'},
                              ),
                              style: const TextStyle(
                                color: AppColors.orange,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ] else if ('${option['why']}'.isNotEmpty) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.greyDark, width: 0.5),
                  ),
                ),
                child: Text(
                  '${option['why']}',
                  style: const TextStyle(
                    color: AppColors.grey,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _highlight(index, subirAlMapa: true),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.greyDark),
                      minimumSize: const Size(0, 38),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: Text(
                      'assistant.options_show'.tr(),
                      style: const TextStyle(
                        color: AppColors.cyan,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _choose(index),
                    style: ElevatedButton.styleFrom(
                      // Relleno en la recomendada y contorno naranja en las demás.
                      // Antes eran gris sobre gris, y el motero dijo que "no le
                      // dejaba elegir las otras": no es que no funcionaran —están
                      // conectadas desde el primer día—, es que parecían apagadas.
                      backgroundColor: recommended
                          ? AppColors.orange
                          : AppColors.surface,
                      side: recommended
                          ? null
                          : const BorderSide(
                              color: AppColors.orange,
                              width: 1.2,
                            ),
                      minimumSize: const Size(0, 38),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: Text(
                      'assistant.options_choose'.tr(),
                      style: TextStyle(
                        color: recommended ? Colors.white : AppColors.orange,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.grey, fontSize: 11),
    ),
  );
}

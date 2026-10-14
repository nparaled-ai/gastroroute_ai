import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/route_assistant_service.dart';
import 'route_assistant_review_screen.dart';

/// Primera pantalla del asistente: el motero cuenta en una frase qué ruta
/// quiere.
///
/// El formulario de siempre pide más de veinte datos para algo que se piensa en
/// una frase. Esto no lo sustituye —sigue accesible desde abajo— sino que le
/// pone otra puerta delante.
///
/// El dictado es el del teclado del móvil: con un campo multilínea ya aparece,
/// sin librerías ni permisos.
class RouteAssistantScreen extends StatefulWidget {
  const RouteAssistantScreen({super.key});

  @override
  State<RouteAssistantScreen> createState() => _RouteAssistantScreenState();
}

class _RouteAssistantScreenState extends State<RouteAssistantScreen> {
  final _controller = TextEditingController();

  bool _loading = false;
  String? _zone;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadZone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// La zona del motero, para que los ejemplos hablen de su sierra y no de una
  /// genérica.
  ///
  /// No pide el permiso de ubicación: si no lo tiene ya, los ejemplos salen sin
  /// zona. Pedir un permiso para adornar tres ejemplos sería desproporcionado.
  Future<void> _loadZone() async {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return;
    }

    try {
      final position = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low),
          );

      final zone = await RouteAssistantService.zone(
          position.latitude, position.longitude);

      if (mounted && zone != null) setState(() => _zone = zone);
    } catch (_) {
      // Sin ubicación, ejemplos genéricos. No es un error que contar.
    }
  }

  List<String> get _examples => [
        if (_zone != null)
          'assistant.example_zone'.tr(namedArgs: {'zone': _zone!})
        else
          'assistant.example_curves'.tr(),
        'assistant.example_day'.tr(),
        'assistant.example_easy'.tr(),
      ];

  Future<void> _continue() async {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      setState(() => _error = 'assistant.empty'.tr());
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await RouteAssistantService.interpret(text);
    if (!mounted) return;

    setState(() => _loading = false);

    if (result['understood'] != true) {
      // Un camino de salida claro, en vez de inventarse una ruta con todo por
      // defecto: el motero sabe qué ha pasado y qué puede hacer.
      setState(() => _error = switch (result['reason']) {
            'multi_day' => 'assistant.multi_day'.tr(),
            'unclear' => 'assistant.unclear'.tr(),
            _ => result['error'] ?? 'errors.connection'.tr(),
          });
      return;
    }

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RouteAssistantReviewScreen(
          request: text,
          interpretation: result,
        ),
      ),
    );

    // Si vuelve para retocar la frase, se queda escrita tal cual.
    if (changed == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('assistant.title'.tr(),
            style: const TextStyle(
                color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          Text('assistant.heading'.tr(),
              style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.25)),
          const SizedBox(height: 8),
          Text('assistant.sub'.tr(),
              style: const TextStyle(
                  color: AppColors.grey, fontSize: 13, height: 1.45)),

          const SizedBox(height: 18),

          TextField(
            controller: _controller,
            // Multilínea para que el teclado ofrezca el dictado y para que la
            // frase se vea entera mientras se escribe.
            maxLines: 4,
            minLines: 3,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(
                color: AppColors.white, fontSize: 15, height: 1.5),
            decoration: InputDecoration(
              hintText: 'assistant.hint'.tr(),
              hintStyle: const TextStyle(
                  color: AppColors.grey, fontSize: 14, height: 1.5),
              filled: true,
              fillColor: AppColors.surface,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.greyDark),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.greyDark),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.orange),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_error!,
                      style: const TextStyle(
                          color: AppColors.grey, fontSize: 12, height: 1.4)),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 16),

          // Los ejemplos no son adorno: una caja vacía intimida más que un
          // formulario, y estos enseñan a la vez qué se puede pedir y en qué
          // tono.
          Text('assistant.examples_label'.tr(),
              style: const TextStyle(color: AppColors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: _examples
                .map((e) => GestureDetector(
                      onTap: () => setState(() {
                        _controller.text = e;
                        _error = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.greyDark),
                        ),
                        child: Text(e,
                            style: const TextStyle(
                                color: AppColors.grey, fontSize: 12)),
                      ),
                    ))
                .toList(),
          ),

          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _loading ? null : _continue,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _loading
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Text('assistant.thinking'.tr(),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ])
                : Text('assistant.continue'.tr(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
          ),

          const SizedBox(height: 12),

          // El formulario no desaparece: funciona y hay gente que prefiere los
          // botones.
          Center(
            child: TextButton(
              onPressed: () => context.pushReplacement('/rider/route-generator'),
              child: Text('assistant.manual'.tr(),
                  style: const TextStyle(
                      color: AppColors.grey,
                      fontSize: 12,
                      decoration: TextDecoration.underline)),
            ),
          ),
        ],
      ),
    );
  }
}

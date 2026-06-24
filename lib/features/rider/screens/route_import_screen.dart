import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/route_import_service.dart';
import '../providers/rider_profile_service.dart';

class RouteImportScreen extends StatefulWidget {
  const RouteImportScreen({super.key});

  @override
  State<RouteImportScreen> createState() => _RouteImportScreenState();
}

class _RouteImportScreenState extends State<RouteImportScreen> {
  final _urlController = TextEditingController();
  final _pageController = PageController();

  int    _currentStep = 0;
  bool   _loading     = false;
  String? _error;
  int?   _motoId;
  String? _motoLabel;
  List<Map<String, dynamic>> _motos = [];
  String? _departureDate;
  String  _departureTime = '09:00';

  final List<_TutorialStep> _steps = [
    _TutorialStep(
      icon: Icons.map_outlined,
      color: const Color(0xFF4285F4), // Google blue
      title: 'Abre Google Maps',
      description: 'Busca tu ruta en Google Maps con origen, destino y los puntos intermedios que quieras.',
      tip: 'Puedes añadir hasta 9 paradas intermedias pulsando "Añadir parada".',
      illustration: _StepIllustration.googleMaps,
    ),
    _TutorialStep(
      icon: Icons.share_outlined,
      color: AppColors.orange,
      title: 'Pulsa Compartir',
      description: 'Una vez tengas la ruta lista, pulsa el botón "Compartir" en la parte inferior de la pantalla.',
      tip: 'El botón de compartir tiene el icono típico de compartir (flecha hacia arriba).',
      illustration: _StepIllustration.shareButton,
    ),
    _TutorialStep(
      icon: Icons.link,
      color: AppColors.cyan,
      title: 'Copia el enlace',
      description: 'En el menú que aparece, selecciona "Copiar enlace". El enlace se guardará en tu portapapeles.',
      tip: 'También puedes compartir directamente a GastroRouteAI si aparece en las opciones.',
      illustration: _StepIllustration.copyLink,
    ),
    _TutorialStep(
      icon: Icons.download_outlined,
      color: Colors.green,
      title: 'Pega el enlace aquí',
      description: 'Vuelve a GastroRouteAI y pega el enlace. Procesaremos la ruta y añadiremos tiempos, gasolineras y clima automáticamente.',
      tip: null,
      illustration: _StepIllustration.pasteLink,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadMoto();
  }

  Future<void> _loadMoto() async {
    final result = await RiderProfileService.getMotos();
    if (!mounted) return;
    final motos = result['motos'] as List? ?? [];
    setState(() {
      _motos = List<Map<String, dynamic>>.from(motos);
    });
    final primary = _motos.firstWhere(
      (m) => m['is_primary'] == true || m['is_primary'] == 1,
      orElse: () => _motos.isNotEmpty ? _motos.first : <String, dynamic>{},
    );
    if (primary.isNotEmpty) {
      setState(() {
        _motoId    = primary['id'];
        _motoLabel = '${primary['brand']} ${primary['model']}';
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() => _urlController.text = data!.text!.trim());
    }
  }

  Future<void> _import() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Pega el enlace de Google Maps.');
      return;
    }
    if (_departureDate == null) {
      setState(() => _error = 'Selecciona una fecha de salida.');
      return;
    }
    if (!url.contains('google') && !url.contains('goo.gl') && !url.contains('maps')) {
      setState(() => _error = 'El enlace no parece ser de Google Maps.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final result = await RouteImportService.importFromUrl(
      url: url,
      motoId: _motoId,
      departureDate: _departureDate,
      departureTime: _departureTime,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['error'] != null) {
      setState(() => _error = result['error']);
      return;
    }

    // Navegar al resultado igual que una ruta IA
    if (!mounted) return;
    context.push('/rider/route-result', extra: result['result']);
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
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
        title: const Text('Importar desde Google Maps',
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: Column(children: [
        // Indicador de pasos
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_steps.length, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _currentStep ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == _currentStep ? AppColors.orange : AppColors.greyDark,
                borderRadius: BorderRadius.circular(4),
              ),
            )),
          ),
        ),

        // Tutorial
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentStep = i),
            itemCount: _steps.length,
            itemBuilder: (_, i) => _buildStepPage(_steps[i], i),
          ),
        ),

        // Navegación
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: _currentStep < _steps.length - 1
              ? Row(children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _prevStep,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          side: const BorderSide(color: AppColors.greyDark),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Atrás', style: TextStyle(color: AppColors.grey)),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        minimumSize: const Size(0, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(_currentStep == 0 ? 'Empezar' : 'Siguiente',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                      ]),
                    ),
                  ),
                ])
              : _buildImportPanel(),
        ),
      ]),
    );
  }

  Widget _buildStepPage(_TutorialStep step, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(children: [
        const SizedBox(height: 8),

        // Ilustración
        Expanded(
          flex: 3,
          child: _buildIllustration(step),
        ),

        const SizedBox(height: 20),

        // Número y título
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: step.color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: step.color),
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: TextStyle(color: step.color, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(step.title,
                style: const TextStyle(
                    color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 12),

        // Descripción
        Text(step.description,
            style: const TextStyle(color: AppColors.grey, fontSize: 14, height: 1.6)),

        if (step.tip != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: step.color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: step.color.withOpacity(0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline, color: step.color, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(step.tip!,
                  style: TextStyle(color: step.color, fontSize: 12, height: 1.4))),
            ]),
          ),
        ],
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _buildIllustration(_TutorialStep step) {
    switch (step.illustration) {
      case _StepIllustration.googleMaps:
        return _GoogleMapsIllustration();
      case _StepIllustration.shareButton:
        return _ShareButtonIllustration();
      case _StepIllustration.copyLink:
        return _CopyLinkIllustration();
      case _StepIllustration.pasteLink:
        return _PasteLinkIllustration();
    }
  }

  Widget _buildImportPanel() {
  return Column(mainAxisSize: MainAxisSize.min, children: [
  if (_error != null) ...[  
  Container(
  padding: const EdgeInsets.all(12),
  margin: const EdgeInsets.only(bottom: 12),
  decoration: BoxDecoration(
  color: AppColors.error.withOpacity(0.1),
  borderRadius: BorderRadius.circular(10),
  border: Border.all(color: AppColors.error.withOpacity(0.4)),
  ),
  child: Row(children: [
  const Icon(Icons.error_outline, color: AppColors.error, size: 18),
  const SizedBox(width: 8),
  Expanded(child: Text(_error!,
  style: const TextStyle(color: AppColors.error, fontSize: 13))),
  ]),
  ),
  ],

  // Botón abrir Google Maps
  OutlinedButton(
  onPressed: () async {
  final uri = Uri.parse('https://maps.google.com');
  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  },
  style: OutlinedButton.styleFrom(
  minimumSize: const Size(double.infinity, 46),
  side: const BorderSide(color: Color(0xFF4285F4)),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
  Icon(Icons.open_in_new, color: Color(0xFF4285F4), size: 18),
  SizedBox(width: 8),
  Text('Abrir Google Maps', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w700)),
  ]),
  ),
  const SizedBox(height: 10),

  // Campo URL
  Row(children: [
  Expanded(
    child: TextField(
    controller: _urlController,
    style: const TextStyle(color: AppColors.white, fontSize: 13),
  decoration: InputDecoration(
    hintText: 'https://maps.app.goo.gl/...',
  hintStyle: const TextStyle(color: AppColors.grey, fontSize: 12),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  prefixIcon: const Icon(Icons.link, color: AppColors.cyan, size: 18),
    suffixIcon: _urlController.text.isNotEmpty
        ? IconButton(
              icon: const Icon(Icons.clear, color: AppColors.grey, size: 16),
                onPressed: () => setState(() => _urlController.clear()),
                )
                  : null,
        ),
            onChanged: (_) => setState(() {}),
      ),
    ),
  const SizedBox(width: 8),
  GestureDetector(
  onTap: _pasteFromClipboard,
  child: Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
      color: AppColors.cyan.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
  ),
  child: const Icon(Icons.content_paste, color: AppColors.cyan, size: 20),
  ),
  ),
      ]),
  const SizedBox(height: 10),

  // Fecha y hora
  Row(children: [
  // Fecha
  Expanded(
  child: GestureDetector(
    onTap: () async {
        final picked = await showDatePicker(
          context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
  firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
  );
  if (picked != null) {
  setState(() => _departureDate = picked.toIso8601String().split('T')[0]);
  }
  },
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _departureDate != null ? AppColors.cyan : AppColors.greyDark),
              ),
              child: Row(children: [
                const Icon(Icons.event, color: AppColors.cyan, size: 16),
                const SizedBox(width: 6),
                Text(
                  _departureDate ?? 'Fecha de salida',
                  style: TextStyle(
                    color: _departureDate != null ? AppColors.cyan : AppColors.grey,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Hora
        GestureDetector(
          onTap: () async {
            final parts = _departureTime.split(':');
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
            );
            if (picked != null) {
              setState(() => _departureTime =
                  '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.greyDark),
            ),
            child: Row(children: [
              const Icon(Icons.schedule, color: AppColors.orange, size: 16),
              const SizedBox(width: 6),
              Text(_departureTime,
                  style: const TextStyle(
                      color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 10),

      // Selector de moto
      if (_motos.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.greyDark),
          ),
          child: Row(children: [
            const Icon(Icons.two_wheeler, color: AppColors.orange, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _motoId,
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: AppColors.white, fontSize: 13),
                  hint: const Text('Selecciona tu moto',
                      style: TextStyle(color: AppColors.grey, fontSize: 13)),
                  items: _motos.map((m) => DropdownMenuItem<int>(
                    value: m['id'] as int,
                    child: Text('${m['brand']} ${m['model']}',
                        style: const TextStyle(color: AppColors.white, fontSize: 13)),
                  )).toList(),
                  onChanged: (val) => setState(() {
                    _motoId = val;
                    final m = _motos.firstWhere((m) => m['id'] == val, orElse: () => {});
                    _motoLabel = m.isNotEmpty ? '${m['brand']} ${m['model']}' : null;
                  }),
                ),
              ),
            ),
            const Text('para gasolineras',
                style: TextStyle(color: AppColors.greyDark, fontSize: 11)),
          ]),
        ),

      const SizedBox(height: 12),

      ElevatedButton(
        onPressed: _loading ? null : _import,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _loading
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.download_outlined, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Importar ruta',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
      ),
    ]);
  }
}

// ─── Modelo paso del tutorial ─────────────────────────────────────────────────
enum _StepIllustration { googleMaps, shareButton, copyLink, pasteLink }

class _TutorialStep {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String? tip;
  final _StepIllustration illustration;

  const _TutorialStep({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.tip,
    required this.illustration,
  });
}

// ─── Ilustraciones SVG ────────────────────────────────────────────────────────

class _GoogleMapsIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.greyDark),
      ),
      child: Stack(children: [
        // Fondo mapa simulado
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: CustomPaint(
            size: const Size(double.infinity, double.infinity),
            painter: _MapBackgroundPainter(),
          ),
        ),
        // Contenido
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Barra de búsqueda
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
              ),
              child: Row(children: [
                const Icon(Icons.search, color: Color(0xFF4285F4), size: 18),
                const SizedBox(width: 8),
                const Text('Busca tu ruta...', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ]),
            ),
            const Spacer(),
            // Panel inferior
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Mi ruta', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 6),
                Row(children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF34A853), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  const Text('Origen → Destino', style: TextStyle(color: Colors.black54, fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                Row(children: const [
                  Text('2h 30min', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13)),
                  SizedBox(width: 8),
                  Text('185 km', style: TextStyle(color: Colors.black54, fontSize: 12)),
                ]),
              ]),
            ),
          ]),
        ),
        // Marcador rojo animado (pin)
        Positioned(
          top: 80, left: 100,
          child: Column(children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFEA4335),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
              ),
              child: const Icon(Icons.place, color: Colors.white, size: 14),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ShareButtonIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.greyDark),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Spacer(),
          // Panel inferior simulado de Google Maps
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
            ),
            child: Column(children: [
              const Text('Ruta encontrada', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _GoogleMapButton(icon: Icons.directions, label: 'Inicio', color: const Color(0xFF4285F4)),
                // Botón compartir resaltado
                Stack(clipBehavior: Clip.none, children: [
                  _GoogleMapButton(icon: Icons.share, label: 'Compartir', color: AppColors.orange),
                  Positioned(
                    top: -8, right: -8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
                      child: const Icon(Icons.touch_app, color: Colors.white, size: 10),
                    ),
                  ),
                ]),
                _GoogleMapButton(icon: Icons.bookmark_border, label: 'Guardar', color: Colors.grey),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          // Flecha indicando el botón
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.orange.withOpacity(0.4)),
              ),
              child: const Row(children: [
                Icon(Icons.arrow_upward, color: AppColors.orange, size: 16),
                SizedBox(width: 6),
                Text('Pulsa aquí', style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _CopyLinkIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.greyDark),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Spacer(),
          // Modal de compartir de Android
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2d2d2d),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Compartir vía', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _ShareOption(icon: Icons.message, label: 'Mensaje', color: Colors.green),
                _ShareOption(icon: Icons.email, label: 'Email', color: Colors.blue),
                // Opción copiar enlace resaltada
                Stack(clipBehavior: Clip.none, children: [
                  _ShareOption(icon: Icons.copy, label: 'Copiar\nenlace', color: AppColors.cyan),
                  Positioned(
                    top: -6, right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: AppColors.cyan, shape: BoxShape.circle),
                      child: const Icon(Icons.touch_app, color: Colors.white, size: 10),
                    ),
                  ),
                ]),
                _ShareOption(icon: Icons.more_horiz, label: 'Más', color: Colors.grey),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cyan.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cyan.withOpacity(0.4)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.copy, color: AppColors.cyan, size: 16),
              SizedBox(width: 6),
              Text('Selecciona "Copiar enlace"', style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PasteLinkIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.greyDark),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.download_outlined, color: AppColors.orange, size: 48),
          const SizedBox(height: 16),
          // Campo simulado con enlace pegado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cyan),
            ),
            child: Row(children: [
              const Icon(Icons.link, color: AppColors.cyan, size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('https://maps.app.goo.gl/...',
                    style: TextStyle(color: AppColors.cyan, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.content_paste, color: AppColors.grey, size: 16),
            ]),
          ),
          const SizedBox(height: 20),
          // Resultado esperado
          Row(children: [
            _ResultChip(icon: Icons.route, label: '185 km', color: AppColors.orange),
            const SizedBox(width: 8),
            _ResultChip(icon: Icons.access_time, label: '2.5 h', color: AppColors.cyan),
            const SizedBox(width: 8),
            _ResultChip(icon: Icons.local_gas_station, label: 'Gasolineras', color: AppColors.gold),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _ResultChip(icon: Icons.wb_sunny_outlined, label: 'Clima', color: AppColors.gold),
            const SizedBox(width: 8),
            _ResultChip(icon: Icons.schedule, label: 'Horarios', color: Colors.green),
          ]),
        ]),
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────
class _GoogleMapButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _GoogleMapButton({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ShareOption({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: color, fontSize: 10), textAlign: TextAlign.center),
    ]);
  }
}

class _ResultChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ResultChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _MapBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF2d4a3e);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Calles simuladas
    final roadPaint = Paint()
      ..color = const Color(0xFF3d5c4e)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, size.height * 0.3), Offset(size.width, size.height * 0.3), roadPaint);
    canvas.drawLine(Offset(0, size.height * 0.6), Offset(size.width, size.height * 0.6), roadPaint);
    canvas.drawLine(Offset(size.width * 0.3, 0), Offset(size.width * 0.3, size.height), roadPaint);
    canvas.drawLine(Offset(size.width * 0.7, 0), Offset(size.width * 0.7, size.height), roadPaint);

    // Ruta resaltada
    final routePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.1, size.height * 0.6)
      ..lineTo(size.width * 0.3, size.height * 0.6)
      ..lineTo(size.width * 0.3, size.height * 0.3)
      ..lineTo(size.width * 0.7, size.height * 0.3)
      ..lineTo(size.width * 0.7, size.height * 0.6)
      ..lineTo(size.width * 0.9, size.height * 0.6);

    canvas.drawPath(path, routePaint);
  }

  @override
  bool shouldRepaint(_) => false;
}

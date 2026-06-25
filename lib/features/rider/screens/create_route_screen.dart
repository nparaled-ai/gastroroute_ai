import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class CreateRouteScreen extends StatelessWidget {
  const CreateRouteScreen({super.key});

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
        title: const Text('Crear ruta',
            style: TextStyle(
                color: AppColors.white, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          const Text('¿Cómo quieres crear tu ruta?',
              style: TextStyle(
                  color: AppColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
              'Elige la opción que mejor se adapte a tu aventura.',
              style: TextStyle(
                  color: AppColors.grey, fontSize: 14, height: 1.5)),
          const SizedBox(height: 32),

          // ── Generar con IA ────────────────────────────────
          _OptionCard(
            emoji: '✨',
            color: AppColors.orange,
            title: 'Generar con IA',
            desc: 'Describe tu aventura y la IA crea la ruta perfecta para ti: waypoints, tiempos, gasolineras y clima.',
            tags: ['Recomendado', 'Rutas únicas'],
            onTap: () => context.push('/rider/route-generator'),
          ),
          const SizedBox(height: 16),

          // ── Google Maps ───────────────────────────────────
          _OptionCard(
            emoji: '🗺️',
            color: const Color(0xFF4285F4),
            title: 'Desde Google Maps',
            desc: 'Importa cualquier ruta que tengas en Google Maps. Pega el enlace y la procesamos automáticamente.',
            tags: ['Enlace corto o largo', 'Con waypoints'],
            onTap: () => context.push('/rider/route-import'),
          ),
          const SizedBox(height: 16),

          // ── GPX ───────────────────────────────────────────
          _OptionCard(
            emoji: '📂',
            color: AppColors.cyan,
            title: 'Archivo GPX',
            desc: 'Importa rutas desde Wikiloc, Komoot, Garmin Connect u otras apps. Compatible con cualquier archivo .gpx.',
            tags: ['Wikiloc', 'Komoot', 'Garmin'],
            comingSoon: true,
            onTap: () {},
          ),
          const SizedBox(height: 16),

          // ── Viaje multi-día ───────────────────────────────
          _OptionCard(
            emoji: '🏕️',
            color: AppColors.gold,
            title: 'Viaje multi-día',
            desc: 'Planifica un viaje de varios días con alojamiento, etapas y todo lo necesario para la aventura.',
            tags: ['Multi-día', 'Con hoteles'],
            comingSoon: true,
            onTap: () {},
          ),

          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String emoji;
  final Color color;
  final String title;
  final String desc;
  final List<String> tags;
  final bool comingSoon;
  final VoidCallback onTap;

  const _OptionCard({
    required this.emoji,
    required this.color,
    required this.title,
    required this.desc,
    required this.tags,
    required this.onTap,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: comingSoon ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: comingSoon
                ? AppColors.greyDark
                : color.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Emoji icono
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: comingSoon
                  ? AppColors.greyDark
                  : color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 16),

          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title,
                    style: TextStyle(
                        color: comingSoon ? AppColors.grey : AppColors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                if (comingSoon) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.greyDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Próximamente',
                        style: TextStyle(
                            color: AppColors.grey,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
              const SizedBox(height: 6),
              Text(desc,
                  style: const TextStyle(
                      color: AppColors.grey, fontSize: 13, height: 1.4)),
              const SizedBox(height: 10),
              // Tags
              Wrap(spacing: 6, runSpacing: 6, children: tags.map((tag) =>
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: comingSoon
                        ? AppColors.greyDark.withOpacity(0.5)
                        : color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: comingSoon
                            ? AppColors.greyDark
                            : color.withOpacity(0.3)),
                  ),
                  child: Text(tag,
                      style: TextStyle(
                          color: comingSoon ? AppColors.grey : color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ).toList()),
            ]),
          ),

          // Flecha o lock
          const SizedBox(width: 8),
          Icon(
            comingSoon ? Icons.lock_outline : Icons.arrow_forward_ios,
            color: comingSoon ? AppColors.greyDark : color,
            size: 16,
          ),
        ]),
      ),
    );
  }
}

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

/// Términos de uso y política de privacidad, tal como los sirve el servidor en el idioma de la app.
///
/// El texto NO está metido en la app: vive en el servidor (lang/{idioma}/legal.php) para poder corregirlo sin sacar
/// una versión y para que sea el mismo que ve cualquiera en la web (/legal/terms, /legal/privacy). Pública: se abre
/// desde el registro, antes de tener cuenta.
class LegalScreen extends StatefulWidget {
  /// `terms` o `privacy`.
  final String doc;
  const LegalScreen({super.key, required this.doc});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final r = await ApiClient.dio.get('/auth/legal/${widget.doc}');
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(r.data as Map);
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.doc) {
      'terms' => 'legal.terms'.tr(),
      'notice' => 'legal.notice'.tr(),
      _ => 'legal.privacy'.tr(),
    };
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(title, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _error
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.grey),
                      const SizedBox(height: 12),
                      Text('common.connection_error'.tr(),
                          style: const TextStyle(color: AppColors.white, fontSize: 16)),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text('my_routes.offline_retry'.tr()),
                      ),
                    ]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    Text('${_data!['title']}',
                        style: const TextStyle(color: AppColors.orange, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('${'legal.version'.tr()} ${_data!['version']} · ${_data!['updated']}',
                        style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                    const SizedBox(height: 16),
                    for (final s in (_data!['sections'] as List)) ...[
                      Text('${s['heading']}',
                          style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('${s['body']}',
                          style: const TextStyle(color: AppColors.greyText, fontSize: 14, height: 1.5)),
                      const SizedBox(height: 18),
                    ],
                  ],
                ),
    );
  }
}

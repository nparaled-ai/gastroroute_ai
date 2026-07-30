import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/route_import_service.dart';
import '../providers/rider_profile_service.dart';

class RouteImportGpxScreen extends StatefulWidget {
  const RouteImportGpxScreen({super.key});

  @override
  State<RouteImportGpxScreen> createState() => _RouteImportGpxScreenState();
}

class _RouteImportGpxScreenState extends State<RouteImportGpxScreen> {
  bool    _loading      = false;
  String? _error;
  String? _selectedFileName;
  String? _selectedFilePath;
  int?    _motoId;
  List<Map<String, dynamic>> _motos = [];
  String? _departureDate;
  String  _departureTime = '09:00';

  @override
  void initState() {
    super.initState();
    _loadMoto();
  }

  Future<void> _loadMoto() async {
    final result = await RiderProfileService.getMotos();
    if (!mounted) return;
    final motos = result['motos'] as List? ?? [];
    setState(() => _motos = List<Map<String, dynamic>>.from(motos));
    final primary = _motos.firstWhere(
      (m) => m['is_primary'] == true || m['is_primary'] == 1,
      orElse: () => _motos.isNotEmpty ? _motos.first : <String, dynamic>{},
    );
    if (primary.isNotEmpty) {
      setState(() => _motoId = primary['id']);
    }
  }

  Future<void> _pickFile() async {
    setState(() => _error = null);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
      withReadStream: false,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path == null) {
        setState(() => _error = 'No se pudo acceder al archivo. Inténtalo de nuevo.');
        return;
      }
      if (!file.name.toLowerCase().endsWith('.gpx')) {
        setState(() => _error = 'El archivo debe tener extensión .gpx (Wikiloc, Komoot, Garmin…)');
        return;
      }
      setState(() {
        _selectedFilePath = file.path;
        _selectedFileName = file.name;
      });
    }
  }

  Future<void> _import() async {
    if (_selectedFilePath == null) {
      setState(() => _error = 'Selecciona un archivo .gpx primero.');
      return;
    }
    if (_departureDate == null) {
      setState(() => _error = 'Selecciona una fecha de salida.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final result = await RouteImportService.importFromGpx(
      filePath:      _selectedFilePath!,
      fileName:      _selectedFileName!,
      motoId:        _motoId,
      departureDate: _departureDate,
      departureTime: _departureTime,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['error'] != null) {
      setState(() => _error = result['error']);
      return;
    }

    if (!mounted) return;
    context.push('/rider/route-result', extra: result['result']);
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
        title: const Text('Importar archivo GPX',
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Cabecera
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cyan.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.folder_open, color: AppColors.cyan, size: 26),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Compatible con Wikiloc, Komoot, Garmin y cualquier app que exporte .gpx',
                      style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  SizedBox(height: 6),
                  Text('Selecciona el archivo y procesaremos la ruta automáticamente: distancia, tiempos, gasolineras y clima.',
                      style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.5)),
                ]),
              ),
            ]),
          ),

          const SizedBox(height: 32),

          // Selector de archivo
          const Text('Archivo GPX', style: TextStyle(color: AppColors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _loading ? null : _pickFile,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedFileName != null ? AppColors.cyan : AppColors.greyDark,
                  width: 1.5,
                ),
              ),
              child: _selectedFileName != null
                  ? Row(children: [
                      const Icon(Icons.check_circle, color: AppColors.cyan, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_selectedFileName!,
                              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          const Text('Toca para cambiar el archivo',
                              style: TextStyle(color: AppColors.grey, fontSize: 11)),
                        ]),
                      ),
                    ])
                  : const Column(children: [
                      Icon(Icons.upload_file, color: AppColors.cyan, size: 36),
                      SizedBox(height: 8),
                      Text('Toca para seleccionar archivo .gpx',
                          style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 14)),
                      SizedBox(height: 4),
                      Text('Wikiloc · Komoot · Garmin Connect · otros',
                          style: TextStyle(color: AppColors.grey, fontSize: 12)),
                    ]),
            ),
          ),

          const SizedBox(height: 24),

          // Fecha y hora
          const Text('Salida', style: TextStyle(color: AppColors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _departureDate != null ? AppColors.cyan : AppColors.greyDark),
                  ),
                  child: Row(children: [
                    const Icon(Icons.event, color: AppColors.cyan, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _departureDate ?? 'Fecha de salida',
                      style: TextStyle(
                        color: _departureDate != null ? AppColors.cyan : AppColors.grey,
                        fontSize: 13, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () async {
                final parts  = _departureTime.split(':');
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.greyDark),
                ),
                child: Row(children: [
                  const Icon(Icons.schedule, color: AppColors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text(_departureTime,
                      style: const TextStyle(
                          color: AppColors.orange, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // Moto
          if (_motos.isNotEmpty) ...[
            const Text('Moto (para gasolineras)', style: TextStyle(color: AppColors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.greyDark),
              ),
              child: Row(children: [
                const Icon(Icons.two_wheeler, color: AppColors.orange, size: 18),
                const SizedBox(width: 10),
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
                      onChanged: (val) => setState(() => _motoId = val),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
          ],

          // Error
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
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
            const SizedBox(height: 16),
          ],

          // Botón importar
          ElevatedButton(
            onPressed: _loading ? null : _import,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyan,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.download_outlined, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Importar ruta GPX',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
          ),

          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

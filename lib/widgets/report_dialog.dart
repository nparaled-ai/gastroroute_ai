import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/api/report_service.dart';
import '../core/theme/app_theme.dart';

/// Denunciar contenido: motivo, explicación y declaración de buena fe (Reglamento UE 2022/2065, art. 16).
/// [targetType]: `catalog_route` o `catalog_comment`.
Future<void> showReportDialog(BuildContext context, {required String targetType, required int targetId}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportDialog(targetType: targetType, targetId: targetId),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('report.sent'.tr())));
  }
}

/// Entrada discreta: texto pequeño y gris con una bandera, nada de botón llamativo.
class ReportLink extends StatelessWidget {
  final String targetType;
  final int targetId;
  const ReportLink({super.key, required this.targetType, required this.targetId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showReportDialog(context, targetType: targetType, targetId: targetId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.outlined_flag, size: 13, color: AppColors.grey),
          const SizedBox(width: 3),
          Text('report.menu'.tr(), style: const TextStyle(color: AppColors.grey, fontSize: 11.5)),
        ]),
      ),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  final String targetType;
  final int targetId;
  const _ReportDialog({required this.targetType, required this.targetId});

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  static const _reasons = ['offensive', 'personal_data', 'misleading', 'dangerous', 'copyright', 'other'];
  String _reason = 'offensive';
  final _details = TextEditingController();
  bool _goodFaith = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_details.text.trim().length < 10) {
      setState(() => _error = 'report.too_short'.tr());
      return;
    }
    if (!_goodFaith) {
      setState(() => _error = 'report.must_confirm'.tr());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ReportService.send(
      targetType: widget.targetType,
      targetId: widget.targetId,
      reason: _reason,
      details: _details.text.trim(),
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isRoute = widget.targetType == 'catalog_route';
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(isRoute ? 'report.route_title'.tr() : 'report.comment_title'.tr()),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('report.intro'.tr(), style: const TextStyle(color: AppColors.greyText, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _reason,
            isExpanded: true,
            dropdownColor: AppColors.surface,
            decoration: InputDecoration(labelText: 'report.reason_label'.tr()),
            items: [
              for (final r in _reasons)
                DropdownMenuItem(value: r, child: Text('report.reasons.$r'.tr(), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _busy ? null : (v) => setState(() => _reason = v ?? _reason),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _details,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            style: const TextStyle(color: AppColors.white, fontSize: 14),
            decoration: InputDecoration(labelText: 'report.details'.tr()),
          ),
          InkWell(
            onTap: _busy ? null : () => setState(() => _goodFaith = !_goodFaith),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(
                value: _goodFaith,
                onChanged: _busy ? null : (v) => setState(() => _goodFaith = v ?? false),
                activeColor: AppColors.orange,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('report.good_faith'.tr(),
                      style: const TextStyle(color: AppColors.greyText, fontSize: 12.5, height: 1.35)),
                ),
              ),
            ]),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text('common.cancel'.tr())),
        TextButton(
          onPressed: _busy ? null : _send,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('report.send'.tr()),
        ),
      ],
    );
  }
}

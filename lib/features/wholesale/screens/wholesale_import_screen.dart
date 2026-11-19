import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctionsException;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/wholesale_product.dart';
import '../services/wholesale_import_service.dart';

/// «Excel орқали юклаш» (эга, 2026-11-19): шаблон → файл → текширув (preview) → тасдиқ.
/// Улгуржи ва Хитой бозорида бир хил; бозор [market] билан берилади.
class WholesaleImportScreen extends StatefulWidget {
  const WholesaleImportScreen({super.key, required this.market, this.service, this.pickFile});

  final String market;

  /// Тест учун алмаштирилади.
  final WholesaleImportService? service;

  /// Файл танлаш (тестда алмаштирилади); `null` — бекор қилинди.
  final Future<({String name, Uint8List bytes})?> Function()? pickFile;

  @override
  State<WholesaleImportScreen> createState() => _WholesaleImportScreenState();
}

class _WholesaleImportScreenState extends State<WholesaleImportScreen> {
  late final WholesaleImportService _svc = widget.service ?? WholesaleImportService();

  bool _busy = false;
  String _busyKey = '';
  String? _errorKey;
  List<String> _missing = const [];
  WholesaleImportPreview? _preview;
  WholesaleImportResult? _result;
  bool _imported = false;

  bool get _isChina => widget.market == WholesaleProduct.marketChina;

  Future<void> _run(String busyKey, Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _busyKey = busyKey;
      _errorKey = null;
      _missing = const [];
    });
    try {
      await fn();
    } catch (e) {
      debugPrint('[WholesaleImport] $busyKey failed: $e');
      final code = wholesaleImportExceptionCode(e);
      if (!mounted) return;
      setState(() {
        _errorKey = wholesaleImportErrorKey(code);
        _missing = _missingOf(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _missingOf(Object e) {
    final d = e is FirebaseFunctionsException ? e.details : null;
    if (d is Map && d['missing'] is List) {
      return (d['missing'] as List).map((x) => '$x').toList(growable: false);
    }
    return const [];
  }

  Future<void> _downloadTemplate() => _run('wsimp_busy_template', () async {
        final t = await _svc.template(widget.market);
        await Share.shareXFiles([
          XFile.fromData(
            t.bytes,
            name: t.fileName,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ], fileNameOverrides: [t.fileName]);
      });

  Future<void> _pickFile() async {
    final f = await (widget.pickFile ?? _systemPick)();
    if (f == null || !mounted) return;
    final bytes = f.bytes;
    if (bytes.length > WholesaleImportService.maxFileBytes) {
      setState(() => _errorKey = wholesaleImportErrorKey('FILE_TOO_LARGE'));
      return;
    }
    final requestId = WholesaleImportService.newRequestId();
    await _run('wsimp_busy_checking', () async {
      final p = await _svc.preview(
        market: widget.market,
        fileName: f.name,
        bytes: bytes,
        requestId: requestId,
      );
      if (!mounted) return;
      setState(() {
        _preview = p;
        _result = null;
      });
    });
  }

  static Future<({String name, Uint8List bytes})?> _systemPick() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final f = picked?.files.single;
    final bytes = f?.bytes;
    if (f == null || bytes == null) return null;
    return (name: f.name, bytes: bytes);
  }

  Future<void> _confirm() async {
    final p = _preview;
    final batchId = _result?.batchId ?? p?.batchId ?? '';
    if (batchId.isEmpty) return;
    await _run('wsimp_busy_importing', () async {
      final r = await _svc.confirm(batchId);
      if (!mounted) return;
      setState(() {
        _result = r;
        _imported = _imported || r.created + r.updated > 0;
      });
    });
  }

  void _reset() => setState(() {
        _preview = null;
        _result = null;
        _errorKey = null;
      });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Тизим «орқага»си ҳам натижани ([_imported]) қайтарсин; юклаш пайтида ёпилмайди.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) Navigator.pop(context, _imported);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('wsimp_title')),
          leading: BackButton(onPressed: _busy ? null : () => Navigator.pop(context, _imported)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              context.tr(_isChina ? 'wholesale_title_china' : 'wholesale_title'),
              style: TextStyle(fontSize: AppText.labelSmall, color: AppColors.sectionMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (_result != null)
              _resultView(_result!)
            else if (_preview != null)
              _previewView(_preview!)
            else
              ..._startView(),
            if (_busy) ...[
              const SizedBox(height: 16),
              Row(children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text(context.tr(_busyKey))),
              ]),
            ],
            if (_errorKey != null) ...[
              const SizedBox(height: 16),
              Container(
                key: const ValueKey('wsimp-error'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  [context.tr(_errorKey!), if (_missing.isNotEmpty) _missing.join(', ')].join('\n'),
                  style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _startView() => [
        _StepCard(
          number: 1,
          title: context.tr('wsimp_step_template'),
          body: context.tr('wsimp_step_template_help'),
          action: OutlinedButton.icon(
            key: const ValueKey('wsimp-template'),
            onPressed: _busy ? null : _downloadTemplate,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.download_outlined),
            label: Text(context.tr('wsimp_template_btn')),
          ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          number: 2,
          title: context.tr('wsimp_step_upload'),
          body: context.tr('wsimp_step_upload_help'),
          action: FilledButton.icon(
            key: const ValueKey('wsimp-pick'),
            onPressed: _busy ? null : _pickFile,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(context.tr('wsimp_pick_btn')),
          ),
        ),
      ];

  Widget _previewView(WholesaleImportPreview p) {
    final toWrite = p.create + p.update;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('wsimp_preview_title'),
            style: const TextStyle(fontSize: AppText.bodyLarge, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _CountChip(label: context.tr('wsimp_count_ready'), value: p.ready, color: Colors.green),
          _CountChip(label: context.tr('wsimp_count_errors'), value: p.errors, color: AppColors.error),
          _CountChip(label: context.tr('wsimp_count_new'), value: p.create),
          _CountChip(label: context.tr('wsimp_count_update'), value: p.update),
          _CountChip(label: context.tr('wsimp_count_unchanged'), value: p.unchanged),
        ]),
        if (p.update > 0) ...[
          const SizedBox(height: 8),
          Text(context.tr('wsimp_update_note'),
              style: TextStyle(fontSize: AppText.bodySmall, color: AppColors.sectionMuted)),
        ],
        if (p.errors > 0) ...[
          const SizedBox(height: 8),
          Text(context.tr('wsimp_errors_skipped'),
              style: TextStyle(fontSize: AppText.bodySmall, color: AppColors.sectionMuted)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('wsimp-confirm'),
          onPressed: _busy || !p.canConfirm ? null : _confirm,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(p.canConfirm
              ? context.tr('wsimp_confirm_btn').replaceAll('{n}', '$toWrite')
              : context.tr('wsimp_nothing_to_import')),
        ),
        TextButton(
          onPressed: _busy ? null : _reset,
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(context.tr('wsimp_choose_other')),
        ),
        if (p.errorRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(context.tr('wsimp_error_rows_title'),
              style: const TextStyle(fontSize: AppText.bodyMedium, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final r in p.errorRows) _ErrorRowTile(row: r),
        ],
        const SizedBox(height: 12),
        Text(
          context.tr('wsimp_quota').replaceAll('{used}', '${p.quotaUsed}').replaceAll('{max}', '${p.quotaMax}'),
          style: TextStyle(fontSize: AppText.bodySmall, color: AppColors.sectionMuted),
        ),
      ],
    );
  }

  Widget _resultView(WholesaleImportResult r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(r.isPartial ? Icons.hourglass_bottom : Icons.check_circle_outline,
            size: 48, color: r.isPartial ? Colors.orange : Colors.green),
        const SizedBox(height: 8),
        Text(
          context.tr(r.isPartial ? 'wsimp_result_partial' : 'wsimp_result_done'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: AppText.bodyLarge, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          _CountChip(label: context.tr('wsimp_count_created'), value: r.created, color: Colors.green),
          _CountChip(label: context.tr('wsimp_count_updated'), value: r.updated),
          _CountChip(label: context.tr('wsimp_count_unchanged'), value: r.unchanged),
          _CountChip(label: context.tr('wsimp_count_errors'), value: r.failed, color: AppColors.error),
          if (r.pending > 0) _CountChip(label: context.tr('wsimp_count_pending'), value: r.pending, color: Colors.orange),
        ]),
        if (r.created + r.updated > 0) ...[
          const SizedBox(height: 8),
          Text(
            context.tr(r.autoApprove && r.updated == 0 ? 'wsimp_result_active' : 'wsimp_result_moderation'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.bodySmall, color: AppColors.sectionMuted),
          ),
        ],
        const SizedBox(height: 12),
        if (r.isPartial)
          FilledButton(
            key: const ValueKey('wsimp-continue'),
            onPressed: _busy ? null : _confirm,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(context.tr('wsimp_continue_btn')),
          )
        else
          FilledButton(
            key: const ValueKey('wsimp-done'),
            onPressed: () => Navigator.pop(context, _imported),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(context.tr('wsimp_done_btn')),
          ),
        if (r.errorRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(context.tr('wsimp_error_rows_title'),
              style: const TextStyle(fontSize: AppText.bodyMedium, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final e in r.errorRows) _ErrorRowTile(row: e),
        ],
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.number, required this.title, required this.body, required this.action});

  final int number;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              CircleAvatar(radius: 13, child: Text('$number', style: const TextStyle(fontSize: 13))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: AppText.bodyMedium, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(body, style: TextStyle(fontSize: AppText.bodySmall, color: AppColors.sectionMuted)),
            const SizedBox(height: 10),
            action,
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primaryText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$label: $value', style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    );
  }
}

class _ErrorRowTile extends StatelessWidget {
  const _ErrorRowTile({required this.row});

  final WholesaleImportRow row;

  @override
  Widget build(BuildContext context) {
    final head = context
        .tr('wsimp_row_n')
        .replaceAll('{n}', '${row.row}')
        .replaceAll('{sku}', row.sku.isEmpty ? '—' : row.sku);
    final msgs = (row.errors.isEmpty ? const ['WRITE_FAILED'] : row.errors)
        .map((c) => context.tr(wholesaleImportErrorKey(c)))
        .toSet()
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$head  ', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (row.price != null && row.title.isNotEmpty)
                TextSpan(text: '${row.title}, ${formatPrice(row.price!)}\n'),
              TextSpan(text: msgs, style: TextStyle(color: AppColors.error)),
            ])),
          ),
        ],
      ),
    );
  }
}

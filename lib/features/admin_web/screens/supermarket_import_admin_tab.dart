// «AVA Супермаркет» — Excel импорт (2-босқич, эга 2026-11-21). Улгуржи импорт оқими кўзгуси:
// шаблон → файл танлаш → текширув (сонлар + хато қаторлар) → тасдиқлаш → натижа. Текширув ва ёзув — серверда
// (`adminSupermarketImportTemplate|Preview|Confirm`). Матнлар — Кирилл (админ конвенцияси).

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/idempotency_keys.dart';
import '../services/admin_supermarket_service.dart';

typedef SmPickedFile = ({String name, Uint8List bytes});

class SmImportAdminTab extends StatefulWidget {
  const SmImportAdminTab({super.key, required this.service, this.pickFile, this.saveFile, this.newRequestId});

  final AdminSupermarketService service;

  /// Тест учун; бўлмаса — [FilePicker] (.xlsx).
  final Future<SmPickedFile?> Function()? pickFile;

  /// Тест учун; бўлмаса — [Share.shareXFiles] (вебда юклаб олиш).
  final Future<void> Function(String fileName, Uint8List bytes)? saveFile;
  final String Function()? newRequestId;

  @override
  State<SmImportAdminTab> createState() => _SmImportAdminTabState();
}

class _SmImportAdminTabState extends State<SmImportAdminTab> {
  bool _busy = false;
  String _busyText = '';
  String? _error;
  SmImportPreview? _preview;
  SmImportResult? _result;
  String _batchId = '';

  Future<void> _run(String busyText, Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _busyText = busyText;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      debugPrint('[SmImport] $busyText failed: $e');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _template() => _run('Шаблон тайёрланмоқда…', () async {
        final t = await widget.service.importTemplate();
        await (widget.saveFile ?? _share)(t.fileName, t.bytes);
      });

  static Future<void> _share(String name, Uint8List bytes) => Share.shareXFiles([
        XFile.fromData(bytes, name: name, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      ], fileNameOverrides: [name]);

  static Future<SmPickedFile?> _systemPick() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
    final f = picked?.files.single;
    final bytes = f?.bytes;
    if (f == null || bytes == null) return null;
    return (name: f.name, bytes: bytes);
  }

  Future<void> _pick() async {
    final f = await (widget.pickFile ?? _systemPick)();
    if (f == null || !mounted) return;
    if (f.bytes.length > kSmImportMaxBytes) {
      setState(() => _error = 'Файл жуда катта (5 МБ гача)');
      return;
    }
    // Бир файл = бир калит: таймаутдан кейин қайта юбориш иккинчи партия очмайди.
    final rid = (widget.newRequestId ?? newRequestId)();
    await _run('Текширилмоқда…', () async {
      final p = await widget.service.importPreview(fileName: f.name, bytes: f.bytes, clientRequestId: rid);
      if (!mounted) return;
      setState(() {
        _preview = p;
        _result = null;
        _batchId = p.batchId;
      });
    });
  }

  Future<void> _confirm() async {
    if (_batchId.isEmpty) return;
    await _run('Ёзилмоқда…', () async {
      final r = await widget.service.importConfirm(_batchId);
      if (mounted) setState(() => _result = r);
    });
  }

  void _reset() => setState(() {
        _preview = null;
        _result = null;
        _batchId = '';
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final r = _result;
    return ListView(
      key: const ValueKey('sm_import_tab'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Таклифларни Excel орқали юклаш', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (r != null)
          ..._resultView(r)
        else if (p != null)
          ..._previewView(p)
        else ...[
          _step(1, 'Шаблонни юклаб олинг', 'Устунлар ва кўрсатма шаблон ичида.',
              OutlinedButton.icon(
                key: const ValueKey('sm_import_template'),
                onPressed: _busy ? null : _template,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Шаблон'),
              )),
          _step(2, 'Тўлдирилган файлни танланг', '.xlsx, 5 МБ гача. Аввал текширилади — ҳеч нарса ёзилмайди.',
              FilledButton.icon(
                key: const ValueKey('sm_import_pick'),
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Файл танлаш'),
              )),
        ],
        if (_busy) ...[
          const SizedBox(height: 12),
          Row(children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 12),
            Text(_busyText, key: const ValueKey('sm_import_busy')),
          ]),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, key: const ValueKey('sm_import_error'), style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }

  Widget _step(int n, String title, String body, Widget action) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(radius: 14, child: Text('$n')),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(body),
              ]),
            ),
            const SizedBox(width: 12),
            action,
          ]),
        ),
      );

  List<Widget> _counts(Map<String, int> m) => [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in m.entries)
            Chip(key: ValueKey('sm_import_count_${e.key}'), label: Text('${e.key}: ${e.value}')),
        ]),
      ];

  List<Widget> _errors(List<SmImportRow> rows) => [
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Хато қаторлар (${rows.length}):', style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final row in rows.take(200))
            ListTile(
              key: ValueKey('sm_import_err_${row.row}'),
              dense: true,
              leading: Text('#${row.row}'),
              title: Text([row.key, row.title].where((s) => s.isNotEmpty).join(' · ')),
              subtitle: Text(row.errors.join(', '), style: const TextStyle(color: Colors.red)),
            ),
        ],
      ];

  List<Widget> _previewView(SmImportPreview p) => [
        const Text('Текширув натижаси (ҳали ҳеч нарса ёзилмади):'),
        const SizedBox(height: 8),
        ..._counts({
          'Жами': p.total,
          'Янги': p.create,
          'Ўзгаради': p.update,
          'Ўзгармайди': p.unchanged,
          'Хато': p.errors,
        }),
        ..._errors(p.errorRows),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, children: [
          FilledButton(
            key: const ValueKey('sm_import_confirm'),
            onPressed: _busy || !p.canConfirm ? null : _confirm,
            child: Text('Тасдиқлаш (${p.create + p.update} та ёзилади)'),
          ),
          OutlinedButton(key: const ValueKey('sm_import_reset'), onPressed: _busy ? null : _reset, child: const Text('Бошқа файл')),
        ]),
        if (!p.canConfirm) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Ёзиладиган янги ёки ўзгарган қатор йўқ.')),
      ];

  List<Widget> _resultView(SmImportResult r) => [
        Text(r.isPartial ? 'Қисман ёзилди — давом эттиринг' : 'Импорт тугади',
            key: const ValueKey('sm_import_result'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ..._counts({'Янги': r.created, 'Янгиланди': r.updated, 'Ўзгармади': r.unchanged, 'Хато': r.failed}),
        ..._errors(r.errorRows),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, children: [
          if (r.isPartial)
            FilledButton(key: const ValueKey('sm_import_continue'), onPressed: _busy ? null : _confirm, child: const Text('Давом эттириш')),
          OutlinedButton(key: const ValueKey('sm_import_new'), onPressed: _busy ? null : _reset, child: const Text('Янги импорт')),
        ]),
      ];
}

import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctionsException;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../admin_web/services/admin_supermarket_service.dart' show SmImportPreview, SmImportResult;
import '../data/supermarket_repository.dart';
import '../domain/sm_taxonomy.dart';
import 'sm_partner_service.dart';

/// «Супермаркетга чиқариш» (эга 2026-11-28, а-вариант) — тасдиқланган Улгуржи сотувчиси ЎЗ таклифларини AVA
/// Супермаркетга қўяди: қўлда (гуруҳ/нав/сифат/қадоқ/нарх/қолдиқ/ҳолат) ёки Excel. Харидор «AVA Супермаркет»ни
/// кўради; модерациядан ўтгач сотувга чиқади. Тўлов кейинга қолдирилган (матнда айтилади).
class SmPartnerScreen extends StatefulWidget {
  const SmPartnerScreen({super.key, this.service, this.loadTaxonomy, this.pickFile});

  final SmPartnerService? service;

  /// Тест учун; сукут — `taxonomy/supermarket`.
  final Future<SmTaxonomy> Function()? loadTaxonomy;
  final Future<({String name, Uint8List bytes})?> Function()? pickFile;

  @override
  State<SmPartnerScreen> createState() => _SmPartnerScreenState();
}

class _SmPartnerScreenState extends State<SmPartnerScreen> {
  late final SmPartnerService _svc = widget.service ?? SmPartnerService();
  SmTaxonomy _tx = SmTaxonomy.empty;
  List<SmPartnerOffer> _offers = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  SmImportPreview? _preview;
  SmImportResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tx = await (widget.loadTaxonomy ?? () => FirebaseSupermarketApi().loadTaxonomy())();
      final offers = await _svc.myOffers();
      if (!mounted) return;
      setState(() {
        _tx = tx;
        _offers = offers;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _err(Object e) {
    final lang = context.contentLang;
    if (e is FirebaseFunctionsException && e.details is Map) {
      final d = e.details as Map;
      final m = d['messages'];
      if (m is Map && m[lang] != null) return '${m[lang]}';
      if ('${d['code']}' == 'PARTNER_NOT_APPROVED') return context.tr('smp_not_approved');
    }
    return context.tr('smp_err_generic');
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([SmPartnerOffer? o]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => SmPartnerOfferDialog(service: _svc, taxonomy: _tx, initial: o),
    );
    if (saved == true) await _load();
  }

  Future<void> _template() => _run(() async {
        final t = await _svc.importTemplate();
        await Share.shareXFiles([
          XFile.fromData(t.bytes, name: t.fileName, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
        ], fileNameOverrides: [t.fileName]);
      });

  Future<void> _pickAndPreview() async {
    final f = await (widget.pickFile ?? _systemPick)();
    if (f == null || !mounted) return;
    final rid = 'smp${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 20)}';
    await _run(() async {
      final p = await _svc.importPreview(fileName: f.name, bytes: f.bytes, clientRequestId: rid);
      if (mounted) {
        setState(() {
          _preview = p;
          _result = null;
        });
      }
    });
  }

  Future<void> _confirm() => _run(() async {
        final r = await _svc.importConfirm(_preview!.batchId);
        if (!mounted) return;
        setState(() {
          _result = r;
          if (!r.isPartial) _preview = null;
        });
        await _load();
      });

  static Future<({String name, Uint8List bytes})?> _systemPick() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
    final f = picked?.files.single;
    final bytes = f?.bytes;
    if (f == null || bytes == null) return null;
    return (name: f.name, bytes: bytes);
  }

  String _modLabel(String m) => context.tr(switch (m) {
        'approved' => 'smp_mod_approved',
        'rejected' => 'smp_mod_rejected',
        _ => 'smp_mod_pending',
      });

  @override
  Widget build(BuildContext context) {
    final lang = context.contentLang;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('smp_title'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('smp_add'),
        onPressed: _busy || _loading ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(context.tr('smp_add')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  Text(context.tr('smp_intro'), key: const ValueKey('smp_intro'), style: TextStyle(color: Colors.grey.shade700)),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, key: const ValueKey('smp_error'), style: const TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.tr('smp_import_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Wrap(spacing: 8, children: [
                          TextButton.icon(
                            key: const ValueKey('smp_template'),
                            onPressed: _busy ? null : _template,
                            icon: const Icon(Icons.download),
                            label: Text(context.tr('smp_import_template')),
                          ),
                          TextButton.icon(
                            key: const ValueKey('smp_pick'),
                            onPressed: _busy ? null : _pickAndPreview,
                            icon: const Icon(Icons.upload_file),
                            label: Text(context.tr('smp_import_pick')),
                          ),
                        ]),
                        if (_preview != null) ...[
                          Text(
                            context
                                .tr('smp_import_preview')
                                .replaceAll('{create}', '${_preview!.create}')
                                .replaceAll('{update}', '${_preview!.update}')
                                .replaceAll('{errors}', '${_preview!.errors}'),
                            key: const ValueKey('smp_preview'),
                          ),
                          for (final r in _preview!.errorRows.take(20))
                            Text('#${r.row} ${r.key}: ${r.errors.join(', ')}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                          if (_preview!.canConfirm)
                            FilledButton(
                              key: const ValueKey('smp_confirm'),
                              onPressed: _busy ? null : _confirm,
                              child: Text(context.tr('smp_import_confirm')),
                            ),
                        ],
                        if (_result != null)
                          Text(
                            context
                                .tr('smp_import_done')
                                .replaceAll('{created}', '${_result!.created}')
                                .replaceAll('{updated}', '${_result!.updated}')
                                .replaceAll('{errors}', '${_result!.failed}'),
                            key: const ValueKey('smp_result'),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_offers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(context.tr('smp_empty'), key: const ValueKey('smp_empty'), textAlign: TextAlign.center),
                    ),
                  for (final o in _offers)
                    Card(
                      key: ValueKey('smp_offer_${o.sku}'),
                      child: ListTile(
                        title: Text(o.name),
                        subtitle: Text([
                          '${_tx.group(o.groupId)?.name(lang) ?? o.groupId} · ${formatMoney(o.price)} · ${o.stock ?? 0}',
                          _modLabel(o.moderation),
                          if (o.moderation == 'rejected' && o.moderationReason.isNotEmpty) o.moderationReason,
                        ].join('\n')),
                        isThreeLine: true,
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: _busy ? null : () => _edit(o),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Таклиф шакли (яратиш/таҳрирлаш). SKU — ҳамкорнинг ўз коди (ўзгармайди).
class SmPartnerOfferDialog extends StatefulWidget {
  const SmPartnerOfferDialog({super.key, required this.service, required this.taxonomy, this.initial});

  final SmPartnerService service;
  final SmTaxonomy taxonomy;
  final SmPartnerOffer? initial;

  @override
  State<SmPartnerOfferDialog> createState() => _SmPartnerOfferDialogState();
}

class _SmPartnerOfferDialogState extends State<SmPartnerOfferDialog> {
  late final SmPartnerOffer? _o = widget.initial;
  late final _sku = TextEditingController(text: _o?.sku ?? '');
  late String _group = _o?.groupId ?? '';
  late final _varId = TextEditingController(text: _o?.varietyId ?? '');
  late final Map<String, TextEditingController> _var = {
    for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) l: TextEditingController(text: _o?.varietyNames[l] ?? ''),
  };
  late final Map<String, TextEditingController> _q = {
    for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) l: TextEditingController(text: _o?.qualityNames[l] ?? ''),
  };
  late final _pack = TextEditingController(text: _o?.packLabel ?? '');
  late final _price = TextEditingController(text: _o == null ? '' : '${_o.price}');
  late final _stock = TextEditingController(text: _o?.stock == null ? '' : '${_o!.stock}');
  late String _status = _o?.partnerStatus ?? 'active';
  List<String> _problems = const [];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_sku, _varId, _pack, _price, _stock, ..._var.values, ..._q.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final r = smPartnerOfferFromForm(
      sku: _sku.text,
      groupId: _group,
      varietyId: _varId.text,
      varietyNames: {for (final e in _var.entries) e.key: e.value.text},
      qualityNames: {for (final e in _q.entries) e.key: e.value.text},
      packLabel: _pack.text,
      price: _price.text,
      stock: _stock.text,
      status: _status,
    );
    if (r.problems.isNotEmpty) return setState(() => _problems = r.problems);
    setState(() {
      _busy = true;
      _problems = const [];
      _error = null;
    });
    try {
      await widget.service.upsert(_sku.text.trim(), r.offer);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final lang = context.contentLang;
      var msg = context.tr('smp_err_generic');
      if (e is FirebaseFunctionsException && e.details is Map && (e.details as Map)['messages'] is Map) {
        msg = '${((e.details as Map)['messages'] as Map)[lang] ?? msg}';
      }
      if (mounted) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tf(String key, String label, TextEditingController c, {TextInputType? kb, bool enabled = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: ValueKey('smp_f_$key'),
          controller: c,
          enabled: enabled,
          keyboardType: kb,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lang = context.contentLang;
    final groups = [for (final c in widget.taxonomy.categories) ...c.groups];
    return AlertDialog(
      title: Text(context.tr(_o == null ? 'smp_add' : 'smp_edit')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _tf('sku', context.tr('smp_f_sku'), _sku, enabled: _o == null),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DropdownButtonFormField<String>(
                key: const ValueKey('smp_f_group'),
                initialValue: groups.any((g) => g.id == _group) ? _group : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('smp_f_group'), border: const OutlineInputBorder(), isDense: true),
                items: [for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name(lang)))],
                onChanged: (v) => setState(() => _group = v ?? ''),
              ),
            ),
            _tf('variety_id', context.tr('smp_f_variety_id'), _varId),
            _tf('variety_uz_Cyrl', '${context.tr('smp_f_variety')} (кирилл)', _var['uz_Cyrl']!),
            _tf('variety_uz_Latn', '${context.tr('smp_f_variety')} (lotin)', _var['uz_Latn']!),
            _tf('variety_ru', '${context.tr('smp_f_variety')} (рус)', _var['ru']!),
            _tf('quality_uz_Cyrl', '${context.tr('smp_f_quality')} (кирилл)', _q['uz_Cyrl']!),
            _tf('quality_uz_Latn', '${context.tr('smp_f_quality')} (lotin)', _q['uz_Latn']!),
            _tf('quality_ru', '${context.tr('smp_f_quality')} (рус)', _q['ru']!),
            _tf('pack', context.tr('smp_f_pack'), _pack),
            _tf('price', context.tr('smp_f_price'), _price, kb: TextInputType.number),
            _tf('stock', context.tr('smp_f_stock'), _stock, kb: const TextInputType.numberWithOptions(decimal: true)),
            DropdownButtonFormField<String>(
              key: const ValueKey('smp_f_status'),
              initialValue: _status,
              decoration: InputDecoration(labelText: context.tr('smp_f_status'), border: const OutlineInputBorder(), isDense: true),
              items: [
                for (final s in const ['active', 'out_of_stock', 'hidden'])
                  DropdownMenuItem(value: s, child: Text(context.tr('smp_status_$s'))),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            for (final p in _problems) Text(context.tr(p), style: const TextStyle(color: Colors.red, fontSize: 12)),
            if (_error != null) Text(_error!, key: const ValueKey('smp_f_error'), style: const TextStyle(color: Colors.red)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.tr('smp_cancel'))),
        FilledButton(key: const ValueKey('smp_f_save'), onPressed: _busy ? null : _save, child: Text(context.tr('smp_save'))),
      ],
    );
  }
}

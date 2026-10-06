// AVA LOGISTICS — админ: тариф версиялари (D-2/D-8) ва жўнатмалар (D-9).
//
// Ҳамма ёзув СЕРВЕРДА (europe-west1 callable'лар): `adminUpsertLogisticsTariff`
// (қоралама: валидация, фаол/эски версия ўзгармас), `adminActivateLogisticsTariff`
// (тўлиқ бўлмаган тариф фаол бўлмайди; эскиси retired; pointer),
// `adminPlanShipmentRoute` (маршрутни LEG'ларга бўлиш — фақат йўлга
// чиқмаган жўнатмада). Ҳар амал `logistics_audit`га тушади (41-банд).
// Клиент SDK билан ёзиш қоидада ЁПИҚ — экран фақат ўқийди ва чақиради.
//
// Тариф таҳрири — JSON (v1 admin): рақамлар эга қарори, экран уларни
// ўйлаб топмайди. `prices` бўш қоралама фаоллаштирилмайди (сервер).

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../demand_offer/data/demand_repository.dart' show kDemandCoreRegion;

class LogisticsAdminScreen extends StatefulWidget {
  const LogisticsAdminScreen({super.key});

  @override
  State<LogisticsAdminScreen> createState() => _LogisticsAdminScreenState();
}

class _LogisticsAdminScreenState extends State<LogisticsAdminScreen> {
  static const _serverKeys = [
    'status', 'updatedAt', 'updatedBy', 'createdAt',
    'activatedAt', 'activatedBy', 'retiredAt', 'retiredBy',
  ];
  static const _shipmentFilters = <String, String>{
    '': 'Ҳаммаси',
    'awaiting_payment': 'Тўлов кутилмоқда',
    'ready': 'Ижрочи қидирилмоқда',
    'in_transit': 'Йўлда',
    'delivered': 'Етказилди',
    'closed': 'Ёпилган',
    'cancelled': 'Бекор',
    'disputed': 'Низо',
    'lost': 'Йўқолган',
  };

  final _db = FirebaseFirestore.instance;
  int _tab = 0;
  String _filter = '';
  bool _busy = false;

  // ── Callable ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _call(String name, Map<String, dynamic> payload) async {
    setState(() => _busy = true);
    try {
      final res = await FirebaseFunctions.instanceFor(region: kDemandCoreRegion)
          .httpsCallable(name)
          .call<Object?>(payload);
      final d = res.data;
      return d is Map ? d.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final errors = details is Map ? details['errors'] : null;
      _snack(
        'Хато: ${e.message ?? e.code}'
        '${errors is List && errors.isNotEmpty ? '\n${errors.join('\n')}' : ''}',
        error: true,
      );
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? Colors.red.shade700 : null,
      duration: Duration(seconds: error ? 8 : 4),
      content: Text(text),
    ));
  }

  // ── Тариф ──────────────────────────────────────────────────────────

  Future<void> _editTariff(Map<String, dynamic>? base, {required int version}) async {
    final initial = <String, dynamic>{...?base}
      ..removeWhere((k, _) => _serverKeys.contains(k))
      ..['module'] = 'logistics'
      ..['version'] = version;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _JsonEditorDialog(
        title: 'Тариф v$version — қоралама',
        hint: 'Сақлангач, тўлиқ бўлса «Фаоллаштириш» очилади. `prices` бўш '
            'бўлса сервер фаол қилмайди (нархлар — эга қарори).',
        initial: const JsonEncoder.withIndent('  ').convert(initial),
      ),
    );
    if (text == null) return;
    Map<String, dynamic> parsed;
    try {
      parsed = (json.decode(text) as Map).map((k, v) => MapEntry(k.toString(), v));
    } catch (e) {
      _snack('JSON хато: $e', error: true);
      return;
    }
    final res = await _call('adminUpsertLogisticsTariff', {'tariff': parsed});
    if (res == null) return;
    final errs = (res['activationErrors'] as List?) ?? const [];
    _snack(errs.isEmpty
        ? 'Сақланди: v${res['version']} (қоралама) — фаоллаштиришга тайёр'
        : 'Сақланди (қоралама). Фаоллаштириш учун етишмайди:\n${errs.join('\n')}');
  }

  Future<void> _activate(int version) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('v$version фаоллаштирилсинми?'),
        content: const Text(
          'Эски фаол версия «retired» бўлади. Мавжуд буюртмалар ўз '
          'тариф версияси билан қолади (D-8), янгилари янги версияда.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Фаоллаштириш')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _call('adminActivateLogisticsTariff', {'version': version});
    if (res != null) {
      _snack('Фаол: v${res['version']}'
          '${res['previousVersion'] != null ? ' (аввалгиси v${res['previousVersion']} retired)' : ''}');
    }
  }

  // ── Маршрут ────────────────────────────────────────────────────────

  Future<void> _replan(String shipmentId, Map<String, dynamic> ship) async {
    Map<String, dynamic> pt(dynamic p) {
      final m = p is Map ? p : const {};
      return {'regionId': m['regionId'] ?? '', 'districtId': m['districtId'] ?? ''};
    }

    final template = [
      {'from': pt(ship['origin']), 'to': {'regionId': '', 'districtId': ''}},
      {'from': {'regionId': '', 'districtId': ''}, 'to': pt(ship['destination'])},
    ];
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _JsonEditorDialog(
        title: 'Маршрут — ${ship['trackingNumber'] ?? shipmentId}',
        hint: 'LEG рўйхати (1..6). Биринчи `from` = origin, охирги `to` = '
            'destination (сервер ўзи қўяди); оралиқ нуқталар уланган бўлиши '
            'керак. Ижрочи аллақачон олган LEG бўлса — рад.',
        initial: const JsonEncoder.withIndent('  ').convert(template),
        withReason: true,
      ),
    );
    if (text == null) return;
    final sep = text.indexOf('\n---REASON---\n');
    final legsText = sep < 0 ? text : text.substring(0, sep);
    final reason = sep < 0 ? '' : text.substring(sep + '\n---REASON---\n'.length).trim();
    List<dynamic> legs;
    try {
      legs = json.decode(legsText) as List<dynamic>;
    } catch (e) {
      _snack('JSON хато: $e', error: true);
      return;
    }
    final res = await _call('adminPlanShipmentRoute', {
      'shipmentId': shipmentId,
      'legs': legs,
      'reason': reason,
    });
    if (res != null) _snack('Маршрут v${res['version']}: ${res['legCount'] ?? legs.length} LEG');
  }

  Future<void> _showCustody(String shipmentId) async {
    final snap = await _db
        .collection('custody_events')
        .where('shipmentId', isEqualTo: shipmentId)
        .orderBy('timestamp')
        .get();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custody тарихи'),
        content: SizedBox(
          width: 520,
          child: snap.docs.isEmpty
              ? const Text('Ҳодиса йўқ')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in snap.docs)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          d.data()['kind'] == 'delivery' ? Icons.check_circle_outline : Icons.swap_horiz,
                        ),
                        title: Text(
                          '${d.data()['kind']}: '
                          '${(d.data()['from'] as Map?)?['kind']} ${(d.data()['from'] as Map?)?['id'] ?? ''} → '
                          '${(d.data()['to'] as Map?)?['kind']} ${(d.data()['to'] as Map?)?['id'] ?? ''}',
                        ),
                        subtitle: Text(
                          '${_fmt(d.data()['timestamp'])} · '
                          '${((d.data()['proof'] as Map?)?['conditionFlags'] as List?)?.join(', ') ?? ''} · '
                          'расм: ${((d.data()['proof'] as Map?)?['photoUrls'] as List?)?.length ?? 0}',
                        ),
                      ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ёпиш'))],
      ),
    );
  }

  static String _fmt(dynamic v) {
    DateTime? d;
    if (v is Timestamp) d = v.toDate();
    if (v is DateTime) d = v;
    if (d == null) return '';
    final l = d.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  // ── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Text('AVA Logistics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(width: 16),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Тариф'), icon: Icon(Icons.price_change_outlined)),
                  ButtonSegment(value: 1, label: Text('Жўнатмалар'), icon: Icon(Icons.local_post_office_outlined)),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const Spacer(),
              if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
        Expanded(child: _tab == 0 ? _tariffTab() : _shipmentsTab()),
      ],
    );
  }

  Widget _tariffTab() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('module_tariffs').doc('logistics').snapshots(),
      builder: (context, ptrSnap) {
        final active = (ptrSnap.data?.data()?['activeVersion'] as num?)?.toInt() ?? 0;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('module_tariffs').where('module', isEqualTo: 'logistics').snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Хато: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs.toList()
              ..sort((a, b) => ((b.data()['version'] as num?) ?? 0).compareTo((a.data()['version'] as num?) ?? 0));
            final latest = docs.isEmpty ? null : docs.first.data();
            final nextVersion = ((latest?['version'] as num?)?.toInt() ?? 0) + 1;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    Chip(
                      avatar: Icon(active > 0 ? Icons.check_circle : Icons.pause_circle_outline,
                          size: 18, color: active > 0 ? Colors.green : Colors.orange),
                      label: Text(active > 0 ? 'Фаол версия: v$active' : 'Фаол тариф ЙЎҚ — хизмат ишламайди'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _editTariff(latest, version: nextVersion),
                      icon: const Icon(Icons.add),
                      label: Text('Янги версия (v$nextVersion)'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (docs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Тариф версиялари йўқ. Қоралама: '
                      '`node functions_demand/tools/seed_logistics_tariff.js --write` '
                      'ёки «Янги версия».',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                for (final d in docs) _tariffTile(d.data(), active),
              ],
            );
          },
        );
      },
    );
  }

  Widget _tariffTile(Map<String, dynamic> t, int active) {
    final version = (t['version'] as num?)?.toInt() ?? 0;
    final status = (t['status'] ?? '').toString();
    final isDraft = status == 'draft';
    final prices = t['prices'];
    final priceCount = prices is Map ? prices.length : 0;
    final color = switch (status) {
      'active' => Colors.green,
      'draft' => Colors.orange,
      _ => Colors.grey,
    };
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text('v$version', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        title: Text('v$version · $status${version == active ? ' · ФАОЛ' : ''}'),
        subtitle: Text(
          'зоналар: ${(t['zones'] as List?)?.length ?? 0} · нарх жадваллари: $priceCount · '
          'divisor: ${t['volumetricDivisor']} · янгиланган: ${_fmt(t['updatedAt'])}'
          '${t['activatedAt'] != null ? ' · фаол: ${_fmt(t['activatedAt'])}' : ''}',
        ),
        trailing: Wrap(
          spacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => isDraft
                      ? _editTariff(t, version: version)
                      : showDialog<void>(
                          context: context,
                          builder: (_) => _JsonEditorDialog(
                            title: 'Тариф v$version — $status (ўзгармас)',
                            initial: const JsonEncoder.withIndent('  ').convert(
                              Map<String, dynamic>.from(t)..removeWhere((k, _) => _serverKeys.contains(k)),
                            ),
                            readOnly: true,
                          ),
                        ),
              icon: Icon(isDraft ? Icons.edit_outlined : Icons.visibility_outlined, size: 16),
              label: Text(isDraft ? 'Таҳрир' : 'Кўриш'),
            ),
            if (isDraft)
              FilledButton.icon(
                onPressed: _busy ? null : () => _activate(version),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Фаоллаштириш'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _shipmentsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              const Text('Ҳолат:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _filter,
                items: _shipmentFilters.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _filter = v ?? ''),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('shipments').orderBy('updatedAt', descending: true).limit(100).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Хато: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs
                  .where((d) => _filter.isEmpty || d.data()['status'] == _filter)
                  .toList();
              if (docs.isEmpty) {
                return Center(child: Text('Жўнатма йўқ', style: TextStyle(color: Colors.grey.shade600)));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _shipmentTile(docs[i].id, docs[i].data()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _shipmentTile(String id, Map<String, dynamic> s) {
    final status = (s['status'] ?? '').toString();
    final replannable = status == 'awaiting_payment' || status == 'ready';
    final cust = s['currentCustodian'] is Map ? s['currentCustodian'] as Map : const {};
    final price = (s['priceSnapshot'] is Map ? (s['priceSnapshot'] as Map)['customerPrice'] : null) ?? 0;
    return Card(
      child: ListTile(
        title: Text('${s['trackingNumber'] ?? id} · $status · ${s['paymentStatus'] ?? ''}'),
        subtitle: Text(
          'эгаси: ${s['ownerId']} · қўлида: ${cust['kind']} ${cust['id'] ?? ''} · '
          'LEG: ${s['legCount'] ?? 1} (маршрут v${s['routePlanVersion'] ?? 1}) · '
          'нарх: $price · янгиланган: ${_fmt(s['updatedAt'])}',
        ),
        trailing: Wrap(
          spacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: () => _showCustody(id),
              icon: const Icon(Icons.history, size: 16),
              label: const Text('Custody'),
            ),
            if (replannable)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _replan(id, s),
                icon: const Icon(Icons.alt_route, size: 16),
                label: const Text('Маршрут'),
              ),
          ],
        ),
      ),
    );
  }
}

/// JSON муҳаррири — тариф/маршрут учун (v1 admin).
class _JsonEditorDialog extends StatefulWidget {
  const _JsonEditorDialog({
    required this.title,
    required this.initial,
    this.hint,
    this.readOnly = false,
    this.withReason = false,
  });

  final String title;
  final String initial;
  final String? hint;
  final bool readOnly;

  /// Маршрут учун: сабаб (audit) алоҳида майдонда — натижа
  /// `json\n---REASON---\nsabab` шаклида қайтади.
  final bool withReason;

  @override
  State<_JsonEditorDialog> createState() => _JsonEditorDialogState();
}

class _JsonEditorDialogState extends State<_JsonEditorDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  final _reason = TextEditingController();
  String? _parseError;

  @override
  void dispose() {
    _ctrl.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _validate() {
    try {
      json.decode(_ctrl.text);
      setState(() => _parseError = null);
    } catch (e) {
      setState(() => _parseError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.hint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(widget.hint!, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ),
            SizedBox(
              height: 360,
              child: TextField(
                controller: _ctrl,
                readOnly: widget.readOnly,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) => _validate(),
              ),
            ),
            if (widget.withReason) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Сабаб (audit)', border: OutlineInputBorder()),
              ),
            ],
            if (_parseError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_parseError!, style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.readOnly ? 'Ёпиш' : 'Бекор')),
        if (!widget.readOnly)
          FilledButton(
            onPressed: _parseError != null
                ? null
                : () => Navigator.pop(
                      context,
                      widget.withReason ? '${_ctrl.text}\n---REASON---\n${_reason.text}' : _ctrl.text,
                    ),
            child: const Text('Сақлаш'),
          ),
      ],
    );
  }
}

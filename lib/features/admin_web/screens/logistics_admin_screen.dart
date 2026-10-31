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
import '../../logistics/domain/logistics_models.dart' show logisticsMoney;
import '../../logistics/domain/tariff_adjust.dart';
import '../services/admin_courier_payout_service.dart';
import '../services/admin_logistics_service.dart';
import '../utils/logistics_tariff_inputs.dart';
import '../widgets/logistics_loss_dialogs.dart';
import '../widgets/logistics_loss_list.dart';
import '../widgets/courier_service_fee_panel.dart';
import '../widgets/logistics_stage_panel.dart';
import '../widgets/region_zone_matrix_dialog.dart';

class LogisticsAdminScreen extends StatefulWidget {
  const LogisticsAdminScreen({super.key});

  @override
  State<LogisticsAdminScreen> createState() => _LogisticsAdminScreenState();
}

class _LogisticsAdminScreenState extends State<LogisticsAdminScreen> {
  static const _serverKeys = kLogisticsTariffServerKeys;
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
    'leg_problem': '⚠ LEG муддати тугаган',
  };

  final _db = FirebaseFirestore.instance;
  final _logistics = AdminLogisticsService();
  final _courierPayout = AdminCourierPayoutService();
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

  /// Нарх жадвали муҳаррири (зона × поғона, «ҳаммасини % га» тугмаси,
  /// ички улушлар). Фаол/эски версиядан — ЯНГИ қоралама (ўзгармаслик,
  /// 9-банд); қораламанинг ўзи — жойида.
  Future<void> _editPrices(
    Map<String, dynamic> base, {
    required int version,
    required bool asNewVersion,
  }) async {
    final initial = <String, dynamic>{...base}
      ..removeWhere((k, _) => _serverKeys.contains(k))
      ..['module'] = 'logistics'
      ..['version'] = version;
    final doc = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PriceGridDialog(base: initial, version: version, asNewVersion: asNewVersion),
    );
    if (doc == null) return;
    final res = await _call('adminUpsertLogisticsTariff', {'tariff': doc});
    if (res == null) return;
    final errs = (res['activationErrors'] as List?) ?? const [];
    _snack(errs.isEmpty
        ? 'Сақланди: v${res['version']} (қоралама) — фаоллаштиришга тайёр'
        : 'Сақланди (қоралама). Фаоллаштириш учун етишмайди:\n${errs.join('\n')}');
  }

  /// Вилоятлар матрицаси (14×14, юқори учбурчак, кўзгу) — фақат қоралама.
  Future<void> _editMatrix(Map<String, dynamic> t) async {
    setState(() => _busy = true);
    try {
      await editTariffRegionMatrix(context, tariff: t, service: _logistics);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                  ButtonSegment(value: 2, label: Text('Йўқолганлар'), icon: Icon(Icons.report_gmailerrorred_outlined)),
                  ButtonSegment(value: 3, label: Text('Босқич'), icon: Icon(Icons.tune)),
                  ButtonSegment(value: 4, label: Text('Курьер ҳақи'), icon: Icon(Icons.account_balance_wallet_outlined)),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const Spacer(),
              if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
        _serverSwitchBar(),
        Expanded(
          child: switch (_tab) {
            0 => _tariffTab(),
            1 => _shipmentsTab(),
            2 => LogisticsLossList(service: _logistics),
            3 => LogisticsStagePanel(service: _logistics),
            _ => CourierServiceFeePanel(service: _courierPayout),
          },
        ),
      ],
    );
  }

  /// Сервер калити — фақат кўрсатиш. Логистика CF'лари (quote/create/
  /// accept/handover, LEG push) `module_config/logistics_all`га қарайди;
  /// «Ҳудудлар ва хизматлар»даги `logistics` ҳолати эса фақат иловадаги
  /// плиткани бошқаради (бошқа ҳужжат). Аввал админ «Ёпиқ» қўйса ҳам
  /// сервер ишлашда давом этар ва буни ҳеч ерда кўрмасди. Калитни эга
  /// `functions_demand/tools/enable_module.js` билан бошқаради.
  Widget _serverSwitchBar() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('module_config').doc('logistics_all').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final d = snap.data!.data() ?? const <String, dynamic>{};
        // Сервер семантикаси (`functions_demand/core/config.js` resolveFlags):
        // enabled/push — фақат `true` бўлса; matching — `false` бўлмаса ёқиқ.
        String on(bool v) => v ? 'ёқиқ' : 'ўчиқ';
        final enabled = d['enabled'] == true;
        String flag(String key) => key == 'matchingEnabled'
            ? on(d[key] != false)
            : on(d[key] == true);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? Colors.green.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            snap.data!.exists
                ? 'Сервер калити (module_config/logistics_all): модул ${flag('enabled')} · '
                    'matching ${flag('matchingEnabled')} · push ${flag('pushEnabled')}. '
                    '«Ҳудудлар ва хизматлар» фақат иловадаги плиткани бошқаради.'
                : 'Сервер калити (module_config/logistics_all) йўқ — логистика CF\'лари ўчиқ.',
            style: const TextStyle(fontSize: 12),
          ),
        );
      },
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
            _latestVersion = (latest?['version'] as num?)?.toInt() ?? 0;
            final nextVersion = _latestVersion + 1;
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

  /// Фаол/эски версиядан янги қоралама рақами — рўйхатдаги энг каттасидан
  /// кейингиси (stream'даги ҳужжатлар `_latestVersion`да сақланади).
  int _nextVersionFrom(Map<String, dynamic> t, int active) =>
      (_latestVersion > 0 ? _latestVersion : ((t['version'] as num?)?.toInt() ?? active)) + 1;

  int _latestVersion = 0;

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
            FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () => _editPrices(
                        t,
                        version: isDraft ? version : (_nextVersionFrom(t, active)),
                        asNewVersion: !isDraft,
                      ),
              icon: const Icon(Icons.grid_on, size: 16),
              label: Text(isDraft ? 'Нархлар' : 'Нархлар → янги версия'),
            ),
            // Вилоятлар матрицаси (Ulgurji Q-6): фақат қораламада; бўш катак — бўш.
            if (isDraft)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _editMatrix(t),
                icon: const Icon(Icons.table_chart_outlined, size: 16),
                label: const Text('Матрица'),
              ),
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
            // «⚠ LEG муддати тугаган» — серверда сараланади: `legProblem.at`
            // бўйича тартиблаш фақат муаммоли жўнатмаларни қайтаради
            // (null/майдонсиз ҳужжатлар тушмайди; single-field индекс). Аввал
            // охирги 100 та янгиланган жўнатма ичидан қидириларди — 100 та
            // янги жўнатмадан кейин огоҳлантириш кўздан йўқоларди.
            stream: (_filter == 'leg_problem'
                    ? _db.collection('shipments').orderBy('legProblem.at', descending: true)
                    : _db.collection('shipments').orderBy('updatedAt', descending: true))
                .limit(100)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Хато: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs
                  .where((d) => _filter.isEmpty
                      || (_filter == 'leg_problem'
                          ? d.data()['legProblem'] != null
                          : d.data()['status'] == _filter))
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

  /// Muddati tugagan LEG (sweeper `legProblem` yozgan) — qayta ochish:
  /// matching qaytadan, payout/marshrut o'zgarmaydi, audit bilan.
  Future<void> _reactivateLeg(String shipmentId, String legId) async {
    final reason = await _askReason('LEG\'ни қайта очиш — сабаб (audit)');
    if (reason == null) return;
    final res = await _call('adminReactivateLeg', {'legId': legId, 'reason': reason});
    if (res != null) _snack('LEG қайта очилди: ${res['legId']} (ижрочилар: ${res['matchedBucket']})');
  }

  /// «Йўқолди» (D1): диалог чақирувни ўзи бажаради (`opId` диалогда), бу ерда
  /// фақат натижа хабари. Сервер рад этса — диалогда хато кўринади.
  Future<void> _markLost(String shipmentId, Map<String, dynamic> s) async {
    final res = await showMarkShipmentLostDialog(
      context,
      service: _logistics,
      shipmentId: shipmentId,
      label: (s['trackingNumber'] ?? shipmentId).toString(),
    );
    if (res == null) return;
    final value = res['goodsValue'];
    _snack(
      '${res['idempotent'] == true ? 'Аввал ҳам белгиланган. ' : ''}'
      'Йўқолган деб белгиланди${value is num ? ' · товар қиймати: ${logisticsMoney(value.toInt())} сўм' : ''}. '
      'Пул ҳисоби сервер томонидан бажарилади — «Йўқолганлар» табида кўринг.',
    );
  }

  Future<String?> _askReason(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Қисқа сабаб'),
          maxLength: 300,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Бекор')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Тасдиқлаш')),
        ],
      ),
    );
  }

  Widget _shipmentTile(String id, Map<String, dynamic> s) {
    final status = (s['status'] ?? '').toString();
    final replannable = status == 'awaiting_payment' || status == 'ready';
    final cust = s['currentCustodian'] is Map ? s['currentCustodian'] as Map : const {};
    final price = (s['priceSnapshot'] is Map ? (s['priceSnapshot'] as Map)['customerPrice'] : null) ?? 0;
    final rawProblem = s['legProblem'] is Map ? s['legProblem'] as Map : null;
    // Фақат ЖОРИЙ маршрутдаги LEG муаммоси: қайта режалангандан кейин эски
    // `legProblem` эски LEG'га ишора қилади — уни очиш етим LEG яратарди
    // (сервер ҳам `leg_superseded` билан рад этади). Бекор/етказилган
    // жўнатмада ҳам тугма маъносиз.
    final legIds = s['legIds'] is List ? s['legIds'] as List : const [];
    final problem = rawProblem != null &&
            legIds.contains(rawProblem['legId']) &&
            (status == 'ready' || status == 'in_transit')
        ? rawProblem
        : null;
    return Card(
      color: problem != null ? Colors.orange.shade50 : null,
      child: ListTile(
        title: Text('${s['trackingNumber'] ?? id} · $status · ${s['paymentStatus'] ?? ''}'),
        subtitle: Text(
          'эгаси: ${s['ownerId']} · қўлида: ${cust['kind']} ${cust['id'] ?? ''} · '
          'LEG: ${s['legCount'] ?? 1} (маршрут v${s['routePlanVersion'] ?? 1}) · '
          'нарх: $price · янгиланган: ${_fmt(s['updatedAt'])}'
          '${problem != null ? '\n⚠ LEG муддати тугаган: ${problem['legId']} (${_fmt(problem['at'])}) — ижрочи топилмади' : ''}',
        ),
        isThreeLine: problem != null,
        trailing: Wrap(
          spacing: 6,
          children: [
            if (problem != null)
              FilledButton.icon(
                onPressed: _busy ? null : () => _reactivateLeg(id, (problem['legId'] ?? '').toString()),
                icon: const Icon(Icons.replay, size: 16),
                label: const Text('LEG\'ни қайта очиш'),
              ),
            OutlinedButton.icon(
              onPressed: () => _showCustody(id),
              icon: const Icon(Icons.history, size: 16),
              label: const Text('Custody'),
            ),
            // Тугма фақат кўрсатма; рухсат (in_transit/disputed, ижрочи қўлида,
            // тўлов ҳолати) серверда текширилади (`adminMarkShipmentLost`).
            if ((status == 'in_transit' || status == 'disputed') && cust['kind'] == 'provider')
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _markLost(id, s),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                icon: const Icon(Icons.report_gmailerrorred_outlined, size: 16),
                label: const Text('Йўқолди'),
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

/// Нарх жадвали: зона × вазн поғонаси + охирги поғонадан ошган ҳар кг + ички
/// улушлар. «Ҳаммасини % га» — битта тугма (эга талаби, 2026-10-07):
/// фоиз (манфий = камайтириш), яхлитлаш қадами; натижа катакларда
/// кўринади, кейин «Сақлаш». Ҳисоб — `tariff_adjust.dart` (соф Dart,
/// тестланган); сервер яна текширади.
class _PriceGridDialog extends StatefulWidget {
  const _PriceGridDialog({
    required this.base,
    required this.version,
    required this.asNewVersion,
  });

  final Map<String, dynamic> base;
  final int version;
  final bool asNewVersion;

  @override
  State<_PriceGridDialog> createState() => _PriceGridDialogState();
}

class _PriceGridDialogState extends State<_PriceGridDialog> {
  static const _zones = ['ZONE_0', 'ZONE_1', 'ZONE_2', 'ZONE_3', 'ZONE_4', 'ZONE_5'];
  static const _legKeys = ['first_mile', 'line_haul', 'last_mile'];
  static const _legLabels = {'first_mile': 'Биринчи чақирим', 'line_haul': 'Асосий йўл', 'last_mile': 'Охирги чақирим'};

  late final List<int> _brackets;
  late final Map<String, List<TextEditingController>> _cells; // zone → [b0..bn, extraPerKg]
  late final TextEditingController _margin;
  late final TextEditingController _divisor;
  late final Map<String, TextEditingController> _legShare;
  final _pct = TextEditingController(text: '-10');
  int _step = 1000;
  String? _error;

  @override
  void initState() {
    super.initState();
    final wb = widget.base['weightBrackets'];
    _brackets = wb is List ? wb.map((v) => (v as num).toInt()).toList() : const [];
    final prices = widget.base['prices'] is Map ? widget.base['prices'] as Map : const {};
    _cells = {
      for (final z in _zones)
        z: [
          for (var i = 0; i < _brackets.length; i += 1)
            TextEditingController(text: _cellText(prices[z], i)),
          TextEditingController(text: _extraText(prices[z])),
        ],
    };
    final internal = widget.base['internal'] is Map ? widget.base['internal'] as Map : const {};
    final div = widget.base['volumetricDivisor'];
    _divisor = TextEditingController(text: div is num ? div.toInt().toString() : '');
    _margin = TextEditingController(
      text: internal['platformMarginBps'] is num ? bpsToPercentText((internal['platformMarginBps'] as num).toInt()) : '',
    );
    final share = internal['legShareBps'] is Map ? internal['legShareBps'] as Map : const {};
    _legShare = {
      for (final k in _legKeys)
        k: TextEditingController(text: share[k] is num ? bpsToPercentText((share[k] as num).toInt()) : ''),
    };
  }

  static String _cellText(Object? zone, int i) {
    if (zone is! Map) return '';
    final b = zone['brackets'];
    if (b is! List || i >= b.length) return '';
    return (b[i] as num?)?.toInt().toString() ?? '';
  }

  static String _extraText(Object? zone) {
    if (zone is! Map) return '';
    final v = zone['extraPerKg'];
    return v is num ? v.toInt().toString() : '';
  }

  @override
  void dispose() {
    for (final row in _cells.values) {
      for (final c in row) {
        c.dispose();
      }
    }
    _margin.dispose();
    _divisor.dispose();
    for (final c in _legShare.values) {
      c.dispose();
    }
    _pct.dispose();
    super.dispose();
  }

  int? _int(TextEditingController c) {
    final t = c.text.replaceAll(RegExp(r'\s'), '');
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  /// «Ҳаммасини % га» — фақат тўлдирилган катакларга.
  void _applyPercent() {
    final bps = percentTextToBps(_pct.text);
    if (bps == null) {
      setState(() => _error = 'Фоиз нотўғри (масалан −10 ёки 7,5)');
      return;
    }
    for (final row in _cells.values) {
      for (var i = 0; i < row.length; i += 1) {
        final v = _int(row[i]);
        if (v == null) continue;
        final isExtra = i == row.length - 1;
        row[i].text = (isExtra
                ? adjustPrice(v, percentBps: bps, step: _step)
                : adjustBracketPrice(v, percentBps: bps, step: _step))
            .toString();
      }
    }
    setState(() => _error = null);
  }

  Map<String, dynamic>? _buildDoc() {
    final prices = <String, dynamic>{};
    for (final z in _zones) {
      final row = _cells[z]!;
      final vals = [for (var i = 0; i < _brackets.length; i += 1) _int(row[i])];
      final filled = vals.where((v) => v != null).length;
      if (filled == 0) continue;
      if (filled != _brackets.length || vals.any((v) => v! <= 0)) {
        _error = '$z: ҳамма поғона мусбат бутун сўм бўлиши керак (ёки қатор тўлиқ бўш)';
        return null;
      }
      // Бўш — «ҳали берилмаган» (null): сервер фаоллаштиришни блоклайди.
      // 0 га айлантирилмайди — акс ҳолда оғир посилка жимгина охирги
      // поғона нархида кетарди.
      final extra = _int(row.last);
      if (extra != null && extra < 0) {
        _error = '$z: ${_kgLabel(_brackets.last)} кг дан ошган ҳар кг нархи манфий бўлмайди';
        return null;
      }
      prices[z] = {'brackets': vals.cast<int>(), 'extraPerKg': extra};
    }
    final internal = <String, dynamic>{};
    final mBps = _margin.text.trim().isEmpty ? null : percentTextToBps(_margin.text);
    if (_margin.text.trim().isNotEmpty && (mBps == null || mBps < 0 || mBps > 10000)) {
      _error = 'Платформа улуши 0..100 % бўлиши керак';
      return null;
    }
    internal['platformMarginBps'] = mBps;
    final anyShare = _legShare.values.any((c) => c.text.trim().isNotEmpty);
    if (anyShare) {
      final share = <String, int>{};
      var sum = 0;
      for (final k in _legKeys) {
        final b = percentTextToBps(_legShare[k]!.text);
        if (b == null || b < 0 || b > 10000) {
          _error = '${_legLabels[k]}: 0..100 % бўлиши керак';
          return null;
        }
        share[k] = b;
        sum += b;
      }
      if (sum != 10000) {
        _error = 'LEG улушлари йиғиндиси 100 % бўлиши керак (ҳозир ${bpsToPercentText(sum)} %)';
        return null;
      }
      internal['legShareBps'] = share;
    } else {
      internal['legShareBps'] = null;
    }
    final divisor = parseVolumetricDivisor(_divisor.text);
    if (divisor.error != null) {
      _error = divisor.error;
      return null;
    }
    return {
      ...widget.base,
      'version': widget.version,
      // Бўш майдон — ҳужжатдаги қиймат ўзгармайди (ўйлаб топилмайди).
      if (divisor.value != null) 'volumetricDivisor': divisor.value,
      'prices': prices,
      'internal': internal,
    };
  }

  void _save() {
    final doc = _buildDoc();
    if (doc == null) {
      setState(() {});
      return;
    }
    Navigator.pop(context, doc);
  }

  static String _kgLabel(int grams) =>
      grams % 1000 == 0 ? (grams ~/ 1000).toString() : (grams / 1000).toStringAsFixed(1);

  String _bracketLabel(int i) => '≤${_kgLabel(_brackets[i])} кг';

  @override
  Widget build(BuildContext context) {
    final cellStyle = const TextStyle(fontSize: 12);
    InputDecoration deco([String? label]) => InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          border: const OutlineInputBorder(),
        );
    return AlertDialog(
      title: Text(widget.asNewVersion ? 'Нархлар → янги қоралама v${widget.version}' : 'Нархлар — қоралама v${widget.version}'),
      content: SizedBox(
        width: 860,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Битта тугма: ҳаммасини % га ──
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    const Text('Барча нархларни', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _pct,
                        decoration: deco('% га'),
                        style: cellStyle,
                        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('яхлитлаш:'),
                    const SizedBox(width: 6),
                    DropdownButton<int>(
                      value: _step,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1 сўм')),
                        DropdownMenuItem(value: 100, child: Text('100 сўм')),
                        DropdownMenuItem(value: 1000, child: Text('1 000 сўм')),
                      ],
                      onChanged: (v) => setState(() => _step = v ?? _step),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _applyPercent,
                      icon: const Icon(Icons.percent, size: 16),
                      label: const Text('Қўллаш'),
                    ),
                    const Spacer(),
                    Text(
                      'манфий = камайтириш · сақланмагунча ҳеч нарса ўзгармайди',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ── Жадвал ──
              Table(
                defaultColumnWidth: const FlexColumnWidth(),
                columnWidths: const {0: FixedColumnWidth(84)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: [
                      const Padding(padding: EdgeInsets.all(4), child: Text('Зона', style: TextStyle(fontWeight: FontWeight.w700))),
                      for (var i = 0; i < _brackets.length; i += 1)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(_bracketLabel(i), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          _brackets.isEmpty
                              ? '+1 кг'
                              : '+1 кг (${_kgLabel(_brackets.last)} кг дан ошса, ҳар бошланган кг)',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  for (final z in _zones)
                    TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(4), child: Text(z, style: const TextStyle(fontWeight: FontWeight.w600))),
                        for (final c in _cells[z]!)
                          Padding(
                            padding: const EdgeInsets.all(3),
                            child: TextField(
                              controller: c,
                              decoration: deco(),
                              style: cellStyle,
                              textAlign: TextAlign.right,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Бутун сўм. Қатор тўлиқ бўш бўлса — шу зонага нарх йўқ (матритсада ишлатилса фаоллашмайди). '
                '«+1 кг» бўш бўлса — оғир посилка нархи йўқ, фаоллаштириб бўлмайди; 0 — қўшимча ҳақ олинмайди.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),
              // ── Ҳажмий вазн бўлувчиси (12-банд; қиймат — эга қарори) ──
              const Text('Ҳажмий вазн', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _divisor,
                      decoration: deco('Бўлувчи (У×Э×Б / бўлувчи)'),
                      style: cellStyle,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Мусбат бутун сон. Бўш қолса — ҳужжатдаги қиймат ўзгармайди. '
                      'Чегаравий вазн = max(ҳақиқий, ҳажмий).',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // ── Ички улушлар (14-банд: мижозга кўрсатилмайди) ──
              const Text('Ички тақсимот (мижозга кўринмайди)', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(width: 150, child: TextField(controller: _margin, decoration: deco('Платформа улуши, %'), style: cellStyle)),
                  const SizedBox(width: 10),
                  for (final k in _legKeys) ...[
                    SizedBox(width: 150, child: TextField(controller: _legShare[k], decoration: deco('${_legLabels[k]}, %'), style: cellStyle)),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'LEG улушлари йиғиндиси 100 %. Бўш қолса — фаоллаштириб бўлмайди (сервер талаб қилади).',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          onPressed: _save,
          child: Text(widget.asNewVersion ? 'Янги қоралама сифатида сақлаш' : 'Сақлаш'),
        ),
      ],
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

// «AVA Супермаркет» — Ҳамкорларга тўлов (эга 2026-11-28; матнлар — Кирилл, админ конвенцияси).
// Созлама (босқич + комиссия, версияли), ҳамкорлар бўйича қарз (ledger баланси), «Тўланди» белгиси (нақд / банк / offset),
// тескари ёзув, кутилаётганлар навбати ва қайта ҳисоблаш. Пул ТИЗИМДАН ТАШҚАРИДА ўтказилади — бу ерда фақат белги.
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../services/admin_sm_partner_payout_service.dart';

class SmPartnerPayoutsAdminTab extends StatefulWidget {
  const SmPartnerPayoutsAdminTab({super.key, this.service, this.today, this.newRequestId});
  final AdminSmPartnerPayoutService? service;

  /// Тест учун (Тошкент санаси `yyyy-MM-dd`).
  final String Function()? today;
  final String Function()? newRequestId;

  @override
  State<SmPartnerPayoutsAdminTab> createState() => _SmPartnerPayoutsAdminTabState();
}

class _SmPartnerPayoutsAdminTabState extends State<SmPartnerPayoutsAdminTab> {
  late final AdminSmPartnerPayoutService _svc = widget.service ?? AdminSmPartnerPayoutService();
  SmPpList? _list;
  SmPpList? _detail;
  String? _selected;
  final Set<String> _checked = {};
  bool _busy = false;
  String? _msg;
  String _stage = 'off';
  final _bp = TextEditingController();
  final _reason = TextEditingController();
  late final _from = TextEditingController(text: _today());
  late final _to = TextEditingController(text: _today());

  String _today() =>
      widget.today?.call() ?? DateTime.now().toUtc().add(const Duration(hours: 5)).toIso8601String().substring(0, 10);
  String _rid() => widget.newRequestId?.call() ?? 'smpp${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 20)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_bp, _reason, _from, _to]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await _svc.list();
      final d = _selected == null ? null : await _svc.list(partnerKey: _selected);
      if (!mounted) return;
      setState(() {
        _list = l;
        _detail = d;
        _stage = l.settings.stage;
        _bp.text = l.settings.commissionBp == null ? '' : smBpToPercent(l.settings.commissionBp!);
        _checked.removeWhere((id) => !(d?.payables.any((p) => p.payableId == id && p.payable) ?? false));
      });
    } catch (e) {
      if (mounted) setState(() => _msg = 'Юклаб бўлмади: $e');
    }
  }

  Future<void> _do(Future<void> Function() job, String? ok) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await job();
      if (mounted && ok != null) setState(() => _msg = ok);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _msg = 'Хато: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSettings() async {
    final raw = _bp.text.trim();
    final bp = raw.isEmpty ? null : smPercentTextToBp(raw);
    if (raw.isNotEmpty && bp == null) return setState(() => _msg = 'Комиссия: 0–100 %, кўпи билан 2 каср (масалан 12.5)');
    if (_reason.text.trim().length < 3) return setState(() => _msg = 'Сабаб ёзинг (камида 3 белги)');
    await _do(() => _svc.saveSettings(stage: _stage, commissionBp: bp, reason: _reason.text.trim()), 'Созлама сақланди');
  }

  Future<void> _select(String key) async {
    setState(() {
      _selected = key;
      _checked.clear();
    });
    await _load();
  }

  Future<String?> _ask(String title, {String label = 'Сабаб'}) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(key: const ValueKey('smpp_ask_field'), controller: ctl, autofocus: true, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
          FilledButton(key: const ValueKey('smpp_ask_ok'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Тасдиқлаш')),
        ],
      ),
    );
    // Контроллер бу ерда dispose қилинмайди: диалог ёпилиш анимацияси уни ҳали ишлатади (мавжуд табларда ҳам шундай).
    return ok == true ? ctl.text.trim() : null;
  }

  Future<void> _markPaid() async {
    final d = _detail;
    if (d == null || _selected == null || _checked.isEmpty) return;
    final rows = d.payables.where((p) => _checked.contains(p.payableId)).toList();
    final sum = rows.fold<int>(0, (a, p) => a + (p.amount ?? 0));
    final rid = _rid();
    var method = 'cash';
    final ref = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Тўланди: ${formatMoney(sum)} (${rows.length} та)'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Пулни ҳамкорга тизимдан ТАШҚАРИДА (нақд ёки банк) ўтказганингиздан кейин белгиланг.'),
            DropdownButton<String>(
              key: const ValueKey('smpp_method'),
              value: method,
              isExpanded: true,
              items: [for (final m in const ['cash', 'bank_transfer', 'offset']) DropdownMenuItem(value: m, child: Text(smPpMethodText(m)))],
              onChanged: (v) => setD(() => method = v ?? method),
            ),
            TextField(
              key: const ValueKey('smpp_reference'),
              controller: ref,
              decoration: const InputDecoration(labelText: 'Ўтказма рақами / изоҳ (банк учун шарт)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
            FilledButton(key: const ValueKey('smpp_paid_ok'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Тўланди')),
          ],
        ),
      ),
    );
    final reference = ref.text.trim();
    if (ok != true) return;
    if (method == 'bank_transfer' && reference.length < 3) return setState(() => _msg = 'Банк ўтказмаси рақамини ёзинг');
    await _do(
      () => _svc.markPaid(partnerKey: _selected!, payableIds: rows.map((p) => p.payableId).toList(), method: method, clientRequestId: rid, reference: reference),
      'Тўланди деб белгиланди: ${formatMoney(sum)}',
    );
  }

  Future<void> _reverse(SmPpPayable p) async {
    final r = await _ask(p.status == 'paid' ? 'Тўланган ёзувни қайтариш (ҳамкор AVA\'га қарздор бўлади)' : 'Қарзни қайтариш');
    if (r == null) return;
    if (r.length < 3) return setState(() => _msg = 'Сабаб ёзинг (камида 3 белги)');
    await _do(() => _svc.reverse(p.payableId, r), 'Қайтарилди');
  }

  Future<void> _recompute() => _do(() async {
        final r = await _svc.recompute(from: _from.text.trim(), to: _to.text.trim());
        if (mounted) {
          setState(() => _msg = 'Қайта ҳисоб: буюртма ${r['orders']}, янги ${r['accrued']}, кутилмоқда ${r['blocked']}, хато ${r['errors']}');
        }
      }, null);

  Widget _settingsCard(SmPpSettings s) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Созлама (v${s.version})', style: const TextStyle(fontWeight: FontWeight.w700)),
            const Text(
              'Комиссия — AVA улуши (ҳамкор нархидан, %). Белгиланмаса қарз ҳисобланмайди ва буюртма «кутилмоқда» бўлади. '
              'Босқич: off — ҳисоб йўқ; internal — фақат админ кўради; public — ҳамкор ҳам ўз балансини кўради.',
              style: TextStyle(color: Colors.black54),
            ),
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<String>(
                key: const ValueKey('smpp_stage'),
                value: _stage,
                items: const [
                  DropdownMenuItem(value: 'off', child: Text('off — ўчиқ')),
                  DropdownMenuItem(value: 'internal', child: Text('internal — фақат админ')),
                  DropdownMenuItem(value: 'public', child: Text('public — ҳамкор ҳам')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _stage = v ?? _stage),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  key: const ValueKey('smpp_bp'),
                  controller: _bp,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Комиссия, %', hintText: 'белгиланмаган'),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(key: const ValueKey('smpp_reason'), controller: _reason, decoration: const InputDecoration(labelText: 'Сабаб (аудит учун)')),
              ),
              FilledButton(key: const ValueKey('smpp_save'), onPressed: _busy ? null : _saveSettings, child: const Text('Сақлаш')),
            ]),
            if (s.commissionBp == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Комиссия белгиланмаган — қарзлар ҳисобланмайди.', key: ValueKey('smpp_rule_missing'), style: TextStyle(color: Colors.orange)),
              ),
          ]),
        ),
      );

  Widget _partnerCard(SmPpPartner p) => Card(
        key: ValueKey('smpp_partner_${p.partnerKey}'),
        color: _selected == p.partnerKey ? Colors.orange.shade50 : null,
        child: ListTile(
          onTap: _busy ? null : () => _select(p.partnerKey),
          title: Text(p.companyName.isEmpty ? p.partnerKey : p.companyName),
          subtitle: Text([
            'Ҳисобланган ${formatMoney(p.accruedTotal)} · тўланган ${formatMoney(p.paidTotal)}'
                '${p.offsetTotal > 0 ? ' · offset ${formatMoney(p.offsetTotal)}' : ''}'
                '${p.reversedTotal > 0 ? ' · қайтарилган ${formatMoney(p.reversedTotal)}' : ''}',
            'Очиқ ${p.openCount} · кутилмоқда ${p.blockedCount}${p.sellerId == null ? '' : ' · ${p.sellerId}'}',
          ].join('\n')),
          isThreeLine: true,
          trailing: Text(
            formatMoney(p.balance),
            key: ValueKey('smpp_balance_${p.partnerKey}'),
            style: TextStyle(fontWeight: FontWeight.w700, color: p.balance < 0 ? Colors.red : null),
          ),
        ),
      );

  Widget _payableTile(SmPpPayable p) => CheckboxListTile(
        key: ValueKey('smpp_row_${p.payableId}'),
        value: _checked.contains(p.payableId),
        onChanged: !p.payable || _busy ? null : (v) => setState(() => v == true ? _checked.add(p.payableId) : _checked.remove(p.payableId)),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        title: Text('${p.orderId} · ${p.slotDate} · ${smPpStatusText(p.status)}${p.clawback ? ' (clawback)' : ''}'),
        subtitle: Text([
          if (p.amount != null)
            'Маҳсулот ${formatMoney(p.goodsBasis)} − ${p.commissionBp == null ? '' : '${smBpToPercent(p.commissionBp!)} % '}${formatMoney(p.commission ?? 0)} = ${formatMoney(p.amount!)}'
          else
            'Маҳсулот ${formatMoney(p.goodsBasis)}',
          if (p.blockReason != null) smPpBlockReasonText(p.blockReason),
          if (p.method != null) smPpMethodText(p.method),
          if (p.reverseReason != null) 'Сабаб: ${p.reverseReason}',
        ].join('\n')),
        secondary: p.reversible
            ? IconButton(
                key: ValueKey('smpp_reverse_${p.payableId}'),
                tooltip: 'Қайтариш',
                icon: const Icon(Icons.undo),
                onPressed: _busy ? null : () => _reverse(p),
              )
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final l = _list;
    if (l == null && _msg == null) return const Center(child: CircularProgressIndicator());
    final d = _detail;
    final sum = d == null ? 0 : d.payables.where((p) => _checked.contains(p.payableId)).fold<int>(0, (a, p) => a + (p.amount ?? 0));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'Ҳамкор нархи = мижоз нархи (каталог). Буюртма етказилганда ҳамкор қарзи ledger\'га ёзилади; тўловни админ тизимдан '
          'ташқарида ўтказиб, шу ерда белгилайди. Пул автоматик ўтказилмайди.',
          style: TextStyle(color: Colors.black54),
        ),
        if (_msg != null) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(_msg!, key: const ValueKey('smpp_msg'))),
        if (l != null) ...[
          _settingsCard(l.settings),
          const SizedBox(height: 8),
          Text('Ҳамкорлар (${l.partners.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (l.partners.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Ҳали ёзув йўқ', key: ValueKey('smpp_empty'))),
          for (final p in l.partners) _partnerCard(p),
          if (d != null && _selected != null) ...[
            const Divider(height: 24),
            Row(children: [
              Expanded(child: Text('Ёзувлар (${d.payables.length})', style: const TextStyle(fontWeight: FontWeight.w700))),
              FilledButton(
                key: const ValueKey('smpp_mark_paid'),
                onPressed: _busy || _checked.isEmpty ? null : _markPaid,
                child: Text('Тўланди деб белгилаш${_checked.isEmpty ? '' : ' · ${formatMoney(sum)}'}'),
              ),
            ]),
            for (final p in d.payables) _payableTile(p),
            if (d.payments.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Тўловлар', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final pay in d.payments)
                Text('${formatMoney(pay.amount)} · ${smPpMethodText(pay.method)} · ${pay.count} та${pay.reference.isEmpty ? '' : ' · ${pay.reference}'}'),
            ],
          ],
          const Divider(height: 24),
          Text('Кутилаётганлар (${l.blocked.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final b in l.blocked)
            ListTile(
              key: ValueKey('smpp_blocked_${b.payableId}'),
              dense: true,
              title: Text('${b.companyName.isEmpty ? b.partnerKey : b.companyName} · ${b.orderId} · ${formatMoney(b.goodsBasis)}'),
              subtitle: Text(smPpBlockReasonText(b.blockReason)),
            ),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 130, child: TextField(key: const ValueKey('smpp_from'), controller: _from, decoration: const InputDecoration(labelText: 'Сана, дан'))),
            SizedBox(width: 130, child: TextField(key: const ValueKey('smpp_to'), controller: _to, decoration: const InputDecoration(labelText: 'гача'))),
            OutlinedButton(
              key: const ValueKey('smpp_recompute'),
              onPressed: _busy || l.settings.stage == 'off' ? null : _recompute,
              child: const Text('Қайта ҳисоблаш (≤31 кун)'),
            ),
          ]),
        ],
      ],
    );
  }
}

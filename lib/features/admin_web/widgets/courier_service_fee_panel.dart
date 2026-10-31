// AVA Logistics → «Курьер ҳақи»: курьер ХИЗМАТ ҲАҚИ (эга қарори 2026-10-31).
//
// Курьер LEG учун ишлаб топган ҳақ АВТОМАТИК AVA ҳамёнига тушади; тўлов
// пайтида шу фоиз (тарифдаги AVA улушига ҚЎШИМЧА) ушланади. Ўқиш ва ёзув —
// фақат callable (`adminGetCourierServiceFee` / `adminSetCourierServiceFee`,
// default, us-central1); версия, тарих, admin_audit — серверда (41-банд).
// «Курьер вазифалари»даги «Курьер ҳақи, %» (гилам/сут вазифа улуши) — БОШҚА созлама.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../logistics/domain/logistics_models.dart' show logisticsMoney;
import '../../logistics/domain/tariff_adjust.dart' show bpsToPercentText;
import '../services/admin_callable.dart';
import '../services/admin_courier_payout_service.dart';
import '../utils/courier_service_fee_admin.dart';
import 'admin_reason_dialog.dart';

final _dtFmt = DateFormat('dd.MM.yyyy HH:mm');

class CourierServiceFeePanel extends StatefulWidget {
  const CourierServiceFeePanel({super.key, required this.service});

  final AdminCourierPayoutService service;

  @override
  State<CourierServiceFeePanel> createState() => _CourierServiceFeePanelState();
}

class _CourierServiceFeePanelState extends State<CourierServiceFeePanel> {
  final _pct = TextEditingController();
  CourierServiceFeeState _cur = const CourierServiceFeeState();
  bool _loading = true;
  bool _loadedOnce = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pct.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.service.getServiceFee();
      _pct.text = s.percentText;
      if (mounted) setState(() => _cur = s);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorText(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red.shade700 : null,
      duration: Duration(seconds: error ? 8 : 4),
    ));
  }

  Future<void> _saveFee() async {
    final plan = planCourierFeeChange(currentBps: _cur.valid ? _cur.feeBps : null, text: _pct.text);
    if (plan.error != null) {
      _snack(plan.error!, error: true);
      return;
    }
    if (!plan.changed && _cur.configured) {
      _snack('Ўзгариш йўқ');
      return;
    }
    final ex = courierFeeExample(plan.bps!);
    final reason = await showAdminReasonDialog(
      context,
      title: 'Курьер хизмат ҳақи',
      message: 'Янги қиймат: ${bpsToPercentText(plan.bps!)} %.\n'
          'Мисол: ${logisticsMoney(ex.gross)} сўм → ҳақ ${logisticsMoney(ex.fee)} → ҳамёнга ${logisticsMoney(ex.net)} сўм.\n'
          'Шу заҳоти КЕЙИНГИ тўловларга қўлланади; аввалги тўловлар ўзгармайди.',
    );
    if (reason == null || !mounted) return;
    await _submit(() => widget.service.setServiceFee(feeBps: plan.bps, reason: reason));
  }

  Future<void> _toggleAuto(bool next) async {
    final reason = await showAdminReasonDialog(
      context,
      title: next ? 'Авто-тўловни ёқиш' : 'Авто-тўловни ўчириш',
      message: next
          ? 'Кутилаётган тўловлар 15 дақиқа ичида (reconcile) ҳамёнларга тушади.'
          : 'Курьер ҳақи ҳамёнга ТУШМАЙДИ — қарз сақланади, қайта ёқилганда тўланади.',
    );
    if (reason == null || !mounted) return;
    await _submit(() => widget.service.setServiceFee(autoPayoutEnabled: next, reason: reason));
  }

  Future<void> _submit(Future<Map<String, dynamic>> Function() run) async {
    setState(() => _saving = true);
    try {
      final res = await run();
      _snack(res['unchanged'] == true ? 'Ўзгариш йўқ (сервер)' : 'Сақланди: v${res['feeVersion']}');
      await _load();
    } catch (e) {
      _snack('Хато: ${adminErrorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _when(int? ms) => ms == null ? '—' : _dtFmt.format(DateTime.fromMillisecondsSinceEpoch(ms));

  @override
  Widget build(BuildContext context) {
    if (_loading && !_loadedOnce) return const Center(child: CircularProgressIndicator());
    final plan = planCourierFeeChange(currentBps: _cur.feeBps, text: _pct.text);
    final ex = plan.bps == null ? null : courierFeeExample(plan.bps!);
    final grey = TextStyle(fontSize: 12.5, color: Colors.grey.shade700);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(child: Text('Хато: $_error', style: TextStyle(color: Colors.red.shade700))),
              TextButton(onPressed: _load, child: const Text('Қайта')),
            ]),
          ),
        const Text('Курьер хизмат ҳақи', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          'Курьер LEG учун ишлаб топган ҳақ АВТОМАТИК AVA ҳамёнига тушади; тўлов пайтида шу фоиз '
          '(тарифдаги AVA улушига қўшимча) ушланади. Курьер пулни ҳамёндан ечиш орқали олади.',
          style: grey,
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _cur.valid
                      ? 'Ҳозир: ${bpsToPercentText(_cur.feeBps ?? 0)} %'
                          '${_cur.configured ? ' · v${_cur.feeVersion}' : ' · созланмаган (0 %)'}'
                          '${_cur.updatedBy.isNotEmpty ? ' · ${_cur.updatedBy}' : ''}'
                          '${_cur.updatedAtMs != null ? ' · ${_when(_cur.updatedAtMs)}' : ''}'
                      : '⚠ Сервердаги қиймат бузуқ — тўловлар тўхтаган. Янги фоизни сақланг.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _cur.valid ? null : Colors.red.shade700,
                  ),
                ),
                if (_cur.reason.isNotEmpty) Text('Сабаб: ${_cur.reason}', style: grey),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      child: TextField(
                        key: const ValueKey('courierFeePct'),
                        controller: _pct,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        decoration: const InputDecoration(
                          labelText: 'Хизмат ҳақи, % (0..50)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveFee,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Сақлаш'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  ex != null
                      ? 'Мисол: ${logisticsMoney(ex.gross)} сўм ишлаб топилди → хизмат ҳақи '
                          '${logisticsMoney(ex.fee)} сўм → ҳамёнга ${logisticsMoney(ex.net)} сўм'
                      : (plan.error ?? ''),
                  key: const ValueKey('courierFeeExample'),
                  style: TextStyle(color: ex != null ? Colors.green.shade800 : Colors.red.shade700),
                ),
                const SizedBox(height: 4),
                Text('Ҳақ бутун сўмга юқорига яхлитланади (сервер ҳисоблайди).', style: grey),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _cur.autoPayoutEnabled,
                  onChanged: _saving ? null : _toggleAuto,
                  title: const Text('Авто-тўлов ҳамёнга'),
                  subtitle: Text(
                    _cur.autoPayoutEnabled
                        ? 'Ёқилган: ҳар LEG тугагач ҳақ ҳамёнга тушади'
                        : 'ЎЧИҚ: ҳақ ҳамёнга тушмайди, қарз сақланади (ёқилганда тўланади)',
                    style: TextStyle(color: _cur.autoPayoutEnabled ? null : Colors.orange.shade900),
                  ),
                ),
                Text('Йиғилган хизмат ҳақи (ledger): ${logisticsMoney(_cur.feeAccountBalance)} сўм', style: grey),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Ҳал қилинмаган тўловлар (${_cur.openAnomalies.length})',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        if (_cur.openAnomalies.isEmpty)
          const Padding(padding: EdgeInsets.all(8), child: Text('Йўқ', style: TextStyle(color: Colors.grey))),
        for (final a in _cur.openAnomalies)
          Card(
            child: ListTile(
              dense: true,
              leading: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
              title: Text(courierFeeAnomalyLabel(a.reason)),
              subtitle: SelectableText(
                '${a.shipmentId} · ${a.legId} · курьер ${a.providerId}'
                ' · уриниш ${a.attempts} · ${_when(a.lastSeenAtMs)}',
              ),
              trailing: Text(a.amount == null ? '—' : '${logisticsMoney(a.amount!)} сўм'),
            ),
          ),
        const SizedBox(height: 12),
        const Text('Охирги тўловлар', style: TextStyle(fontWeight: FontWeight.w700)),
        if (_cur.recentPayouts.isEmpty)
          const Padding(padding: EdgeInsets.all(8), child: Text('Ҳали йўқ', style: TextStyle(color: Colors.grey))),
        for (final p in _cur.recentPayouts)
          Card(
            child: ListTile(
              dense: true,
              title: Text('${logisticsMoney(p.gross)} − ${logisticsMoney(p.fee)} = ${logisticsMoney(p.net)} сўм'),
              subtitle: SelectableText(
                '${p.shipmentId} · ${p.legId} · курьер ${p.providerId}'
                '${p.feeVersion != null ? ' · v${p.feeVersion}' : ''} · ${_when(p.createdAtMs)}',
              ),
            ),
          ),
        TextButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Қайта юклаш'),
        ),
      ],
    );
  }
}

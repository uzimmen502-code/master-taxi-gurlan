// Улгуржи буюртма — AVA улуши (Q-4: админ таҳрирлайди, версияли, audit).
// Ўқиш: `settings/wholesale_orders` (`avaFeeBps`, `feeVersion`; rules — ўқиш очиқ,
// клиент ёзуви ёпиқ). Ёзув: `setWholesaleOrderSettings({avaFeeBps, reason})`
// (demand, europe-west1; чегара 0..3000 bps, версия + `admin_audit` — сервер).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_callable.dart';
import '../services/admin_wholesale_orders_service.dart';
import '../utils/wholesale_orders_admin.dart';
import 'admin_reason_dialog.dart';

class WholesaleFeeCard extends StatefulWidget {
  const WholesaleFeeCard({super.key, required this.svc, this.loader});

  final AdminWholesaleOrdersService svc;

  /// Тест учун: ҳужжатни ўқишни алмаштириш (`null` — ҳужжат йўқ).
  final Future<Map<String, dynamic>?> Function()? loader;

  @override
  State<WholesaleFeeCard> createState() => _WholesaleFeeCardState();
}

class _WholesaleFeeCardState extends State<WholesaleFeeCard> {
  final _fee = TextEditingController();
  WholesaleFeeCurrent _current = const WholesaleFeeCurrent();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = widget.loader != null
          ? await widget.loader!()
          : (await FirebaseFirestore.instance.collection('settings').doc('wholesale_orders').get()).data();
      final cur = WholesaleFeeCurrent.fromDoc(data);
      _fee.text = wholesaleFeeBpsToPercent(cur.effectiveBps);
      if (mounted) setState(() => _current = cur);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _save() async {
    final plan = planWholesaleFee(_fee.text, _current);
    if (plan.error != null) {
      setState(() => _inputError = plan.error);
      return;
    }
    setState(() => _inputError = null);
    if (plan.unchanged) {
      _snack('Ўзгариш йўқ');
      return;
    }
    final bps = plan.bps!;
    final reason = await showAdminReasonDialog(
      context,
      title: 'AVA улуши: ${wholesaleFeeBpsToPercent(bps)} %',
      message: 'Ҳозир: ${wholesaleFeeBpsToPercent(_current.effectiveBps)} % → янги: ${wholesaleFeeBpsToPercent(bps)} % '
          '($bps bps).\nЯнги улуш фақат ЯНГИ нарх ҳисобларига (квота) қўлланади; берилган буюртмалар '
          'ўз муҳрланган улуши билан қолади.',
    );
    if (reason == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final res = await widget.svc.setFeeSettings(avaFeeBps: bps, reason: reason);
      if (!mounted) return;
      _snack(res['unchanged'] == true ? 'Ўзгариш йўқ (сервер)' : 'Сақланди: v${res['feeVersion']}');
      await _load();
    } catch (e) {
      _snack('Хато: ${adminErrorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())));
    }
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(child: Text('Хато: $_error', style: TextStyle(color: Colors.red.shade700))),
            TextButton(onPressed: _load, child: const Text('Қайта')),
          ]),
        ),
      );
    }
    final muted = TextStyle(fontSize: 12.5, color: Colors.grey.shade700);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AVA улуши (товар суммасидан)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _current.exists
                  ? 'Ҳозир: ${wholesaleFeeBpsToPercent(_current.effectiveBps)} % (${_current.effectiveBps} bps) · v${_current.feeVersion}'
                  : 'Созлама ҳужжати йўқ — сервер 0 % ҳисоблайди (v0)',
              key: const ValueKey('wholesale-fee-current'),
              style: muted,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _fee,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(
                  labelText: 'AVA улуши, % (0..30)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _inputError,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Сақлаш'),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: _saving ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Қайта юклаш'),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'Ҳисоб: улуш = товар суммаси × bps / 10 000, юқорига бутун сўмгача (сервер). '
              'Курьер/етказиш ҳақи — AVA Logistics тарифида (Нархлар жадвали ва ички улушлар).',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}

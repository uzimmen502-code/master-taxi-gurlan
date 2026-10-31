// Улгуржи буюртма — ДАРВОЗА ва ТЕСТЧИЛАР (Q-7: ички синов; ҳаммага очиш — эга).
//
// Ўқиш ва ёзув — ФАҚАТ callable (demand, europe-west1):
//   adminGetWholesaleOrdersStage()  → {exists, enabled, stage, testerIds, globalEnabled, effectiveOpen}
//   adminSetWholesaleOrdersStage({enabled?, stage?, addTesterIds?, removeTesterIds?, reason})
// Ҳужжат: `module_config/wholesale_orders_all` (квота дарвозаси шуни ўқийди).
// Ҳар ўзгариш — сабаб мажбурий, `admin_audit` (41-банд).

import 'package:flutter/material.dart';

import '../services/admin_callable.dart';
import '../services/admin_wholesale_orders_service.dart';
import '../utils/logistics_stage.dart' show normalizeTesterPhone, testerListContains;
import '../utils/wholesale_orders_admin.dart';
import 'admin_reason_dialog.dart';

/// Огоҳлантириш матни (docs/ulgurji_buyurtma_zanjiri_uz.md §4) — тестда ҳам текширилади.
const kWholesaleGateWarning =
    'ДИҚҚАТ: дарвоза relay guard\'лари (feat/ulg-relay-guards) production\'га чиқмагунча ЁПИҚ турсин. '
    'Ҳозирги жонли relay функцияларида Ulgurji жўнатмасининг эгаси (сотувчи) жўнатмани бекор қилиши, '
    'етказиш кодини олиб харидорсиз «етказилди» қилиши мумкин. Тестчиларни олдиндан қўшиш мумкин — '
    '«Ёқиқ» ўчиқ турганда ҳеч ким буюртма бера олмайди.';

class WholesaleStagePanel extends StatefulWidget {
  const WholesaleStagePanel({super.key, required this.svc});

  final AdminWholesaleOrdersService svc;

  @override
  State<WholesaleStagePanel> createState() => _WholesaleStagePanelState();
}

class _WholesaleStagePanelState extends State<WholesaleStagePanel> {
  final _phone = TextEditingController();
  WholesaleGateState? _state;
  Object? _loadError;
  String? _picked;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final s = await widget.svc.getStage();
      if (mounted) {
        setState(() {
          _state = s;
          _picked = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red.shade700 : null,
      duration: Duration(seconds: error ? 8 : 5),
    ));
  }

  String _resultText(WholesaleGateChange r) {
    if (r.unchanged) return 'Ўзгариш йўқ';
    return '${r.created ? 'Дарвоза ҳужжати яратилди. ' : ''}Сақланди: ${r.enabled ? 'ёқиқ' : 'ўчиқ'} · ${r.stage.toUpperCase()} · '
        'тестчилар: ${r.testerCount}${r.added > 0 ? ' (+${r.added})' : ''}${r.removed > 0 ? ' (−${r.removed})' : ''}';
  }

  Future<void> _run(String title, String message, Future<WholesaleGateChange> Function(String reason) action) async {
    final reason = await showAdminReasonDialog(context, title: title, message: message);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await action(reason);
      _snack(_resultText(r));
      await _load();
    } catch (e) {
      _snack('Хато: ${_errorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _errorText(Object e) {
    if (e is AdminCallableException) {
      const byReason = <String, String>{
        'reason_required': 'Сабаб камида 3 белги (audit)',
        'tester_args_conflict': 'Битта рақам ҳам қўшилиб, ҳам олинмайди',
        'nothing_to_change': 'Ўзгартириш йўқ',
        'enabled_invalid': 'Ёқиқ/ўчиқ қиймати нотўғри',
      };
      final m = byReason[e.reason];
      if (m != null) return m;
      if (e.code == 'not-found') return 'Callable топилмади — server deploy қилинмаган бўлиши мумкин';
    }
    return adminErrorText(e);
  }

  Future<void> _setEnabled(bool v) => _run(
        v ? 'Дарвозани ЁҚИШ' : 'Дарвозани ЎЧИРИШ',
        v ? '$kWholesaleGateWarning\n\nЁқилгач, танланган босқичга кўра (${_state?.stage.toUpperCase()}) буюртма очилади.'
          : 'Ўчирилгач, ҳеч ким янги Ulgurji буюртма бера олмайди (берилганлари давом этади).',
        (reason) => widget.svc.setStage(enabled: v, reason: reason),
      );

  Future<void> _saveStage(String stage) => _run(
        'Босқич: ${stage.toUpperCase()}',
        stage == 'public'
            ? 'PUBLIC — «Ёқиқ» бўлса БАРЧА фойдаланувчилар буюртма бера олади. Бу — эга қарори (Q-7).\n\n$kWholesaleGateWarning'
            : (kWholesaleStageLabels[stage] ?? stage),
        (reason) => widget.svc.setStage(stage: stage, reason: reason),
      );

  Future<void> _addTester() async {
    final phone = normalizeTesterPhone(_phone.text);
    if (phone == null) {
      _snack('Телефон: 9 рақам ёки 998 билан 12 рақам', error: true);
      return;
    }
    if (testerListContains(_state?.testerIds ?? const [], phone)) {
      _snack('Бу рақам рўйхатда бор');
      return;
    }
    await _run('Тестчи қўшиш', '$phone тестчилар рўйхатига қўшилади.', (reason) async {
      final r = await widget.svc.setStage(addTesterIds: [phone], reason: reason);
      _phone.clear();
      return r;
    });
  }

  Future<void> _removeTester(String id) => _run(
        'Тестчини олиш',
        '$id тестчилар рўйхатидан олинади.',
        (reason) => widget.svc.setStage(removeTesterIds: [id], reason: reason),
      );

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final muted = TextStyle(fontSize: 12.5, color: Colors.grey.shade700);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          key: const ValueKey('wholesale-gate-warning'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text(kWholesaleGateWarning, style: TextStyle(fontSize: 12.5, color: Colors.red.shade900))),
          ]),
        ),
        const SizedBox(height: 12),
        if (_loadError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: Text('Ҳолат юкланмади: ${_errorText(_loadError!)}', style: TextStyle(color: Colors.red.shade700)),
                ),
                TextButton(onPressed: _load, child: const Text('Қайта')),
              ]),
            ),
          )
        else if (s == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else ...[
          Row(children: [
            Chip(
              key: const ValueKey('wholesale-gate-effective'),
              avatar: Icon(s.effectiveOpen ? Icons.lock_open : Icons.lock, size: 18,
                  color: s.effectiveOpen ? Colors.orange.shade800 : Colors.green.shade700),
              label: Text(s.effectiveOpen ? 'Ҳозир ОЧИҚ (${s.stage.toUpperCase()})' : 'Ҳозир ЁПИҚ'),
            ),
            const SizedBox(width: 8),
            if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const Spacer(),
            TextButton.icon(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Янгилаш')),
          ]),
          Text(
            '${s.exists ? 'module_config/wholesale_orders_all бор' : 'Дарвоза ҳужжати ЙЎҚ (сервер биринчи ўзгаришда ЁПИҚ ҳолда яратади)'}'
            ' · ёқиқ: ${s.enabled ? 'ҳа' : 'йўқ'} · босқич: ${s.stage.toUpperCase()} · тестчилар: ${s.testerIds.length}'
            '${s.globalEnabled ? '' : ' · ГЛОБАЛ КАЛИТ ЎЧИҚ (module_config/global)'}',
            style: muted,
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SwitchListTile(
                  key: const ValueKey('wholesale-gate-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Дарвоза ёқиқ (enabled)'),
                  subtitle: const Text('Ўчиқ бўлса босқичдан қатъи назар ҳеч ким буюртма бермайди'),
                  value: s.enabled,
                  onChanged: _busy ? null : _setEnabled,
                ),
                const Divider(),
                DropdownButton<String>(
                  key: const ValueKey('wholesale-gate-stage'),
                  value: _picked ?? s.stage,
                  isExpanded: true,
                  items: [
                    for (final st in kWholesaleStages)
                      DropdownMenuItem(value: st, child: Text(kWholesaleStageLabels[st] ?? st)),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _picked = v),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy || (_picked ?? s.stage) == s.stage ? null : () => _saveStage(_picked!),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Босқични сақлаш'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Тестчилар (INTERNAL / PILOT)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      key: const ValueKey('wholesale-tester-phone'),
                      controller: _phone,
                      enabled: !_busy,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Телефон (9 рақам ёки 998…)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addTester(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _addTester,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Қўшиш'),
                  ),
                ]),
                const SizedBox(height: 10),
                if (s.testerIds.isEmpty)
                  Text('Тестчи йўқ', style: TextStyle(color: Colors.grey.shade600))
                else
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final id in s.testerIds)
                      InputChip(label: Text(id), onDeleted: _busy ? null : () => _removeTester(id)),
                  ]),
              ]),
            ),
          ),
        ],
      ],
    );
  }
}

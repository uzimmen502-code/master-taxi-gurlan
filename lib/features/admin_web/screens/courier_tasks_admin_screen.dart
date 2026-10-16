// АДМИН «Курьер вазифалари»:
//   1. Қотиб қолган вазифалар (D6) — `adminListStaleTasks({hours})`, фақат ўқиш:
//      автоматик қайта тайинлаш ЙЎҚ; админ рўйхатни кўради ва керак бўлса
//      қўлда ҳаракат қилади («Кўчирма: Gilam yuvish / Sut qabul → Kuryerdan olish»).
//   2. Курьер ҳақи фоизи (D2) — гилам / сут / йиғиб олиш:
//      `adminGetCourierTaskPayoutSettings` (ўқиш — ФАҚАТ callable, рules
//      `settings/courier_task_payout`ни клиентга бермайди) ва
//      `adminSetCourierTaskPayoutPct` (ёзув).
// Ҳамма ҳисоб ва текширув СЕРВЕРДА (default, us-central1); экран кўрсатади.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../logistics/domain/tariff_adjust.dart' show bpsToPercentText;
import '../services/admin_callable.dart';
import '../services/admin_courier_tasks_service.dart';
import '../utils/courier_tasks_admin.dart';
import '../widgets/admin_reason_dialog.dart';

final _dtFmt = DateFormat('dd.MM.yyyy HH:mm');

class CourierTasksAdminScreen extends StatelessWidget {
  const CourierTasksAdminScreen({super.key, this.service});

  final AdminCourierTasksService? service;

  @override
  Widget build(BuildContext context) {
    final svc = service ?? AdminCourierTasksService();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          title: const Text('Курьер вазифалари', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            labelColor: AppColors.onPrimary,
            unselectedLabelColor: AppColors.onPrimary.withValues(alpha: 0.6),
            indicatorColor: AppColors.onPrimary,
            tabs: const [
              Tab(text: 'Қотиб қолган'),
              Tab(text: 'Курьер ҳақи, %'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            StaleTasksTab(svc: svc),
            PayoutPctTab(svc: svc),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. Қотиб қолган вазифалар
// ═══════════════════════════════════════════════════════════════════════════

class StaleTasksTab extends StatefulWidget {
  const StaleTasksTab({super.key, required this.svc});

  final AdminCourierTasksService svc;

  @override
  State<StaleTasksTab> createState() => _StaleTasksTabState();
}

class _StaleTasksTabState extends State<StaleTasksTab> {
  final _hours = TextEditingController(text: '$kStaleDefaultHours');
  StaleTasksResult? _result;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final h = parseStaleHours(_hours.text);
    if (h == null) {
      setState(() => _error = 'Соат $kStaleMinHours..$kStaleMaxHours оралиғида бутун сон бўлиши керак');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.svc.listStaleTasks(hours: h);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Ҳолати ўзгармаганига камида'),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _hours,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                onSubmitted: (_) => _load(),
              ),
            ),
            const Text('соат ($kStaleMinHours..$kStaleMaxHours)'),
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Янгилаш'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Фақат кўриш: вазифалар автоматик қайта тайинланмайди. Гилам/сут вазифасини '
          '«Gilam yuvish» / «Sut qabul» бўлимидаги «Kuryerdan olish» билан қайтариш мумкин.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ),
        if (r != null) ...[
          const SizedBox(height: 10),
          Text(
            'Жами: ${r.totalAll} та (≥ ${r.hours} соат)'
            '${r.generatedAtMs != null ? ' · ${_dtFmt.format(DateTime.fromMillisecondsSinceEpoch(r.generatedAtMs!))}' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final e in kStaleModuleLabels.entries) _moduleCard(e.value, r.modules[e.key] ?? const StaleModule()),
        ],
      ],
    );
  }

  Widget _moduleCard(String label, StaleModule m) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        key: PageStorageKey(label),
        initiallyExpanded: m.total > 0,
        title: Text('$label — ${m.total}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'сканер қилинди: ${m.scanned}${m.truncated ? ' · КЎПРОҚ БОР (рўйхат чекланган)' : ''}',
          style: TextStyle(fontSize: 12, color: m.truncated ? Colors.orange.shade900 : Colors.grey.shade700),
        ),
        children: [
          if (m.items.isEmpty)
            const Padding(padding: EdgeInsets.all(12), child: Text('Йўқ', style: TextStyle(color: Colors.grey))),
          for (final it in m.items)
            ListTile(
              dense: true,
              title: SelectableText(it.id),
              subtitle: Text(
                '${it.status.isEmpty ? '—' : it.status}'
                '${it.courierId.isEmpty ? ' · курьер: йўқ' : ' · курьер: ${it.courierId}'}',
              ),
              trailing: Text(formatStaleAge(it.ageHours), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          if (m.truncated)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(
                'Кўпроқ бор: фақат энг эскилари кўрсатилди (жами ${m.total}+). '
                'Соатни кўпайтириб торайтиринг.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. Курьер ҳақи фоизи
// ═══════════════════════════════════════════════════════════════════════════

class PayoutPctTab extends StatefulWidget {
  const PayoutPctTab({super.key, required this.svc});

  final AdminCourierTasksService svc;

  @override
  State<PayoutPctTab> createState() => _PayoutPctTabState();
}

class _PayoutPctTabState extends State<PayoutPctTab> {
  final Map<String, TextEditingController> _c = {
    for (final k in kCourierPayoutModules.keys) k: TextEditingController(),
  };
  CourierPayoutSettings _cur = const CourierPayoutSettings();
  bool _loading = true;
  bool _loadedOnce = false;
  String? _busyModule;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.svc.getPayoutSettings();
      for (final k in kCourierPayoutModules.keys) {
        _c[k]!.text = s.percentText(k);
      }
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

  Future<void> _save(String module) async {
    final plan = planPayoutPctChange(currentBps: _cur.bps[module], text: _c[module]!.text);
    if (plan.error != null) {
      _snack(plan.error!, error: true);
      return;
    }
    if (!plan.changed) {
      _snack('Ўзгариш йўқ');
      return;
    }
    final label = kCourierPayoutModules[module] ?? module;
    final reason = await showAdminReasonDialog(
      context,
      title: '$label: курьер ҳақи',
      message: plan.bps == null
          ? '«Созланмаган»га қайтарилади.'
          : 'Янги қиймат: ${bpsToPercentText(plan.bps!)} %. Шу заҳоти ЯНГИ вазифаларга қўлланади.',
    );
    if (reason == null || !mounted) return;
    setState(() => _busyModule = module);
    try {
      final res = await widget.svc.setPayoutPct(module: module, bps: plan.bps, reason: reason);
      _snack(res['unchanged'] == true ? 'Ўзгариш йўқ (сервер)' : 'Сақланди: v${res['version']}');
      await _load();
    } catch (e) {
      _snack('Хато: ${adminErrorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busyModule = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_loadedOnce) return const Center(child: CircularProgressIndicator());
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
        Text(
          'Курьерга тўланадиган ҳақ — вазифа суммасининг фоизи (бутун сўмга ҳисоблашни сервер қилади). '
          'Бўш майдон = «созланмаган»: сервер ҳақни ҳисобламайди.'
          '${_cur.version > 0 ? '\nЖорий версия: v${_cur.version}' : ''}'
          '${_cur.updatedBy.isNotEmpty ? ' · ${_cur.updatedBy}' : ''}'
          '${_cur.updatedAtMs != null ? ' · ${_dtFmt.format(DateTime.fromMillisecondsSinceEpoch(_cur.updatedAtMs!))}' : ''}',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 10),
        for (final e in kCourierPayoutModules.entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox(width: 130, child: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600))),
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _c[e.key],
                      enabled: _busyModule == null,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: InputDecoration(
                        labelText: '%',
                        hintText: _cur.bps[e.key] == null ? 'созланмаган' : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _busyModule == null ? () => _save(e.key) : null,
                    child: _busyModule == e.key
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Сақлаш'),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _cur.bps[e.key] == null ? 'созланмаган' : '${bpsToPercentText(_cur.bps[e.key]!)} %',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                ],
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

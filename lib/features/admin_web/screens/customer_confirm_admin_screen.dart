// АДМИН «Мижоз тасдиғи» (D2/D7): курьер «олдим/етказдим» деганидан кейин мижоз
// ўз қурилмасида тасдиқлаши — модуллар бўйича босқич (OFF / INTERNAL / PUBLIC)
// ва INTERNAL синовчилар рўйхати.
//   `adminGetCustomerConfirmation` (ўқиш) ва `adminSetCustomerConfirmation`
//   (ёзув, audit сабаби билан) — default codebase, us-central1.
// Ҳамма текширув ва ҳолат СЕРВЕРДА; экран фақат кўрсатади ва юборади.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../services/admin_callable.dart';
import '../services/admin_customer_confirm_service.dart';
import '../utils/customer_confirm_admin.dart';
import '../widgets/admin_reason_dialog.dart';

class CustomerConfirmAdminScreen extends StatelessWidget {
  const CustomerConfirmAdminScreen({super.key, this.service});

  final AdminCustomerConfirmService? service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: const Text('Мижоз тасдиғи', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: CustomerConfirmAdminBody(svc: service ?? AdminCustomerConfirmService()),
    );
  }
}

class CustomerConfirmAdminBody extends StatefulWidget {
  const CustomerConfirmAdminBody({super.key, required this.svc});

  final AdminCustomerConfirmService svc;

  @override
  State<CustomerConfirmAdminBody> createState() => _CustomerConfirmAdminBodyState();
}

class _CustomerConfirmAdminBodyState extends State<CustomerConfirmAdminBody> {
  final _phone = TextEditingController();
  CustomerConfirmState _cur = const CustomerConfirmState();
  final Map<String, String> _picked = {}; // модул → ҳали сақланмаган танлов
  String _testerModule = kCustomerConfirmModules.keys.first;
  bool _loading = true;
  bool _loadedOnce = false;
  bool _busy = false;
  String? _error;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.svc.get();
      if (mounted) {
        setState(() {
          _cur = s;
          _picked.clear();
        });
      }
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
      duration: Duration(seconds: error ? 8 : 5),
    ));
  }

  Future<void> _run(Future<CustomerConfirmSetResult> Function() action) async {
    setState(() => _busy = true);
    try {
      final r = await action();
      _snack(r.describe());
      await _load();
    } catch (e) {
      _snack('Хато: ${adminErrorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveStage(String module, String stage) async {
    final label = kCustomerConfirmModules[module] ?? module;
    final reason = await showAdminReasonDialog(
      context,
      title: '$label: ${stage.toUpperCase()}',
      message: switch (stage) {
        'public' => 'PUBLIC — барча мижозлар учун ёқилади.\n$kCustomerConfirmPublicWarning',
        'off' => 'OFF — мижоз тасдиғи шу модул учун ўчади.',
        _ => 'INTERNAL — фақат синовчилар. Синовчилар рўйхати «Синовчилар» бўлимида.',
      },
    );
    if (reason == null || !mounted) return;
    await _run(() => widget.svc.set(module: module, stage: stage, reason: reason));
  }

  Future<void> _changeTester({required bool add}) async {
    final phone = normalizeTesterPhone(_phone.text);
    if (phone == null) {
      _snack('Телефон: 9 рақам ёки 998 билан 12 рақам', error: true);
      return;
    }
    final label = kCustomerConfirmModules[_testerModule] ?? _testerModule;
    final reason = await showAdminReasonDialog(
      context,
      title: add ? 'Синовчи қўшиш' : 'Синовчини олиш',
      message: add
          ? '$phone — «$label» INTERNAL рўйхатига қўшилади.'
          : '$phone — «$label» INTERNAL рўйхатидан олинади.',
    );
    if (reason == null || !mounted) return;
    await _run(() async {
      final r = await widget.svc.set(
        module: _testerModule,
        addTesterIds: add ? [phone] : null,
        removeTesterIds: add ? null : [phone],
        reason: reason,
      );
      if (mounted) _phone.clear();
      return r;
    });
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
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border.all(color: Colors.orange.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(kCustomerConfirmPublicWarning, style: TextStyle(color: Colors.orange.shade900)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Ўзгариш кучга киришига бир оз вақт кетиши мумкин. Ҳар ўзгариш сабаби билан audit журналига ёзилади.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        for (final e in kCustomerConfirmModules.entries) _stageRow(e.key, e.value),
        const SizedBox(height: 14),
        const Text('Синовчилар (INTERNAL)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        _testersCard(),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _loading || _busy ? null : _load,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Қайта юклаш'),
        ),
      ],
    );
  }

  Widget _stageRow(String module, String label) {
    final current = _cur.stages[module];
    final selected = _picked[module] ?? current;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 130, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            SizedBox(
              width: 240,
              child: DropdownButton<String>(
                key: ValueKey('stage_$module'),
                value: selected,
                hint: const Text('—'),
                isExpanded: true,
                items: [
                  for (final s in kCustomerConfirmStages)
                    DropdownMenuItem(value: s, child: Text(kCustomerConfirmStageLabels[s] ?? s)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _picked[module] = v!),
              ),
            ),
            FilledButton(
              key: ValueKey('save_$module'),
              onPressed: _busy || selected == null || selected == current ? null : () => _saveStage(module, selected),
              child: const Text('Сақлаш'),
            ),
            Text(
              current == null ? 'серверда: номаълум' : 'серверда: ${current.toUpperCase()}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _testersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Рўйхат танланган модулнинг INTERNAL синовчиларига тегишли. '
              'Синовчилар сони (серверда): ${_cur.testerCount?.toString() ?? '—'}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButton<String>(
                    key: const ValueKey('tester_module'),
                    value: _testerModule,
                    isExpanded: true,
                    items: [
                      for (final e in kCustomerConfirmModules.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _testerModule = v!),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _phone,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Телефон (9 рақам ёки 998…)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('tester_add'),
                  onPressed: _busy ? null : () => _changeTester(add: true),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Қўшиш'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('tester_remove'),
                  onPressed: _busy ? null : () => _changeTester(add: false),
                  icon: const Icon(Icons.person_remove_alt_1, size: 18),
                  label: const Text('Олиш'),
                ),
                if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
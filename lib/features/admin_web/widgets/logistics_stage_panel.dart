// Админ: AVA Logistics ишга тушириш босқичи ва синовчилар (D8, 42-банд).
//
// Ўқиш: `module_config/logistics_all` (`logistics.stage`, `logistics.testerIds`).
// Ёзиш: ФАҚАТ `adminSetLogisticsStage` (demand, europe-west1; audit, кэш
// ~60 сония). Босқич ёки рўйхат ўзгаргани сервер томонидан текширилади.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/admin_callable.dart';
import '../services/admin_logistics_service.dart';
import '../utils/logistics_stage.dart';
import 'admin_reason_dialog.dart';

class LogisticsStagePanel extends StatefulWidget {
  const LogisticsStagePanel({super.key, required this.service});

  final AdminLogisticsService service;

  @override
  State<LogisticsStagePanel> createState() => _LogisticsStagePanelState();
}

class _LogisticsStagePanelState extends State<LogisticsStagePanel> {
  final _phone = TextEditingController();
  String? _picked; // ҳали сақланмаган танлов
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red.shade700 : null,
      duration: Duration(seconds: error ? 8 : 5),
    ));
  }

  String _resultText(StageChangeResult r) {
    if (r.unchanged) return 'Ўзгариш йўқ (босқич: ${r.stage}, синовчилар: ${r.testerCount})';
    final within = r.effectiveWithinSeconds;
    return 'Сақланди: ${r.stage} · синовчилар: ${r.testerCount}'
        '${r.added > 0 ? ' · қўшилди ${r.added}' : ''}${r.removed > 0 ? ' · олинди ${r.removed}' : ''}'
        '${within != null ? '. Кучга кириши: ~$within сония ичида' : ''}';
  }

  Future<void> _run(Future<StageChangeResult> Function() action) async {
    setState(() => _busy = true);
    try {
      final r = await action();
      if (mounted) {
        setState(() => _picked = null);
        _snack(_resultText(r));
      }
    } catch (e) {
      _snack('Хато: ${adminErrorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveStage(String stage) async {
    final reason = await showAdminReasonDialog(
      context,
      title: 'Босқич: ${stage.toUpperCase()}',
      message: stage == 'public'
          ? 'PUBLIC — барча фойдаланувчилар жўнатма юбора олади.'
          : stage == 'off'
              ? 'OFF — хизмат ёпилади ва янги LEG қабул қилиш ҳам тўхтайди.'
              : 'Босқич ўзгаради. Кучга кириши ~1 дақиқа.',
      required: false,
    );
    if (reason == null || !mounted) return;
    await _run(() => widget.service.setStage(stage: stage, reason: reason));
  }

  Future<void> _addTester() async {
    final phone = normalizeTesterPhone(_phone.text);
    if (phone == null) {
      _snack('Телефон: 9 рақам ёки 998 билан 12 рақам', error: true);
      return;
    }
    await _run(() async {
      final r = await widget.service.setStage(addTesterIds: [phone]);
      _phone.clear();
      return r;
    });
  }

  Future<void> _removeTester(String id) async {
    final reason = await showAdminReasonDialog(
      context,
      title: 'Синовчини олиш',
      message: '$id синовчилар рўйхатидан олинади.',
      required: false,
    );
    if (reason == null || !mounted) return;
    await _run(() => widget.service.setStage(removeTesterIds: [id], reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('module_config').doc('logistics_all').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Хато: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final cfg = LogisticsStageConfig.fromDoc(snap.data!.data(), exists: snap.data!.exists);
        final selected = _picked ?? cfg.stage;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Ишга тушириш босқичи', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Серверда ҳозир: ${cfg.stage.toUpperCase()} · синовчилар: ${cfg.testerIds.length}. '
              'Ўзгариш ~1 дақиқа ичида кучга киради. OFF янги LEG қабул қилишни ҳам тўхтатади.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            if (!cfg.exists)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'module_config/logistics_all ҳужжати йўқ — сервер уни яратмайди (босқични ўзгартириб бўлмайди).',
                  style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
                ),
              ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButton<String>(
                      value: selected,
                      isExpanded: true,
                      items: [
                        for (final s in kLogisticsStages)
                          DropdownMenuItem(value: s, child: Text(kLogisticsStageLabels[s] ?? s)),
                      ],
                      onChanged: _busy ? null : (v) => setState(() => _picked = v),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy || !cfg.exists || selected == cfg.stage ? null : () => _saveStage(selected),
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Босқични сақлаш'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Синовчилар (INTERNAL / PILOT)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
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
                            onSubmitted: (_) => _addTester(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _busy || !cfg.exists ? null : _addTester,
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
                          label: const Text('Қўшиш'),
                        ),
                        if (_busy) ...[
                          const SizedBox(width: 12),
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (cfg.testerIds.isEmpty)
                      Text('Синовчи йўқ', style: TextStyle(color: Colors.grey.shade600))
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final id in cfg.testerIds)
                            InputChip(
                              label: Text(id),
                              onDeleted: _busy ? null : () => _removeTester(id),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

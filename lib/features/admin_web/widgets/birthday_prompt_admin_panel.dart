import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_birthday_prompt_service.dart';

const _stageLabels = <String, String>{
  'off': 'Ўчиқ',
  'internal': 'Ички синов (фақат рақамлар)',
  'pilot': 'Пилот (рақамлар + туманлар)',
  'public': 'Ҳамма учун',
};

/// Админ: «Туғилган кунингизни киритинг» пуши (эга 2026-11-28, сервер `functions/birthday_prompt.js`):
/// 4 кун кунига бир марта → 7 кун танаффус → ҳар якшанба (чегарасиз). Босқич, синов рақамлари, пилот туманлари,
/// кунлик эслатмалар сони (1–14), якшанба эслатмаси ёқиқ/ўчиқ; охирги тарқатишлар. Ойна 08:00–19:59 (эга: «соат 8:00 - 20:00 гача»), соат созламаси йўқ.
/// Сақлаш — `adminSetBirthdayPromptSettings` (версия + admin_audit). Кирилл (админ конвенцияси).
class BirthdayPromptAdminPanel extends StatefulWidget {
  const BirthdayPromptAdminPanel({super.key, this.api});

  final AdminBirthdayPromptApi? api;

  @override
  State<BirthdayPromptAdminPanel> createState() => _BirthdayPromptAdminPanelState();
}

class _BirthdayPromptAdminPanelState extends State<BirthdayPromptAdminPanel> {
  AdminBirthdayPromptApi? _apiCache;
  BirthdayPromptAdminState? _state;
  String? _loadError;
  final _internal = TextEditingController();
  final _pilot = TextEditingController();
  final _dailyCount = TextEditingController();
  final _reason = TextEditingController();
  String _stage = 'off';
  bool _weeklySunday = true;
  List<String> _errors = const [];
  bool _saving = false;
  String? _saved;

  AdminBirthdayPromptApi get _api => _apiCache ??= widget.api ?? FirebaseAdminBirthdayPromptApi();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _internal.dispose();
    _pilot.dispose();
    _dailyCount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final st = await _api.load();
      if (!mounted) return;
      setState(() {
        _state = st;
        _stage = st.settings.stage;
        _internal.text = st.settings.internalPhones.join(', ');
        _pilot.text = st.settings.pilotDistrictIds.join(', ');
        _dailyCount.text = '${st.settings.dailyCount}';
        _weeklySunday = st.settings.weeklySunday;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Юклаб бўлмади: $e');
    }
  }

  List<String> _list(TextEditingController c) => [for (final s in c.text.split(RegExp(r'[,\s]+'))) if (s.trim().isNotEmpty) s.trim()];

  Future<void> _save() async {
    final st = _state;
    if (st == null) return;
    final s = BirthdayPromptSettings(
      stage: _stage,
      internalPhones: _list(_internal),
      pilotDistrictIds: _list(_pilot),
      dailyCount: int.tryParse(_dailyCount.text.trim()) ?? -1,
      weeklySunday: _weeklySunday,
    );
    final errs = birthdayPromptProblems(s);
    setState(() {
      _errors = errs;
      _saved = null;
    });
    if (errs.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      await _api.save(s, expectedVersion: st.settings.version, reason: _reason.text);
      _reason.clear();
      await _load();
      if (mounted) setState(() => _saved = 'Сақланди.');
    } catch (e) {
      if (mounted) setState(() => _errors = ['Сақлаб бўлмади: $e']);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_loadError!),
          TextButton(onPressed: _load, child: const Text('Қайта уриниш')),
        ]),
      );
    }
    final st = _state;
    if (st == null) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
        'Туғилган санасини киритмаган фойдаланувчиларга «Туғилган кунингизни киритинг» пуши: аввал кетма-кет '
        'бир неча кун кунига бир марта, кейин 7 кун танаффус, сўнг ҳар якшанба (08:00–20:00, Тошкент вақти). '
        'Босилганда — туғилган сана киритиладиган экран. Сана киритилгач, «Байрам эслатмалари» ўчирилгач '
        'ёки ҳисоб ўчирилгач тўхтайди.',
        style: TextStyle(color: Colors.black54),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const ValueKey('bp_admin_stage'),
        initialValue: _stage,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Босқич'),
        items: [for (final s in kBirthdayPromptStages) DropdownMenuItem(value: s, child: Text(_stageLabels[s]!))],
        onChanged: (v) => setState(() => _stage = v ?? 'off'),
      ),
      TextField(
        key: const ValueKey('bp_admin_internal'),
        controller: _internal,
        decoration: const InputDecoration(labelText: 'Ички синов рақамлари (998…, вергул билан)'),
      ),
      TextField(
        key: const ValueKey('bp_admin_pilot'),
        controller: _pilot,
        decoration: const InputDecoration(labelText: 'Пилот туман ID лари (вергул билан, 30 тагача)'),
      ),
      TextField(
        key: const ValueKey('bp_admin_daily'),
        controller: _dailyCount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Неча кун кунига бир марта ($kBirthdayPromptDailyCountMin–$kBirthdayPromptDailyCountMax; '
              'сукут $kBirthdayPromptDefaultDailyCount)',
        ),
      ),
      SwitchListTile(
        key: const ValueKey('bp_admin_weekly'),
        contentPadding: EdgeInsets.zero,
        value: _weeklySunday,
        onChanged: (v) => setState(() => _weeklySunday = v),
        title: const Text('Кейин ҳар якшанба эслатиш (7 кун танаффусдан сўнг, чегарасиз)'),
      ),
      TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Сабаб (журнал учун, ихтиёрий)')),
      for (final s in _errors) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s, style: const TextStyle(color: Colors.red))),
      if (_saved != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_saved!, style: const TextStyle(color: Colors.green))),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          key: const ValueKey('bp_admin_save'),
          onPressed: _saving ? null : _save,
          child: Text('Сақлаш (версия ${st.settings.version})'),
        ),
      ),
      const SizedBox(height: 16),
      const Text('Охирги тарқатишлар', style: TextStyle(fontWeight: FontWeight.w700)),
      if (st.runs.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Ҳали юборилмаган.')),
      for (final r in st.runs)
        ListTile(
          key: ValueKey('bp_admin_run_${r.id}'),
          dense: true,
          title: Text('${r.day.isNotEmpty ? r.day : r.week} · ${_stageLabels[r.stage] ?? r.stage} · ${r.done ? 'тугади' : 'давом этмоқда'}'),
          subtitle: Text('юборилди: ${r.stats['sent'] ?? 0} (кунлик ${r.stats['sentDaily'] ?? 0}, якшанба ${r.stats['sentWeekly'] ?? 0}) · '
              'кўрилди: ${r.stats['scanned'] ?? 0} · санаси бор: ${r.stats['HAS_BIRTHDATE'] ?? 0} · '
              'танаффусда: ${r.stats['PAUSE'] ?? 0} · хато: ${r.stats['NOTIFY_FAILED'] ?? 0}'),
        ),
    ]);
  }
}

// «ТАЛАБ ЯДРОСИ» — админ: ҳудуд бўйича ёқиш/ўчириш ва push чегараси
// (эга қарори 2026-10-20).
//
// Ҳамма ёзув СЕРВЕРДА (`adminSetCoreConfig`, europe-west1): сервер текширади —
// ёзиш фақат admin/superadmin; ҳудудда ишлай оладиган таклифчи >= 5; push
// учун чегара (`push.minScore`) ўлчаб қўйилган бўлиши шарт; ҳар ўзгариш
// `admin_audit`га тушади (41-банд). Экран қоидани ўйлаб топмайди: хира тугма —
// фақат олдиндан кўрсатма, сервер барибир текширади.
//
// Ҳолатлар: Ўчиқ (сўров яратиб бўлмайди) · Shadow (сўровлар қабул қилинади ва
// мослик ҳисобланади, push ЙЎҚ) · Push (мос таклифчиларга, чегарадан юқорига).
// Ўзгариш 60 сонияда кучга киради (серверда конфиг кеши).

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../demand_offer/data/demand_repository.dart' show kDemandCoreRegion;
import '../utils/core_admin_logic.dart';

typedef CoreOverviewLoader = Future<Map<String, dynamic>> Function();
typedef CoreSetter = Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

/// Бошқариладиган модул (ҳозирча фақат хизмат сўрови; сервер ҳам шуни талаб қилади).
const String _kModule = 'service';

Future<Map<String, dynamic>> _callOverview() async {
  final res = await FirebaseFunctions.instanceFor(region: kDemandCoreRegion)
      .httpsCallable('adminGetCoreOverview')
      .call<Object?>({'module': _kModule});
  final d = res.data;
  return d is Map ? d.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
}

Future<Map<String, dynamic>> _callSet(Map<String, dynamic> payload) async {
  final res = await FirebaseFunctions.instanceFor(region: kDemandCoreRegion)
      .httpsCallable('adminSetCoreConfig')
      .call<Object?>(payload);
  final d = res.data;
  return d is Map ? d.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
}

class DemandCoreAdminScreen extends StatefulWidget {
  const DemandCoreAdminScreen({super.key, this.loader, this.setter});

  /// Тест учун алмаштирилади; стандарт — callable.
  final CoreOverviewLoader? loader;
  final CoreSetter? setter;

  @override
  State<DemandCoreAdminScreen> createState() => _DemandCoreAdminScreenState();
}

class _DemandCoreAdminScreenState extends State<DemandCoreAdminScreen> {
  CoreOverview? _overview;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  CoreOverviewLoader get _load => widget.loader ?? _callOverview;
  CoreSetter get _set => widget.setter ?? _callSet;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _load();
      if (!mounted) return;
      setState(() {
        _overview = CoreOverview.fromMap(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errorText(e);
        _loading = false;
      });
    }
  }

  String _errorText(Object e) {
    if (e is FirebaseFunctionsException) {
      final d = e.details;
      final reason = d is Map ? d['reason']?.toString() : null;
      return serverReasonText(reason, e.message ?? e.code);
    }
    return e.toString();
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? Colors.red.shade700 : null,
      duration: Duration(seconds: error ? 8 : 4),
      content: Text(text),
    ));
  }

  /// Серверга ёзиш: муваффақиятда — хабар ва қайта юклаш; рад этилса — сабаб.
  Future<void> _apply(Map<String, dynamic> payload) async {
    setState(() => _busy = true);
    try {
      final res = await _set(payload);
      if (res['changed'] == false) {
        _snack('Ўзгариш йўқ: шундай ҳолатда экан');
      } else {
        _snack('Сақланди. 60 сонияда кучга киради');
      }
      await _reload();
    } catch (e) {
      _snack('Хато: ${_errorText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _consequence(String target) {
    switch (target) {
      case 'off':
        return 'Ҳудудда янги сўров яратиб бўлмайди.';
      case 'shadow':
        return 'Ҳудудда сўровлар қабул қилинади ва мослик ҳисобланади. '
            'Фойдаланувчилар сўров яратиши мумкин, усталарга push ЮБОРИЛМАЙДИ.';
      case 'push':
        return 'Мос усталарга (чегарадан юқори) push юборилади.';
      default:
        return '';
    }
  }

  Future<void> _confirm(CoreRegionRow row, String target) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${row.name}: ${stateLabel(target)}'),
        content: Text(_consequence(target)),
        actions: [
          TextButton(
            key: const ValueKey('confirm_no'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Йўқ'),
          ),
          FilledButton(
            key: const ValueKey('confirm_yes'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ҳа, ўзгартириш'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _apply({'module': _kModule, 'regionId': row.regionId, 'state': target});
  }

  Future<void> _editMinScore(CoreOverview o) async {
    final result = await showDialog<_MinScoreChoice>(
      context: context,
      builder: (_) => _MinScoreDialog(initial: o.minScoreAll),
    );
    if (result == null) return;
    await _apply({'module': _kModule, 'regionId': 'all', 'minScore': result.value});
  }
  // ── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _overview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _overview == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Юкланмади: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('retry'),
                onPressed: _reload,
                child: const Text('Қайта уриниш'),
              ),
            ],
          ),
        ),
      );
    }
    final o = _overview!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Талаб ядроси — хизмат сўровлари',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              key: const ValueKey('refresh'),
              tooltip: 'Янгилаш',
              onPressed: (_loading || _busy) ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_busy || _loading) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        if (o.globalKillActive) _killBanner(o),
        _legend(o),
        const SizedBox(height: 12),
        _minScoreCard(o),
        const SizedBox(height: 12),
        for (final r in o.rows) _regionCard(o, r),
        const SizedBox(height: 12),
        _auditCard(o),
      ],
    );
  }

  Widget _killBanner(CoreOverview o) {
    return Container(
      key: const ValueKey('global_kill_banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Глобал kill-switch ФАОЛ — ҳамма ҳудуд амалда ЎЧИҚ'
        '${o.globalKillReason.isEmpty ? '' : '\nСабаб: ${o.globalKillReason}'}',
        style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _legend(CoreOverview o) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ўчиқ — сўров яратиб бўлмайди.', style: TextStyle(fontSize: 12)),
            const Text(
              'Shadow — сўровлар қабул қилинади, мослик ҳисобланади, push ЮБОРИЛМАЙДИ.',
              style: TextStyle(fontSize: 12),
            ),
            const Text(
              'Push — мос таклифчиларга (push чегарасидан юқорига) хабар кетади.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Ҳудуд ёқилиши учун унда камида ${o.minProviders} та ишлай оладиган '
              'таклифчи керак; push учун чегара ўлчаб қўйилган бўлиши шарт. '
              'Ўзгариш 60 сонияда кучга киради.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _minScoreCard(CoreOverview o) {
    final v = o.minScoreAll;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        // Тор экран ва катта шрифтда қирқилмаслиги учун устун (Row эмас).
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              v == null
                  ? 'Push чегараси: ўрнатилмаган — push ёқиб бўлмайди'
                  : 'Push чегараси: $v (барча ҳудудлар учун)',
              key: const ValueKey('min_score_state'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('btn_edit_min_score'),
              onPressed: _busy ? null : () => _editMinScore(o),
              child: const Text('Ўзгартириш'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _regionCard(CoreOverview o, CoreRegionRow r) {
    final shown = r.providers > o.minProviders ? 1.0 : r.providers / o.minProviders;
    return Card(
      key: ValueKey('region_${r.regionId}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(
                  key: ValueKey('chip_${r.regionId}'),
                  label: Text(
                    stateLabel(r.state),
                    key: ValueKey('state_${r.regionId}'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  backgroundColor: _chipColor(r.state),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Таклифчилар:', style: TextStyle(fontSize: 12)),
                Text(
                  '${r.providers} / ${o.minProviders}',
                  key: ValueKey('providers_${r.regionId}'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (r.ready)
                  const Icon(Icons.check_circle, size: 16, color: Colors.green)
                else
                  const Icon(Icons.hourglass_empty, size: 16, color: Colors.orange),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: shown, minHeight: 4),
            if (r.configErrors.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Конфиг огоҳлантириши: ${r.configErrors.join('; ')}',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in const ['off', 'shadow', 'push']) _stateButton(o, r, t),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _chipColor(String state) {
    switch (state) {
      case 'push':
        return Colors.green.shade100;
      case 'shadow':
        return Colors.orange.shade100;
      case 'matching_off':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade300;
    }
  }

  String _blockText(CoreBlock b, CoreRegionRow r, CoreOverview o) {
    switch (b) {
      case CoreBlock.current:
        return 'Ҳозирги ҳолат';
      case CoreBlock.notEnoughProviders:
        return 'Таклифчи ${r.providers} та, камида ${o.minProviders} та керак';
      case CoreBlock.minScoreMissing:
        return 'Push чегараси ўрнатилмаган';
    }
  }

  Widget _stateButton(CoreOverview o, CoreRegionRow r, String target) {
    final block = blockReason(r, target, o);
    final key = ValueKey('btn_${r.regionId}_$target');
    final label = Text(stateLabel(target));
    if (block == CoreBlock.current) {
      return FilledButton(key: key, onPressed: null, child: label);
    }
    final btn = OutlinedButton(
      key: key,
      onPressed: (block == null && !_busy) ? () => _confirm(r, target) : null,
      child: label,
    );
    if (block == null) return btn;
    return Tooltip(message: _blockText(block, r, o), child: btn);
  }

  Widget _auditCard(CoreOverview o) {
    final names = {for (final r in o.rows) r.regionId: r.name};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Охирги ўзгаришлар',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            if (o.audit.isEmpty)
              const Text(
                'Ҳали ўзгариш йўқ',
                key: ValueKey('audit_empty'),
                style: TextStyle(fontSize: 12, color: Colors.black54),
              )
            else
              for (final a in o.audit)
                ListTile(
                  key: ValueKey('audit_${a.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_auditTitle(a, names)),
                  subtitle: Text('${_fmt(a.at)} · ${a.actor}'),
                ),
          ],
        ),
      ),
    );
  }

  String _auditTitle(CoreAuditEntry a, Map<String, String> names) {
    final region = a.regionId == 'all' ? 'Барча ҳудудлар' : (names[a.regionId] ?? a.regionId);
    final parts = <String>[];
    if (a.fromState != a.toState) {
      parts.add('${stateLabel(a.fromState)} → ${stateLabel(a.toState)}');
    }
    if (a.fromMinScore != a.toMinScore) {
      parts.add('чегара: ${a.fromMinScore ?? '—'} → ${a.toMinScore ?? '—'}');
    }
    return '$region: ${parts.isEmpty ? 'ўзгаришсиз' : parts.join('; ')}';
  }

  String _fmt(DateTime? t) {
    if (t == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _MinScoreChoice {
  const _MinScoreChoice(this.value);

  /// `null` — чегарани ўчириш.
  final double? value;
}

/// Чегара киритиш диалоги. Controller'ни ДИАЛОГНИНГ ўзи бошқаради: уни экран
/// `showDialog` қайтгач `dispose` қилса, диалог ёпилиш анимациясида ўчирилган
/// controller'ни ишлатиб хато берарди.
class _MinScoreDialog extends StatefulWidget {
  const _MinScoreDialog({required this.initial});

  final double? initial;

  @override
  State<_MinScoreDialog> createState() => _MinScoreDialogState();
}

class _MinScoreDialogState extends State<_MinScoreDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial?.toString() ?? '');
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Push чегараси (барча ҳудудлар)'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Чегара 50 мослик баҳосидан ўлчаб танланади '
                '(calibrate_push_threshold.js). «90» (фоиз) ёзманг: 0.01 дан 1 гача, '
                'масалан 0.75.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('min_score_field'),
                controller: _ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'push.minScore',
                  errorText: _err,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('min_score_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Бекор'),
        ),
        TextButton(
          key: const ValueKey('min_score_clear'),
          onPressed: () => Navigator.of(context).pop(const _MinScoreChoice(null)),
          child: const Text('Ўчириш'),
        ),
        FilledButton(
          key: const ValueKey('min_score_save'),
          onPressed: () {
            final v = parseMinScoreInput(_ctrl.text);
            if (v == null) {
              setState(() => _err = 'Чегара 0.01 дан 1 гача бўлиши керак (масалан 0.75)');
              return;
            }
            Navigator.of(context).pop(_MinScoreChoice(v));
          },
          child: const Text('Сақлаш'),
        ),
      ],
    );
  }
}

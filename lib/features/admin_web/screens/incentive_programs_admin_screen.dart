import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_name_text.dart';
import '../../../core/geo/geo_selector.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/uz_script.dart';
import '../services/admin_business_orders_service.dart' show parseTesterPhones, invalidTesterPhones;
import '../services/admin_incentives_service.dart';
import '../services/incentive_categories.dart';

/// «Рағбат дастурлари» (эга қарори 2026-11-02): аёллар / машина — AVA дўкони учун бонус.
///
/// Админ: дастур яратиш ва таҳрирлаш, босқич (Ўчиқ → Ички синов → Битта ҳудуд → Ҳамма учун), бюджет
/// панели (берилган / сарфланган / ёнган / бекор / қолган), фойдаланувчи бўйича грант ва журнал, грантни
/// бекор қилиш. Ёзиш — фақат callable ([AdminIncentivesService]); ўқиш — rules'да `isAdmin()`.
class IncentiveProgramsAdminScreen extends StatelessWidget {
  const IncentiveProgramsAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              labelColor: AppColors.primaryText,
              indicatorColor: AppColors.primaryText,
              unselectedLabelColor: Colors.grey.shade600,
              tabs: const [
                Tab(icon: Icon(Icons.card_giftcard, size: 18), text: 'Дастурлар'),
                Tab(icon: Icon(Icons.person_search, size: 18), text: 'Фойдаланувчи'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [_ProgramsTab(), _UserLookupTab()],
            ),
          ),
        ],
      ),
    );
  }
}

const _stageLabels = <String, String>{
  'off': 'Ўчиқ',
  'internal': 'Ички синов',
  'pilot': 'Битта ҳудуд (пилот)',
  'public': 'Ҳамма учун',
};

String _sum(num v) => formatMoney(v);

int _int(Object? v) => v is num ? v.toInt() : 0;

String _date(Object? v) {
  if (v is Timestamp) {
    final d = v.toDate().toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
  return '—';
}

class _ProgramsTab extends StatelessWidget {
  const _ProgramsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('incentive_programs').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('Юклаб бўлмади. Саҳифани янгиланг.'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs.toList()
          ..sort((a, b) => '${a.data()['key']}'.compareTo('${b.data()['key']}'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Рағбат — фойдаланувчига ҳамёнда пул бўлиб кўринади, лекин фақат AVA дўконида '
                    'сарфланади, нақдга ечилмайди ва муддати тугаса ёнади.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  key: const ValueKey('incentive_new'),
                  onPressed: () => _openForm(context, null, null,
                      existingIds: {for (final d in docs) ...[d.id, '${d.data()['key'] ?? ''}']}),
                  icon: const Icon(Icons.add),
                  label: const Text('Янги дастур'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (docs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Ҳали дастур йўқ. «Янги дастур» тугмасини босинг.', textAlign: TextAlign.center),
              ),
            for (final d in docs) _ProgramCard(id: d.id, data: d.data()),
          ],
        );
      },
    );
  }
}

Future<void> _openForm(BuildContext context, String? id, Map<String, dynamic>? data,
    {Set<String> existingIds = const {}}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => IncentiveProgramFormDialog(programId: id, initial: data, existingIds: existingIds),
  );
}

String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

class _ProgramCard extends StatefulWidget {
  const _ProgramCard({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;

  @override
  State<_ProgramCard> createState() => _ProgramCardState();
}

class _ProgramCardState extends State<_ProgramCard> {
  bool _busy = false;

  Future<void> _changeStage(String stage) async {
    final from = '${widget.data['stage'] ?? 'off'}';
    if (stage == from) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Босқични ўзгартириш'),
        content: Text('«${_stageLabels[from]}» → «${_stageLabels[stage]}». Тасдиқлайсизми?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Тасдиқлаш')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AdminIncentivesService().setStage(widget.id, stage);
      messenger.showSnackBar(SnackBar(content: Text('Босқич: ${_stageLabels[stage]}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(incentiveAdminError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final title = (d['title'] is Map ? (d['title'] as Map)['uz_Cyrl'] : null) ?? d['key'] ?? widget.id;
    final aud = d['audience'] is Map ? Map<String, dynamic>.from(d['audience'] as Map) : const <String, dynamic>{};
    final c = d['counters'] is Map ? Map<String, dynamic>.from(d['counters'] as Map) : const <String, dynamic>{};
    final budget = _int(d['budgetTotal']);
    final granted = _int(c['grantedAmount']);
    final spent = _int(c['spentAmount']);
    final expired = _int(c['expiredAmount']);
    final revoked = _int(c['revokedAmount']);
    final left = budget - granted;
    final buckets = d['buckets'] is List ? (d['buckets'] as List) : const [];
    final who = incentiveAudienceText(aud);
    final startAt = d['startAt'] is Timestamp ? (d['startAt'] as Timestamp).millisecondsSinceEpoch : null;
    final endAt = d['endAt'] is Timestamp ? (d['endAt'] as Timestamp).millisecondsSinceEpoch : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('$title  (${d['key']})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                // Махсус дастурлар (`kind`: яқинлар, оила, машина суғуртаси) — ЯГОНА ёзиш йўли ўз модулида;
                // бу ерда фақат кўриш (сервер ҳам PROGRAM_SPECIAL, эга 2026-11-28).
                if (incentiveProgramLocked(widget.id, d))
                  Text(
                    'Таҳрир: ${incentiveLockedWhere(widget.id, d)} · ${_stageLabels[d['stage']] ?? 'Ўчиқ'}',
                    key: ValueKey('incentive_locked_${widget.id}'),
                    style: const TextStyle(color: Colors.black54),
                  )
                else ...[
                DropdownButton<String>(
                  key: ValueKey('incentive_stage_${widget.id}'),
                  value: _stageLabels.containsKey(d['stage']) ? d['stage'] as String : 'off',
                  items: [
                    for (final e in _stageLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: _busy ? null : (v) => v == null ? null : _changeStage(v),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openForm(context, widget.id, d),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Таҳрирлаш'),
                ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text('Кимга: $who', key: ValueKey('incentive_who_${widget.id}'), style: const TextStyle(color: Colors.black87)),
            Text(
              'Ҳар бир кишига: ${_sum(_int(d['amount']))} · буюртманинг ${_int(d['maxOrderSharePct'])}% игача · '
              'муддат ${_int(d['validityDays'])} кун',
            ),
            if (buckets.isNotEmpty)
              Text('Туркумлар: ${buckets.map((b) => b is Map ? '${incentiveCategoryLabel('${b['category']}')} ${formatPrice(_int(b['amount']))}' : '').join(' · ')}')
            else
              const Text('Туркумлар: AVA дўконидаги исталган маҳсулот'),
            if (startAt != null || endAt != null)
              Text(
                [
                  if (startAt != null) 'бошланиш ${_dmy(tashkentDateOf(startAt))}',
                  if (endAt != null) 'охирги кун ${_dmy(incentiveEndInclusiveDay(endAt))} (шу кун ҳам киради)',
                ].join(' · '),
                key: ValueKey('incentive_dates_${widget.id}'),
              ),
            const SizedBox(height: 10),
            _BudgetBar(budget: budget, granted: granted),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('Бюджет: ${_sum(budget)}'),
                Text('Берилган: ${_sum(granted)} (${_int(c['grantedCount'])} та)'),
                Text('Сарфланган: ${_sum(spent)}'),
                Text('Ёнган: ${_sum(expired)}'),
                Text('Бекор қилинган: ${_sum(revoked)}'),
                Text('Қолган бюджет: ${_sum(left < 0 ? 0 : left)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (_int(d['budgetDaily']) > 0) Text('Кунлик чегара: ${_sum(_int(d['budgetDaily']))}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.budget, required this.granted});
  final int budget;
  final int granted;

  @override
  Widget build(BuildContext context) {
    final v = budget <= 0 ? 0.0 : (granted / budget).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(value: v, minHeight: 10, backgroundColor: Colors.grey.shade200, color: AppColors.primary),
    );
  }
}

/// Дастур формаси (эга 2026-11-28 соддалаштириш). Пул — бутун сўм.
///
/// • Номи: кирилл → лотин автоматик ([UzScript.toLatin]), таҳрирлаш мумкин; рус — қўлда.
/// • Калит: лотин номдан автоматик, фақат ЯНГИ дастурда таҳрирланади (банд/махсус калит — рад).
/// • Туркумлар рўйхатдан ([kIncentiveProgramCategories]); туркум бўлса «Ҳар бир кишига» = йиғинди.
/// • Ёш бўш — чекловсиз (0/120 юборилади). «Фақат янги фойдаланувчилар» ўчиқ — 2020-01-01 (ҳамма).
/// • Синовчилар/туманлар фақат «Ички синов»/«Пилот»да кўринади (яширилганда ҳам ўчирилмайди).
/// • Саналар Тошкент куни бўйича: бошланиш — кун 00:00; тугаш — танланган кун ТЎЛИҚ киради (кейинги кун 00:00).
///   Санага тегилмаса — сақланган вақт айнан қайтарилади (эски ҳужжатлар ўзгармайди).
class IncentiveProgramFormDialog extends StatefulWidget {
  const IncentiveProgramFormDialog({
    super.key,
    this.programId,
    this.initial,
    this.existingIds = const {},
    @visibleForTesting this.onSave,
    @visibleForTesting this.pickDistrict,
  });
  final String? programId;
  final Map<String, dynamic>? initial;

  /// Мавжуд дастур ID/калитлари — янги калит банд эмаслигини текшириш учун.
  final Set<String> existingIds;

  /// Тест учун (бўлмаса — [AdminIncentivesService.upsertProgram]).
  final Future<void> Function(Map<String, dynamic> program, String? programId)? onSave;

  /// Тест учун (бўлмаса — мавжуд [GeoAreaPickScreen]).
  final Future<GeoArea?> Function(BuildContext context)? pickDistrict;

  @override
  State<IncentiveProgramFormDialog> createState() => _ProgramFormDialogState();
}

class _BucketRow {
  _BucketRow(this.category, int amount) : amount = TextEditingController(text: amount > 0 ? '$amount' : '');
  String category;
  final TextEditingController amount;
}

class _ProgramFormDialogState extends State<IncentiveProgramFormDialog> {
  final _key = TextEditingController();
  final _cyrl = TextEditingController();
  final _latn = TextEditingController();
  final _ru = TextEditingController();
  final _ageMin = TextEditingController();
  final _ageMax = TextEditingController();
  final _amount = TextEditingController();
  final _share = TextEditingController();
  final _validity = TextEditingController();
  final _budget = TextEditingController();
  final _people = TextEditingController();
  final _daily = TextEditingController();
  final _phoneInput = TextEditingController();
  String _stage = 'off';
  String _gender = 'any';
  bool _requireCar = false;
  bool _latnAuto = true;
  bool _keyAuto = true;

  bool _onlyNew = true;
  DateTime _sinceDay = tashkentDateOf(DateTime.now().millisecondsSinceEpoch);
  int? _sinceOrigMs;
  bool _sinceChanged = false;

  DateTime? _startDay;
  int? _startOrigMs;
  bool _startChanged = false;
  DateTime? _endDay;
  int? _endOrigMs;
  bool _endChanged = false;

  List<String> _phones = [];
  String? _phoneError;
  List<String> _districts = [];
  final Map<String, String> _districtLabels = {};

  final List<_BucketRow> _buckets = [];
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.programId == null;

  String get _origKey => '${widget.initial?['key'] ?? widget.programId ?? ''}';

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    if (d == null) {
      _share.text = '30';
      _validity.text = '90';
      _daily.text = '0';
      return;
    }
    final t = d['title'] is Map ? Map<String, dynamic>.from(d['title'] as Map) : const <String, dynamic>{};
    final a = d['audience'] is Map ? Map<String, dynamic>.from(d['audience'] as Map) : const <String, dynamic>{};
    _key.text = _origKey;
    _cyrl.text = '${t['uz_Cyrl'] ?? ''}';
    _latn.text = '${t['uz_Latn'] ?? ''}';
    _ru.text = '${t['ru'] ?? ''}';
    _latnAuto = _latn.text.isEmpty || _latn.text == UzScript.toLatin(_cyrl.text);
    _stage = _stageLabels.containsKey(d['stage']) ? d['stage'] as String : 'off';
    _gender = const ['female', 'male', 'any'].contains(a['gender']) ? a['gender'] as String : 'any';
    final ageMin = _int(a['ageMin']);
    final ageMax = a['ageMax'] == null ? 120 : _int(a['ageMax']);
    _ageMin.text = ageMin > 0 ? '$ageMin' : '';
    _ageMax.text = ageMax < 120 ? '$ageMax' : '';
    _requireCar = a['requireCar'] == true;
    if (a['newUsersSince'] is Timestamp) {
      final ms = (a['newUsersSince'] as Timestamp).millisecondsSinceEpoch;
      _sinceOrigMs = ms;
      _onlyNew = !incentiveSinceMeansAll(ms);
      if (_onlyNew) _sinceDay = tashkentDateOf(ms);
    }
    _amount.text = _int(d['amount']) > 0 ? '${_int(d['amount'])}' : '';
    _share.text = '${_int(d['maxOrderSharePct'])}';
    _validity.text = '${_int(d['validityDays'])}';
    _budget.text = '${_int(d['budgetTotal'])}';
    _daily.text = '${_int(d['budgetDaily'])}';
    _phones = d['internalPhones'] is List ? [for (final p in d['internalPhones'] as List) '$p'] : [];
    _districts = d['pilotDistrictIds'] is List ? [for (final p in d['pilotDistrictIds'] as List) '$p'] : [];
    if (d['startAt'] is Timestamp) {
      _startOrigMs = (d['startAt'] as Timestamp).millisecondsSinceEpoch;
      _startDay = tashkentDateOf(_startOrigMs!);
    }
    if (d['endAt'] is Timestamp) {
      _endOrigMs = (d['endAt'] as Timestamp).millisecondsSinceEpoch;
      _endDay = incentiveEndInclusiveDay(_endOrigMs!);
    }
    if (d['buckets'] is List) {
      for (final b in d['buckets'] as List) {
        if (b is Map) _buckets.add(_BucketRow('${b['category'] ?? ''}', _int(b['amount'])));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _key, _cyrl, _latn, _ru, _ageMin, _ageMax, _amount, _share, _validity, _budget, _people, _daily, _phoneInput,
    ]) {
      c.dispose();
    }
    for (final b in _buckets) {
      b.amount.dispose();
    }
    super.dispose();
  }

  int? _num(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'[\s ]'), ''));

  int get _bucketSum => _buckets.fold<int>(0, (s, b) => s + (_num(b.amount) ?? 0));

  /// Ҳар бир кишига: туркум бўлса — йиғинди (ўқиш учун), бўлмаса — қўлда.
  int? get _effectiveAmount => _buckets.isNotEmpty ? _bucketSum : _num(_amount);

  // ── Ном / калит ──

  void _onCyrlChanged(String v) {
    if (_latnAuto) _latn.text = UzScript.toLatin(v);
    _syncKey();
    setState(() {});
  }

  void _onLatnChanged(String v) {
    _latnAuto = v == UzScript.toLatin(_cyrl.text);
    _syncKey();
    setState(() {});
  }

  void _syncKey() {
    if (_isNew && _keyAuto) _key.text = incentiveKeyFromLatin(_latn.text);
  }

  void _onKeyChanged(String v) {
    setState(() => _keyAuto = v.isEmpty || v == incentiveKeyFromLatin(_latn.text));
  }

  // ── Пул ──

  void _onAmountChanged() {
    final people = _num(_people);
    final amount = _effectiveAmount;
    if (people != null && people > 0 && amount != null && amount > 0) _budget.text = '${people * amount}';
    setState(() {});
  }

  void _addBucket() {
    final used = _buckets.map((b) => b.category).toSet();
    final free = kIncentiveProgramCategories.keys.firstWhere((k) => !used.contains(k), orElse: () => '');
    // Биринчи туркум — жорий миқдор билан (йиғинди ўзгармасин).
    final amount = _buckets.isEmpty ? (_num(_amount) ?? 0) : 0;
    setState(() => _buckets.add(_BucketRow(free, amount)));
    _onAmountChanged();
  }

  void _removeBucket(_BucketRow b) {
    if (_buckets.length == 1) _amount.text = _bucketSum > 0 ? '$_bucketSum' : _amount.text;
    setState(() => _buckets.remove(b));
    b.amount.dispose();
    _onAmountChanged();
  }

  // ── Синовчилар / туманлар ──

  /// Киритилган рақамларни чипларга қўшади. → false: нотўғри рақам бор (хато кўрсатилади).
  bool _addPhones() {
    final parsed = parseTesterPhones(_phoneInput.text);
    if (parsed.isEmpty) return true;
    final bad = invalidTesterPhones(parsed);
    if (bad.isNotEmpty) {
      setState(() => _phoneError = 'Нотўғри рақам: ${bad.take(3).join(', ')} (998 + 9 рақам ёки 9 рақам)');
      return false;
    }
    setState(() {
      _phones = ({..._phones, ...parsed}.toList()..sort());
      _phoneInput.clear();
      _phoneError = null;
    });
    return true;
  }

  Future<void> _addDistrict() async {
    final pick = widget.pickDistrict ??
        (BuildContext ctx) => Navigator.of(ctx).push<GeoArea>(MaterialPageRoute(builder: (_) => const GeoAreaPickScreen()));
    final area = await pick(context);
    if (!mounted || area == null || area.districtId.isEmpty) return;
    setState(() {
      if (!_districts.contains(area.districtId)) _districts = [..._districts, area.districtId];
      if (area.label.isNotEmpty) _districtLabels[area.districtId] = area.label;
    });
  }

  // ── Саналар ──

  Future<DateTime?> _pickDate(DateTime? current) {
    final init = current ?? tashkentDateOf(DateTime.now().millisecondsSinceEpoch);
    return showDatePicker(
      context: context,
      initialDate: init,
      firstDate: init.isBefore(DateTime(2020)) ? init : DateTime(2020),
      lastDate: DateTime(2036),
    );
  }

  int? _startMs() => _startDay == null
      ? null
      : (!_startChanged && _startOrigMs != null ? _startOrigMs : tashkentDayStartMs(_startDay!));

  int? _endMs() => _endDay == null
      ? null
      : (!_endChanged && _endOrigMs != null ? _endOrigMs : tashkentDayEndExclusiveMs(_endDay!));

  int _sinceMs() {
    if (!_onlyNew) return kIncentiveAllUsersSinceMs;
    final orig = _sinceOrigMs;
    if (!_sinceChanged && orig != null && !incentiveSinceMeansAll(orig)) return orig;
    return tashkentDayStartMs(_sinceDay);
  }

  // ── Сақлаш ──

  String? _validate() {
    if (_isNew) {
      final e = incentiveKeyError(_key.text.trim(), widget.existingIds);
      if (e != null) return e;
    }
    if (_cyrl.text.trim().isEmpty || _latn.text.trim().isEmpty || _ru.text.trim().isEmpty) {
      return 'Номини уч тилда ёзинг (кирилл, лотин, рус).';
    }
    final min = _num(_ageMin) ?? 0;
    final max = _num(_ageMax) ?? 120;
    if (min > 120 || max > 120 || min > max) return 'Ёш оралиғи нотўғри (0–120, «дан» ≤ «гача»).';
    for (final b in _buckets) {
      if (b.category.isEmpty) return 'Ҳар бир туркум учун турни танланг.';
      if ((_num(b.amount) ?? 0) <= 0) return 'Ҳар бир туркум миқдори 1 сўмдан кам бўлмасин.';
    }
    final amount = _effectiveAmount ?? 0;
    if (amount <= 0) return 'Ҳар бир кишига миқдорни киритинг.';
    final total = _num(_budget) ?? 0;
    if (total < amount) return 'Умумий бюджет камида битта киши миқдорича бўлсин.';
    final dailyErr = incentiveBudgetDailyError(amount: amount, total: total, daily: _num(_daily) ?? 0);
    if (dailyErr != null) return dailyErr;
    if (_stage == 'internal' && _phones.isEmpty) return '«Ички синов» учун камида битта синовчи рақами керак.';
    if (_stage == 'pilot' && _phones.isEmpty && _districts.isEmpty) {
      return '«Пилот» учун камида битта туман ёки синовчи рақами керак.';
    }
    final s = _startMs();
    final e = _endMs();
    if (s != null && e != null && e <= s) return 'Тугаш санаси бошланишдан олдин бўлмасин.';
    return null;
  }

  Future<void> _save() async {
    if (_phoneInput.text.trim().isNotEmpty && !_addPhones()) return;
    final invalid = _validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final program = <String, dynamic>{
      'key': _isNew ? _key.text.trim() : _origKey,
      'title': {'uz_Cyrl': _cyrl.text.trim(), 'uz_Latn': _latn.text.trim(), 'ru': _ru.text.trim()},
      'stage': _stage,
      'internalPhones': _phones,
      'pilotDistrictIds': _districts,
      'audience': {
        'gender': _gender,
        'ageMin': _num(_ageMin) ?? 0,
        'ageMax': _num(_ageMax) ?? 120,
        'requireCar': _requireCar,
        'newUsersSince': _sinceMs(),
      },
      'amount': _effectiveAmount,
      'buckets': [
        for (final b in _buckets) {'category': b.category, 'amount': _num(b.amount)},
      ],
      'maxOrderSharePct': _num(_share),
      'validityDays': _num(_validity),
      'budgetTotal': _num(_budget),
      'budgetDaily': _num(_daily) ?? 0,
      'startAt': _startMs(),
      'endAt': _endMs(),
    };
    try {
      final save = widget.onSave;
      if (save != null) {
        await save(program, widget.programId);
      } else {
        await AdminIncentivesService().upsertProgram(program, programId: widget.programId);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = incentiveAdminError(e);
        });
      }
    }
  }

  Widget _field(
    TextEditingController c,
    String label, {
    Key? key,
    bool digits = false,
    double width = 220,
    String? hint,
    String? helper,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        key: key,
        controller: c,
        keyboardType: digits ? TextInputType.number : TextInputType.text,
        inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 2,
          errorText: errorText,
          errorMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _section(String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)));

  List<Widget> _bucketRows() {
    return [
      for (final b in _buckets)
        Padding(
          key: ObjectKey(b),
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('incentive_bucket_cat_${_buckets.indexOf(b)}'),
                initialValue: b.category.isEmpty ? null : b.category,
                hint: const Text('Туркумни танланг'),
                decoration: const InputDecoration(labelText: 'Туркум', border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final e in kIncentiveProgramCategories.entries)
                    if (e.key == b.category || !_buckets.any((o) => o != b && o.category == e.key))
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  // Рўйхатда йўқ эски калит — йўқолмасин.
                  if (b.category.isNotEmpty && !kIncentiveProgramCategories.containsKey(b.category))
                    DropdownMenuItem(value: b.category, child: Text('${b.category} (бошқа)')),
                ],
                onChanged: (v) => setState(() => b.category = v ?? ''),
              ),
            ),
            const SizedBox(width: 12),
            _field(b.amount, 'Миқдор (сўм)',
                key: ValueKey('incentive_bucket_amount_${_buckets.indexOf(b)}'),
                digits: true,
                width: 180,
                onChanged: (_) => _onAmountChanged()),
            IconButton(
              key: ValueKey('incentive_bucket_remove_${_buckets.indexOf(b)}'),
              tooltip: 'Олиб ташлаш',
              onPressed: () => _removeBucket(b),
              icon: const Icon(Icons.delete_outline),
            ),
          ]),
        ),
    ];
  }

  List<Widget> _stageTargets() {
    final showPhones = _stage == 'internal' || _stage == 'pilot';
    final showDistricts = _stage == 'pilot';
    if (!showPhones) return const [];
    return [
      const SizedBox(height: 12),
      Text(
        _stage == 'internal' ? 'Синовчилар (фақат шу рақамлар олади)' : 'Синовчилар (туманлардан ташқари ҳам олади)',
        style: TextStyle(color: Colors.grey.shade800),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final p in _phones)
          InputChip(
            key: ValueKey('incentive_phone_$p'),
            label: Text(p),
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () => setState(() => _phones = _phones.where((x) => x != p).toList()),
          ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        SizedBox(
          width: 320,
          child: TextField(
            key: const ValueKey('incentive_phone_input'),
            controller: _phoneInput,
            keyboardType: TextInputType.phone,
            onSubmitted: (_) => _addPhones(),
            decoration: InputDecoration(
              labelText: 'Синовчи рақами',
              hintText: '998901234567 ёки 901234567',
              helperText: 'Бир нечтаси — вергул билан',
              errorText: _phoneError,
              errorMaxLines: 2,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const ValueKey('incentive_phone_add'),
          onPressed: _addPhones,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Қўшиш'),
        ),
      ]),
      if (showDistricts) ...[
        const SizedBox(height: 12),
        Text('Пилот туманлар', style: TextStyle(color: Colors.grey.shade800)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in _districts)
            InputChip(
              key: ValueKey('incentive_district_$id'),
              label: GeoDistrictText(id, fallback: _districtLabels[id] ?? id),
              deleteIcon: const Icon(Icons.close, size: 18),
              onDeleted: () => setState(() => _districts = _districts.where((x) => x != id).toList()),
            ),
          ActionChip(
            key: const ValueKey('incentive_add_district'),
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Туман қўшиш'),
            onPressed: _addDistrict,
          ),
        ]),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final amount = _effectiveAmount ?? 0;
    final total = _num(_budget) ?? 0;
    final dailyErr = (_num(_daily) ?? 0) == 0 ? null : incentiveBudgetDailyError(amount: amount, total: total, daily: _num(_daily) ?? 0);
    final keyErr = _isNew && _key.text.isNotEmpty ? incentiveKeyError(_key.text.trim(), widget.existingIds) : null;
    return AlertDialog(
      title: Text(_isNew ? 'Янги рағбат дастури' : 'Дастурни таҳрирлаш'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section('Номи'),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _field(_cyrl, 'Номи (кирилл)', key: const ValueKey('incentive_name_cyrl'), width: 236, onChanged: _onCyrlChanged),
                _field(_latn, 'Номи (лотин)',
                    key: const ValueKey('incentive_name_latn'),
                    width: 236,
                    helper: _latnAuto ? 'Кириллдан автоматик' : null,
                    onChanged: _onLatnChanged),
                _field(_ru, 'Номи (рус)', key: const ValueKey('incentive_name_ru'), width: 236),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (_isNew)
                  _field(_key, 'Калит (лотин номдан)',
                      key: const ValueKey('incentive_key'),
                      width: 280,
                      helper: _keyAuto ? 'Автоматик; кейин ўзгармайди' : 'Кейин ўзгармайди',
                      errorText: keyErr,
                      onChanged: _onKeyChanged)
                else
                  SizedBox(
                    width: 280,
                    child: Text('Калит: $_origKey', key: const ValueKey('incentive_key_readonly'), style: const TextStyle(color: Colors.black54)),
                  ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: const ValueKey('incentive_form_stage'),
                    initialValue: _stage,
                    decoration: const InputDecoration(labelText: 'Босқич', border: OutlineInputBorder(), isDense: true),
                    items: [for (final e in _stageLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _stage = v ?? 'off'),
                  ),
                ),
              ]),
              ..._stageTargets(),
              const Divider(height: 28),
              _section('Кимга'),
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _gender,
                    decoration: const InputDecoration(labelText: 'Жинс', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'female', child: Text('Аёллар')),
                      DropdownMenuItem(value: 'male', child: Text('Эркаклар')),
                      DropdownMenuItem(value: 'any', child: Text('Ҳамма')),
                    ],
                    onChanged: (v) => setState(() => _gender = v ?? 'any'),
                  ),
                ),
                _field(_ageMin, 'Ёш (дан)', key: const ValueKey('incentive_age_min'), digits: true, width: 120, hint: 'чекловсиз'),
                _field(_ageMax, 'Ёш (гача)', key: const ValueKey('incentive_age_max'), digits: true, width: 120, hint: 'чекловсиз'),
                FilterChip(
                  label: const Text('Машина профили шарт'),
                  selected: _requireCar,
                  onSelected: (v) => setState(() => _requireCar = v),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 330,
                  child: SwitchListTile(
                    key: const ValueKey('incentive_only_new'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Фақат янги фойдаланувчилар'),
                    subtitle: Text(_onlyNew ? 'Шу санадан кейин рўйхатдан ўтганлар' : 'Эски ва янги — ҳамма'),
                    value: _onlyNew,
                    onChanged: (v) => setState(() => _onlyNew = v),
                  ),
                ),
                if (_onlyNew)
                  OutlinedButton.icon(
                    key: const ValueKey('incentive_since'),
                    onPressed: () async {
                      final p = await _pickDate(_sinceDay);
                      if (p != null) {
                        setState(() {
                          _sinceDay = p;
                          _sinceChanged = true;
                        });
                      }
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('Шу санадан: ${_dmy(_sinceDay)}'),
                  ),
              ]),
              const Divider(height: 28),
              _section('Пул'),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Туркумлар (бўш — AVA дўконидаги исталган маҳсулот). Туркум қўшилса, «Ҳар бир кишига» = уларнинг йиғиндиси.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('incentive_add_bucket'),
                    onPressed: _buckets.length >= kIncentiveProgramCategories.length + 1 ? null : _addBucket,
                    icon: const Icon(Icons.add),
                    label: const Text('Туркум қўшиш'),
                  ),
                ],
              ),
              ..._bucketRows(),
              const SizedBox(height: 14),
              Wrap(spacing: 12, runSpacing: 12, children: [
                if (_buckets.isEmpty)
                  _field(_amount, 'Ҳар бир кишига (сўм)',
                      key: const ValueKey('incentive_amount'), digits: true, width: 230, onChanged: (_) => _onAmountChanged())
                else
                  SizedBox(
                    width: 230,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Ҳар бир кишига (сўм)',
                        helperText: 'Туркумлар йиғиндиси',
                        border: OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                      ),
                      child: Text(formatPrice(_bucketSum), key: const ValueKey('incentive_amount_sum')),
                    ),
                  ),
                _field(_share, 'Буюртмадаги улуш (%)', digits: true, width: 180),
                _field(_validity, 'Муддат (кун)', digits: true, width: 140),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _field(_people, 'Неча кишига',
                    key: const ValueKey('incentive_people'),
                    digits: true,
                    width: 200,
                    hint: 'ихтиёрий',
                    helper: 'Бюджет = кишилар × миқдор',
                    onChanged: (_) => _onAmountChanged()),
                _field(_budget, 'Умумий бюджет (сўм)',
                    key: const ValueKey('incentive_budget'),
                    digits: true,
                    width: 220,
                    helper: amount > 0 && total > 0 ? '≈ ${total ~/ amount} кишига етади' : null,
                    onChanged: (_) => setState(() {})),
                _field(_daily, 'Кунлик бюджет (0 — чекловсиз)',
                    key: const ValueKey('incentive_daily'),
                    digits: true,
                    width: 260,
                    errorText: dailyErr,
                    onChanged: (_) => setState(() {})),
              ]),
              const Divider(height: 28),
              _section('Муддат'),
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  key: const ValueKey('incentive_start'),
                  onPressed: () async {
                    final p = await _pickDate(_startDay);
                    if (p != null) {
                      setState(() {
                        _startDay = p;
                        _startChanged = true;
                      });
                    }
                  },
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(_startDay == null ? 'Бошланиш: дарҳол' : 'Бошланиш: ${_dmy(_startDay!)} (00:00 дан)'),
                ),
                if (_startDay != null)
                  TextButton(onPressed: () => setState(() => _startDay = null), child: const Text('тозалаш')),
                OutlinedButton.icon(
                  key: const ValueKey('incentive_end'),
                  onPressed: () async {
                    final p = await _pickDate(_endDay);
                    if (p != null) {
                      setState(() {
                        _endDay = p;
                        _endChanged = true;
                      });
                    }
                  },
                  icon: const Icon(Icons.stop, size: 18),
                  label: Text(_endDay == null ? 'Охирги кун: муддатсиз' : 'Охирги кун: ${_dmy(_endDay!)} (шу кун ҳам киради)'),
                ),
                if (_endDay != null)
                  TextButton(onPressed: () => setState(() => _endDay = null), child: const Text('тозалаш')),
              ]),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Саналар Тошкент вақти бўйича.', style: TextStyle(color: Colors.black54, fontSize: 12)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(_error!, key: const ValueKey('incentive_form_error'), style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          key: const ValueKey('incentive_save'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Сақлаш'),
        ),
      ],
    );
  }
}

/// Фойдаланувчи бўйича: грантлар, журнал, бекор қилиш.
class _UserLookupTab extends StatefulWidget {
  const _UserLookupTab();

  @override
  State<_UserLookupTab> createState() => _UserLookupTabState();
}

class _UserLookupTabState extends State<_UserLookupTab> {
  final _phone = TextEditingController();
  String _uid = '';

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _search() {
    final uid = canonicalPhoneId(_phone.text);
    setState(() => _uid = uid.length >= 11 ? uid : '');
  }

  Future<void> _revoke(String grantId) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Рағбатни бекор қилиш'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Сабаб (журналга ёзилади)', border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Йўқ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Бекор қилиш')),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final amount = await AdminIncentivesService().revokeGrant(grantId, text);
      messenger.showSnackBar(SnackBar(content: Text(amount > 0 ? 'Бекор қилинди: ${_sum(amount)}' : 'Рағбат аллақачон фаол эмас.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(incentiveAdminError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(labelText: 'Телефон рақам', hintText: '998901234567', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(onPressed: _search, icon: const Icon(Icons.search), label: const Text('Қидириш')),
        ]),
        const SizedBox(height: 16),
        if (_uid.isEmpty)
          const Text('Рақам киритинг (998 билан ёки 9 хонали).', style: TextStyle(color: Colors.black54))
        else ...[
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.collection('users').doc(_uid).snapshots(),
            builder: (context, s) {
              final u = s.data?.data();
              if (u == null) return const Text('Фойдаланувчи топилмади.');
              return Text(
                'Шахсий пул: ${_sum(_int(u['bonusBalance']))} · Рағбат қолдиғи: ${_sum(_int(u['incentiveBalance']))} · '
                'Жинс: ${u['gender'] ?? '—'} · Туғилган сана: ${u['birthDate'] ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text('Рағбатлар', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('incentive_grants').where('uid', isEqualTo: _uid).snapshots(),
            builder: (context, s) {
              if (s.hasError) return const Text('Юклаб бўлмади.');
              if (!s.hasData) return const LinearProgressIndicator();
              if (s.data!.docs.isEmpty) return const Text('Рағбат берилмаган.');
              return Column(children: [
                for (final g in s.data!.docs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${g.data()['programId']} · ${_sum(_int(g.data()['amount']))} · қолдиқ ${_sum(_int(g.data()['remaining']))}'),
                    subtitle: Text(
                      'Ҳолат: ${g.data()['status']} · берилган ${_date(g.data()['createdAt'])} · муддат ${_date(g.data()['expiresAt'])}\n'
                      'Туркумлар: ${g.data()['buckets'] is Map ? (g.data()['buckets'] as Map).entries.map((e) => '${e.key} ${formatPrice(_int(e.value))}').join(' · ') : '—'}',
                    ),
                    isThreeLine: true,
                    trailing: g.data()['status'] == 'active'
                        ? TextButton(onPressed: () => _revoke(g.id), child: const Text('Бекор қилиш'))
                        : null,
                  ),
              ]);
            },
          ),
          const SizedBox(height: 12),
          const Text('Журнал', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('incentive_ledger').where('uid', isEqualTo: _uid).snapshots(),
            builder: (context, s) {
              if (s.hasError) return const Text('Юклаб бўлмади.');
              if (!s.hasData) return const LinearProgressIndicator();
              final docs = s.data!.docs.toList()
                ..sort((a, b) {
                  final ta = a.data()['at']; final tb = b.data()['at'];
                  return (tb is Timestamp ? tb.millisecondsSinceEpoch : 0).compareTo(ta is Timestamp ? ta.millisecondsSinceEpoch : 0);
                });
              if (docs.isEmpty) return const Text('Ёзув йўқ.');
              const types = {'grant': 'Берилди', 'spend': 'Сарфланди', 'refund': 'Қайтди', 'expire': 'Ёнди', 'revoke': 'Бекор қилинди'};
              return Column(children: [
                for (final e in docs)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long, size: 18),
                    title: Text('${types[e.data()['type']] ?? e.data()['type']} · ${_sum(_int(e.data()['amount']))} · ${e.data()['programId'] ?? ''}'),
                    subtitle: Text('${_date(e.data()['at'])}${e.data()['reason'] != null ? ' · ${e.data()['reason']}' : ''}'),
                  ),
              ]);
            },
          ),
        ],
      ],
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../services/admin_incentives_service.dart';

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
                  onPressed: () => _openForm(context, null, null),
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

Future<void> _openForm(BuildContext context, String? id, Map<String, dynamic>? data) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgramFormDialog(programId: id, initial: data),
  );
}

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
    final gender = '${aud['gender'] ?? 'any'}';
    final who = [
      gender == 'female' ? 'аёллар' : gender == 'male' ? 'эркаклар' : 'ҳамма',
      '${_int(aud['ageMin'])}–${_int(aud['ageMax'])} ёш',
      if (aud['requireCar'] == true) 'машина профили шарт',
      'янгилар: ${_date(aud['newUsersSince'])} дан',
    ].join(' · ');
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
            ),
            const SizedBox(height: 6),
            Text('Кимга: $who', style: const TextStyle(color: Colors.black87)),
            Text(
              'Ҳар бир кишига: ${_sum(_int(d['amount']))} · буюртманинг ${_int(d['maxOrderSharePct'])}% игача · '
              'муддат ${_int(d['validityDays'])} кун',
            ),
            if (buckets.isNotEmpty)
              Text('Туркумлар: ${buckets.map((b) => b is Map ? '${b['category']} ${formatPrice(_int(b['amount']))}' : '').join(' · ')}')
            else
              const Text('Туркумлар: AVA дўконидаги исталган маҳсулот'),
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

/// Дастур формаси. Пул — бутун сўм; туркумлар йиғиндиси умумий миқдорга тенг (сервер ҳам текширади).
class _ProgramFormDialog extends StatefulWidget {
  const _ProgramFormDialog({this.programId, this.initial});
  final String? programId;
  final Map<String, dynamic>? initial;

  @override
  State<_ProgramFormDialog> createState() => _ProgramFormDialogState();
}

class _BucketRow {
  _BucketRow(String category, int amount)
      : category = TextEditingController(text: category),
        amount = TextEditingController(text: amount > 0 ? '$amount' : '');
  final TextEditingController category;
  final TextEditingController amount;
}

class _ProgramFormDialogState extends State<_ProgramFormDialog> {
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
  final _daily = TextEditingController();
  final _internal = TextEditingController();
  final _pilot = TextEditingController();
  String _stage = 'off';
  String _gender = 'any';
  bool _requireCar = false;
  DateTime _since = DateTime.now();
  DateTime? _start;
  DateTime? _end;
  final List<_BucketRow> _buckets = [];
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.programId == null;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    if (d == null) {
      _share.text = '30';
      _validity.text = '90';
      _daily.text = '0';
      _ageMin.text = '0';
      _ageMax.text = '120';
      return;
    }
    final t = d['title'] is Map ? Map<String, dynamic>.from(d['title'] as Map) : const <String, dynamic>{};
    final a = d['audience'] is Map ? Map<String, dynamic>.from(d['audience'] as Map) : const <String, dynamic>{};
    _key.text = '${d['key'] ?? ''}';
    _cyrl.text = '${t['uz_Cyrl'] ?? ''}';
    _latn.text = '${t['uz_Latn'] ?? ''}';
    _ru.text = '${t['ru'] ?? ''}';
    _stage = _stageLabels.containsKey(d['stage']) ? d['stage'] as String : 'off';
    _gender = const ['female', 'male', 'any'].contains(a['gender']) ? a['gender'] as String : 'any';
    _ageMin.text = '${_int(a['ageMin'])}';
    _ageMax.text = '${a['ageMax'] == null ? 120 : _int(a['ageMax'])}';
    _requireCar = a['requireCar'] == true;
    if (a['newUsersSince'] is Timestamp) _since = (a['newUsersSince'] as Timestamp).toDate();
    _amount.text = '${_int(d['amount'])}';
    _share.text = '${_int(d['maxOrderSharePct'])}';
    _validity.text = '${_int(d['validityDays'])}';
    _budget.text = '${_int(d['budgetTotal'])}';
    _daily.text = '${_int(d['budgetDaily'])}';
    _internal.text = (d['internalPhones'] is List ? (d['internalPhones'] as List).join(', ') : '');
    _pilot.text = (d['pilotDistrictIds'] is List ? (d['pilotDistrictIds'] as List).join(', ') : '');
    if (d['startAt'] is Timestamp) _start = (d['startAt'] as Timestamp).toDate();
    if (d['endAt'] is Timestamp) _end = (d['endAt'] as Timestamp).toDate();
    if (d['buckets'] is List) {
      for (final b in d['buckets'] as List) {
        if (b is Map) _buckets.add(_BucketRow('${b['category'] ?? ''}', _int(b['amount'])));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_key, _cyrl, _latn, _ru, _ageMin, _ageMax, _amount, _share, _validity, _budget, _daily, _internal, _pilot]) {
      c.dispose();
    }
    for (final b in _buckets) {
      b.category.dispose();
      b.amount.dispose();
    }
    super.dispose();
  }

  int? _num(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'[\s ]'), ''));

  int get _bucketSum => _buckets.fold<int>(0, (s, b) => s + (_num(b.amount) ?? 0));

  List<String> _list(TextEditingController c) =>
      c.text.split(RegExp(r'[,\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _pickDate(DateTime? current, ValueChanged<DateTime?> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2026),
      lastDate: DateTime(2036),
    );
    if (picked != null) setState(() => onPicked(picked));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final amount = _num(_amount);
    if (_buckets.isNotEmpty && amount != null && _bucketSum != amount) {
      setState(() {
        _saving = false;
        _error = 'Туркумлар йиғиндиси (${formatPrice(_bucketSum)}) умумий миқдорга (${formatPrice(amount)}) тенг эмас.';
      });
      return;
    }
    final program = <String, dynamic>{
      'key': _key.text.trim(),
      'title': {'uz_Cyrl': _cyrl.text.trim(), 'uz_Latn': _latn.text.trim(), 'ru': _ru.text.trim()},
      'stage': _stage,
      'internalPhones': _list(_internal).map(canonicalPhoneId).toList(),
      'pilotDistrictIds': _list(_pilot),
      'audience': {
        'gender': _gender,
        'ageMin': _num(_ageMin),
        'ageMax': _num(_ageMax),
        'requireCar': _requireCar,
        'newUsersSince': DateTime(_since.year, _since.month, _since.day).millisecondsSinceEpoch,
      },
      'amount': amount,
      'buckets': [
        for (final b in _buckets) {'category': b.category.text.trim(), 'amount': _num(b.amount)},
      ],
      'maxOrderSharePct': _num(_share),
      'validityDays': _num(_validity),
      'budgetTotal': _num(_budget),
      'budgetDaily': _num(_daily) ?? 0,
      'startAt': _start?.millisecondsSinceEpoch,
      'endAt': _end?.millisecondsSinceEpoch,
    };
    try {
      await AdminIncentivesService().upsertProgram(program, programId: widget.programId);
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

  Widget _field(TextEditingController c, String label, {bool digits = false, double width = 220, String? hint, bool enabled = true}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        enabled: enabled,
        keyboardType: digits ? TextInputType.number : TextInputType.text,
        inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Янги рағбат дастури' : 'Дастурни таҳрирлаш'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                _field(_key, 'Калит (лотин, масалан women)', enabled: _isNew),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _stage,
                    decoration: const InputDecoration(labelText: 'Босқич', border: OutlineInputBorder(), isDense: true),
                    items: [for (final e in _stageLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _stage = v ?? 'off'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _field(_cyrl, 'Номи (кирилл)', width: 236),
                _field(_latn, 'Номи (лотин)', width: 236),
                _field(_ru, 'Номи (рус)', width: 236),
              ]),
              const Divider(height: 28),
              const Text('Кимга', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
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
                _field(_ageMin, 'Ёш (дан)', digits: true, width: 110),
                _field(_ageMax, 'Ёш (гача)', digits: true, width: 110),
                FilterChip(
                  label: const Text('Машина профили шарт'),
                  selected: _requireCar,
                  onSelected: (v) => setState(() => _requireCar = v),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(_since, (d) => _since = d ?? _since),
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('Янгилар — шу санадан: ${_since.day}.${_since.month}.${_since.year}'),
                ),
              ]),
              const Divider(height: 28),
              const Text('Пул', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _field(_amount, 'Ҳар бир кишига (сўм)', digits: true, width: 200),
                _field(_share, 'Буюртмадаги улуш (%)', digits: true, width: 180),
                _field(_validity, 'Муддат (кун)', digits: true, width: 140),
                _field(_budget, 'Умумий бюджет (сўм)', digits: true, width: 200),
                _field(_daily, 'Кунлик бюджет (0 — чекловсиз)', digits: true, width: 240),
              ]),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Туркумлар (бўш — AVA дўконидаги исталган маҳсулот). Калит — маҳсулот туркуми, масалан tire, oil, battery, insurance.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _buckets.add(_BucketRow('', 0))),
                    icon: const Icon(Icons.add),
                    label: const Text('Туркум қўшиш'),
                  ),
                ],
              ),
              for (final b in _buckets)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    _field(b.category, 'Туркум калити', width: 220),
                    const SizedBox(width: 12),
                    _field(b.amount, 'Миқдор (сўм)', digits: true, width: 180),
                    IconButton(
                      tooltip: 'Олиб ташлаш',
                      onPressed: () => setState(() => _buckets.remove(b)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ]),
                ),
              if (_buckets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Туркумлар йиғиндиси: ${formatPrice(_bucketSum)}'),
                ),
              const Divider(height: 28),
              const Text('Босқичлар ва муддат', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _field(_internal, 'Ички синов рақамлари (вергул билан, 998…)', width: 736),
              const SizedBox(height: 12),
              _field(_pilot, 'Пилот туман ID лари (вергул билан)', width: 736),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                OutlinedButton.icon(
                  onPressed: () => _pickDate(_start, (d) => _start = d),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(_start == null ? 'Бошланиш: дарҳол' : 'Бошланиш: ${_start!.day}.${_start!.month}.${_start!.year}'),
                ),
                if (_start != null) TextButton(onPressed: () => setState(() => _start = null), child: const Text('тозалаш')),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(_end, (d) => _end = d),
                  icon: const Icon(Icons.stop, size: 18),
                  label: Text(_end == null ? 'Тугаш: муддатсиз' : 'Тугаш: ${_end!.day}.${_end!.month}.${_end!.year}'),
                ),
                if (_end != null) TextButton(onPressed: () => setState(() => _end = null), child: const Text('тозалаш')),
              ]),
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

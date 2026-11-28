import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../supermarket/domain/sm_holiday.dart';
import '../../supermarket/domain/sm_offer.dart';
import '../../supermarket/domain/sm_qty.dart';
import '../../supermarket/domain/sm_taxonomy.dart';
import '../services/admin_birthday_prompt_service.dart' show AdminBirthdayPromptApi;
import '../services/admin_holiday_service.dart';
import '../widgets/birthday_prompt_admin_panel.dart';
import '../services/admin_incentives_service.dart' show kFamilyBonusProgramIds;
import '../services/admin_supermarket_service.dart';

/// Админ: «Байрам саватчаси» (эга 2026-11-26) — байрамлар (Ҳайит — ой тақвими саналари рўйхати), тайёр
/// саватчалар (гуруҳ/таклиф, миқдор, устуворлик, даража) ва «Яқинлар туғилган куни» бонус дастури. Кирилл
/// (админ конвенцияси). Ҳар сақлаш — сервер callable (admin_audit).
class HolidayAdminScreen extends StatefulWidget {
  const HolidayAdminScreen({super.key, this.api, this.loadTaxonomy, this.loadOffers, this.birthdayPromptApi});

  final AdminHolidayApi? api;

  /// «Туғилган кунни киритинг» ҳафталик пуши (эга 2026-11-28) — алоҳида таб, ўз callable'лари.
  final AdminBirthdayPromptApi? birthdayPromptApi;
  final Future<SmTaxonomy> Function()? loadTaxonomy;
  final Future<List<SmOffer>> Function(SmTaxonomy tx)? loadOffers;

  @override
  State<HolidayAdminScreen> createState() => _HolidayAdminScreenState();
}

class _HolidayAdminScreenState extends State<HolidayAdminScreen> {
  late final AdminHolidayApi _api = widget.api ?? FirebaseAdminHolidayApi();
  List<HolidayOccasion>? _occasions;
  List<HolidayBasket> _baskets = const [];
  Map<String, FamilyBonusProgram?> _family = const {};
  SmTaxonomy _tx = SmTaxonomy.empty;
  List<SmOffer> _offers = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final occ = await _api.loadOccasions();
      final b = await _api.loadBaskets();
      final family = await _api.loadFamilyPrograms();
      final sm = widget.loadTaxonomy == null ? AdminSupermarketService() : null;
      final tx = await (widget.loadTaxonomy?.call() ?? sm!.loadTaxonomyRaw().then(SmTaxonomy.fromMap));
      final offers = await (widget.loadOffers?.call(tx) ?? (sm ?? AdminSupermarketService()).loadOffers(tx));
      if (!mounted) return;
      setState(() {
        _occasions = occ;
        _baskets = b;
        _family = family;
        _tx = tx;
        _offers = offers;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Юклаб бўлмади: $e');
    }
  }

  Future<void> _editOccasion([HolidayOccasion? o]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _OccasionDialog(api: _api, initial: o));
    if (saved == true) await _load();
  }

  Future<void> _editBasket([HolidayBasket? b]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BasketDialog(api: _api, initial: b, occasions: _occasions ?? const [], tx: _tx, offers: _offers),
    );
    if (saved == true) await _load();
  }

  Future<void> _editFamily(String programId) async {
    final saved = await showDialog<bool>(
        context: context, builder: (_) => _FamilyBonusDialog(api: _api, programId: programId, initial: _family[programId]));
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final occ = _occasions;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            tabs: [Tab(text: 'Байрамлар'), Tab(text: 'Саватчалар'), Tab(text: 'Оила бонуслари'), Tab(text: 'Туғилган кун эслатмаси')],
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('Қайта уриниш')),
                    ]),
                  )
                : occ == null
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(children: [
                        ListView(padding: const EdgeInsets.all(16), children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              key: const ValueKey('hb_admin_add_occasion'),
                              onPressed: () => _editOccasion(),
                              icon: const Icon(Icons.add),
                              label: const Text('Байрам қўшиш'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final o in occ)
                            Card(
                              child: ListTile(
                                key: ValueKey('hb_admin_occasion_${o.id}'),
                                title: Text('${o.name('uz_Cyrl')}  (${o.id})'),
                                subtitle: Text(holidayOccasionSummary(o)),
                                trailing: const Icon(Icons.edit_outlined),
                                onTap: () => _editOccasion(o),
                              ),
                            ),
                        ]),
                        ListView(padding: const EdgeInsets.all(16), children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              key: const ValueKey('hb_admin_add_basket'),
                              onPressed: occ.isEmpty ? null : () => _editBasket(),
                              icon: const Icon(Icons.add),
                              label: const Text('Саватча қўшиш'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final o in occ) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 4),
                              child: Text(o.name('uz_Cyrl'), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            for (final b in _baskets.where((b) => b.occasionId == o.id))
                              Card(
                                child: ListTile(
                                  key: ValueKey('hb_admin_basket_${b.id}'),
                                  title: Text('${b.name('uz_Cyrl')}  (${b.id})'),
                                  subtitle: Text([
                                    kHolidayTierLabels[b.tier] ?? b.tier,
                                    '${b.items.length} та маҳсулот',
                                    '${b.baseGuests} меҳмон',
                                    b.active ? 'фаол' : 'ўчиқ',
                                  ].join(' · ')),
                                  trailing: const Icon(Icons.edit_outlined),
                                  onTap: () => _editBasket(b),
                                ),
                              ),
                          ],
                        ]),
                        ListView(padding: const EdgeInsets.all(16), children: [
                          const Text(
                            'Эга 2026-11-28: бонус фақат иккинчи томон (AVA фойдаланувчиси) ТАСДИҚЛАГАНДА — ҳар икки томонга. '
                            'Турмуш ўртоғи — шахсга умрбод бир марта; қариндош (ота, она, ака-ука, опа-сингил) — ҳар тасдиқланган '
                            'жуфтликда бир марта. Ажратиш бонусни қайтариб олмайди. Фақат Супермаркет (байрам саватчаси ҳам), нақдга ечилмайди. '
                            'Эски «3 қариндош → бонус» ёпилган.',
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 12),
                          for (final id in kFamilyBonusProgramIds)
                            Card(
                              child: ListTile(
                                key: ValueKey('hb_admin_family_$id'),
                                title: Text(id == 'spouse_link' ? 'Турмуш ўртоғи (spouse_link)' : 'Қариндошлар (relative_link)'),
                                subtitle: Text(_family[id] == null
                                    ? 'Дастур ҳали яратилмаган (OFF)'
                                    : [
                                        kHolidayStageLabels[_family[id]!.stage] ?? _family[id]!.stage,
                                        '${_family[id]!.amount} сўм',
                                        '${_family[id]!.validityDays} кун',
                                        'буюртма ≥ ${_family[id]!.minOrderAmount} сўм',
                                        if (id == 'relative_link') 'ота-она ≤ ${_family[id]!.maxParents}, ака-ука/опа-сингил ≤ ${_family[id]!.maxSiblings}',
                                        'берилган: ${_family[id]!.grantedCount} та / ${_family[id]!.grantedAmount} сўм',
                                        'бюджет: ${_family[id]!.budgetTotal} сўм',
                                      ].join(' · ')),
                                trailing: const Icon(Icons.edit_outlined),
                                onTap: () => _editFamily(id),
                              ),
                            ),
                        ]),
                        BirthdayPromptAdminPanel(api: widget.birthdayPromptApi),
                      ]),
          ),
        ],
      ),
    );
  }
}

/// Рўйхат қатори: тур · босқич · сана қоидаси · эслатма.
String holidayOccasionSummary(HolidayOccasion o) => [
      o.isBirthday ? 'Туғилган кун' : 'Байрам',
      kHolidayStageLabels[o.stage] ?? o.stage,
      if (o.bigHoliday) 'катта байрам',
      if (!o.isBirthday && o.ruleType == 'fixed') 'ҳар йили ${o.md}',
      if (!o.isBirthday && o.ruleType == 'list') '${o.dates.length} та сана',
      'эслатма ${o.remindDaysBefore} кун олдин',
      if (o.target != null) 'очади: ${kHolidayTargetLabels[o.target!.type] ?? o.target!.type}${o.target!.isMarket ? ' (${o.target!.market})' : ''}',
      if (o.isBirthday)
        o.selfReminders == null
            ? 'ўз туғилган куни: сукут (D-7…D-3)'
            : o.selfReminders!.isEmpty
                ? 'ўз туғилган куни: ўчиқ'
                : 'ўз туғилган куни: ${[for (final r in o.selfReminders!) 'D-${r.daysBefore}'].join(', ')}',
    ].join(' · ');

Widget _names(TextEditingController cyr, TextEditingController lat, TextEditingController ru) => Column(children: [
      TextField(key: const ValueKey('hb_admin_name_cyrl'), controller: cyr, decoration: const InputDecoration(labelText: 'Номи (кирилл)')),
      TextField(key: const ValueKey('hb_admin_name_latn'), controller: lat, decoration: const InputDecoration(labelText: 'Номи (лотин)')),
      TextField(key: const ValueKey('hb_admin_name_ru'), controller: ru, decoration: const InputDecoration(labelText: 'Номи (рус)')),
    ]);

Widget _problems(List<String> p) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final s in p) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s, style: const TextStyle(color: Colors.red))),
    ]);

class _OccasionDialog extends StatefulWidget {
  const _OccasionDialog({required this.api, this.initial});

  final AdminHolidayApi api;
  final HolidayOccasion? initial;

  @override
  State<_OccasionDialog> createState() => _OccasionDialogState();
}

class _OccasionDialogState extends State<_OccasionDialog> {
  late final HolidayOccasion? _o = widget.initial;
  late final _id = TextEditingController(text: _o?.id ?? '');
  late final _cyr = TextEditingController(text: _o?.names['uz_Cyrl'] ?? '');
  late final _lat = TextEditingController(text: _o?.names['uz_Latn'] ?? '');
  late final _ru = TextEditingController(text: _o?.names['ru'] ?? '');
  late final _md = TextEditingController(text: _o?.md ?? '');
  late final _dates = TextEditingController(text: (_o?.dates ?? const []).join('\n'));
  late final _remind = TextEditingController(text: '${_o?.remindDaysBefore ?? 5}');
  late final _order = TextEditingController(text: '${_o?.order ?? 0}');
  late final _image = TextEditingController(text: _o?.image ?? '');
  final _reason = TextEditingController();
  late String _kind = _o?.kind ?? kHolidayKindHoliday;
  late String _rule = _o?.ruleType.isNotEmpty == true ? _o!.ruleType : 'fixed';
  late String _stage = (_o?.stage.isNotEmpty ?? false) ? _o!.stage : 'off';
  late bool _big = _o?.bigHoliday ?? false;
  List<String> _errors = const [];
  bool _saving = false;

  // Байрам мақсади (эга 2026-11-27, сервер шартномаси): '' — саватча (null); бозор / ресторан / супермаркет.
  late String _targetType = (_o?.target == null || _o!.target!.isBasket) ? '' : _o.target!.type;
  late final _market = TextEditingController(text: _o?.target?.market ?? '');
  late final _marketCats = TextEditingController(text: (_o?.target?.categories ?? const []).join(', '));

  // Ўз туғилган куни эслатмалари (фақат туғилган кун). Майдон йўқ — сервер сукути D-7..D-3 ([_selfDefault]).
  late bool _selfDefault = _o?.selfReminders == null;
  late final List<_SelfRow> _self = [for (final r in _o?.selfReminders ?? const <HolidaySelfReminder>[]) _SelfRow.of(r)];

  HolidayTarget? get _target => switch (_targetType) {
        kTargetMarket => HolidayTarget(
            type: kTargetMarket,
            market: _market.text.trim(),
            categories: [for (final s in _marketCats.text.split(RegExp(r'[,\s]+'))) if (s.trim().isNotEmpty) s.trim()],
          ),
        kTargetRestaurantsPreorder || kTargetSupermarket => HolidayTarget(type: _targetType),
        _ => null,
      };

  /// Тавсия этилган 5 та (эга 2026-11-27: D-7, D-6, D-5, D-4, D-3) — бўш рўйхатга бир босишда.
  void _addDefaultSelf() => setState(() {
        _selfDefault = false;
        for (final d in kSelfReminderDefaultDays) {
          if (_self.any((r) => int.tryParse(r.days.text.trim()) == d)) continue;
          _self.add(_SelfRow(days: '$d', target: d == 7 ? kSelfTargetPreorder : (d >= 5 ? kSelfTargetBasket : kSelfTargetGuests)));
        }
      });

  Widget _targetEditor() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('hb_admin_target_type'),
          initialValue: _targetType,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Босилганда нима очилади'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Байрам саватчаси')),
            for (final t in const [kTargetMarket, kTargetRestaurantsPreorder, kTargetSupermarket])
              DropdownMenuItem(value: t, child: Text(kHolidayTargetLabels[t]!)),
          ],
          onChanged: (v) => setState(() => _targetType = v ?? ''),
        ),
        if (_targetType == kTargetMarket) ...[
          TextField(
            key: const ValueKey('hb_admin_target_market'),
            controller: _market,
            decoration: const InputDecoration(labelText: 'Бозор ID (масалан livestock)'),
          ),
          TextField(
            key: const ValueKey('hb_admin_target_cats'),
            controller: _marketCats,
            decoration: const InputDecoration(
              labelText: 'Бўлимлар (вергул билан, масалан sheep_goat, cattle)',
              helperText: 'Биринчиси очилишда танланади.',
            ),
          ),
        ],
      ]);

  Widget _selfEditor() => Column(
        key: const ValueKey('hb_admin_self'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Text('Ўз туғилган куни эслатмалари', style: TextStyle(fontWeight: FontWeight.w700)),
          const Text('Фойдаланувчининг ўз туғилган кунидан неча кун олдин (1–14, 10 тагача) ва босилганда нима очилади.',
              style: TextStyle(color: Colors.black54)),
          if (_selfDefault)
            const Padding(
              key: ValueKey('hb_admin_self_default_note'),
              padding: EdgeInsets.only(top: 6),
              child: Text('Ҳозир сервер сукути ишлайди: D-7, D-6, D-5, D-4, D-3 (тизим матнлари).'),
            ),
          for (var i = 0; i < _self.length; i++)
            Card(
              key: ObjectKey(_self[i]),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    SizedBox(
                      width: 90,
                      child: TextField(
                        key: ValueKey('hb_admin_self_days_$i'),
                        controller: _self[i].days,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Кун (D-)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('hb_admin_self_target_$i'),
                        initialValue: kSelfReminderTargets.contains(_self[i].target) ? _self[i].target : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Мақсад'),
                        items: [
                          for (final t in kSelfReminderTargets)
                            DropdownMenuItem(value: t, child: Text(kSelfTargetLabels[t]!, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => _self[i].target = v ?? ''),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('hb_admin_self_del_$i'),
                      tooltip: 'Ўчириш',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        final gone = _self[i];
                        setState(() => _self.removeAt(i));
                        WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
                      },
                    ),
                  ]),
                  for (final (l, label) in const [('uz_Cyrl', 'кирилл'), ('uz_Latn', 'лотин'), ('ru', 'рус')]) ...[
                    TextField(
                      key: ValueKey('hb_admin_self_title_${l}_$i'),
                      controller: _self[i].title[l],
                      maxLength: kSelfReminderTitleMax,
                      decoration: InputDecoration(labelText: 'Сарлавҳа ($label)', counterText: ''),
                    ),
                    TextField(
                      key: ValueKey('hb_admin_self_body_${l}_$i'),
                      controller: _self[i].body[l],
                      maxLength: kSelfReminderBodyMax,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: 'Матн ($label)', counterText: ''),
                    ),
                  ],
                ]),
              ),
            ),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              key: const ValueKey('hb_admin_self_add'),
              onPressed: _self.length >= kSelfReminderMaxCount
                  ? null
                  : () => setState(() {
                        _selfDefault = false;
                        _self.add(_SelfRow());
                      }),
              icon: const Icon(Icons.add),
              label: const Text('Эслатма қўшиш'),
            ),
            if (_self.isEmpty)
              TextButton(
                key: const ValueKey('hb_admin_self_defaults'),
                onPressed: _addDefaultSelf,
                child: const Text('D-7…D-3 тавсия'),
              ),
            if (!_selfDefault && _self.isEmpty)
              TextButton(
                key: const ValueKey('hb_admin_self_use_default'),
                onPressed: () => setState(() => _selfDefault = true),
                child: const Text('Сервер сукутига қайтариш'),
              ),
          ]),
        ],
      );

  @override
  void dispose() {
    for (final r in _self) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final birthday = _kind == kHolidayKindBirthday;
    // Туғилган кун: сукут — майдон юборилмайди; акс ҳолда рўйхат (бўш — эслатмалар ўчиқ).
    final self = birthday && !_selfDefault ? [for (final r in _self) r.toReminder()] : null;
    final o = HolidayOccasion(
      id: _id.text.trim(),
      names: {'uz_Cyrl': _cyr.text.trim(), 'uz_Latn': _lat.text.trim(), 'ru': _ru.text.trim()},
      kind: _kind,
      bigHoliday: _big,
      ruleType: _kind == kHolidayKindBirthday ? '' : _rule,
      md: _md.text.trim(),
      dates: holidaySplitDates(_dates.text),
      remindDaysBefore: int.tryParse(_remind.text.trim()) ?? 0,
      stage: _stage,
      order: int.tryParse(_order.text.trim()) ?? 0,
      image: _image.text.trim(),
      target: birthday ? null : _target,
      selfReminders: self,
      // Эга 2026-11-28: формада йўқ майдонлар қайта сақлашда йўқолмасин.
      theme: _o?.theme ?? const {},
      reminderTexts: birthday ? null : _o?.reminderTexts,
    );
    final p = [
      ...holidayOccasionProblems(o),
      if (self != null) ...holidaySelfReminderProblems(self),
      if (!birthday && _targetType == kTargetMarket && !(o.target?.isMarket ?? false)) 'Бозор ID нотўғри (кичик лотин, масалан livestock).',
    ];
    setState(() => _errors = p);
    if (p.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.api.saveOccasion(o, reason: _reason.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _errors = ['Сақлаб бўлмади: $e']);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_o == null ? 'Янги байрам' : 'Байрамни таҳрирлаш'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                key: const ValueKey('hb_admin_id'),
                controller: _id,
                enabled: _o == null,
                decoration: const InputDecoration(labelText: 'ID (лотин, масалан navruz)'),
              ),
              _names(_cyr, _lat, _ru),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('hb_admin_kind'),
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Тури'),
                items: const [
                  DropdownMenuItem(value: kHolidayKindHoliday, child: Text('Байрам (сана бўйича)')),
                  DropdownMenuItem(value: kHolidayKindBirthday, child: Text('Туғилган кун (қариндошлардан)')),
                ],
                onChanged: (v) => setState(() => _kind = v ?? kHolidayKindHoliday),
              ),
              if (_kind != kHolidayKindBirthday) ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey('hb_admin_rule'),
                  initialValue: _rule,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Сана'),
                  items: const [
                    DropdownMenuItem(value: 'fixed', child: Text('Ҳар йили бир кун (Наврўз, Янги йил)')),
                    DropdownMenuItem(value: 'list', child: Text('Саналар рўйхати (ой тақвими — Ҳайит)')),
                  ],
                  onChanged: (v) => setState(() => _rule = v ?? 'fixed'),
                ),
                if (_rule == 'fixed')
                  TextField(
                    key: const ValueKey('hb_admin_md'),
                    controller: _md,
                    decoration: const InputDecoration(labelText: 'Кун: ОО-КК (масалан 03-21)'),
                  )
                else
                  TextField(
                    key: const ValueKey('hb_admin_dates'),
                    controller: _dates,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Саналар (ҳар қаторда битта, ЙЙЙЙ-ОО-КК)',
                      helperText: 'Ҳайит санаси ҳар йили расмий эълондан кейин киритилади (30 тагача).',
                    ),
                  ),
                _targetEditor(),
              ],
              if (_kind == kHolidayKindBirthday) _selfEditor(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Катта байрам (эслатма 10 кун олдин)'),
                value: _big,
                onChanged: (v) => setState(() {
                  _big = v;
                  _remind.text = v ? '10' : '5';
                }),
              ),
              TextField(
                controller: _remind,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Эслатма — неча кун олдин (1–30)'),
              ),
              DropdownButtonFormField<String>(
                key: const ValueKey('hb_admin_stage'),
                initialValue: _stage,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Босқич'),
                items: [for (final s in kHolidayStages) DropdownMenuItem(value: s, child: Text(kHolidayStageLabels[s]!))],
                onChanged: (v) => setState(() => _stage = v ?? 'off'),
              ),
              TextField(controller: _order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Тартиб')),
              TextField(controller: _image, decoration: const InputDecoration(labelText: 'Расм URL (https://, ихтиёрий)')),
              TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Сабаб (журнал учун, ихтиёрий)')),
              _problems(_errors),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Бекор')),
          FilledButton(key: const ValueKey('hb_admin_save'), onPressed: _saving ? null : _save, child: const Text('Сақлаш')),
        ],
      );
}

/// Эслатма мақсадлари (админ, Кирилл).
const kSelfTargetLabels = {
  kSelfTargetBasket: 'Туғилган кун саватчаси',
  kSelfTargetPreorder: 'Ресторанда олдиндан буюртма',
  kSelfTargetGuests: 'Меҳмонлар учун саватча',
};

/// Байрам мақсади турлари (админ, Кирилл).
const kHolidayTargetLabels = {
  kTargetHolidayBasket: 'Байрам саватчаси',
  kTargetMarket: 'Бозор (масалан Қурбон ҳайит → Мол бозори)',
  kTargetRestaurantsPreorder: 'Ресторанда олдиндан буюртма',
  kTargetSupermarket: 'Супермаркет',
};

class _SelfRow {
  _SelfRow({String days = '', this.target = '', Map<String, ({String title, String body})> texts = const {}})
      : days = TextEditingController(text: days),
        title = {for (final l in _langs) l: TextEditingController(text: texts[l]?.title ?? '')},
        body = {for (final l in _langs) l: TextEditingController(text: texts[l]?.body ?? '')};

  static const _langs = ['uz_Cyrl', 'uz_Latn', 'ru'];

  factory _SelfRow.of(HolidaySelfReminder r) => _SelfRow(days: '${r.daysBefore}', target: r.target, texts: r.texts);

  final TextEditingController days;
  String target;
  final Map<String, TextEditingController> title;
  final Map<String, TextEditingController> body;

  HolidaySelfReminder toReminder() => HolidaySelfReminder(
        daysBefore: int.tryParse(days.text.trim()) ?? 0,
        texts: {for (final l in _langs) l: (title: title[l]!.text.trim(), body: body[l]!.text.trim())},
        target: target,
      );

  void dispose() {
    for (final c in [days, ...title.values, ...body.values]) {
      c.dispose();
    }
  }
}

class _ItemRow {
  _ItemRow({this.groupId = '', this.offerId = '', String qty = '', String perGuest = '', String priority = ''})
      : qty = TextEditingController(text: qty),
        perGuest = TextEditingController(text: perGuest),
        priority = TextEditingController(text: priority);

  String groupId;
  String offerId;
  final TextEditingController qty;
  final TextEditingController perGuest;
  final TextEditingController priority;
}

class _BasketDialog extends StatefulWidget {
  const _BasketDialog({required this.api, required this.occasions, required this.tx, required this.offers, this.initial});

  final AdminHolidayApi api;
  final HolidayBasket? initial;
  final List<HolidayOccasion> occasions;
  final SmTaxonomy tx;
  final List<SmOffer> offers;

  @override
  State<_BasketDialog> createState() => _BasketDialogState();
}

class _BasketDialogState extends State<_BasketDialog> {
  late final HolidayBasket? _b = widget.initial;
  late final _id = TextEditingController(text: _b?.id ?? '');
  late String _occasionId = _b?.occasionId ?? (widget.occasions.isEmpty ? '' : widget.occasions.first.id);
  late String _tier = _b?.tier ?? 'simple';
  late bool _active = _b?.active ?? false;
  late final _cyr = TextEditingController(text: _b?.names['uz_Cyrl'] ?? '');
  late final _lat = TextEditingController(text: _b?.names['uz_Latn'] ?? '');
  late final _ru = TextEditingController(text: _b?.names['ru'] ?? '');
  late final _guests = TextEditingController(text: '${_b?.baseGuests ?? 10}');
  final _reason = TextEditingController();
  late final List<_ItemRow> _items = [
    for (final i in _b?.items ?? const <HolidayBasketItem>[])
      _ItemRow(
        groupId: i.groupId,
        offerId: i.offerId,
        qty: smFormatQty(i.qtyMilli),
        perGuest: i.qtyPerGuestMilli > 0 ? smFormatQty(i.qtyPerGuestMilli) : '',
        priority: i.priority > 0 ? '${i.priority}' : '',
      ),
  ];
  List<String> _errors = const [];
  bool _saving = false;

  List<SmGroup> get _groups => [for (final c in widget.tx.categories) ...c.groups];

  num? _num(String s) => num.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final b = HolidayBasket(
      id: _id.text.trim(),
      occasionId: _occasionId,
      tier: _tier,
      names: {'uz_Cyrl': _cyr.text.trim(), 'uz_Latn': _lat.text.trim(), 'ru': _ru.text.trim()},
      baseGuests: int.tryParse(_guests.text.trim()) ?? 0,
      active: _active,
      items: [
        for (final r in _items)
          HolidayBasketItem(
            groupId: r.groupId,
            offerId: r.offerId,
            qtyMilli: smToMilli(_num(r.qty.text) ?? 0),
            qtyPerGuestMilli: smToMilli(_num(r.perGuest.text) ?? 0),
            priority: int.tryParse(r.priority.text.trim()) ?? 0,
          ),
      ],
    );
    final p = holidayBasketProblems(b);
    setState(() => _errors = p);
    if (p.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.api.saveBasket(b, reason: _reason.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _errors = ['Сақлаб бўлмади: $e']);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _itemRow(_ItemRow r, int index) {
    final groupOffers = [for (final o in widget.offers) if (o.groupId == r.groupId) o];
    return Card(
      key: ValueKey('hb_admin_item_$index'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          DropdownButtonFormField<String>(
            initialValue: _groups.any((g) => g.id == r.groupId) ? r.groupId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Гуруҳ'),
            items: [for (final g in _groups) DropdownMenuItem(value: g.id, child: Text(g.name('uz_Cyrl'), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() {
              r.groupId = v ?? '';
              r.offerId = '';
            }),
          ),
          DropdownButtonFormField<String>(
            initialValue: groupOffers.any((o) => o.id == r.offerId) ? r.offerId : '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Таклиф (ихтиёрий — бўлмаса энг арзони)'),
            items: [
              const DropdownMenuItem(value: '', child: Text('— Тизим танлайди —')),
              for (final o in groupOffers)
                DropdownMenuItem(value: o.id, child: Text('${o.name} · ${o.price} сўм', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => r.offerId = v ?? ''),
          ),
          Row(children: [
            Expanded(child: TextField(controller: r.qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Миқдор'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: r.perGuest,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Ҳар меҳмонга (ихт.)'))),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextField(
                controller: r.priority,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Устуворлик 1–9'),
              ),
            ),
            IconButton(
              tooltip: 'Олиб ташлаш',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _items.removeAt(index)),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_b == null ? 'Янги саватча' : 'Саватчани таҳрирлаш'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                key: const ValueKey('hb_admin_basket_id'),
                controller: _id,
                enabled: _b == null,
                decoration: const InputDecoration(labelText: 'ID (лотин, масалан navruz_medium)'),
              ),
              DropdownButtonFormField<String>(
                initialValue: widget.occasions.any((o) => o.id == _occasionId) ? _occasionId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Байрам'),
                items: [for (final o in widget.occasions) DropdownMenuItem(value: o.id, child: Text(o.name('uz_Cyrl')))],
                onChanged: (v) => setState(() => _occasionId = v ?? ''),
              ),
              DropdownButtonFormField<String>(
                initialValue: _tier,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Даража'),
                items: [for (final t in kHolidayTiers) DropdownMenuItem(value: t, child: Text(kHolidayTierLabels[t]!))],
                onChanged: (v) => setState(() => _tier = v ?? 'simple'),
              ),
              _names(_cyr, _lat, _ru),
              TextField(
                controller: _guests,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Асосий меҳмонлар сони (1–500)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Фаол'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 8),
              const Text('Маҳсулотлар (бюджет етмаса — устуворлик рақами катталари аввал олиб ташланади)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              for (var i = 0; i < _items.length; i++) _itemRow(_items[i], i),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('hb_admin_add_item'),
                  onPressed: () => setState(() => _items.add(_ItemRow(qty: '1'))),
                  icon: const Icon(Icons.add),
                  label: const Text('Маҳсулот қўшиш'),
                ),
              ),
              TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Сабаб (журнал учун, ихтиёрий)')),
              _problems(_errors),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Бекор')),
          FilledButton(key: const ValueKey('hb_admin_save'), onPressed: _saving ? null : _save, child: const Text('Сақлаш')),
        ],
      );
}

class _FamilyBonusDialog extends StatefulWidget {
  const _FamilyBonusDialog({required this.api, required this.programId, this.initial});

  final AdminHolidayApi api;
  final String programId;
  final FamilyBonusProgram? initial;

  @override
  State<_FamilyBonusDialog> createState() => _FamilyBonusDialogState();
}

class _FamilyBonusDialogState extends State<_FamilyBonusDialog> {
  late final FamilyBonusProgram _p = widget.initial ?? FamilyBonusProgram.defaults(widget.programId);
  late final _cyr = TextEditingController(text: _p.title['uz_Cyrl'] ?? '');
  late final _lat = TextEditingController(text: _p.title['uz_Latn'] ?? '');
  late final _ru = TextEditingController(text: _p.title['ru'] ?? '');
  late final _amount = TextEditingController(text: _p.amount > 0 ? '${_p.amount}' : '');
  late final _minOrder = TextEditingController(text: '${_p.minOrderAmount}');
  late final _share = TextEditingController(text: '${_p.maxOrderSharePct}');
  late final _validity = TextEditingController(text: '${_p.validityDays}');
  late final _budget = TextEditingController(text: _p.budgetTotal > 0 ? '${_p.budgetTotal}' : '');
  late final _parents = TextEditingController(text: '${_p.maxParents}');
  late final _siblings = TextEditingController(text: '${_p.maxSiblings}');
  late final _internal = TextEditingController(text: _p.internalPhones.join(', '));
  late final _pilot = TextEditingController(text: _p.pilotDistrictIds.join(', '));
  final _reason = TextEditingController();
  late String _stage = _p.stage;
  List<String> _errors = const [];
  bool _saving = false;

  bool get _rel => widget.programId == 'relative_link';
  int _int(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'[\s  ]'), '')) ?? -1;
  List<String> _list(TextEditingController c) => [for (final s in c.text.split(RegExp(r'[,\s]+'))) if (s.trim().isNotEmpty) s.trim()];

  Future<void> _save() async {
    final p = FamilyBonusProgram(
      title: {'uz_Cyrl': _cyr.text.trim(), 'uz_Latn': _lat.text.trim(), 'ru': _ru.text.trim()},
      stage: _stage,
      internalPhones: _list(_internal),
      pilotDistrictIds: _list(_pilot),
      amount: _int(_amount),
      minOrderAmount: _int(_minOrder),
      maxOrderSharePct: _int(_share),
      validityDays: _int(_validity),
      budgetTotal: _int(_budget),
      maxParents: _rel ? _int(_parents) : 2,
      maxSiblings: _rel ? _int(_siblings) : 15,
    );
    final errs = familyBonusProblems(widget.programId, p);
    setState(() => _errors = errs);
    if (errs.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.api.saveFamilyProgram(widget.programId, p, reason: _reason.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _errors = ['Сақлаб бўлмади: $e']);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _f(TextEditingController c, String label, {bool digits = true, Key? key}) => TextField(
        key: key,
        controller: c,
        keyboardType: digits ? TextInputType.number : TextInputType.text,
        inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(labelText: label),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_rel ? '«Қариндошлар» бонуси (ўзаро тасдиқ)' : '«Турмуш ўртоғи» бонуси (ўзаро тасдиқ)'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _names(_cyr, _lat, _ru),
              DropdownButtonFormField<String>(
                key: const ValueKey('hb_admin_family_stage'),
                initialValue: _stage,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Босқич'),
                items: [for (final s in kHolidayStages) DropdownMenuItem(value: s, child: Text(kHolidayStageLabels[s]!))],
                onChanged: (v) => setState(() => _stage = v ?? 'off'),
              ),
              _f(_amount, _rel ? 'Ҳар бир томонга, ҳар жуфтлик учун (сўм)' : 'Ҳар бир томонга (сўм)', key: const ValueKey('hb_admin_family_amount')),
              _f(_minOrder, 'Энг кам буюртма (сўм, 0 — чекловсиз)'),
              _f(_share, 'Буюртмадаги улуш (%)'),
              _f(_validity, 'Амал қилиш муддати (кун, 1–365)'),
              _f(_budget, 'Умумий бюджет (сўм)'),
              if (_rel) ...[
                _f(_parents, 'Ота-она чегараси (сукут 2)', key: const ValueKey('hb_admin_family_parents')),
                _f(_siblings, 'Ака-ука/опа-сингил чегараси (сукут 15)', key: const ValueKey('hb_admin_family_siblings')),
              ],
              _f(_internal, 'Ички синов рақамлари (998…, вергул билан)', digits: false),
              _f(_pilot, 'Пилот туман ID лари (вергул билан)', digits: false),
              TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Сабаб (журнал учун, ихтиёрий)')),
              _problems(_errors),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Бекор')),
          FilledButton(key: const ValueKey('hb_admin_family_save'), onPressed: _saving ? null : _save, child: const Text('Сақлаш')),
        ],
      );
}

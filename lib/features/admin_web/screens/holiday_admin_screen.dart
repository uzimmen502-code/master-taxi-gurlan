import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../supermarket/domain/sm_holiday.dart';
import '../../supermarket/domain/sm_offer.dart';
import '../../supermarket/domain/sm_qty.dart';
import '../../supermarket/domain/sm_taxonomy.dart';
import '../services/admin_holiday_service.dart';
import '../services/admin_supermarket_service.dart';

/// Админ: «Байрам саватчаси» (эга 2026-11-26) — байрамлар (Ҳайит — ой тақвими саналари рўйхати), тайёр
/// саватчалар (гуруҳ/таклиф, миқдор, устуворлик, даража) ва «Яқинлар туғилган куни» бонус дастури. Кирилл
/// (админ конвенцияси). Ҳар сақлаш — сервер callable (admin_audit).
class HolidayAdminScreen extends StatefulWidget {
  const HolidayAdminScreen({super.key, this.api, this.loadTaxonomy, this.loadOffers});

  final AdminHolidayApi? api;
  final Future<SmTaxonomy> Function()? loadTaxonomy;
  final Future<List<SmOffer>> Function(SmTaxonomy tx)? loadOffers;

  @override
  State<HolidayAdminScreen> createState() => _HolidayAdminScreenState();
}

class _HolidayAdminScreenState extends State<HolidayAdminScreen> {
  late final AdminHolidayApi _api = widget.api ?? FirebaseAdminHolidayApi();
  List<HolidayOccasion>? _occasions;
  List<HolidayBasket> _baskets = const [];
  RelativesBonusProgram? _bonus;
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
      final bonus = await _api.loadBonusProgram();
      final sm = widget.loadTaxonomy == null ? AdminSupermarketService() : null;
      final tx = await (widget.loadTaxonomy?.call() ?? sm!.loadTaxonomyRaw().then(SmTaxonomy.fromMap));
      final offers = await (widget.loadOffers?.call(tx) ?? (sm ?? AdminSupermarketService()).loadOffers(tx));
      if (!mounted) return;
      setState(() {
        _occasions = occ;
        _baskets = b;
        _bonus = bonus;
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

  Future<void> _editBonus() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _BonusDialog(api: _api, initial: _bonus));
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final occ = _occasions;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: 'Байрамлар'), Tab(text: 'Саватчалар'), Tab(text: 'Яқинлар бонуси')]),
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
                            'Камида N та қариндошнинг исми ва туғилган кунини киритган фойдаланувчига бир марта бонус. '
                            'Бонус фақат Супермаркетда, энг кам буюртмадан ошганда ишлатилади; нақдга ечилмайди.',
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: ListTile(
                              key: const ValueKey('hb_admin_bonus'),
                              title: Text(_bonus == null ? 'Дастур ҳали яратилмаган' : (_bonus!.title['uz_Cyrl'] ?? 'Яқинлар бонуси')),
                              subtitle: _bonus == null
                                  ? null
                                  : Text([
                                      kHolidayStageLabels[_bonus!.stage] ?? _bonus!.stage,
                                      '${_bonus!.amount} сўм',
                                      'камида ${_bonus!.minRelatives} қариндош',
                                      'буюртма ≥ ${_bonus!.minOrderAmount} сўм',
                                      'берилган: ${_bonus!.grantedCount} та / ${_bonus!.grantedAmount} сўм',
                                      'бюджет: ${_bonus!.budgetTotal} сўм',
                                    ].join(' · ')),
                              trailing: const Icon(Icons.edit_outlined),
                              onTap: _editBonus,
                            ),
                          ),
                        ]),
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

  Future<void> _save() async {
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
    );
    final p = holidayOccasionProblems(o);
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
              ],
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

class _BonusDialog extends StatefulWidget {
  const _BonusDialog({required this.api, this.initial});

  final AdminHolidayApi api;
  final RelativesBonusProgram? initial;

  @override
  State<_BonusDialog> createState() => _BonusDialogState();
}

class _BonusDialogState extends State<_BonusDialog> {
  late final RelativesBonusProgram _p = widget.initial ?? const RelativesBonusProgram();
  late final _cyr = TextEditingController(text: _p.title['uz_Cyrl'] ?? 'Яқинлар бонуси');
  late final _lat = TextEditingController(text: _p.title['uz_Latn'] ?? 'Yaqinlar bonusi');
  late final _ru = TextEditingController(text: _p.title['ru'] ?? 'Бонус за близких');
  late final _amount = TextEditingController(text: _p.amount > 0 ? '${_p.amount}' : '');
  late final _minRel = TextEditingController(text: '${_p.minRelatives}');
  late final _minOrder = TextEditingController(text: '${_p.minOrderAmount}');
  late final _share = TextEditingController(text: '${_p.maxOrderSharePct}');
  late final _validity = TextEditingController(text: '${_p.validityDays}');
  late final _budget = TextEditingController(text: _p.budgetTotal > 0 ? '${_p.budgetTotal}' : '');
  late final _internal = TextEditingController(text: _p.internalPhones.join(', '));
  late final _pilot = TextEditingController(text: _p.pilotDistrictIds.join(', '));
  final _reason = TextEditingController();
  late String _stage = _p.stage;
  List<String> _errors = const [];
  bool _saving = false;

  int _int(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'[\s  ]'), '')) ?? -1;
  List<String> _list(TextEditingController c) => [for (final s in c.text.split(RegExp(r'[,\s]+'))) if (s.trim().isNotEmpty) s.trim()];

  Future<void> _save() async {
    final p = RelativesBonusProgram(
      title: {'uz_Cyrl': _cyr.text.trim(), 'uz_Latn': _lat.text.trim(), 'ru': _ru.text.trim()},
      stage: _stage,
      internalPhones: _list(_internal),
      pilotDistrictIds: _list(_pilot),
      amount: _int(_amount),
      minRelatives: _int(_minRel),
      minOrderAmount: _int(_minOrder),
      maxOrderSharePct: _int(_share),
      validityDays: _int(_validity),
      budgetTotal: _int(_budget),
    );
    final errs = relativesBonusProblems(p);
    setState(() => _errors = errs);
    if (errs.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.api.saveBonusProgram(p, reason: _reason.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _errors = ['Сақлаб бўлмади: $e']);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _f(TextEditingController c, String label, {bool digits = true}) => TextField(
        controller: c,
        keyboardType: digits ? TextInputType.number : TextInputType.text,
        inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(labelText: label),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('«Яқинлар туғилган куни» бонуси'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _names(_cyr, _lat, _ru),
              DropdownButtonFormField<String>(
                key: const ValueKey('hb_admin_bonus_stage'),
                initialValue: _stage,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Босқич'),
                items: [for (final s in kHolidayStages) DropdownMenuItem(value: s, child: Text(kHolidayStageLabels[s]!))],
                onChanged: (v) => setState(() => _stage = v ?? 'off'),
              ),
              _f(_amount, 'Бонус миқдори (сўм)'),
              _f(_minRel, 'Камида неча қариндош (исм + туғилган кун)'),
              _f(_minOrder, 'Энг кам буюртма (сўм, 0 — чекловсиз)'),
              _f(_share, 'Буюртмадаги улуш (%)'),
              _f(_validity, 'Амал қилиш муддати (кун, 1–365)'),
              _f(_budget, 'Умумий бюджет (сўм)'),
              _f(_internal, 'Ички синов рақамлари (998…, вергул билан)', digits: false),
              _f(_pilot, 'Пилот туман ID лари (вергул билан)', digits: false),
              TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Сабаб (журнал учун, ихтиёрий)')),
              _problems(_errors),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Бекор')),
          FilledButton(key: const ValueKey('hb_admin_bonus_save'), onPressed: _saving ? null : _save, child: const Text('Сақлаш')),
        ],
      );
}

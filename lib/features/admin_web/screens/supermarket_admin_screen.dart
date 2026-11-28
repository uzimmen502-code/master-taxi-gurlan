// «AVA Супермаркет» админ бўлими (1-босқич, эга 2026-11-20). Матнлар — Кирилл (админ конвенцияси).
// Таблар: Таклифлар · Excel импорт (2-босқич) · Тоифалар ва гуруҳлар (таксономия) · Буюртмалар (тортиш, олиш, етишмовчилик) · Созламалар ·
// Харид режаси · Аналитика (3-босқич — фақат ҳисобот).

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../supermarket/domain/sm_offer.dart';
import '../../supermarket/domain/sm_qty.dart';
import '../../supermarket/domain/sm_taxonomy.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_market_service.dart';
import '../services/admin_supermarket_service.dart';
import 'supermarket_import_admin_tab.dart';
import 'supermarket_reports_admin_tab.dart';
import 'supermarket_partners_admin_tab.dart';

export 'supermarket_import_admin_tab.dart';
export 'supermarket_reports_admin_tab.dart';
export 'supermarket_partners_admin_tab.dart';

const _statusText = <String, String>{
  'active': 'Сотувда',
  'out_of_stock': 'Тугаган',
  'hidden': 'Яширин',
};

// Ягона манба — sm_units.dart (functions/supermarket_units.json); янги бирликлар (г, мл, қути, м) рўйхатга ўзи қўшилади.
final _unitText = <String, String>{for (final id in kSmUnitIds) id: smUnitText(id)};

class SupermarketAdminScreen extends StatelessWidget {
  const SupermarketAdminScreen({super.key, this.service});

  /// Тест учун; бўлмаса — Firebase.
  final AdminSupermarketService? service;

  @override
  Widget build(BuildContext context) {
    final s = service ?? AdminSupermarketService();
    return DefaultTabController(
      length: 9,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Таклифлар'),
              Tab(text: 'Excel импорт'),
              Tab(text: 'Тоифалар ва гуруҳлар'),
              Tab(text: 'Буюртмалар'),
              Tab(text: 'Созламалар'),
              Tab(text: 'Харид режаси'),
              Tab(text: 'Аналитика'),
              Tab(text: 'Курьерларга тўлов'),
              Tab(text: 'Ҳамкорлар'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [
              SmOffersAdminTab(service: s),
              SmImportAdminTab(service: s),
              SmTaxonomyAdminTab(service: s),
              SmOrdersAdminTab(service: s),
              SmSettingsAdminTab(service: s),
              SmProcurementAdminTab(service: s),
              SmAnalyticsAdminTab(service: s),
              SmCourierPayoutsAdminTab(service: s),
              SmPartnersAdminTab(service: s),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── Таклифлар ─────────────────────────────────────────────────────────────

class SmOffersAdminTab extends StatefulWidget {
  const SmOffersAdminTab({super.key, required this.service});
  final AdminSupermarketService service;

  @override
  State<SmOffersAdminTab> createState() => _SmOffersAdminTabState();
}

class _SmOffersAdminTabState extends State<SmOffersAdminTab> {
  SmTaxonomy _tx = SmTaxonomy.empty;
  List<SmOffer> _offers = const [];
  String _groupFilter = '';
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tx = SmTaxonomy.fromMap(await widget.service.loadTaxonomyRaw());
      final offers = await widget.service.loadOffers(tx);
      if (!mounted) return;
      setState(() {
        _tx = tx;
        _offers = offers;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: TextButton(onPressed: _load, child: Text('Юклаб бўлмади. Қайта уриниш\n$_error')));
    }
    final list = _offers.where((o) => _groupFilter.isEmpty || o.groupId == _groupFilter).toList()
      ..sort((a, b) => a.groupId == b.groupId ? a.price.compareTo(b.price) : a.groupId.compareTo(b.groupId));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const ValueKey('sm_admin_group_filter'),
                initialValue: _groupFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Гуруҳ', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Барчаси')),
                  for (final c in _tx.categories)
                    for (final g in c.groups)
                      DropdownMenuItem(value: g.id, child: Text('${c.name('uz_Cyrl')} → ${g.name('uz_Cyrl')}')),
                ],
                onChanged: (v) => setState(() => _groupFilter = v ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: 'Янгилаш', onPressed: _load, icon: const Icon(Icons.refresh)),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('sm_admin_new_offer'),
              onPressed: () async {
                final saved = await showDialog<bool>(
                  context: context,
                  builder: (_) => SmOfferEditorDialog(service: widget.service, taxonomy: _tx),
                );
                if (saved == true) _load();
              },
              icon: const Icon(Icons.add),
              label: const Text('Янги таклиф'),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Таклиф = platform_products ҳужжати (гуруҳ → нав → сифат/қадоқ/нарх). Сақлаш — сервер '
            "(нарх ва харид нархи audit'га ёзилади). Янги таклиф эски Улгуржи/«Тавсия» лентасига чиқмайди. "
            'Excel/CSV импорт — 2-босқич.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Супермаркет таклифлари йўқ'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final o = list[i];
                    final g = _tx.group(o.groupId);
                    return ListTile(
                      key: ValueKey('sm_admin_offer_${o.id}'),
                      title: Text('${o.name} · ${o.varietyName('uz_Cyrl')}'),
                      subtitle: Text([
                        g?.name('uz_Cyrl') ?? '⚠ гуруҳ йўқ: ${o.groupId}',
                        '${formatMoney(o.price)}/${_unitText[o.unit] ?? o.unit}',
                        _statusText[smStatusWire(o.status)] ?? '',
                        smPriceChangeText(o),
                      ].where((s) => s.isNotEmpty).join(' · ')),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () async {
                        final saved = await showDialog<bool>(
                          context: context,
                          builder: (_) => SmOfferEditorDialog(service: widget.service, taxonomy: _tx, offer: o),
                        );
                        if (saved == true) _load();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// «Нарх: 12.11 14:05, uid…» — ким/қачон (сервер `priceUpdatedBy` ёзмаса — фақат вақт).
String smPriceChangeText(SmOffer o) {
  final at = o.priceUpdatedAt;
  if (at == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  final when = '${two(at.day)}.${two(at.month)}.${at.year} ${two(at.hour)}:${two(at.minute)}';
  final who = o.priceUpdatedBy.isEmpty ? '' : ', ${o.priceUpdatedBy.length > 8 ? o.priceUpdatedBy.substring(0, 8) : o.priceUpdatedBy}…';
  return 'нарх ўзгарди: $when$who';
}

class SmOfferEditorDialog extends StatefulWidget {
  const SmOfferEditorDialog({super.key, required this.service, required this.taxonomy, this.offer});

  final AdminSupermarketService service;
  final SmTaxonomy taxonomy;

  /// `null` — янги таклиф (ID клиентда ясалади, сервер қайта юборишда идемпотент).
  final SmOffer? offer;

  @override
  State<SmOfferEditorDialog> createState() => _SmOfferEditorDialogState();
}

class _SmOfferEditorDialogState extends State<SmOfferEditorDialog> {
  late final SmOffer _o = widget.offer ?? const SmOffer(id: '', name: '', groupId: '', price: 0, stepMilli: 1000);
  late final String _productId = widget.offer?.id ?? widget.service.newProductId();
  late final _name = TextEditingController(text: widget.offer?.name ?? '');
  late String _group = _o.groupId;
  late String _unit = _o.unit.isEmpty ? 'kg' : _o.unit;
  late String _status = smStatusWire(_o.status);
  late bool _weighed = _o.weighed;
  late final _varietyId = TextEditingController(text: _o.varietyId);
  late final _vCyr = TextEditingController(text: _o.varietyNames['uz_Cyrl'] ?? '');
  late final _vLat = TextEditingController(text: _o.varietyNames['uz_Latn'] ?? '');
  late final _vRu = TextEditingController(text: _o.varietyNames['ru'] ?? '');
  late final _qCyr = TextEditingController(text: _o.qualityNames['uz_Cyrl'] ?? '');
  late final _qLat = TextEditingController(text: _o.qualityNames['uz_Latn'] ?? '');
  late final _qRu = TextEditingController(text: _o.qualityNames['ru'] ?? '');
  late final _pack = TextEditingController(text: _o.packLabel);
  late final _packQty = TextEditingController(
      text: _o.packQtyMilli == null ? '' : smFormatQty(_o.packQtyMilli!).replaceAll(',', '.'));
  late String _packUnit = _o.packUnit;
  late final _step = TextEditingController(text: smFormatQty(_o.stepMilli).replaceAll(',', '.'));
  late final _stock = TextEditingController(
      text: _o.stockMilli == null ? '' : smFormatQty(_o.stockMilli!).replaceAll(',', '.'));
  late final _price = TextEditingController(text: _o.price > 0 ? '${_o.price}' : '');
  final _purchase = TextEditingController();
  final _supplier = TextEditingController();
  List<String> _errors = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.offer == null) return;
    widget.service.loadCost(_productId).then((m) {
      if (!mounted || m == null) return;
      setState(() {
        _purchase.text = m['purchasePrice'] == null ? '' : '${m['purchasePrice']}';
        _supplier.text = '${m['supplier'] ?? ''}';
      });
    }).catchError((Object e) {
      debugPrint('[SmAdmin] cost load: $e');
    });
  }

  Map<String, String> _names(TextEditingController c, TextEditingController l, TextEditingController r) => {
        if (c.text.trim().isNotEmpty) 'uz_Cyrl': c.text.trim(),
        if (l.text.trim().isNotEmpty) 'uz_Latn': l.text.trim(),
        if (r.text.trim().isNotEmpty) 'ru': r.text.trim(),
      };

  SmOfferDraft _draft() => SmOfferDraft(
        name: _name.text,
        packQty: _packQty.text.trim().isEmpty ? null : (num.tryParse(_packQty.text.trim().replaceAll(',', '.')) ?? -1),
        packUnit: _packUnit,
        groupId: _group,
        varietyId: _varietyId.text.trim(),
        varietyNames: _names(_vCyr, _vLat, _vRu),
        qualityNames: _names(_qCyr, _qLat, _qRu),
        packLabel: _pack.text.trim(),
        unit: _unit,
        qtyStep: num.tryParse(_step.text.trim().replaceAll(',', '.')) ?? 0,
        weighed: _weighed,
        stock: _stock.text.trim().isEmpty ? null : num.tryParse(_stock.text.trim().replaceAll(',', '.')),
        status: _status,
        price: int.tryParse(_price.text.trim().replaceAll(' ', '')) ?? 0,
      );

  Future<void> _save() async {
    final d = _draft();
    final errs = d.validate(widget.taxonomy);
    final purchase = _purchase.text.trim().isEmpty ? null : int.tryParse(_purchase.text.trim().replaceAll(' ', ''));
    if (_purchase.text.trim().isNotEmpty && (purchase == null || purchase < 0)) errs.add('Харид нархи бутун сон');
    setState(() => _errors = errs);
    if (errs.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.service.saveOffer(
        productId: _productId,
        draft: d,
        purchasePrice: purchase,
        supplier: _supplier.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _errors = ['Сақлаб бўлмади: $e']);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _f(String key, String label, TextEditingController c, {TextInputType? kb}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          key: ValueKey('sm_admin_$key'),
          controller: c,
          keyboardType: kb,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final groups = [for (final c in widget.taxonomy.categories) ...c.groups];
    return AlertDialog(
      title: Text(widget.offer == null ? 'Янги таклиф' : _o.name),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('sm_admin_group'),
                initialValue: groups.any((g) => g.id == _group) ? _group : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Гуруҳ', border: OutlineInputBorder(), isDense: true),
                items: [for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name('uz_Cyrl')))],
                onChanged: (v) => setState(() {
                  _group = v ?? _group;
                  final g = widget.taxonomy.group(_group);
                  if (g != null) {
                    _unit = g.unit;
                    _weighed = g.weighed;
                    _step.text = smFormatQty(g.stepMilli).replaceAll(',', '.');
                  }
                }),
              ),
              _f('name', 'Номи (бўш — «гуруҳ + нав»)', _name),
              _f('variety_id', 'Нав ID (лотин, масалан red)', _varietyId),
              _f('variety_cyr', 'Нав (uz_Cyrl)', _vCyr),
              _f('variety_lat', 'Нав (uz_Latn)', _vLat),
              _f('variety_ru', 'Нав (ru)', _vRu),
              _f('quality_cyr', 'Сифат (uz_Cyrl)', _qCyr),
              _f('quality_lat', 'Сифат (uz_Latn)', _qLat),
              _f('quality_ru', 'Сифат (ru)', _qRu),
              _f('pack', 'Қадоқ / партия ёрлиғи', _pack),
              Row(children: [
                Expanded(
                  child: _f('pack_qty', 'Қадоқ ичида (масалан 0.9; бўш — йўқ)', _packQty,
                      kb: const TextInputType.numberWithOptions(decimal: true)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('sm_admin_pack_unit'),
                      initialValue: _packUnit,
                      decoration: const InputDecoration(labelText: 'Бирлиги', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('—')),
                        DropdownMenuItem(value: 'l', child: Text('л')),
                        DropdownMenuItem(value: 'kg', child: Text('кг')),
                        DropdownMenuItem(value: 'piece', child: Text('дона')),
                      ],
                      onChanged: (v) => setState(() => _packUnit = v ?? ''),
                    ),
                  ),
                ),
              ]),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Мижозга «1 л — N сўм» кўринади (нарх / қадоқ ичидаги миқдор).',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                // Гуруҳ алмашса бирлик ўзи янгиланади — калит қийматга боғлиқ (initialValue қайта ўқилади).
                key: ValueKey('sm_admin_unit_$_unit'),
                initialValue: _unit,
                decoration: const InputDecoration(labelText: 'Бирлик', border: OutlineInputBorder(), isDense: true),
                items: [for (final e in _unitText.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _unit = v ?? _unit),
              ),
              _f('step', 'Қадам (0.5 / 1)', _step, kb: const TextInputType.numberWithOptions(decimal: true)),
              SwitchListTile(
                key: const ValueKey('sm_admin_weighed'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Тортиладиган (+10% вақтинча ушлаш)'),
                value: _weighed,
                onChanged: (v) => setState(() => _weighed = v),
              ),
              _f('stock', 'Қолдиқ (0 — тугаган; сотиш миқдори қолдиқдан ошмайди)', _stock,
                  kb: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('sm_admin_status'),
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Ҳолат', border: OutlineInputBorder(), isDense: true),
                items: [for (final e in _statusText.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              _f('price', 'Нарх (сўм / бирлик, бутун)', _price, kb: TextInputType.number),
              if (smPriceChangeText(_o).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(smPriceChangeText(_o), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ),
              const Divider(height: 24),
              const Text('Фақат админ кўради (private/cost):', style: TextStyle(fontWeight: FontWeight.w600)),
              _f('purchase', 'Харид нархи (сўм, бутун)', _purchase, kb: TextInputType.number),
              _f('supplier', 'Етказиб берувчи', _supplier),
              for (final e in _errors)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(e, key: const ValueKey('sm_admin_error'), style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Бекор')),
        FilledButton(
          key: const ValueKey('sm_admin_save_offer'),
          onPressed: _busy ? null : _save,
          child: const Text('Сақлаш'),
        ),
      ],
    );
  }
}

// ─── Таксономия ────────────────────────────────────────────────────────────

/// JSON матни → текширув (соф, тест учун): хато бўлса Кирилл матн, акс ҳолда `null`.
String? smTaxonomyJsonProblem(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return 'JSON нотўғри';
  }
  if (decoded is! Map<String, dynamic>) return 'Илдиз объект бўлиши керак';
  if (decoded.keys.any((k) => k != 'categories')) return 'Илдизда фақат `categories` бўлсин';
  final cats = decoded['categories'];
  if (cats is! List || cats.isEmpty) return '`categories` рўйхати бўш';
  // Сервер `validateSupermarketTaxonomy` кўзгуси: 3 тилда ном, icon, бўш бўлмаган гуруҳлар, synonyms рўйхати.
  bool names3(Object? n) =>
      n is Map && ['uz_Cyrl', 'uz_Latn', 'ru'].every((l) => n[l] is String && (n[l] as String).trim().isNotEmpty);
  for (final c in cats) {
    if (c is! Map) return 'Категория объект бўлиши керак';
    if (!names3(c['names'])) return 'Категория номи 3 тилда бўлсин: ${c['id']}';
    if (c['icon'] is! String || (c['icon'] as String).isEmpty) return 'Категорияда `icon` йўқ: ${c['id']}';
    if (c['groups'] is! List || (c['groups'] as List).isEmpty) return 'Категорияда гуруҳ йўқ: ${c['id']}';
    for (final g in c['groups'] as List) {
      if (g is! Map) return 'Гуруҳ объект бўлиши керак';
      if (!names3(g['names'])) return 'Гуруҳ номи 3 тилда бўлсин: ${g['id']}';
      if (g['synonyms'] is! List) return 'Гуруҳда `synonyms` рўйхати бўлсин: ${g['id']}';
      if (g['weighed'] is! bool) return 'Гуруҳда `weighed` true/false бўлсин: ${g['id']}';
    }
  }
  final parsed = SmTaxonomy.fromMap(decoded);
  if (parsed.categories.length != cats.length) return 'Баъзи категорияларда `id` йўқ';
  var rawGroups = 0;
  for (final c in cats) {
    if (c is Map && c['groups'] is List) rawGroups += (c['groups'] as List).length;
  }
  final okGroups = parsed.categories.fold<int>(0, (n, c) => n + c.groups.length);
  if (okGroups != rawGroups) return 'Баъзи гуруҳларда `id` йўқ ёки бирлик нотўғри (kg|l|piece|pack|bunch)';
  final ids = <String>{};
  for (final c in parsed.categories) {
    for (final g in c.groups) {
      if (!ids.add(g.id)) return 'Гуруҳ ID такрорланган: ${g.id}';
    }
  }
  return null;
}

// ─── «Тоифалар ва гуруҳлар» таҳрирловчиси (эга 2026-11-28) — соф ёрдамчилар ─────────────────────────────

List<Map<String, dynamic>> _txCopy(List<Map<String, dynamic>> cats) =>
    (jsonDecode(jsonEncode(cats)) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

List<Map<String, dynamic>> _txGroups(Map<String, dynamic> c) =>
    [for (final g in (c['groups'] is List ? c['groups'] as List : const [])) Map<String, dynamic>.from(g as Map)];

/// Тартиб рақамлари қайта (1, 2, 3…) — тоифалар ва гуруҳлар кўринган тартибда.
@visibleForTesting
List<Map<String, dynamic>> smTxRenumber(List<Map<String, dynamic>> cats) {
  final out = _txCopy(cats);
  for (var i = 0; i < out.length; i++) {
    out[i]['order'] = i + 1;
    final gs = _txGroups(out[i]);
    for (var j = 0; j < gs.length; j++) {
      gs[j]['order'] = j + 1;
    }
    out[i]['groups'] = gs;
  }
  return out;
}

/// Гуруҳни тоифа ичида юқори/пастга суриш ([delta] −1 / +1); чегарадан ташқари — ўзгармайди.
@visibleForTesting
List<Map<String, dynamic>> smTxMoveGroup(List<Map<String, dynamic>> cats, int ci, int gi, int delta) {
  final out = _txCopy(cats);
  final gs = _txGroups(out[ci]);
  final to = gi + delta;
  if (to < 0 || to >= gs.length) return out;
  final g = gs.removeAt(gi);
  gs.insert(to, g);
  out[ci]['groups'] = gs;
  return smTxRenumber(out);
}

/// Гуруҳ қўшиш ([gi] null) ёки алмаштириш. Номаълум майдонлар (масалан, келажакдаги) сақланади.
@visibleForTesting
List<Map<String, dynamic>> smTxUpsertGroup(List<Map<String, dynamic>> cats, int ci, Map<String, dynamic> group, {int? gi}) {
  final out = _txCopy(cats);
  final gs = _txGroups(out[ci]);
  if (gi == null) {
    gs.add(group);
  } else {
    gs[gi] = {...gs[gi], ...group};
  }
  out[ci]['groups'] = gs;
  return smTxRenumber(out);
}

/// Ўчириш: фаол таклифи бор гуруҳ — рад (сервер ҳам GROUP_IN_USE); бошқа гуруҳларнинг `pairs`идан ҳам олинади;
/// тоифадаги охирги гуруҳ — рад (сервер GROUPS_EMPTY).
@visibleForTesting
({List<Map<String, dynamic>> cats, String? error}) smTxRemoveGroup(
  List<Map<String, dynamic>> cats,
  int ci,
  int gi,
  Set<String> inUse,
) {
  final gs = _txGroups(cats[ci]);
  final id = '${gs[gi]['id']}';
  if (inUse.contains(id)) return (cats: cats, error: 'Бу гуруҳда фаол таклифлар бор — аввал уларни ўчиринг ёки бошқа гуруҳга ўтказинг.');
  if (gs.length <= 1) return (cats: cats, error: 'Тоифада камида битта гуруҳ бўлиши керак.');
  final out = _txCopy(cats);
  final next = _txGroups(out[ci])..removeAt(gi);
  out[ci]['groups'] = next;
  for (final c in out) {
    c['groups'] = [
      for (final g in _txGroups(c))
        if (g['pairs'] is List) {...g, 'pairs': [for (final p in g['pairs'] as List) if (p != id) p]} else g,
    ];
  }
  return (cats: smTxRenumber(out), error: null);
}

/// Формадан гуруҳ (сервер шакли); хатолар — Кирилл матн (бўш — тўғри).
@visibleForTesting
({Map<String, dynamic> group, List<String> problems}) smTxGroupFromForm({
  required String id,
  required Map<String, String> names,
  required String unit,
  required String step,
  required bool weighed,
  required String synonyms,
  required String pairs,
  Set<String> takenIds = const {},
  Set<String> knownIds = const {},
}) {
  List<String> split(String s) => [for (final x in s.split(RegExp(r'[,;\n]'))) if (x.trim().isNotEmpty) x.trim()];
  final stepVal = num.tryParse(step.trim().replaceAll(',', '.'));
  final syn = split(synonyms);
  final pr = split(pairs);
  final problems = [
    if (!RegExp(r'^[a-z][a-z0-9_]{1,39}$').hasMatch(id)) 'ID: кичик лотин ҳарф, рақам, «_» (2–40 белги)',
    if (takenIds.contains(id)) 'ID банд: $id',
    for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru'])
      if ((names[l] ?? '').trim().isEmpty) 'Ном ($l) шарт',
    if (!_unitText.containsKey(unit)) 'Бирлик нотўғри',
    if (stepVal == null || stepVal <= 0) 'Қадам мусбат сон бўлсин (масалан 0.5 ёки 1)',
    for (final p in pr)
      if (!knownIds.contains(p) || p == id) 'Бирга олинади: номаълум гуруҳ $p',
    if (pr.length > 10) 'Бирга олинади: кўпи билан 10 та',
  ];
  return (
    group: {
      'id': id,
      'names': {for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) l: (names[l] ?? '').trim()},
      'unit': unit,
      'step': stepVal ?? 0,
      'weighed': weighed,
      'synonyms': syn,
      if (pr.isNotEmpty) 'pairs': pr,
    },
    problems: problems,
  );
}

class SmTaxonomyAdminTab extends StatefulWidget {
  const SmTaxonomyAdminTab({super.key, required this.service});
  final AdminSupermarketService service;

  @override
  State<SmTaxonomyAdminTab> createState() => _SmTaxonomyAdminTabState();
}

class _SmTaxonomyAdminTabState extends State<SmTaxonomyAdminTab> {
  final _json = TextEditingController();
  SmTaxonomy _tx = SmTaxonomy.empty;

  /// Таҳрирланаётган нусха (сервер шакли) — «Сақлаш»гача ҳеч нарса ёзилмайди.
  List<Map<String, dynamic>> _cats = [];

  /// Фаол таклифи бор гуруҳлар (ўчириш рад). Сервер ҳам текширади (GROUP_IN_USE).
  Set<String> _inUse = {};
  bool _dirty = false;

  /// Юкланган ҳужжат версияси — сервер `expectedVersion` (бошқа админ ўзгартирган бўлса — рад).
  int _version = 0;
  String? _msg;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.service.loadTaxonomyRaw();
      if (!mounted) return;
      final tx = SmTaxonomy.fromMap(raw);
      setState(() {
        _tx = tx;
        _version = (raw?['version'] as num?)?.toInt() ?? 0;
        _cats = [for (final c in (raw?['categories'] is List ? raw!['categories'] as List : const [])) Map<String, dynamic>.from(c as Map)];
        _dirty = false;
        // Сервер фақат `categories` калитини қабул қилади.
        _json.text = const JsonEncoder.withIndent('  ').convert({'categories': raw?['categories'] ?? const []});
      });
      final offers = await widget.service.loadOffers(tx);
      if (mounted) setState(() => _inUse = {for (final o in offers) if (o.status == SmStatus.active) o.groupId});
    } catch (e) {
      if (mounted) setState(() => _msg = 'Юклаб бўлмади: $e');
    }
  }

  Future<void> _saveCategories(List<dynamic> cats) async {
    final problem = smTaxonomyJsonProblem(jsonEncode({'categories': cats}));
    if (problem != null) return setState(() => _msg = problem);
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await widget.service.saveTaxonomy(cats, _version);
      if (mounted) setState(() => _msg = 'Сақланди');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _msg = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveJson() async {
    final problem = smTaxonomyJsonProblem(_json.text);
    if (problem != null) return setState(() => _msg = problem);
    await _saveCategories((jsonDecode(_json.text) as Map<String, dynamic>)['categories'] as List);
  }

  void _apply(List<Map<String, dynamic>> next) => setState(() {
        _cats = next;
        _dirty = true;
        _msg = null;
      });

  Set<String> get _allIds => {for (final c in _cats) for (final g in _txGroups(c)) '${g['id']}'};

  Future<void> _editGroup(int ci, {int? gi}) async {
    final base = gi == null ? null : _txGroups(_cats[ci])[gi];
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SmGroupDialog(
        base: base,
        takenIds: gi == null ? _allIds : (_allIds..remove('${base!['id']}')),
        knownIds: _allIds,
      ),
    );
    if (res != null) _apply(smTxUpsertGroup(_cats, ci, res, gi: gi));
  }

  void _remove(int ci, int gi) {
    final r = smTxRemoveGroup(_cats, ci, gi, _inUse);
    if (r.error != null) return setState(() => _msg = r.error);
    _apply(r.cats);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _tx.categories.fold<int>(0, (n, c) => n + c.groups.length);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Версия ${_tx.version} · ${_tx.categories.length} категория · $groups гуруҳ',
            key: const ValueKey('sm_admin_tx_summary')),
        const SizedBox(height: 4),
        const Text('Гуруҳ номлари (3 тилда), бирлик, қадам, тортиладими, синонимлар ва «бирга олинади». '
            'Фаол таклифи бор гуруҳни ўчириб бўлмайди.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        for (var ci = 0; ci < _cats.length; ci++)
          ExpansionTile(
            key: ValueKey('sm_admin_tx_cat_${_cats[ci]['id']}'),
            title: Text('${(_cats[ci]['names'] as Map?)?['uz_Cyrl'] ?? _cats[ci]['id']} (${_txGroups(_cats[ci]).length})'),
            children: [
              for (var gi = 0; gi < _txGroups(_cats[ci]).length; gi++) _groupTile(ci, gi),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('sm_admin_tx_add_${_cats[ci]['id']}'),
                  onPressed: _busy ? null : () => _editGroup(ci),
                  icon: const Icon(Icons.add),
                  label: const Text('Гуруҳ қўшиш'),
                ),
              ),
            ],
          ),
        if (_msg != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, key: const ValueKey('sm_admin_tx_msg'))),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('sm_admin_tx_form_save'),
          onPressed: _busy || !_dirty ? null : () => _saveCategories(smTxRenumber(_cats)),
          child: const Text('Ўзгаришларни сақлаш'),
        ),
        const Divider(height: 24),
        ExpansionTile(
          key: const ValueKey('sm_admin_tx_advanced'),
          title: const Text('Кенгайтирилган (JSON)'),
          children: [
            const Text('Тўлиқ JSON. Сақлаш — сервер `adminSetSupermarketTaxonomy` (версия + audit).'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('sm_admin_tx_json'),
              controller: _json,
              maxLines: 18,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('sm_admin_tx_save'),
              onPressed: _busy ? null : _saveJson,
              child: const Text('JSON сақлаш'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _groupTile(int ci, int gi) {
    final g = _txGroups(_cats[ci])[gi];
    final id = '${g['id']}';
    final used = _inUse.contains(id);
    final names = g['names'] is Map ? g['names'] as Map : const {};
    final syn = g['synonyms'] is List ? (g['synonyms'] as List).join(', ') : '';
    return ListTile(
      key: ValueKey('sm_admin_tx_group_$id'),
      dense: true,
      title: Text('${names['uz_Cyrl'] ?? id}'),
      subtitle: Text('$id · ${_unitText[g['unit']] ?? g['unit']} · қадам ${g['step']}'
          '${g['weighed'] == true ? ' · тортилади' : ''}${syn.isEmpty ? '' : ' · $syn'}${used ? ' · фаол таклиф бор' : ''}'),
      trailing: Wrap(children: [
        IconButton(key: ValueKey('sm_admin_tx_up_$id'), icon: const Icon(Icons.arrow_upward), onPressed: gi == 0 ? null : () => _apply(smTxMoveGroup(_cats, ci, gi, -1))),
        IconButton(
            key: ValueKey('sm_admin_tx_down_$id'),
            icon: const Icon(Icons.arrow_downward),
            onPressed: gi == _txGroups(_cats[ci]).length - 1 ? null : () => _apply(smTxMoveGroup(_cats, ci, gi, 1))),
        IconButton(key: ValueKey('sm_admin_tx_edit_$id'), icon: const Icon(Icons.edit_outlined), onPressed: () => _editGroup(ci, gi: gi)),
        IconButton(
          key: ValueKey('sm_admin_tx_del_$id'),
          tooltip: used ? 'Фаол таклифи бор — ўчириб бўлмайди' : 'Ўчириш',
          icon: const Icon(Icons.delete_outline),
          onPressed: used ? null : () => _remove(ci, gi),
        ),
      ]),
    );
  }
}

class _SmGroupDialog extends StatefulWidget {
  const _SmGroupDialog({this.base, required this.takenIds, required this.knownIds});
  final Map<String, dynamic>? base;
  final Set<String> takenIds;
  final Set<String> knownIds;

  @override
  State<_SmGroupDialog> createState() => _SmGroupDialogState();
}

class _SmGroupDialogState extends State<_SmGroupDialog> {
  late final Map<String, dynamic> _b = widget.base ?? const {};
  late final _id = TextEditingController(text: '${_b['id'] ?? ''}');
  late final Map<String, TextEditingController> _names = {
    for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) l: TextEditingController(text: '${(_b['names'] as Map?)?[l] ?? ''}'),
  };
  late String _unit = _unitText.containsKey(_b['unit']) ? '${_b['unit']}' : 'kg';
  late final _step = TextEditingController(text: '${_b['step'] ?? 1}');
  late bool _weighed = _b['weighed'] == true;
  late final _syn = TextEditingController(text: _b['synonyms'] is List ? (_b['synonyms'] as List).join(', ') : '');
  late final _pairs = TextEditingController(text: _b['pairs'] is List ? (_b['pairs'] as List).join(', ') : '');
  List<String> _problems = const [];

  @override
  void dispose() {
    for (final c in [_id, _step, _syn, _pairs, ..._names.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _ok() {
    final r = smTxGroupFromForm(
      id: _id.text.trim(),
      names: {for (final e in _names.entries) e.key: e.value.text},
      unit: _unit,
      step: _step.text,
      weighed: _weighed,
      synonyms: _syn.text,
      pairs: _pairs.text,
      takenIds: widget.takenIds,
      knownIds: widget.knownIds,
    );
    if (r.problems.isNotEmpty) return setState(() => _problems = r.problems);
    Navigator.of(context).pop(r.group);
  }

  Widget _tf(String key, String label, TextEditingController c, {bool enabled = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: ValueKey('sm_admin_txg_$key'),
          controller: c,
          enabled: enabled,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.base == null ? 'Янги гуруҳ' : 'Гуруҳни таҳрирлаш'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _tf('id', 'ID (лотин, ўзгармайди)', _id, enabled: widget.base == null),
            _tf('name_uz_Cyrl', 'Номи (кирилл)', _names['uz_Cyrl']!),
            _tf('name_uz_Latn', 'Номи (лотин)', _names['uz_Latn']!),
            _tf('name_ru', 'Номи (рус)', _names['ru']!),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('sm_admin_txg_unit'),
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'Бирлик', border: OutlineInputBorder(), isDense: true),
                  items: [for (final e in _unitText.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _unit = v ?? _unit),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _tf('step', 'Қадам', _step)),
            ]),
            SwitchListTile(
              key: const ValueKey('sm_admin_txg_weighed'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Тортилади (оғирлик бўйича)'),
              value: _weighed,
              onChanged: (v) => setState(() => _weighed = v),
            ),
            _tf('synonyms', 'Синонимлар (вергул билан)', _syn),
            _tf('pairs', 'Бирга олинади — гуруҳ ID (вергул билан)', _pairs),
            for (final p in _problems) Text(p, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Бекор')),
        FilledButton(key: const ValueKey('sm_admin_txg_ok'), onPressed: _ok, child: const Text('Тайёр')),
      ],
    );
  }
}
// ─── Буюртмалар ────────────────────────────────────────────────────────────

/// Буюртма қатори (supermarket.js `priceSupermarketOrder` / `applyWeights` / олиб ташлаш шакли).
typedef SmOrderLine = ({
  String productId,
  String name,
  num qty,
  String unit,
  bool weighed,
  num? actualQty,
  bool removed,
  bool shortage,
});

/// `items[{productId, name, qty, unit (кўриниш), smUnit, weighed, actualQty?, removed?{reason,...}}]`.
List<SmOrderLine> smOrderLines(Map<String, dynamic> o) {
  final raw = o['items'];
  if (raw is! List) return const [];
  return [
    for (final i in raw)
      if (i is Map)
        (
          productId: '${i['productId'] ?? i['itemId'] ?? ''}',
          name: '${i['name'] ?? ''}',
          qty: (i['qty'] ?? i['count'] ?? 0) as num,
          unit: '${i['smUnit'] ?? i['unit'] ?? ''}',
          weighed: i['weighed'] == true,
          actualQty: i['actualQty'] is num ? i['actualQty'] as num : null,
          removed: i['removed'] != null && i['removed'] != false,
          // Сервер (cd02561a): `shortage{state 'pending'|'resolved'|'admin_removed', ...}`.
          shortage: i['shortage'] is Map && (i['shortage'] as Map)['state'] == 'pending',
        ),
  ];
}

/// Тортилиши кутилаётган қаторлар (олинмаган, ҳали тортилмаган).
List<SmOrderLine> smLinesToWeigh(List<SmOrderLine> lines) =>
    lines.where((l) => l.weighed && !l.removed && l.actualQty == null).toList();

/// Сервер `ADJUSTABLE_STATUSES` — тортиш/олиш фақат шу ҳолатларда.
const kSmAdjustableStatuses = {'new', 'accepted', 'ready'};

const _moneyLabels = <String, String>{
  'itemsTotal': 'Маҳсулот',
  'weighHold': 'Тортиш ушлаши',
  'deliveryFee': 'Етказиш',
  'total': 'Ечилган',
  'smRefundedTotal': 'Қайтарилган',
};

class SmOrdersAdminTab extends StatelessWidget {
  const SmOrdersAdminTab({super.key, required this.service, this.orders});

  final AdminSupermarketService service;

  /// Тест учун.
  final Stream<List<Map<String, dynamic>>>? orders;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: orders ?? service.watchOrders(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Юклаб бўлмади: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!;
        if (list.isEmpty) return const Center(child: Text('Супермаркет буюртмалари йўқ'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          itemBuilder: (context, i) => _OrderCard(service: service, order: list[i]),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.service, required this.order});

  final AdminSupermarketService service;
  final Map<String, dynamic> order;

  String get _id => '${order['id']}';

  @override
  Widget build(BuildContext context) {
    final lines = smOrderLines(order);
    final rawStatus = '${order['status'] ?? ''}';
    final fs = '${order['fulfillmentStatus'] ?? ''}';
    final status = fs.isEmpty || fs == 'pending' ? rawStatus : '$rawStatus / $fs';
    final adjustable = kSmAdjustableStatuses.contains(rawStatus);
    final toWeigh = smLinesToWeigh(lines);
    final money = [
      for (final e in _moneyLabels.entries)
        if (order[e.key] is num) '${e.value}: ${formatMoney(order[e.key] as num)}',
    ];
    return Card(
      key: ValueKey('sm_admin_order_$_id'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('#$_id · $status', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (money.isNotEmpty) Text(money.join(' · ')),
            for (final l in lines)
              Row(children: [
                Expanded(
                  child: Text(
                    '${l.name} — ${l.qty} ${_unitText[l.unit] ?? l.unit}'
                    '${l.weighed ? (l.actualQty == null ? ' (тортилади)' : ' (тортилди: ${l.actualQty})') : ''}'
                    '${l.removed ? ' — ОЛИНДИ' : ''}'
                    '${l.shortage && !l.removed ? ' — ЕТИШМОВЧИЛИК: мижоз жавобини кутмоқда' : ''}',
                    style: l.removed ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.black45) : null,
                  ),
                ),
                if (adjustable && !l.removed && !l.shortage)
                  IconButton(
                    key: ValueKey('sm_admin_shortage_${_id}_${l.productId}'),
                    tooltip: 'Етишмовчилик (мижоз танлайди)',
                    icon: const Icon(Icons.production_quantity_limits_outlined),
                    onPressed: () => _shortage(context, l),
                  ),
                if (adjustable && !l.removed)
                  IconButton(
                    key: ValueKey('sm_admin_remove_${_id}_${l.productId}'),
                    tooltip: 'Қаторни олиб ташлаш',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _remove(context, l.productId, l.name),
                  ),
              ]),
            if (adjustable && toWeigh.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  key: ValueKey('sm_admin_settle_$_id'),
                  onPressed: () => _settle(context, toWeigh),
                  child: const Text('Тортиб ҳисоблаш'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(BuildContext context, String productId, String name) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('«$name» қаторини олиб ташлаш'),
        content: TextField(
          key: const ValueKey('sm_admin_remove_reason'),
          controller: reason,
          decoration: const InputDecoration(labelText: 'Сабаб (мижозга пул қайтади)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
          FilledButton(
            key: const ValueKey('sm_admin_remove_confirm'),
            onPressed: () => Navigator.pop(ctx, reason.text.trim().length >= 3),
            child: const Text('Олиб ташлаш'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () => service.removeLine(_id, productId, reason.text.trim()));
  }

  Future<void> _settle(BuildContext context, List<SmOrderLine> lines) async {
    final ctrls = {for (final l in lines) l.productId: TextEditingController(text: '${l.qty}')};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ҳақиқий оғирлик'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in lines)
              TextField(
                key: ValueKey('sm_admin_actual_${l.productId}'),
                controller: ctrls[l.productId],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: '${l.name} (${_unitText[l.unit] ?? l.unit})'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
          FilledButton(
            key: const ValueKey('sm_admin_settle_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ҳисоблаш'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final parsed = smParseActualQty({for (final e in ctrls.entries) e.key: e.value.text});
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оғирлик нотўғри (0 дан катта сон)')));
      return;
    }
    await _run(context, () => service.settleWeights(_id, parsed));
  }

  /// Етишмовчилик: мавжуд миқдор + кўпи билан 3 та ўрнини босувчи (шу гуруҳ, сотувда, арзонидан).
  Future<void> _shortage(BuildContext context, SmOrderLine l) async {
    final m = ScaffoldMessenger.of(context);
    final groupId = _groupOf(l.productId);
    List<SmOffer> pool;
    try {
      final all = await service.loadOffers(SmTaxonomy.empty);
      // Сервер: ўзи ва буюртмадаги бошқа маҳсулотлар ўрнини босувчи бўлолмайди (SUBSTITUTE_INVALID).
      final inOrder = {for (final x in smOrderLines(order)) if (!x.removed) x.productId};
      pool = smSortOffersAsc(all.where((o) => !inOrder.contains(o.id) && o.available && (groupId.isEmpty || o.groupId == groupId)));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Таклифларни юклаб бўлмади: $e')));
      return;
    }
    if (!context.mounted) return;
    final res = await showDialog<({num available, List<String> subs})>(
      context: context,
      builder: (_) => SmShortageAdminDialog(line: l, pool: pool),
    );
    if (res == null || !context.mounted) return;
    await _run(context, () => service.reportShortage(_id, l.productId, res.available, res.subs));
  }

  String _groupOf(String productId) {
    final raw = order['items'];
    if (raw is List) {
      for (final i in raw) {
        if (i is Map && i['productId'] == productId && i['groupId'] is String) return i['groupId'] as String;
      }
    }
    return '';
  }

  Future<void> _run(BuildContext context, Future<void> Function() f) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await f();
      m.showSnackBar(const SnackBar(content: Text('Бажарилди')));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

/// Ҳақиқий миқдорлар (соф): ҳаммаси мусбат сон бўлса рўйхат, акс ҳолда `null`.
List<({String productId, num actualQty})>? smParseActualQty(Map<String, String> raw) {
  final out = <({String productId, num actualQty})>[];
  for (final e in raw.entries) {
    final v = num.tryParse(e.value.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    out.add((productId: e.key, actualQty: v));
  }
  return out;
}

// ─── Созламалар ────────────────────────────────────────────────────────────

/// Етказиш ҳақи % (`settings/app.platformDeliveryFeePercent`) — ЯГОНА манба (AVA товари ва супермаркет бир хил):
/// ўқиш — `settings/app` оқими, ёзиш — мавжуд `AdminMarketService.setPlatformDeliveryFeePercent` (эга 2026-11-28).
class SmDeliveryFeeSource {
  const SmDeliveryFeeSource({required this.watch, required this.save});
  final Stream<num?> Function() watch;
  final Future<void> Function(double percent) save;
}

/// Фоиз матни: бутун бўлса «11», бўлмаса «11.5»; йўқ — «—».
@visibleForTesting
String smFeePercentText(num? v) => v == null ? '—' : (v == v.roundToDouble() ? '${v.round()}' : '$v');

class SmSettingsAdminTab extends StatefulWidget {
  const SmSettingsAdminTab({super.key, required this.service, this.fee});
  final AdminSupermarketService service;

  /// Тест учун; сукут — Firestore `settings/app` + `AdminMarketService` (Provider) + админ телефони.
  final SmDeliveryFeeSource? fee;

  @override
  State<SmSettingsAdminTab> createState() => _SmSettingsAdminTabState();
}

class _SmSettingsAdminTabState extends State<SmSettingsAdminTab> {
  final _holdPct = TextEditingController();
  final _reason = TextEditingController();
  final _feePct = TextEditingController();

  /// Курьер тўлови: '' — созланмаган, 'percent' | 'fixed'.
  String _cpMode = '';
  final _cpValue = TextEditingController();

  /// Юкланган версия — сервер `expectedVersion` (бошқа админ ўзгартирган бўлса — рад, саҳифани янгилаш).
  int _version = 0;
  String? _msg;
  String? _feeMsg;
  bool _busy = false;
  bool _feeBusy = false;
  bool _loaded = false;
  bool _feeSynced = false;
  late final SmDeliveryFeeSource _fee = widget.fee ?? _defaultFee();
  late final Stream<num?> _feeStream = _fee.watch();

  SmDeliveryFeeSource _defaultFee() => SmDeliveryFeeSource(
        watch: () => FirebaseFirestore.instance
            .collection('settings')
            .doc('app')
            .snapshots()
            .map((s) => s.data()?['platformDeliveryFeePercent'] as num?),
        save: (pct) async {
          final phone = context.read<AdminAuthService>().phoneDigits ?? '';
          if (phone.isEmpty) throw StateError('Admin телефон топилмади — қайта киринг');
          await context.read<AdminMarketService>().setPlatformDeliveryFeePercent(adminPhone: phone, percent: pct);
        },
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_holdPct, _reason, _feePct, _cpValue]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.service.loadSettings();
      if (!mounted) return;
      setState(() {
        _version = s.version;
        _holdPct.text = '${s.weighHoldPercent}';
        final cp = s.courierPayout;
        _cpMode = cp?.mode ?? '';
        _cpValue.text = cp == null ? '' : '${cp.mode == 'percent' ? cp.percent : cp.fixedAmount}';
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _msg = 'Юклаб бўлмади: $e');
    }
  }

  Future<void> _saveFee() async {
    final pct = double.tryParse(_feePct.text.trim().replaceAll(',', '.'));
    if (pct == null || pct < 0 || pct > 100) return setState(() => _feeMsg = 'Фоиз 0…100 оралиғида бўлиши керак');
    setState(() {
      _feeBusy = true;
      _feeMsg = null;
    });
    try {
      await _fee.save(pct);
      if (mounted) setState(() => _feeMsg = 'Етказиш ҳақи: ${smFeePercentText(pct)}% сақланди');
    } catch (e) {
      if (mounted) setState(() => _feeMsg = 'Сақлаб бўлмади: $e');
    } finally {
      if (mounted) setState(() => _feeBusy = false);
    }
  }

  Future<void> _save() async {
    final hold = int.tryParse(_holdPct.text.trim()) ?? -1;
    final cpVal = int.tryParse(_cpValue.text.trim()) ?? -1;
    final cp = _cpMode == 'percent'
        ? SmCourierPayout.percent(cpVal)
        : _cpMode == 'fixed'
            ? SmCourierPayout.fixed(cpVal)
            : null;
    final settings = SmSettings(weighHoldPercent: hold, courierPayout: cp);
    final errs = [
      ...settings.problems(),
      if (_reason.text.trim().length < 3) 'Сабаб ёзинг (audit)',
    ];
    if (errs.isNotEmpty) return setState(() => _msg = errs.join('\n'));
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await widget.service.saveSettings(settings, expectedVersion: _version, reason: _reason.text.trim());
      if (mounted) setState(() => _msg = 'Сақланди');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _msg = 'Сақлаб бўлмади: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && _msg == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Эга 2026-11-28: ким кўради — ФАҚАТ «Ҳудудлар ва хизматлар» (модул «supermarket»); вақт оралиқлари йўқ.
        const Text(
          'Супермаркет кимга кўринади — «Ҳудудлар ва хизматлар» бўлимида («AVA Супермаркет» модули, туман бўйича). '
          'Оддий буюртма имкон қадар тез етказилади; совға/байрам саватчасида мижоз фақат санани танлайди.',
          key: ValueKey('sm_admin_visibility_note'),
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        StreamBuilder<num?>(
          stream: _feeStream,
          builder: (context, snap) {
            final live = snap.data;
            if (!_feeSynced && snap.hasData) {
              _feeSynced = true;
              _feePct.text = live == null ? '' : smFeePercentText(live);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('sm_admin_fee_pct'),
                    controller: _feePct,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Етказиш ҳақи, %', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('sm_admin_fee_save'),
                  onPressed: _feeBusy ? null : _saveFee,
                  child: const Text('Сақлаш'),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Ҳозир: ${smFeePercentText(live)}% — AVA товари ва супермаркет учун ягона созлама '
                  '(settings/app.platformDeliveryFeePercent). Янги буюртмаларга қўлланади.',
                  key: const ValueKey('sm_admin_fee_live'),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              if (_feeMsg != null) Text(_feeMsg!, key: const ValueKey('sm_admin_fee_msg')),
            ]);
          },
        ),
        const Divider(height: 28),
        _field('hold_pct', 'Тортиладиган маҳсулот учун вақтинча ушлаш, % (0..50; эга қарори — 10)', _holdPct),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const ValueKey('sm_admin_cp_mode'),
                initialValue: _cpMode,
                decoration: const InputDecoration(labelText: 'Курьерга тўлов (супермаркет буюртмаси)', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Созланмаган')),
                  DropdownMenuItem(value: 'percent', child: Text('Етказиш ҳақидан %')),
                  DropdownMenuItem(value: 'fixed', child: Text('Белгиланган сумма (сўм)')),
                ],
                onChanged: (v) => setState(() => _cpMode = v ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            if (_cpMode.isNotEmpty)
              Expanded(
                child: TextField(
                  key: const ValueKey('sm_admin_cp_value'),
                  controller: _cpValue,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _cpMode == 'percent' ? 'Фоиз (0..100)' : 'Сумма, сўм',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Сумма ҳар буюртмага яратилганда ёзилади — кейинги ўзгариш эски буюртмаларга таъсир қилмайди. '
            'Тўлов курьер картасига тизимдан ташқарида қўлда ўтказилади; карта рақами сақланмайди.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        _field('reason', 'Сабаб (audit)', _reason),
        if (_msg != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, key: const ValueKey('sm_admin_settings_msg'))),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('sm_admin_settings_save'),
          onPressed: _busy ? null : _save,
          child: const Text('Сақлаш'),
        ),
      ],
    );
  }

  Widget _field(String key, String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          key: ValueKey('sm_admin_$key'),
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );
}
/// Етишмовчилик ойнаси: мавжуд миқдор (0 ≤ x < буюртмадаги) + кўпи билан 3 та ўрнини босувчи.
class SmShortageAdminDialog extends StatefulWidget {
  const SmShortageAdminDialog({super.key, required this.line, required this.pool});

  final SmOrderLine line;

  /// Шу гуруҳдаги сотувдаги таклифлар (арзонидан).
  final List<SmOffer> pool;

  @override
  State<SmShortageAdminDialog> createState() => _SmShortageAdminDialogState();
}

class _SmShortageAdminDialogState extends State<SmShortageAdminDialog> {
  final _qty = TextEditingController(text: '0');
  final _subs = <String>[];
  List<String> _problems = const [];

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _submit() {
    final v = num.tryParse(_qty.text.trim().replaceAll(',', '.'));
    final p = smShortageAdminProblems(orderedQty: widget.line.qty, availableQty: v, substitutes: _subs);
    if (p.isNotEmpty) {
      setState(() => _problems = p);
      return;
    }
    Navigator.pop(context, (available: v!, subs: List<String>.of(_subs)));
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    return AlertDialog(
      title: Text('«${l.name}» — етишмовчилик'),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('Буюртмада: ${l.qty} ${_unitText[l.unit] ?? l.unit}. Мижоз ўзи танлайди: ўрнини босувчи / камайтириш / олиб ташлаш.'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('sm_admin_shortage_qty'),
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Мавжуд миқдор (${_unitText[l.unit] ?? l.unit})'),
            ),
            const SizedBox(height: 12),
            Text('Ўрнини босувчилар (кўпи билан 3 та): ${_subs.length}/3', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (widget.pool.isEmpty) const Text('Шу гуруҳда сотувда бошқа таклиф йўқ'),
            for (final o in widget.pool)
              CheckboxListTile(
                key: ValueKey('sm_admin_shortage_sub_${o.id}'),
                dense: true,
                value: _subs.contains(o.id),
                onChanged: !_subs.contains(o.id) && _subs.length >= 3
                    ? null
                    : (v) => setState(() => v == true ? _subs.add(o.id) : _subs.remove(o.id)),
                title: Text(o.name),
                subtitle: Text('${formatMoney(o.price)}/${_unitText[o.unit] ?? o.unit}'),
              ),
            for (final p in _problems) Text(p, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(key: const ValueKey('sm_admin_shortage_confirm'), onPressed: _submit, child: const Text('Мижозга юбориш')),
      ],
    );
  }
}
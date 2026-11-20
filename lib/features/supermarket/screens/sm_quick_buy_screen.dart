import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../domain/sm_cross_sell.dart';
import '../domain/sm_offer.dart';
import '../domain/sm_qty.dart';
import '../domain/sm_search.dart';
import '../domain/sm_taxonomy.dart';
import '../supermarket_controller.dart';
import '../widgets/sm_offer_pick_sheet.dart';
import '../widgets/sm_widgets.dart';
import 'supermarket_home_screen.dart';

/// «Тезкор харид» (2-босқич, эга 2026-11-21): қидирув + категория чиплари + ихчам гуруҳлар рўйхати.
/// «＋» — танланган таклифни бир қадам қўшади ёки ихчам ойнани очади; рўйхат ўрни сақланади.
class SmQuickBuyScreen extends StatefulWidget {
  const SmQuickBuyScreen({super.key, required this.controller});

  final SupermarketController controller;

  @override
  State<SmQuickBuyScreen> createState() => _SmQuickBuyScreenState();
}

class _SmQuickBuyScreenState extends State<SmQuickBuyScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _category = '';

  SupermarketController get _c => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SmGroup> _groups() {
    final q = _query.trim();
    if (q.isEmpty) return smQuickGroups(_c.taxonomy, _c.offersByGroup, categoryId: _category);
    final found = smSearchGroups(_c.taxonomy, _c.offersByGroup, q);
    return _category.isEmpty ? found : found.where((g) => g.categoryId == _category).toList();
  }

  Future<void> _choose(SmGroup g) async {
    final sel = _c.quickSelected(g.id);
    final r = await showSmOfferPickSheet(context, controller: _c, group: g, initialOfferId: sel?.id);
    if (r == null || !mounted) return;
    _added(r.offer, r.qtyMilli, g);
  }

  void _plus(SmGroup g) {
    final sel = _c.quickSelected(g.id);
    if (sel == null) {
      _choose(g);
      return;
    }
    _added(sel, sel.stepMilli, g);
  }

  void _added(SmOffer o, int qtyMilli, SmGroup g) {
    _c.quickAdd(o, qtyMilli);
    final lang = context.contentLang;
    final name = o.varietyNames.isNotEmpty ? o.varietyName(lang) : g.name(lang);
    final unit = smUnitLabel(context, o.unit);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('sm_added_snack'),
        duration: const Duration(seconds: 2),
        content: Text(context
            .tr('sm_added_to_cart')
            .replaceAll('{name}', name)
            .replaceAll('{qty}', '${smFormatQty(qtyMilli)} $unit'.trim())),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('sm_quick_title')),
        actions: [SmCartAction(controller: _c, onTap: () => smOpenCart(context, _c))],
      ),
      bottomNavigationBar: SmBottomBar(controller: _c, onCart: () => smOpenCart(context, _c)),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final groups = _groups();
          return CustomScrollView(
            key: const PageStorageKey('sm_quick_list'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    key: const ValueKey('sm_quick_search'),
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: context.tr('sm_search_hint'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.tr('sm_clear'),
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                            ),
                      filled: true,
                      fillColor: c.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.line)),
                      enabledBorder:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.line)),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _CatChip(id: 'all', label: context.tr('sm_all'), selected: _category.isEmpty, onTap: () => setState(() => _category = '')),
                      for (final cat in _c.taxonomy.categories)
                        if (_c.visibleGroups(cat).isNotEmpty)
                          _CatChip(
                            id: cat.id,
                            label: cat.name(lang),
                            icon: smCategoryIcon(cat.icon),
                            selected: _category == cat.id,
                            onTap: () => setState(() => _category = cat.id),
                          ),
                    ],
                  ),
                ),
              ),
              if (groups.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(context.tr('sm_search_none'),
                        key: const ValueKey('sm_quick_none'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: groups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) => _QuickRow(
                      group: groups[i],
                      lang: lang,
                      selected: _c.quickSelected(groups[i].id),
                      cheapest: smCheapestActivePrice(_c.offersByGroup[groups[i].id] ?? const []),
                      inCartMilli: _cartQtyOfGroup(groups[i].id),
                      onChoose: () => _choose(groups[i]),
                      onPlus: () => _plus(groups[i]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  int _cartQtyOfGroup(String groupId) {
    var n = 0;
    for (final l in _c.cart.lines) {
      if (_c.offers[l.productId]?.groupId == groupId) n += l.qtyMilli;
    }
    return n;
  }
}

class _CatChip extends StatelessWidget {
  const _CatChip({required this.id, required this.label, required this.selected, required this.onTap, this.icon});

  final String id;
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: ValueKey('sm_quick_cat_$id'),
          avatar: icon == null ? null : Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontSize: 15)),
          selected: selected,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          onSelected: (_) => onTap(),
        ),
      );
}

class _QuickRow extends StatelessWidget {
  const _QuickRow({
    required this.group,
    required this.lang,
    required this.selected,
    required this.cheapest,
    required this.inCartMilli,
    required this.onChoose,
    required this.onPlus,
  });

  final SmGroup group;
  final String lang;
  final SmOffer? selected;
  final int? cheapest;
  final int inCartMilli;
  final VoidCallback onChoose;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final sel = selected;
    final unit = smUnitLabel(context, group.unit);
    final String sub;
    if (sel != null) {
      final label = [sel.varietyName(lang), sel.qualityName(lang), sel.packLabel].where((s) => s.isNotEmpty).toSet().join(' · ');
      sub = '$label — ${smPricePerUnit(context, sel.price, sel.unit)}';
    } else if (cheapest != null) {
      sub = context.tr('sm_price_from').replaceAll('{price}', smPricePerUnit(context, cheapest!, group.unit));
    } else {
      sub = context.tr('sm_out_of_stock');
    }
    final canBuy = cheapest != null;
    return Container(
      key: ValueKey('sm_quick_row_${group.id}'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit.isEmpty ? group.name(lang) : '${group.name(lang)}, $unit',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
                ),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.ink2)),
                if (inCartMilli > 0)
                  Text(
                    context.tr('sm_quick_in_cart').replaceAll('{qty}', '${smFormatQty(inCartMilli)} $unit'.trim()),
                    key: ValueKey('sm_quick_in_cart_${group.id}'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.brandText),
                  ),
                TextButton(
                  key: ValueKey('sm_quick_choose_${group.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 44), padding: EdgeInsets.zero),
                  onPressed: canBuy ? onChoose : null,
                  child: Text(context.tr('sm_quick_choose'), style: const TextStyle(fontSize: 15)),
                ),
              ],
            ),
          ),
          IconButton.filled(
            key: ValueKey('sm_quick_add_${group.id}'),
            tooltip: context.tr('sm_add_to_cart'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: canBuy ? onPlus : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

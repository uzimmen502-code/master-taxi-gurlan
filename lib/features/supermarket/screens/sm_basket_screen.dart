import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../restaurants/domain/restaurants_access.dart' show kRestaurantsModuleId;
import '../../restaurants/screens/restaurants_list_screen.dart';
import '../data/holiday_repository.dart' show HolidayCatalogCache;
import '../data/sm_basket_birthdays.dart';
import '../data/sm_lists_repository.dart';
import '../data/supermarket_repository.dart' show smOriginHoliday, smOriginWeekly;
import '../domain/sm_basket.dart';
import '../domain/sm_holiday.dart';
import '../domain/sm_list.dart';
import '../domain/sm_offer.dart';
import '../domain/sm_qty.dart';
import '../domain/sm_taxonomy.dart';
import '../sm_basket_controller.dart';
import '../supermarket_controller.dart';
import '../widgets/sm_compare_dialog.dart';
import '../widgets/sm_widgets.dart';
import 'sm_checkout_screen.dart';
import 'sm_weekly_screen.dart';
import 'supermarket_home_screen.dart' show smCategoryIcon;

/// «Менинг ҳафталик харид саватчам»ни очиш (эга 2026-11-28) — супермаркетдан ташқаридан (бош саҳифа карточкаси,
/// байрам/туғилган кун эслатмалари, қариндошлар). [holiday] — байрам/туғилган кун контексти (буюртма манбаи
/// 'holiday'); [checkout] — совға олдиндан тўлдирилиши (қариндош) ёки 'gift' режими.
Future<void> openSmBasket(
  NavigatorState nav, {
  bool holiday = false,
  SmHolidayCheckout? checkout,
  String? openListId,
}) =>
    nav.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: kSmHomeRouteName),
      builder: (_) => SmBasketScreen(holiday: holiday, checkout: checkout, openListId: openListId),
    ));

/// Саватча экрани: категория чиплари + гуруҳлар 2 устунли тўри (расм, миқдор нишони), пастда ихчам панел.
/// ҲЕЧ ҚАЧОН ўзи буюртма бермайди: «Расмийлаштириш» — мавжуд супермаркет расмийлаштириши.
class SmBasketScreen extends StatefulWidget {
  const SmBasketScreen({
    super.key,
    this.controller,
    this.store,
    this.memo,
    this.pointer,
    this.birthdays,
    this.today,
    this.holiday = false,
    this.checkout,
    this.openListId,
    this.openCheckout,
    this.ordersLoader,
    this.saveDelay = const Duration(milliseconds: 700),
  });

  /// Тест учун; бўлмаса — янги (Firebase), экран ўзи юклайди.
  final SupermarketController? controller;
  final SmListsStore? store;
  final SmListPriceMemo? memo;
  final SmBasketPointer? pointer;
  final SmBasketBirthdaysLoader? birthdays;
  final DateTime? today;
  final bool holiday;
  final SmHolidayCheckout? checkout;

  /// Ҳафталик эслатма push'идан (`smListId`): саватчанинг ўзи бўлмаса — ўша «бошқа рўйхат» очилади.
  final String? openListId;

  /// Тест учун; бўлмаса — [SmCheckoutScreen].
  final void Function(BuildContext context, SmHolidayCheckout checkout)? openCheckout;
  final Duration saveDelay;

  /// Тест учун; бўлмаса — [loadSupermarketOrdersCached] («Олдин олганларингиз»).
  final SmOrdersLoader? ordersLoader;

  @override
  State<SmBasketScreen> createState() => _SmBasketScreenState();
}

class _SmBasketScreenState extends State<SmBasketScreen> {
  late final SupermarketController _c = widget.controller ?? SupermarketController();
  late final SmListsStore _store = widget.store ?? FirestoreSmListsStore();
  SmBasketController? _b;
  final _scroll = ScrollController();
  String _cat = '';
  bool _birthday = false;
  List<SmPastOrder> _pastOrders = const [];

  @override
  void initState() {
    super.initState();
    // context.tr (InheritedWidget) — биринчи кадрдан кейин.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _init();
    });
  }

  Future<void> _init() async {
    if (widget.controller == null) await _c.load();
    if (!mounted) return;
    final b = SmBasketController(
      supermarket: _c,
      store: _store,
      memo: widget.memo,
      pointer: widget.pointer,
      saveDelay: widget.saveDelay,
      defaultName: context.tr('smb_title'),
    );
    setState(() => _b = b);
    await b.load();
    _loadBirthdays();
    _loadPast();
    final target = widget.openListId ?? '';
    if (!mounted || target.isEmpty || target == b.basket.id) return;
    final other = b.others.where((l) => l.id == target).firstOrNull;
    if (other != null) {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => SmSavedListScreen(controller: _c, store: _store, memo: b.memo, list: other),
      ));
    }
  }

  Future<void> _loadPast() async {
    try {
      final list = await (widget.ordersLoader ?? loadSupermarketOrdersCached)();
      if (!mounted) return;
      setState(() => _pastOrders = [
            for (final o in list.take(50))
              (at: o.createdAt, status: o.status, lines: smOrderLineRefs(o.items.map((i) => i.raw))),
          ]);
    } catch (e) {
      debugPrint('[Supermarket] SM_PAST_ORDERS_FAILED: $e');
    }
  }

  Future<void> _loadBirthdays() async {
    final bd = await (widget.birthdays ?? loadSmBasketBirthdays)();
    if (!mounted) return;
    final on = smBasketBirthdayMode(today: widget.today ?? smTashkentDate(), own: bd.own, spouse: bd.spouse);
    if (on != _birthday) setState(() => _birthday = on);
  }

  @override
  void dispose() {
    _b?.dispose();
    _scroll.dispose();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  bool get _holidayContext => widget.holiday || _birthday;

  void _openGroup(SmGroup g) {
    final b = _b;
    if (b == null) return;
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => SmBasketGroupScreen(basket: b, group: g, onCheckout: _checkout),
    ));
  }

  /// Саватча → жорий нархлар билан солиштириш (ўзгариш бўлса — мижоз тасдиғи) → сават (миқдор ТЕНГ қилинади) →
  /// мавжуд расмийлаштириш (совға, сана ≤14 кун, ҳамён, бонус).
  Future<void> _checkout(BuildContext from) async {
    final b = _b;
    if (b == null) return;
    await b.flush();
    if (!from.mounted) return;
    final prices = b.basket.id.isEmpty ? const <String, int>{} : await b.memo.load(b.basket.id);
    if (!from.mounted) return;
    final lines = smCompareItems(b.basket.items,
        offers: _c.offers, offersByGroup: _c.offersByGroup, previousPrices: prices);
    Set<int>? selected;
    if (smBasketNeedsConfirm(lines)) {
      selected = await showDialog<Set<int>>(context: from, builder: (_) => SmCompareDialog(controller: _c, lines: lines));
      if (selected == null || selected.isEmpty) return;
    }
    final cart = smBasketCartLines(lines, selected: selected);
    if (cart.isEmpty || !from.mounted) return;
    final origin = _holidayContext ? smOriginHoliday : smOriginWeekly;
    _c.putLines(cart, origin: smOriginWeekly);
    final checkout = (widget.checkout ?? const SmHolidayCheckout()).copyWith(origin: origin);
    final nav = Navigator.of(from);
    if (nav.canPop() && ModalRoute.of(from) is ModalBottomSheetRoute) nav.pop();
    if (!mounted) return;
    if (widget.openCheckout != null) {
      widget.openCheckout!(context, checkout);
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => SmCheckoutScreen(controller: _c, holiday: checkout),
    ));
  }

  Future<void> _openRemind() async {
    final b = _b;
    if (b == null) return;
    final r = await showModalBottomSheet<SmRemind>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SmBasketRemindSheet(initial: b.basket.remind),
    );
    if (r != null) b.setRemind(r);
  }

  void _openOthers() {
    final b = _b;
    if (b == null) return;
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => SmOtherListsScreen(controller: _c, store: _store, memo: b.memo, excludeId: b.basket.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final b = _b;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr(smBasketTitleKey(birthday: _birthday)),
            key: const ValueKey('smb_title'), maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          if (b != null && b.loaded)
            ListenableBuilder(
              listenable: b,
              builder: (context, _) => IconButton(
                key: const ValueKey('smb_remind'),
                tooltip: context.tr('smb_remind'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _openRemind,
                icon: Icon(b.basket.remind.enabled ? Icons.notifications_active_outlined : Icons.notifications_none_rounded),
              ),
            ),
        ],
      ),
      bottomNavigationBar: b == null || !b.loaded ? null : SmBasketBar(basket: b, onCheckout: _checkout),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          if (b == null || (_c.loading && _c.taxonomy.categories.isEmpty)) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListenableBuilder(listenable: b, builder: (context, _) => _body(context, b));
        },
      ),
    );
  }

  Widget _body(BuildContext context, SmBasketController b) {
    final c = context.ava;
    if (b.loadError || (_c.loadErrorKey != null && _c.taxonomy.categories.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(context.tr('sm_err_load'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('smb_retry'),
              onPressed: () async {
                if (_c.taxonomy.categories.isEmpty) await _c.load();
                await b.load();
              },
              child: Text(context.tr('err_retry')),
            ),
          ]),
        ),
      );
    }
    if (!b.loaded) return const Center(child: CircularProgressIndicator());
    final lang = context.contentLang;
    final cats = smBasketCategories(_c.taxonomy, _c.offersByGroup);
    if (_cat.isNotEmpty && !cats.any((x) => x.id == _cat)) _cat = '';
    final groups = smBasketGroups(_c.taxonomy, _c.offersByGroup, categoryId: _cat);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final showPreorder = _birthday && ServiceConfigHolder.isOpenable(kRestaurantsModuleId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Эга расми (2026-11-28): туғилган кун ҳолати / оддий ҳолат.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              smBasketImage(birthday: _birthday),
              key: ValueKey(_birthday ? 'smb_header_birthday' : 'smb_header_weekly'),
              height: 76,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(height: 76),
            ),
          ),
        ),
        // Эга 2026-11-28: яқинлашаётган байрам мавзуси («Севишганлар куни: гуллар, шоколад, совғалар»).
        if (holidayThemeNow(HolidayCatalogCache.cached?.occasions ?? const [], widget.today ?? smTashkentDate()) case final o?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              '${o.name(lang)}: ${o.themeText(lang)}',
              key: const ValueKey('smb_holiday_theme'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        _pastRow(context, b, lang, scale),
        SizedBox(
          height: 40 + 16 * scale,
          child: ListView(
            key: const ValueKey('smb_chips'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            children: [
              _chip(context, '', context.tr('smb_all'), null),
              for (final cat in cats) _chip(context, cat.id, cat.name(lang), smCategoryIcon(cat.icon)),
            ],
          ),
        ),
        if (!_c.access.allowed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(context.tr('sm_not_available_here'),
                key: const ValueKey('smb_not_available'), style: TextStyle(fontSize: 14, color: c.danger)),
          ),
        if (b.saveError)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(context.tr('smb_save_error'),
                key: const ValueKey('smb_save_error'), style: TextStyle(fontSize: 14, color: c.danger)),
          ),
        if (showPreorder || b.others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Wrap(spacing: 4, children: [
              if (showPreorder)
                TextButton.icon(
                  key: const ValueKey('smb_preorder'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => Navigator.of(context)
                      .push<void>(MaterialPageRoute(builder: (_) => const RestaurantsListScreen(preorderOnly: true))),
                  icon: const Icon(Icons.cake_rounded),
                  label: Text(context.tr('hb_preorder_title')),
                ),
              if (b.others.isNotEmpty)
                TextButton(
                  key: const ValueKey('smb_others'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _openOthers,
                  child: Text(context.tr('smb_other_lists').replaceAll('{n}', '${b.others.length}')),
                ),
            ]),
          ),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(context.tr('smb_group_empty'),
                        key: const ValueKey('smb_no_groups'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  ),
                )
              : GridView.builder(
                  key: const PageStorageKey('smb_grid'),
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 112 + 62 * scale,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, i) => _GroupTile(
                    group: groups[i],
                    lang: lang,
                    offers: _c.offersByGroup[groups[i].id],
                    badge: smBasketGroupBadge(b.basket, groups[i], _c.offers),
                    onTap: () => _openGroup(groups[i]),
                  ),
                ),
        ),
      ],
    );
  }

  /// «Олдин олганларингиз»: ≤12 плитка (расм, ном, охирги миқдор, жорий нарх); бир босишда — охирги миқдор саватчага.
  Widget _pastRow(BuildContext context, SmBasketController b, String lang, double scale) {
    final picks = smPastPurchases(_pastOrders,
        offers: _c.offers, offersByGroup: _c.offersByGroup, now: widget.today ?? DateTime.now());
    if (picks.isEmpty) return const SizedBox.shrink();
    final c = context.ava;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(context.tr('smb_past_title'),
              key: const ValueKey('smb_past_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
        ),
        SizedBox(
          height: 80 + 54 * scale,
          child: ListView.separated(
            key: const ValueKey('smb_past'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: picks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = picks[i];
              final o = p.offer;
              final g = _c.taxonomy.group(o.groupId);
              final name = o.varietyName(lang).isNotEmpty ? o.varietyName(lang) : (g?.name(lang) ?? o.name);
              return SizedBox(
                width: 132,
                child: Material(
                  key: ValueKey('smb_past_${o.id}'),
                  color: c.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => b.setOffer(o, smPastAddQty(o, b.qtyOf(o.id), p.qtyMilli)),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SmThumb(url: o.imageUrl, size: 56),
                          const SizedBox(height: 4),
                          Text(name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
                          Text(
                              context
                                  .tr('smb_past_last')
                                  .replaceAll('{qty}', '${smFormatQty(p.qtyMilli)} ${smUnitLabel(context, o.unit)}'.trim()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: c.ink2)),
                          Text(smPricePerUnit(context, o.price, o.unit),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.ink)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String id, String label, IconData? icon) {
    final selected = _cat == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('smb_chip_${id.isEmpty ? 'all' : id}'),
        selected: selected,
        avatar: icon == null ? null : Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 15)),
        onSelected: (_) {
          if (selected) return;
          setState(() => _cat = id);
          if (_scroll.hasClients) _scroll.jumpTo(0);
        },
      ),
    );
  }
}

/// Нишон матни: «2 кг» / «3 хил».
String smBasketBadgeText(BuildContext context, ({int qtyMilli, String unit, int lines}) b) => b.unit.isEmpty
    ? context.tr('smb_mixed_badge').replaceAll('{n}', '${b.lines}')
    : '${smFormatQty(b.qtyMilli)} ${smUnitLabel(context, b.unit)}'.trim();

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.lang, required this.offers, required this.badge, required this.onTap});

  final SmGroup group;
  final String lang;
  final List<SmOffer>? offers;
  final ({int qtyMilli, String unit, int lines})? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final img = smBasketGroupImage(offers);
    final from = smCheapestActivePrice(offers ?? const []);
    final bd = badge;
    return Material(
      key: ValueKey('smb_group_${group.id}'),
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: bd == null ? c.line : c.brand, width: bd == null ? 1 : 2),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  img.isEmpty
                      ? ColoredBox(color: c.surface2, child: Icon(Icons.local_grocery_store_outlined, color: c.ink3, size: 36))
                      : Image.network(img,
                          fit: BoxFit.cover,
                          cacheWidth: 300,
                          errorBuilder: (_, __, ___) =>
                              ColoredBox(color: c.surface2, child: Icon(Icons.local_grocery_store_outlined, color: c.ink3))),
                  if (bd != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      left: 6,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          key: ValueKey('smb_badge_${group.id}'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(999)),
                          child: Text(smBasketBadgeText(context, bd),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.brandInk)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(group.name(lang),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, height: 1.2, fontWeight: FontWeight.w600, color: c.ink)),
                  if (from != null)
                    Text(context.tr('sm_price_from').replaceAll('{price}', smPricePerUnit(context, from, group.unit)),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.2, color: c.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Гуруҳ: шу гуруҳнинг сотувдаги БАРЧА таклифлари (энг арзони олдин), ҳар бирида «− / +» қадам бўйича.
/// Танланган таклиф ва миқдор — саватчага. «Орқага» — тўрга (жойи сақланади).
class SmBasketGroupScreen extends StatelessWidget {
  const SmBasketGroupScreen({super.key, required this.basket, required this.group, required this.onCheckout});

  final SmBasketController basket;
  final SmGroup group;
  final Future<void> Function(BuildContext from) onCheckout;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    final sm = basket.supermarket;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(group.name(lang), maxLines: 2, overflow: TextOverflow.ellipsis)),
      bottomNavigationBar: SmBasketBar(basket: basket, onCheckout: onCheckout),
      body: ListenableBuilder(
        listenable: Listenable.merge([basket, sm]),
        builder: (context, _) {
          final offers = smBasketGroupOffers(sm.offersByGroup[group.id]);
          if (offers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.tr('smb_group_empty'),
                    key: const ValueKey('smb_offers_empty'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              ),
            );
          }
          return ListView.separated(
            key: const ValueKey('smb_offers'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: offers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _OfferCard(offer: offers[i], lang: lang, basket: basket),
          );
        },
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.lang, required this.basket});

  final SmOffer offer;
  final String lang;
  final SmBasketController basket;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = offer;
    final qty = basket.qtyOf(o.id);
    final variety = o.varietyName(lang);
    final quality = o.qualityName(lang);
    final unitPrice = o.unitPriceOfPack;
    final details = [
      if (quality.isNotEmpty) quality,
      if (o.packLabel.isNotEmpty) o.packLabel,
      if (unitPrice != null) smPricePerUnit(context, unitPrice, o.packUnit),
    ].join(' · ');
    return Container(
      key: ValueKey('smb_offer_${o.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: qty > 0 ? c.brand : c.line, width: qty > 0 ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SmThumb(url: o.imageUrl, size: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(variety.isNotEmpty ? variety : o.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                    if (o.name.isNotEmpty && o.name != variety)
                      Text(o.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.ink2)),
                    if (details.isNotEmpty) Text(details, style: TextStyle(fontSize: 14, color: c.ink2)),
                    const SizedBox(height: 2),
                    Text(smPricePerUnit(context, o.price, o.unit),
                        key: ValueKey('smb_offer_price_${o.id}'),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: SmQtyStepper(
              key: ValueKey('smb_qty_${o.id}'),
              qtyMilli: qty,
              stepMilli: o.stepMilli,
              maxMilli: o.maxQtyMilli,
              allowZero: true,
              unitLabel: smUnitLabel(context, o.unit),
              onChanged: (v) => basket.setOffer(o, v),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ихчам пастки панел: «🧺 7 · 125 000 сўм ›» — ҳар ўзгаришда дарҳол; босилса — ярим экран рўйхат.
class SmBasketBar extends StatelessWidget {
  const SmBasketBar({super.key, required this.basket, required this.onCheckout});

  final SmBasketController basket;
  final Future<void> Function(BuildContext from) onCheckout;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return ListenableBuilder(
      listenable: Listenable.merge([basket, basket.supermarket]),
      builder: (context, _) {
        final t = basket.totals;
        return Material(
          color: c.surface,
          child: SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Material(
                color: t.count == 0 ? c.surface2 : c.brand,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  key: const ValueKey('smb_bar'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => showSmBasketSheet(context, basket: basket, onCheckout: onCheckout),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.shopping_basket_rounded, color: t.count == 0 ? c.ink2 : c.brandInk),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${t.count} · ${formatMoney(t.total)}',
                              key: const ValueKey('smb_bar_text'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.count == 0 ? c.ink : c.brandInk),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: t.count == 0 ? c.ink2 : c.brandInk),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showSmBasketSheet(
  BuildContext context, {
  required SmBasketController basket,
  required Future<void> Function(BuildContext from) onCheckout,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      builder: (_) => SmBasketSheet(basket: basket, onCheckout: onCheckout),
    );

/// Ярим экран: танланган қаторлар (ном, миқдор − / +, олиб ташлаш, сатр нархи), жами, «Расмийлаштириш».
class SmBasketSheet extends StatelessWidget {
  const SmBasketSheet({super.key, required this.basket, required this.onCheckout});

  final SmBasketController basket;
  final Future<void> Function(BuildContext from) onCheckout;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    final sm = basket.supermarket;
    return ListenableBuilder(
      listenable: Listenable.merge([basket, sm]),
      builder: (context, _) {
        final items = basket.basket.items;
        final lines = smCompareItems(items, offers: sm.offers, offersByGroup: sm.offersByGroup);
        final t = basket.totals;
        // Ярим экран (эга 2026-11-28): баландлик қатъий, қаторлар ичида айланади.
        return SizedBox(
          key: const ValueKey('smb_sheet'),
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(context.tr('smb_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
            ),
            Expanded(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.tr('smb_empty'), key: const ValueKey('smb_sheet_empty'), style: const TextStyle(fontSize: 15)),
                    )
                  // ≤ kSmListItemsMax қатор — ҳаммаси бирданига (ихчам, ярим экранда айланади).
                  : SingleChildScrollView(
                      key: const ValueKey('smb_sheet_lines'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (var i = 0; i < items.length; i++) _sheetLine(context, i, items[i], lines[i], lang)],
                      ),
                    ),
            ),
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SmSumRow(label: context.tr('sm_goods_total'), amount: t.total, bold: true, valueKey: const ValueKey('smb_sheet_total')),
                  Text(context.tr('smb_price_note'), style: TextStyle(fontSize: 13, color: c.ink2)),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const ValueKey('smb_checkout'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: t.total <= 0 ? null : () => onCheckout(context),
                    child: Text(context.tr('smb_checkout'), style: const TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  Widget _sheetLine(BuildContext context, int i, SmListItem item, SmCompareLine line, String lang) {
    final c = context.ava;
    final sm = basket.supermarket;
    final g = sm.taxonomy.group(item.groupId);
    final o = sm.offers[item.offerId] ?? line.offer;
    final variety = o == null ? '' : (o.varietyName(lang).isNotEmpty ? o.varietyName(lang) : o.name);
    final step = o?.stepMilli ?? g?.stepMilli ?? 1000;
    return Padding(
      key: ValueKey('smb_line_$i'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g?.name(lang) ?? item.groupId,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                  if (variety.isNotEmpty)
                    Text(variety, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.ink2)),
                  if (!line.addable)
                    Text(context.tr('smb_unavailable'),
                        key: ValueKey('smb_line_unavailable_$i'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.danger)),
                ]),
              ),
              IconButton(
                key: ValueKey('smb_line_remove_$i'),
                tooltip: context.tr('sm_remove'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => basket.removeAt(i),
                icon: Icon(Icons.delete_outline_rounded, color: c.ink2),
              ),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              SmQtyStepper(
                key: ValueKey('smb_line_qty_$i'),
                qtyMilli: item.qtyMilli,
                stepMilli: step,
                maxMilli: o?.maxQtyMilli,
                allowZero: true,
                unitLabel: smUnitLabel(context, o?.unit ?? g?.unit ?? ''),
                onChanged: (v) => basket.setQtyAt(i, v),
              ),
              if (line.addable)
                Text(formatMoney(smLineTotal(line.offer!.price, line.qtyMilli)),
                    key: ValueKey('smb_line_total_$i'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ҳафталик эслатма (аввалги «Ҳафталик сават» хатти-ҳаракати сақланди: ҳафта куни + вақт; сервер эслатади,
/// АВТОМАТИК БУЮРТМА ЙЎҚ).
class SmBasketRemindSheet extends StatefulWidget {
  const SmBasketRemindSheet({super.key, required this.initial, this.pickTime});

  final SmRemind initial;
  final Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initial)? pickTime;

  @override
  State<SmBasketRemindSheet> createState() => _SmBasketRemindSheetState();
}

class _SmBasketRemindSheetState extends State<SmBasketRemindSheet> {
  late SmRemind _r = widget.initial;

  Future<void> _pickTime() async {
    final init = TimeOfDay(hour: _r.minute ~/ 60, minute: _r.minute % 60);
    final t = await (widget.pickTime?.call(context, init) ?? showTimePicker(context: context, initialTime: init));
    if (t == null || !mounted) return;
    setState(() => _r = SmRemind(enabled: _r.enabled, weekday: _r.weekday, minute: t.hour * 60 + t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        SwitchListTile(
          key: const ValueKey('smb_remind_toggle'),
          contentPadding: EdgeInsets.zero,
          value: _r.enabled,
          title: Text(context.tr('smb_remind'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
          onChanged: (v) => setState(() => _r = SmRemind(enabled: v, weekday: _r.weekday, minute: _r.minute)),
        ),
        Text(context.tr('sm_remind_note'), style: TextStyle(fontSize: 14, color: c.ink2)),
        if (_r.enabled) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: const ValueKey('smb_remind_weekday'),
            initialValue: _r.weekday,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('sm_remind_day'), border: const OutlineInputBorder()),
            items: [for (var d = 1; d <= 7; d++) DropdownMenuItem(value: d, child: Text(context.tr(smWeekdayKey(d))))],
            onChanged: (d) => d == null ? null : setState(() => _r = SmRemind(enabled: true, weekday: d, minute: _r.minute)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('smb_remind_time'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _pickTime,
            icon: const Icon(Icons.schedule_rounded),
            label: Text('${context.tr('sm_remind_time')}: ${smHhMmOf(_r.minute)}', style: const TextStyle(fontSize: 16)),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('smb_remind_save'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: smRemindProblems(_r).isEmpty ? () => Navigator.of(context).pop(_r) : null,
          child: Text(context.tr('save'), style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}

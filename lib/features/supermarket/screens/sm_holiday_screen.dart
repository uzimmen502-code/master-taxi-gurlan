import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../restaurants/domain/restaurants_access.dart' show kRestaurantsModuleId;
import '../../restaurants/screens/restaurants_list_screen.dart';
import '../../markets/open_market.dart';
import '../../home/home_module_gate.dart';
import '../data/holiday_repository.dart';
import '../data/sm_lists_repository.dart';
import '../data/supermarket_repository.dart';
import '../domain/sm_access.dart' show smServerMessage;
import '../domain/sm_cart.dart';
import '../domain/sm_holiday.dart';
import '../domain/sm_list.dart';
import '../domain/sm_qty.dart';
import '../supermarket_controller.dart';
import '../widgets/sm_compare_dialog.dart';
import '../widgets/sm_widgets.dart';
import 'sm_checkout_screen.dart';
import 'sm_weekly_screen.dart' show SmListEditorScreen;
import 'supermarket_home_screen.dart' show openSupermarketWith, smOpenCart;

/// «Туғилган кун ва байрам саватчаси»ни очиш (эга 2026-11-26).
/// [occasionId] — шу байрам дарҳол очилади (push); [birthday] — туғилган кун байрами (қариндошдан);
/// [gift] — қабул қилувчи олдиндан тўлдирилади (қариндош телефони бўлса).
Future<void> openHolidayBasket(
  NavigatorState nav, {
  String? occasionId,
  bool birthday = false,
  SmHolidayCheckout? gift,
  bool guestsHint = false,
}) =>
    nav.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: kSmHomeRouteName),
      builder: (_) =>
          SmHolidayScreen(initialOccasionId: occasionId, openBirthday: birthday, gift: gift, guestsHint: guestsHint),
    ));

/// Байрам мақсади бозор бўлса (Қурбон ҳайит → Мол бозори, эга 2026-11-27) — мавжуд [openMarket] (модул дарвозаси
/// шу ерда). [replace] — push'дан автоматик очилганда байрамлар рўйхати орқада қолмасин.
Future<void> openHolidayMarketTarget(BuildContext context, HolidayTarget t, {bool replace = false}) => openMarket(
      context,
      t.market,
      initialCategory: t.initialCategory,
      push: replace ? (s) => Navigator.of(context).pushReplacement<void, void>(MaterialPageRoute(builder: (_) => s)) : null,
    );

/// Байрам мақсади саватча ЭМАС (бозор / ресторанда олдиндан буюртма / супермаркет) — мавжуд экранлар, ўз модул
/// дарвозалари билан. Саватча тури — `false` (чақирувчи байрам экранини очади).
Future<bool> openHolidayNonBasketTarget(BuildContext context, HolidayTarget t, {bool replace = false}) async {
  final nav = Navigator.of(context);
  Future<void> go(Widget s) => replace
      ? nav.pushReplacement<void, void>(MaterialPageRoute(builder: (_) => s))
      : nav.push<void>(MaterialPageRoute(builder: (_) => s));
  switch (t.type) {
    case kTargetMarket:
      await openHolidayMarketTarget(context, t, replace: replace);
      return true;
    case kTargetRestaurantsPreorder:
      if (!ServiceConfigHolder.isOpenable(kRestaurantsModuleId)) {
        HomeModuleGate.onTapBlocked(context, kRestaurantsModuleId);
        return true;
      }
      await go(const RestaurantsListScreen(preorderOnly: true));
      return true;
    case kTargetSupermarket:
      // Супермаркет дарвозаси байрам экранига киришда текширилган.
      await openSupermarketWith(nav);
      return true;
    default:
      return false;
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 1-экран: байрамлар рўйхати (сервер `getHolidayCatalog` — кўриниш серверда ҳал қилинади).
class SmHolidayScreen extends StatefulWidget {
  const SmHolidayScreen({
    super.key,
    this.controller,
    this.api,
    this.listsStore,
    this.initialOccasionId,
    this.openBirthday = false,
    this.gift,
    this.today,
    this.guestsHint = false,
    this.openTarget,
  });

  /// Тест учун; бўлмаса — янги (Firebase).
  final SupermarketController? controller;
  final HolidayApi? api;
  final SmListsStore? listsStore;
  final String? initialOccasionId;
  final bool openBirthday;
  final SmHolidayCheckout? gift;
  final DateTime? today;

  /// Ўз туғилган куни «меҳмонлар учун саватча» эслатмасидан (эга 2026-11-27) — меҳмонлар сони изоҳи.
  final bool guestsHint;

  /// Тест учун; бўлмаса — [openHolidayNonBasketTarget] (саватча тури — `false`).
  final Future<bool> Function(BuildContext context, HolidayTarget target, {bool replace})? openTarget;

  @override
  State<SmHolidayScreen> createState() => _SmHolidayScreenState();
}

class _SmHolidayScreenState extends State<SmHolidayScreen> {
  late final SupermarketController _c = widget.controller ?? SupermarketController();
  late final HolidayApi _api = widget.api ?? FirebaseHolidayApi();
  HolidayCatalog? _catalog;
  bool _error = false;
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      if (widget.controller == null) await _c.load();
      final cat = await _api.loadCatalog();
      if (!mounted) return;
      setState(() => _catalog = cat);
      _maybeAutoOpen(cat);
    } catch (e) {
      debugPrint('[Holiday] HOLIDAY_LOAD_FAILED: $e');
      if (mounted) setState(() => _error = true);
    }
  }

  void _maybeAutoOpen(HolidayCatalog cat) {
    if (_autoOpened) return;
    HolidayOccasion? target;
    final id = widget.initialOccasionId ?? '';
    if (id.isNotEmpty) target = cat.occasions.where((o) => o.id == id).firstOrNull;
    if (target == null && widget.openBirthday) target = cat.occasions.where((o) => o.isBirthday).firstOrNull;
    if (target == null) return;
    _autoOpened = true;
    final t = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(t, auto: true);
    });
  }

  void _open(HolidayOccasion o, {bool auto = false}) {
    final t = o.target;
    if (t != null && !t.isBasket) {
      (widget.openTarget ?? openHolidayNonBasketTarget)(context, t, replace: auto);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SmOccasionScreen(
        controller: _c,
        api: _api,
        occasion: o,
        baskets: holidayBasketsFor(_catalog?.baskets ?? const [], o.id),
        listsStore: widget.listsStore,
        // Қариндош совғаси — туғилган кунда; push «совға» режими — шу push очган байрамда.
        gift: o.isBirthday || o.id == widget.initialOccasionId ? widget.gift : null,
        guestsHint: (auto && widget.guestsHint) || t?.mode == kTargetModeGuests,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    final cat = _catalog;
    final today = widget.today ?? smTashkentDate();
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('hb_title')),
        actions: [SmCartAction(controller: _c, onTap: () => smOpenCart(context, _c))],
      ),
      body: _error
          ? _Retry(onRetry: _load)
          : cat == null
              ? const Center(child: CircularProgressIndicator())
              : cat.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(context.tr('hb_empty'),
                            key: const ValueKey('hb_empty'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        Text(context.tr('hb_intro'), style: TextStyle(fontSize: 16, color: c.ink)),
                        const SizedBox(height: 12),
                        for (final o in cat.occasions) ...[
                          _OccasionCard(occasion: o, lang: lang, today: today, onTap: () => _open(o)),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
    );
  }
}

class _OccasionCard extends StatelessWidget {
  const _OccasionCard({required this.occasion, required this.lang, required this.today, required this.onTap});

  final HolidayOccasion occasion;
  final String lang;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final next = nextOccasionDate(occasion, today);
    final sub = occasion.isBirthday
        ? context.tr('hb_birthday_sub')
        : next == null
            ? ''
            : context.tr('hb_next_date').replaceAll('{date}', '${_two(next.day)}.${_two(next.month)}.${next.year}');
    return Material(
      key: ValueKey('hb_occasion_${occasion.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(occasion.isBirthday ? Icons.cake_outlined : Icons.celebration_outlined, color: c.brandText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(occasion.name(lang),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(sub, style: TextStyle(fontSize: 14, color: c.ink2)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2-экран: байрам — тайёр саватчалар (3 даража) + ўз саватчаларим; туғилган кунда — торт/таомга олдиндан буюртма.
class SmOccasionScreen extends StatefulWidget {
  const SmOccasionScreen({
    super.key,
    required this.controller,
    required this.api,
    required this.occasion,
    required this.baskets,
    this.listsStore,
    this.memo,
    this.gift,
    this.openRestaurants,
    this.guestsHint = false,
  });

  /// «Меҳмонлар учун саватча» эслатмасидан — тепада меҳмонлар сони изоҳи.
  final bool guestsHint;

  final SupermarketController controller;
  final HolidayApi api;
  final HolidayOccasion occasion;
  final List<HolidayBasket> baskets;
  final SmListsStore? listsStore;
  final SmListPriceMemo? memo;
  final SmHolidayCheckout? gift;

  /// Тест учун; бўлмаса — ресторанлар рўйхати (фақат олдиндан буюртма оладиганлар).
  final void Function(BuildContext context)? openRestaurants;

  @override
  State<SmOccasionScreen> createState() => _SmOccasionScreenState();
}

class _SmOccasionScreenState extends State<SmOccasionScreen> {
  late final SmListsStore _store = widget.listsStore ?? FirestoreSmListsStore();
  late final SmListPriceMemo _memo = widget.memo ?? SmListPriceMemo();
  List<SmList>? _own;
  int _allListsCount = 0;

  SmHolidayCheckout _checkout({String basketId = ''}) => SmHolidayCheckout(
        occasionId: widget.occasion.id,
        basketId: basketId,
        asGift: widget.gift?.asGift ?? false,
        recipientName: widget.gift?.recipientName ?? '',
        recipientPhone: widget.gift?.recipientPhone ?? '',
      );

  @override
  void initState() {
    super.initState();
    _loadOwn();
  }

  Future<void> _loadOwn() async {
    List<SmList> lists = const [];
    try {
      lists = await _store.load();
    } catch (e) {
      debugPrint('[Holiday] HOLIDAY_OWN_LISTS_FAILED: $e');
    }
    if (!mounted) return;
    setState(() {
      _allListsCount = lists.length;
      _own = [for (final l in lists) if (l.occasionId == widget.occasion.id) l];
    });
  }

  Future<void> _newOwn() async {
    final lang = context.contentLang;
    final saved = await Navigator.of(context).push<SmList>(MaterialPageRoute(
      builder: (_) => SmListEditorScreen(
        controller: widget.controller,
        store: _store,
        memo: _memo,
        existingCount: _allListsCount,
        initial: SmList(id: '', name: widget.occasion.name(lang), occasionId: widget.occasion.id),
      ),
    ));
    if (saved != null && mounted) await _loadOwn();
  }

  Future<void> _editOwn(SmList l) async {
    final saved = await Navigator.of(context).push<SmList>(MaterialPageRoute(
      builder: (_) => SmListEditorScreen(controller: widget.controller, store: _store, memo: _memo, initial: l),
    ));
    if (saved != null && mounted) await _loadOwn();
  }

  /// Ўз саватчаси → жорий нархлар билан солиштириш → саватга → расмийлаштириш (байрам режими).
  Future<void> _ownToCheckout(SmList l) async {
    final prices = await _memo.load(l.id);
    if (!mounted) return;
    final n = await smCompareAndAddToCart(context,
        controller: widget.controller, items: l.items, previousPrices: prices, origin: smOriginCatalog);
    if (!mounted || n == 0) return;
    await _memo.save(l.id, smPricesOf(l.items, widget.controller.offers));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SmCheckoutScreen(controller: widget.controller, holiday: _checkout()),
    ));
  }

  void _openRestaurants() {
    if (widget.openRestaurants != null) {
      widget.openRestaurants!(context);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RestaurantsListScreen(preorderOnly: true)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    final b = widget.baskets;
    final own = _own ?? const <SmList>[];
    final showRestaurants = widget.occasion.isBirthday &&
        (widget.openRestaurants != null || ServiceConfigHolder.isOpenable(kRestaurantsModuleId));
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(widget.occasion.name(lang))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (widget.guestsHint) ...[
            Container(
              key: const ValueKey('hb_guests_hint'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.groups_rounded, color: c.brandText),
                const SizedBox(width: 8),
                Expanded(child: Text(context.tr('hb_guests_hint'), style: TextStyle(fontSize: 15, color: c.ink))),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          Text(context.tr('hb_ready_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 8),
          if (b.isEmpty)
            Text(context.tr('hb_no_baskets'), key: const ValueKey('hb_no_baskets'), style: const TextStyle(fontSize: 15)),
          for (final basket in b) ...[
            _BasketCard(
              basket: basket,
              lang: lang,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SmHolidayBasketScreen(
                  controller: widget.controller,
                  api: widget.api,
                  basket: basket,
                  checkout: _checkout(basketId: basket.id),
                ),
              )),
            ),
            const SizedBox(height: 10),
          ],
          if (showRestaurants) ...[
            const SizedBox(height: 4),
            Material(
              key: const ValueKey('hb_preorder_link'),
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openRestaurants,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(Icons.cake_rounded, color: c.brandText, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.tr('hb_preorder_title'),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                        Text(context.tr('hb_preorder_caption'), style: TextStyle(fontSize: 14, color: c.ink2)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.ink3),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          Text(context.tr('hb_own_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 8),
          for (final l in own) ...[
            Material(
              key: ValueKey('hb_own_${l.id}'),
              color: c.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                    Text(context.tr('sm_weekly_items_count').replaceAll('{n}', '${l.items.length}'),
                        style: TextStyle(fontSize: 14, color: c.ink2)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton(
                        key: ValueKey('hb_own_order_${l.id}'),
                        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                        onPressed: l.items.isEmpty ? null : () => _ownToCheckout(l),
                        child: Text(context.tr('hb_own_order')),
                      ),
                      OutlinedButton(
                        key: ValueKey('hb_own_edit_${l.id}'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                        onPressed: () => _editOwn(l),
                        child: Text(context.tr('hb_own_edit')),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            key: const ValueKey('hb_own_new'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _own == null || _allListsCount >= kSmMaxLists ? null : _newOwn,
            icon: const Icon(Icons.add_rounded),
            label: Text(context.tr('hb_own_new'), style: const TextStyle(fontSize: 16)),
          ),
          if (_allListsCount >= kSmMaxLists)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.tr('sm_err_list_limit').replaceAll('{n}', '$kSmMaxLists'),
                  style: TextStyle(fontSize: 14, color: c.ink2)),
            ),
        ],
      ),
    );
  }
}

class _BasketCard extends StatelessWidget {
  const _BasketCard({required this.basket, required this.lang, required this.onTap});

  final HolidayBasket basket;
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final name = basket.name(lang);
    return Material(
      key: ValueKey('hb_basket_${basket.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.shopping_basket_outlined, color: c.brandText, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isNotEmpty ? name : context.tr('hb_tier_${basket.tier}'),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                    Text(
                      [
                        context.tr('hb_tier_${basket.tier}'),
                        context.tr('sm_weekly_items_count').replaceAll('{n}', '${basket.itemsCount}'),
                        if (basket.baseGuests > 0) context.tr('hb_guests_n').replaceAll('{n}', '${basket.baseGuests}'),
                      ].join(' · '),
                      style: TextStyle(fontSize: 14, color: c.ink2),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// 3-экран: тайёр саватча — меҳмонлар/бюджет (ихтиёрий), тизим ўзгаришлари (мижоз розилиги), саватга қўшиш.
/// Нарх ва алмаштириш — СЕРВЕР (`buildHolidayBasket`); клиент фақат кўрсатади.
class SmHolidayBasketScreen extends StatefulWidget {
  const SmHolidayBasketScreen({
    super.key,
    required this.controller,
    required this.api,
    required this.basket,
    required this.checkout,
    @visibleForTesting this.openCheckout,
  });

  final SupermarketController controller;
  final HolidayApi api;
  final HolidayBasket basket;
  final SmHolidayCheckout checkout;
  final void Function(BuildContext context)? openCheckout;

  @override
  State<SmHolidayBasketScreen> createState() => _SmHolidayBasketScreenState();
}

class _SmHolidayBasketScreenState extends State<SmHolidayBasketScreen> {
  final _guests = TextEditingController();
  final _budget = TextEditingController();
  HolidayBuildResult? _result;
  bool _loading = false;
  bool _approved = false;
  String? _errorKey;
  Map<String, String> _errorMessages = const {};

  SupermarketController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void dispose() {
    _guests.dispose();
    _budget.dispose();
    super.dispose();
  }

  String? get _guestsError => holidayParseGuests(_guests.text).error;
  String? get _budgetError => holidayParseBudget(_budget.text).error;

  Future<void> _build() async {
    if (_guestsError != null || _budgetError != null) {
      setState(() {});
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _errorKey = null;
      _approved = false;
    });
    try {
      final r = await widget.api.build(
        basketId: widget.basket.id,
        guests: holidayParseGuests(_guests.text).value,
        budget: holidayParseBudget(_budget.text).value,
      );
      if (mounted) setState(() => _result = r);
    } on SmCallError catch (e) {
      if (mounted) {
        setState(() {
          _errorKey = e.key;
          _errorMessages = e.messages;
        });
      }
    } catch (e) {
      debugPrint('[Holiday] HOLIDAY_BUILD_FAILED: $e');
      if (mounted) setState(() => _errorKey = 'sm_err_generic');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toCart() {
    final r = _result;
    if (r == null || r.lines.isEmpty || (r.needsApproval && !_approved)) return;
    _c.addLines([for (final l in r.lines) SmCartLine(l.productId, l.qtyMilli)]);
    if (widget.openCheckout != null) {
      widget.openCheckout!(context);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SmCheckoutScreen(controller: _c, holiday: widget.checkout),
    ));
  }

  String _groupName(String groupId, String lang) => _c.taxonomy.group(groupId)?.name(lang) ?? groupId;

  String _offerName(String offerId, String lang) {
    if (offerId.isEmpty) return '';
    final o = _c.offers[offerId];
    if (o == null) return offerId;
    final v = o.varietyName(lang);
    return v.isNotEmpty ? v : o.name;
  }

  String _changeText(BuildContext context, HolidayChange ch, String lang) => context
      .tr(holidayChangeKey(ch))
      .replaceAll('{group}', _groupName(ch.groupId, lang))
      .replaceAll('{from}', _offerName(ch.fromOfferId, lang))
      .replaceAll('{to}', _offerName(ch.toOfferId, lang))
      .replaceAll('{saving}', formatMoney(ch.saving));

  String _lineTitle(HolidayLine l, String lang) {
    final o = _offerName(l.productId, lang);
    return o.isNotEmpty && o != l.productId ? o : l.name;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    final r = _result;
    final canAdd = !_loading && r != null && r.lines.isNotEmpty && (!r.needsApproval || _approved);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(widget.basket.name(lang).isNotEmpty ? widget.basket.name(lang) : context.tr('hb_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(context.tr('hb_options_hint'), style: TextStyle(fontSize: 15, color: c.ink2)),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('hb_guests'),
            controller: _guests,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: context.tr('hb_guests'),
              hintText: widget.basket.baseGuests > 0 ? '${widget.basket.baseGuests}' : null,
              errorText: _guestsError == null ? null : context.tr(_guestsError!),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('hb_budget'),
            controller: _budget,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: context.tr('hb_budget'),
              suffixText: kCurrencySum,
              errorText: _budgetError == null ? null : context.tr(_budgetError!),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('hb_recalc'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _loading || _guestsError != null || _budgetError != null ? null : _build,
            child: Text(context.tr('hb_recalc'), style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 12),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          if (_errorKey != null)
            Text(
              smServerMessage(_errorMessages, lang).isNotEmpty ? smServerMessage(_errorMessages, lang) : context.tr(_errorKey!),
              key: const ValueKey('hb_error'),
              style: TextStyle(fontSize: 15, color: c.danger),
            ),
          if (r != null && !_loading) ...[
            if (r.changes.isNotEmpty)
              HolidayChangesPanel(
                texts: [for (final ch in r.changes) _changeText(context, ch, lang)],
                approved: _approved,
                onApproved: (v) => setState(() => _approved = v),
              ),
            if (r.withinBudget == false) ...[
              const SizedBox(height: 8),
              Text(context.tr('hb_over_budget'),
                  key: const ValueKey('hb_over_budget'), style: TextStyle(fontSize: 15, color: c.danger)),
            ],
            const SizedBox(height: 8),
            if (r.lines.isEmpty)
              Text(context.tr('hb_nothing'), key: const ValueKey('hb_nothing'), style: const TextStyle(fontSize: 15)),
            for (final l in r.lines)
              Padding(
                key: ValueKey('hb_line_${l.productId}'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_groupName(l.groupId, lang),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                          Text(
                            '${_lineTitle(l, lang)} · ${smFormatQty(l.qtyMilli)} ${smUnitLabel(context, l.unit)}',
                            style: TextStyle(fontSize: 14, color: c.ink2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(formatMoney(l.total), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
                  ],
                ),
              ),
            const Divider(),
            SmSumRow(label: context.tr('sm_goods_total'), amount: r.goods, valueKey: const ValueKey('hb_goods')),
            SmSumRow(label: context.tr('sm_fee'), amount: r.fee),
            SmSumRow(label: context.tr('hb_total'), amount: r.total, bold: true, valueKey: const ValueKey('hb_total')),
            const SizedBox(height: 4),
            Text(context.tr('hb_price_note'), style: TextStyle(fontSize: 13, color: c.ink2)),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('hb_to_cart'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: canAdd ? _toCart : null,
              child: Text(context.tr('hb_to_cart'), style: const TextStyle(fontSize: 16)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Тизим қилган ўзгаришлар рўйхати + «Розиман» (розиликсиз саватга қўшилмайди).
class HolidayChangesPanel extends StatelessWidget {
  const HolidayChangesPanel({super.key, required this.texts, required this.approved, required this.onApproved});

  final List<String> texts;
  final bool approved;
  final ValueChanged<bool> onApproved;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: const ValueKey('hb_changes'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('hb_changes_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 6),
          for (var i = 0; i < texts.length; i++)
            Padding(
              key: ValueKey('hb_change_$i'),
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(fontSize: 15, color: c.ink)),
                  Expanded(child: Text(texts[i], style: TextStyle(fontSize: 15, color: c.ink))),
                ],
              ),
            ),
          CheckboxListTile(
            key: const ValueKey('hb_approve'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: approved,
            onChanged: (v) => onApproved(v ?? false),
            title: Text(context.tr('hb_approve'), style: TextStyle(fontSize: 15, color: c.ink)),
          ),
        ],
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(context.tr('sm_err_load'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            FilledButton(key: const ValueKey('hb_retry'), onPressed: onRetry, child: Text(context.tr('sm_retry'))),
          ]),
        ),
      );
}

// Харидор: маҳсулот варағидаги «Буюртма бериш» (AVA курьери билан етказиш) — «Менинг бизнесим» буюртмаси.
//
// Тугма ФАҚАТ ҳаммаси мос бўлса кўринади (ўлик тугма йўқ):
//  1) таклиф буюртма қилиса бўладиган маҳсулот ([offerItemOrderable]: фаол, қатъий нарх — дона/кг/м²/белгиланган);
//  2) ўз маҳсулоти эмас;
//  3) бозор эълони бўлса — таксономияда бўлим `orderable` ([marketCategoryOrderable]; Аралаш — ҳа);
//  4) сотувчи: объект — харитада (онлайн эмас), блокланмаган ва тури курьер етказишига мос
//     ([BusinessTypeProfile.courierDeliveryApplies] — ягона манба); ўз дўкони («Бозорлар» STAGE 11) — дўкон
//     блокланмаган ва «Маҳсулотни топшириш жойи» белгиланган ([TvShop.hasPickup]);
//  5) сервер дарвозаси очиқ (`getBusinessOrdersAccess{businessId}` ёки `{itemId}` — off/internal/pilot/public).
// Йирик техника ([isLargeDeliveryItem]) — «Етказиш нархини сўраш» (сўров → нарх → тасдиқлаш).
// Сервер барибир ҳаммасини қайта текширади (18-қоида).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../business_map/data/business_repository.dart';
import '../../business_map/domain/business.dart';
import '../../business_map/domain/business_type_profile.dart';
import '../../markets/data/market_taxonomy_repository.dart';
import '../../markets/domain/market_taxonomy.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../data/business_order_session.dart';
import '../data/business_orders_repository.dart';
import '../domain/business_order.dart';
import '../domain/delivery_quote.dart';
import '../screens/business_cart_screen.dart';
import '../screens/business_checkout_sheet.dart';
import '../screens/delivery_quote_screens.dart';
import 'business_order_widgets.dart';

/// Объект курьер етказишига мосми (харитада, блокланмаган, тур профили рухсат беради).
bool businessAcceptsCourierOrders(Business b) =>
    !b.isOwnShop &&
    !b.isBlocked &&
    !b.online &&
    BusinessTypeProfile.forBusiness(b).courierDeliveryApplies(kind: OfferKind.product, online: b.online);

/// Маҳсулот варағидаги тугма тури.
enum OfferOrderMode { none, cart, deliveryQuote }

/// Тармоқсиз олдиндан қарор (сотувчи ва дарвоза кейин текширилади): [OfferOrderMode.none] — тугма йўқ.
OfferOrderMode offerOrderPrecheck(TvShopItem item, {required String myUid, MarketTaxonomy? taxonomy}) {
  if (!offerItemOrderable(item)) return OfferOrderMode.none;
  if (myUid.isNotEmpty && phonesMatch(myUid, item.ownerPhone)) return OfferOrderMode.none;
  if (item.businessId.isEmpty && canonicalPhoneId(item.ownerPhone).isEmpty) return OfferOrderMode.none;
  if (!marketCategoryOrderable(item, taxonomy)) return OfferOrderMode.none;
  return isLargeDeliveryItem(item) ? OfferOrderMode.deliveryQuote : OfferOrderMode.cart;
}

class BusinessOrderEntry extends StatefulWidget {
  const BusinessOrderEntry({
    super.key,
    required this.item,
    required this.myUid,
    this.repository,
    this.loadBusiness,
    this.loadShop,
    this.loadTaxonomy,
    this.store,
    this.accessCache,
    @visibleForTesting this.openCheckout,
    @visibleForTesting this.openCart,
    @visibleForTesting this.openQuote,
  });

  final TvShopItem item;

  /// Жорий фойдаланувчи (канон телефон); бўш — меҳмон (тугма барибир кўринади, сервер рад этса — хабар).
  final String myUid;
  final BusinessOrdersRepository? repository;

  /// Тест учун: объектни ўқиш (бўлмаса — [BusinessRepository.fetchById]).
  final Future<Business?> Function(String businessId)? loadBusiness;

  /// Тест учун: ўз дўкони ҳужжати (бўлмаса — [TvShopRepository.fetchShop]).
  final Future<TvShop?> Function(String ownerPhone)? loadShop;

  /// Тест учун: таксономия (бўлмаса — [MarketTaxonomyRepository.load], сеанс кеши).
  final Future<MarketTaxonomy> Function()? loadTaxonomy;
  final BusinessCartStore? store;
  final BusinessOrdersAccessCache? accessCache;

  /// Тест учун: расмийлаштириш варағи ўрнига.
  final Future<void> Function(BuildContext context, BusinessCart cart)? openCheckout;

  /// Тест учун: «Сават» экрани ўрнига.
  final Future<void> Function(BuildContext context)? openCart;

  /// Тест учун: етказиш нархи сўрови ўрнига.
  final Future<void> Function(BuildContext context, TvShopItem item)? openQuote;

  @override
  State<BusinessOrderEntry> createState() => _BusinessOrderEntryState();
}

class _BusinessOrderEntryState extends State<BusinessOrderEntry> {
  late final BusinessOrdersRepository _repo = widget.repository ?? BusinessOrdersRepository();
  late final BusinessCartStore _store = widget.store ?? BusinessCartStore.instance;
  late final BusinessOrdersAccessCache _cache = widget.accessCache ?? BusinessOrdersAccessCache.instance;

  /// `none` — тугма йўқ (ёки текширилмоқда).
  OfferOrderMode _mode = OfferOrderMode.none;
  String _sellerName = '';

  TvShopItem get _item => widget.item;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onCart);
    unawaited(_store.ensureLoaded());
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(covariant BusinessOrderEntry old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id || old.item.status != widget.item.status || old.myUid != widget.myUid) {
      unawaited(_resolve());
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onCart);
    super.dispose();
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  void _set(OfferOrderMode m, TvShopItem item) {
    if (mounted && item.id == _item.id) setState(() => _mode = m);
  }

  Future<void> _resolve() async {
    final item = _item;
    // 1) Тармоқсиз қисм (таксономия — фақат бозор эълонида, сеанс кешидан).
    var mode = offerOrderPrecheck(item, myUid: widget.myUid, taxonomy: MarketTaxonomy.empty);
    if (mode == OfferOrderMode.none && item.market.isNotEmpty && offerItemOrderable(item)) {
      try {
        final tax = await (widget.loadTaxonomy?.call() ?? MarketTaxonomyRepository.load());
        mode = offerOrderPrecheck(item, myUid: widget.myUid, taxonomy: tax);
      } catch (e) {
        debugPrint('[BizOrderEntry] taxonomy: $e');
        mode = OfferOrderMode.none;
      }
    }
    if (mode == OfferOrderMode.none) return _set(OfferOrderMode.none, item);

    // 2) Сотувчи + сервер дарвозаси.
    var ok = false;
    try {
      if (item.businessId.isNotEmpty) {
        final load = widget.loadBusiness ?? BusinessRepository().fetchById;
        final results = await Future.wait<Object?>([
          load(item.businessId),
          _cache.get(item.businessId, () => _repo.access(businessId: item.businessId)),
        ]);
        final b = results[0] as Business?;
        final access = results[1] as BusinessOrdersAccess;
        ok = b != null && access.allowed && businessAcceptsCourierOrders(b) && !phonesMatch(widget.myUid, b.ownerId);
        if (b != null) _sellerName = b.name;
      } else {
        final load = widget.loadShop ?? TvShopRepository().fetchShop;
        final results = await Future.wait<Object?>([
          load(item.ownerPhone),
          _cache.get('item:${item.id}', () => _repo.access(itemId: item.id)),
        ]);
        final shop = results[0] as TvShop?;
        final access = results[1] as BusinessOrdersAccess;
        ok = shop != null && !shop.isBlocked && shop.hasPickup && access.allowed;
        final shopName = shop?.name.trim() ?? '';
        _sellerName = shopName.isNotEmpty ? shopName : item.ownerName.trim();
      }
    } catch (e) {
      debugPrint('[BizOrderEntry] gate ${item.id}: $e');
      ok = false;
    }
    _set(ok ? mode : OfferOrderMode.none, item);
  }

  BusinessCart get _cart => _store.cartForItem(_item, sellerName: _sellerName);

  BusinessCart? get _existingCart =>
      _store.existing(businessCartKey(businessId: _item.businessId, ownerPhone: _item.ownerPhone));

  Future<void> _checkout() async {
    final cart = _cart;
    final custom = widget.openCheckout;
    if (custom != null) return custom(context, cart);
    await showBusinessCheckoutSheet(context, cart: cart, repository: _repo, store: _store);
  }

  Future<void> _openCart() async {
    final custom = widget.openCart;
    if (custom != null) return custom(context);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BusinessCartScreen(store: _store)));
  }

  Future<void> _quote() async {
    final custom = widget.openQuote;
    if (custom != null) return custom(context, _item);
    await openDeliveryQuoteRequest(context, item: _item, repository: _repo);
  }

  Future<void> _order() async {
    final action = await showModalBottomSheet<_AddAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: context.ava.surface,
      builder: (_) => _AddToCartSheet(item: _item, inCart: _existingCart?.qtyOf(_item.id) ?? 0),
    );
    if (action == null || !mounted) return;
    final added = _cart.add(_item, action.qty);
    _store.changed();
    if (!added) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(context
            .tr('biz_order_cart_full')
            .replaceAll('{max}', '${BusinessOrderLimits.maxItems}')),
      ));
      return;
    }
    if (action.checkout) {
      await _checkout();
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('biz_order_added'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == OfferOrderMode.none) return const SizedBox.shrink();
    final c = context.ava;
    final quote = _mode == OfferOrderMode.deliveryQuote;
    final total = _store.linesCount;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            key: ValueKey(quote ? 'dq_cta' : 'biz_order_cta'),
            onPressed: quote ? _quote : _order,
            icon: Icon(quote ? Icons.local_shipping_outlined : Icons.add_shopping_cart_rounded),
            label: Text(
              context.tr(quote ? 'dq_cta' : 'biz_order_add_to_cart'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: c.brandInk,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AvaRadius.card)),
            ),
          ),
          const SizedBox(height: 4),
          Text(context.tr(quote ? 'dq_cta_hint' : 'biz_order_cta_hint'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.ink2)),
          if (total > 0)
            TextButton.icon(
              key: const ValueKey('biz_order_cart_bar'),
              onPressed: _openCart,
              icon: const Icon(Icons.shopping_basket_outlined, size: 18),
              label: Text(
                context
                    .tr('biz_order_cart_bar')
                    .replaceAll('{count}', '$total')
                    .replaceAll('{amount}', formatMoney(_store.carts.fold<int>(0, (s, c) => s + c.itemsTotal))),
              ),
              style: TextButton.styleFrom(foregroundColor: c.brandText, minimumSize: const Size.fromHeight(AvaTap.minSize)),
            ),
        ],
      ),
    );
  }
}

class _AddAction {
  const _AddAction(this.qty, {required this.checkout});
  final int qty;
  final bool checkout;
}

/// Миқдор танлаш: − N + (1..100, саватдагисини ҳисобга олиб), жами, «Саватга қўшиш» / «Расмийлаштириш».
class _AddToCartSheet extends StatefulWidget {
  const _AddToCartSheet({required this.item, required this.inCart});

  final TvShopItem item;
  final int inCart;

  @override
  State<_AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends State<_AddToCartSheet> {
  int _qty = 1;

  int get _max {
    final left = BusinessOrderLimits.maxQtyPerItem - widget.inCart;
    return left < 1 ? 1 : left;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final it = widget.item;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 0, AvaSpace.screen, AvaSpace.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('biz_order_add_title'), style: AvaText.sectionTitle.copyWith(color: c.ink)),
            const SizedBox(height: 4),
            Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.ink2)),
            Text(it.priceLabel(context.tr), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  key: const ValueKey('biz_add_minus'),
                  tooltip: context.tr('biz_order_qty_less'),
                  onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    bizOrderQtyLabel(context, _qty, it.priceUnit),
                    key: const ValueKey('biz_add_qty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.ink),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton.filledTonal(
                  key: const ValueKey('biz_add_plus'),
                  tooltip: context.tr('biz_order_qty_more'),
                  onPressed: _qty < _max ? () => setState(() => _qty++) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('biz_order_line_total').replaceAll('{amount}', formatMoney(it.price * _qty)),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.ink),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('biz_add_to_cart'),
                    onPressed: () => Navigator.pop(context, _AddAction(_qty, checkout: false)),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: Text(context.tr('biz_order_add_to_cart'), textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('biz_add_checkout'),
                    onPressed: () => Navigator.pop(context, _AddAction(_qty, checkout: true)),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      foregroundColor: c.brandInk,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(context.tr('biz_order_checkout'), textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

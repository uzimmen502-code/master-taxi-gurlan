// Харидор: маҳсулот варағидаги «Буюртма бериш» (AVA курьери билан етказиш) — «Менинг бизнесим» буюртмаси.
//
// Тугма ФАҚАТ ҳаммаси мос бўлса кўринади (ўлик тугма йўқ):
//  1) таклиф буюртма қилиса бўладиган маҳсулот ([businessItemOrderable]: объектга боғланган, фаол, қатъий нарх);
//  2) ўз маҳсулоти эмас;
//  3) объект харитада (онлайн эмас), блокланмаган ва тури курьер етказишига мос
//     ([BusinessTypeProfile.courierDeliveryApplies] — ягона манба);
//  4) сервер дарвозаси очиқ (`getBusinessOrdersAccess{businessId}` — босқич off/internal/pilot/public).
// Сервер барибир ҳаммасини қайта текширади (18-қоида).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../business_map/data/business_repository.dart';
import '../../business_map/domain/business.dart';
import '../../business_map/domain/business_type_profile.dart';
import '../../tv_market/models/tv_shop.dart';
import '../data/business_order_session.dart';
import '../data/business_orders_repository.dart';
import '../domain/business_order.dart';
import '../screens/business_checkout_sheet.dart';
import 'business_order_widgets.dart';

/// Объект курьер етказишига мосми (харитада, блокланмаган, тур профили рухсат беради).
bool businessAcceptsCourierOrders(Business b) =>
    !b.isOwnShop &&
    !b.isBlocked &&
    !b.online &&
    BusinessTypeProfile.forBusiness(b).courierDeliveryApplies(kind: OfferKind.product, online: b.online);

class BusinessOrderEntry extends StatefulWidget {
  const BusinessOrderEntry({
    super.key,
    required this.item,
    required this.myUid,
    this.repository,
    this.loadBusiness,
    this.store,
    this.accessCache,
    @visibleForTesting this.openCheckout,
  });

  final TvShopItem item;

  /// Жорий фойдаланувчи (канон телефон); бўш — меҳмон (тугма барибир кўринади, сервер рад этса — хабар).
  final String myUid;
  final BusinessOrdersRepository? repository;

  /// Тест учун: объектни ўқиш (бўлмаса — [BusinessRepository.fetchById]).
  final Future<Business?> Function(String businessId)? loadBusiness;
  final BusinessCartStore? store;
  final BusinessOrdersAccessCache? accessCache;

  /// Тест учун: расмийлаштириш варағи ўрнига.
  final Future<void> Function(BuildContext context, BusinessCart cart)? openCheckout;

  @override
  State<BusinessOrderEntry> createState() => _BusinessOrderEntryState();
}

class _BusinessOrderEntryState extends State<BusinessOrderEntry> {
  late final BusinessOrdersRepository _repo = widget.repository ?? BusinessOrdersRepository();
  late final BusinessCartStore _store = widget.store ?? BusinessCartStore.instance;
  late final BusinessOrdersAccessCache _cache = widget.accessCache ?? BusinessOrdersAccessCache.instance;

  /// `null` — текширилмоқда; `true` — кўрсатилади.
  bool? _visible;
  String _businessName = '';

  TvShopItem get _item => widget.item;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onCart);
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

  bool get _own => widget.myUid.isNotEmpty && phonesMatch(widget.myUid, _item.ownerPhone);

  Future<void> _resolve() async {
    final item = _item;
    if (!businessItemOrderable(item) || _own) {
      if (mounted) setState(() => _visible = false);
      return;
    }
    var ok = false;
    try {
      final load = widget.loadBusiness ?? BusinessRepository().fetchById;
      final results = await Future.wait<Object?>([
        load(item.businessId),
        _cache.get(item.businessId, () => _repo.access(businessId: item.businessId)),
      ]);
      final b = results[0] as Business?;
      final access = results[1] as BusinessOrdersAccess;
      ok = b != null && access.allowed && businessAcceptsCourierOrders(b) && !phonesMatch(widget.myUid, b.ownerId);
      if (b != null) _businessName = b.name;
    } catch (e) {
      debugPrint('[BizOrderEntry] gate ${item.businessId}: $e');
      ok = false;
    }
    if (mounted && item.id == _item.id) setState(() => _visible = ok);
  }

  BusinessCart get _cart => _store.cartFor(_item.businessId, businessName: _businessName);

  Future<void> _checkout() async {
    final cart = _cart;
    final custom = widget.openCheckout;
    if (custom != null) return custom(context, cart);
    await showBusinessCheckoutSheet(context, cart: cart, repository: _repo, store: _store);
  }

  Future<void> _order() async {
    final action = await showModalBottomSheet<_AddAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: context.ava.surface,
      builder: (_) => _AddToCartSheet(item: _item, inCart: _store.existing(_item.businessId)?.qtyOf(_item.id) ?? 0),
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
    if (_visible != true) return const SizedBox.shrink();
    final c = context.ava;
    final cart = _store.existing(_item.businessId);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            key: const ValueKey('biz_order_cta'),
            onPressed: _order,
            icon: const Icon(Icons.delivery_dining_rounded),
            label: Text(context.tr('biz_order_cta'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: c.brandInk,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AvaRadius.card)),
            ),
          ),
          const SizedBox(height: 4),
          Text(context.tr('biz_order_cta_hint'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.ink2)),
          if (cart != null && cart.isNotEmpty)
            TextButton.icon(
              key: const ValueKey('biz_order_cart_bar'),
              onPressed: _checkout,
              icon: const Icon(Icons.shopping_basket_outlined, size: 18),
              label: Text(
                context
                    .tr('biz_order_cart_bar')
                    .replaceAll('{count}', '${cart.lines.length}')
                    .replaceAll('{amount}', formatMoney(cart.itemsTotal)),
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

// «Бозорлар» STAGE 11 (эга 2026-11-16): ЯГОНА «Сават» экрани — сотувчи бўйича гуруҳлар ([BusinessCartStore]).
// Ҳар гуруҳ мавжуд расмийлаштириш варағи ([showBusinessCheckoutSheet]) орқали алоҳида буюртма бўлади (сервер:
// бир буюртма — бир сотувчи). Нархлар фақат кўрсатиш учун; якуний нарх — сервер квотасидан (18-қоида).

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../data/business_order_session.dart';
import '../domain/business_order.dart';
import 'business_checkout_sheet.dart';

class BusinessCartScreen extends StatefulWidget {
  const BusinessCartScreen({super.key, this.store, @visibleForTesting this.openCheckout});

  final BusinessCartStore? store;

  /// Тест учун: расмийлаштириш варағи ўрнига.
  final Future<void> Function(BuildContext context, BusinessCart cart)? openCheckout;

  @override
  State<BusinessCartScreen> createState() => _BusinessCartScreenState();
}

class _BusinessCartScreenState extends State<BusinessCartScreen> {
  late final BusinessCartStore _store = widget.store ?? BusinessCartStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChange);
    _store.ensureLoaded();
  }

  @override
  void dispose() {
    _store.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _setQty(BusinessCart cart, BusinessCartLine l, int qty) {
    cart.setQty(l.itemId, qty);
    if (cart.isEmpty) {
      _store.clear(cart.key);
    } else {
      _store.changed();
    }
  }

  Future<void> _checkout(BusinessCart cart) async {
    final custom = widget.openCheckout;
    if (custom != null) return custom(context, cart);
    await showBusinessCheckoutSheet(context, cart: cart, store: _store);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final carts = _store.carts;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('biz_cart_title'))),
      body: carts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ExcludeSemantics(child: Icon(Icons.shopping_basket_outlined, size: 48, color: c.ink2)),
                  const SizedBox(height: 8),
                  Text(context.tr('biz_order_cart_empty'), textAlign: TextAlign.center, style: TextStyle(color: c.ink2)),
                ]),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 12, AvaSpace.screen, 24),
              children: [
                if (carts.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(context.tr('biz_cart_per_seller_hint'), style: TextStyle(fontSize: 12.5, color: c.ink2)),
                  ),
                for (final cart in carts) ...[
                  _SellerGroup(
                    cart: cart,
                    onQty: (l, n) => _setQty(cart, l, n),
                    onCheckout: () => _checkout(cart),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _SellerGroup extends StatelessWidget {
  const _SellerGroup({required this.cart, required this.onQty, required this.onCheckout});

  final BusinessCart cart;
  final void Function(BusinessCartLine line, int qty) onQty;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final name = cart.businessName.trim().isEmpty ? context.tr('tv_vitrine_seller') : cart.businessName.trim();
    return Container(
      key: ValueKey('biz_cart_group_${cart.key}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            ExcludeSemantics(child: Icon(Icons.storefront_rounded, size: 18, color: c.brandText)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
            ),
          ]),
          const SizedBox(height: 4),
          for (final l in cart.lines) BusinessCartRow(line: l, onQty: (n) => onQty(l, n)),
          const SizedBox(height: 6),
          Text(
            context.tr('biz_order_items_total_line').replaceAll('{amount}', formatMoney(cart.itemsTotal)),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: ValueKey('biz_cart_checkout_${cart.key}'),
            onPressed: onCheckout,
            style: FilledButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: c.brandInk,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AvaRadius.card)),
            ),
            child: Text(context.tr('biz_order_checkout'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// AppBar «Сават» тугмаси: саватда нарса бўлса кўринади, нишонда қаторлар сони ([BusinessCartStore.linesCount]).
class BusinessCartButton extends StatefulWidget {
  const BusinessCartButton({super.key, this.store, this.color});

  final BusinessCartStore? store;
  final Color? color;

  @override
  State<BusinessCartButton> createState() => _BusinessCartButtonState();
}

class _BusinessCartButtonState extends State<BusinessCartButton> {
  late final BusinessCartStore _store = widget.store ?? BusinessCartStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChange);
    _store.ensureLoaded();
  }

  @override
  void dispose() {
    _store.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final n = _store.linesCount;
    if (n == 0) return const SizedBox.shrink();
    final c = context.ava;
    return IconButton(
      key: const ValueKey('biz_cart_button'),
      tooltip: context.tr('biz_cart_title'),
      color: widget.color,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => BusinessCartScreen(store: _store)),
      ),
      icon: Badge(
        label: Text('$n'),
        backgroundColor: c.brand,
        textColor: c.brandInk,
        child: const Icon(Icons.shopping_basket_outlined),
      ),
    );
  }
}

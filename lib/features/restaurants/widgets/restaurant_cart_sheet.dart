// Сават варағи (§12.4): таомлар степпер билан, «Тозалаш» (тасдиқ билан),
// жами, «Буюртма бериш».

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../domain/qty_tiers.dart';
import '../domain/restaurant_models.dart';

Future<void> showRestaurantCartSheet(
  BuildContext context, {
  required RestaurantCart cart,
  required Restaurant restaurant,
  required VoidCallback onCheckout,
}) {
  final c = context.ava;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: c.surface,
    builder: (ctx) => _CartSheet(cart: cart, restaurant: restaurant, onCheckout: onCheckout),
  );
}

class _CartSheet extends StatelessWidget {
  const _CartSheet({required this.cart, required this.restaurant, required this.onCheckout});

  final RestaurantCart cart;
  final Restaurant restaurant;
  final VoidCallback onCheckout;

  Future<void> _clear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('restaurants_cart_clear')),
        content: Text(ctx.tr('restaurants_cart_clear_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('restaurants_cart_clear'))),
        ],
      ),
    );
    if (ok == true) {
      cart.clear();
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final maxH = MediaQuery.sizeOf(context).height * 0.75;
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final lines = cart.lines;
        if (lines.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.tr('restaurants_cart_empty'), textAlign: TextAlign.center, style: TextStyle(color: c.ink2)),
          );
        }
        final missing = restaurant.minOrderAmount - cart.itemsTotal;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(cart.restaurantName, style: AvaText.sectionTitle.copyWith(color: c.ink)),
                    ),
                    TextButton(
                      onPressed: () => _clear(context),
                      child: Text(context.tr('restaurants_cart_clear'), style: TextStyle(color: c.danger)),
                    ),
                  ],
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
                    itemBuilder: (context, i) {
                      final l = lines[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.ink)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${formatPrice(l.unitPrice)} × ${l.qty} = ${formatPrice(l.lineTotal)} ${context.tr('sum')}',
                                    key: ValueKey('cart-line-${l.item.id}'),
                                    style: AvaText.caption.copyWith(color: c.ink2),
                                  ),
                                  // Миқдорга чегирма (D-REST-25): қўлланган бўлса — қайси поғона; бўлмаса — кейингиси.
                                  if (l.discount > 0)
                                    Text(
                                      context.tr('restaurants_tier_applied').replaceAll('{min}', '${QtyTiers.unitPriceFor(l.item.price, l.item.qtyTiers, l.qty).tierMinQty}'),
                                      key: ValueKey('cart-tier-applied-${l.item.id}'),
                                      style: AvaText.caption.copyWith(color: c.ok),
                                    ),
                                  if (QtyTiers.nextTier(l.item.qtyTiers, l.qty) case final next?)
                                    Text(
                                      context
                                          .tr('restaurants_tier_next')
                                          .replaceAll('{n}', '${next.minQty - l.qty}')
                                          .replaceAll('{price}', '${formatPrice(next.price)} ${context.tr('sum')}'),
                                      key: ValueKey('cart-tier-next-${l.item.id}'),
                                      style: AvaText.caption.copyWith(color: c.brandText),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove_circle_outline_rounded),
                              onPressed: () => cart.decrement(l.item.id),
                            ),
                            Text('${l.qty}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.add_circle_rounded, color: c.brand),
                              onPressed: cart.canAddMore(l.item.id, restaurant)
                                  ? () => cart.add(l.item, restaurant: restaurant)
                                  : null,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Divider(height: 16, color: c.line),
                _TotalLine(label: context.tr('restaurants_items_total'), value: cart.itemsTotal),
                if (cart.qtyDiscountTotal > 0)
                  _TotalLine(label: context.tr('restaurants_qty_discount'), value: -cart.qtyDiscountTotal),
                _TotalLine(label: context.tr('restaurants_total'), value: cart.itemsTotal, bold: true),
                if (missing > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      context.tr('restaurants_min_more').replaceAll('{amount}', formatPrice(missing)),
                      style: TextStyle(fontSize: 12, color: c.warn),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: missing > 0
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          onCheckout();
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: c.brand,
                    foregroundColor: c.brandInk,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(context.tr('restaurants_checkout'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.label, required this.value, this.bold = false});

  final String label;
  final int value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final style = TextStyle(fontSize: bold ? 14 : 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: c.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          // Катта шрифт ва узун сумма (900 000 сўм): сумма қирқилмасдан кичрайиб сиғади.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text('${formatPrice(value)} ${context.tr('sum')}', style: style),
            ),
          ),
        ],
      ),
    );
  }
}

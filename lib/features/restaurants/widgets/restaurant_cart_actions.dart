// Саватга қўшиш — ресторан экрани ҳам, таом тафсилоти варағи ҳам ШУ ЯГОНА функцияни ишлатади (4-қоида:
// дубликат мантиқ йўқ). Сават БИТТА ресторандан; бошқа ресторанники турган бўлса — тозалаб ўтиш сўралади.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../domain/restaurant_models.dart';

/// [item]ни саватга қўшади. Сават бошқа рестораннинг бўлса «тозалаймизми?» диалоги чиқади; тасдиқланса
/// сават алмашади. Қайтади: таом саватга тушдими (чегарага етган бўлса ҳам `true` — ўзгариш йўқ, хато эмас).
Future<bool> addToCartOrAskSwitch(
  BuildContext context, {
  required RestaurantCart cart,
  required MenuItem item,
  required Restaurant restaurant,
}) async {
  if (cart.add(item, restaurant: restaurant)) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('restaurants_cart_switch_title')),
      content: Text(
        ctx.tr('restaurants_cart_switch_body')
            .replaceAll('{old}', cart.restaurantName)
            .replaceAll('{new}', restaurant.name),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('restaurants_cart_switch_ok'))),
      ],
    ),
  );
  if (ok != true) return false;
  cart.replaceWith(item, restaurant: restaurant);
  return true;
}

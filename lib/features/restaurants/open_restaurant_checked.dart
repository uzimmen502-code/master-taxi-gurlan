import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../home/home_module_gate.dart';
import '../tv_market/services/shop_stats_recorder.dart';
import 'data/restaurants_repository.dart';
import 'domain/restaurant_models.dart';
import 'domain/restaurants_access.dart';
import 'screens/restaurant_screen.dart';

/// Кафе-ресторанни ID бўйича ОЧИШ ВАҚТИДА текшириб очиш (2026-10-25): доимий ҳавола/QR (`/?shop=<id>`) ва глобал
/// қидирув натижаси шу ердан ўтади. Тартиб:
///  1. модул дарвозаси — бош саҳифадаги бўлим билан бир хил ягона манба ([resolveRestaurantsAccess]);
///  2. ресторан қайта ўқилади: йўқ, тасдиқланмаган (тўхтатилган/ёпилган) ёки ўқиб бўлмаса — АВАГрам «Кафе»
///     тугмасидаги ўша «вақтинча мавжуд эмас» хабари (`tv_market_restaurant_unavailable`); сабаб айтилмайди (45-банд);
///  3. кўриш [source] манбаси билан қайд этилади (`recordShopEvent`, а'золар серверда саналмайди) ва меню очилади.
Future<void> openRestaurantChecked(
  BuildContext context,
  String restaurantId, {
  required String source,
  Future<Restaurant?> Function(String id)? load,
  Future<bool> Function()? canOpenModule,
  void Function(Widget screen)? push,
}) async {
  final gate = canOpenModule ?? () => resolveRestaurantsAccess(accessCheck: () => RestaurantsRepository().hasAccess());
  if (!await gate()) {
    if (context.mounted) HomeModuleGate.onTapBlocked(context, kRestaurantsModuleId);
    return;
  }
  Restaurant? r;
  try {
    r = restaurantId.isEmpty ? null : await (load ?? RestaurantsRepository().getRestaurant)(restaurantId);
  } catch (e) {
    // Тасдиқланмаган ресторанни фақат а'зоси ўқийди — рухсат хатоси ҳам «мавжуд эмас».
    debugPrint('[openRestaurantChecked] $e');
    r = null;
  }
  if (!context.mounted) return;
  if (r == null || !r.isApproved) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.tr('tv_market_restaurant_unavailable'))),
    );
    return;
  }
  ShopStatsRecorder.restaurantView(restaurantId: r.id, source: source);
  final screen = RestaurantScreen(restaurant: r);
  if (push != null) return push(screen);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

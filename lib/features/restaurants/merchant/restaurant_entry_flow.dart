// «＋» → «Уй ошпази бўлиш» / «Кафе-ресторан очиш» (эга қарори, 2026-10-16).
//
// Аввал бу мантиқ Кабинетдаги `RestaurantProfileEntry` да эди. Энди «＋»
// менюсидан чақирилади. Икки банд БИР рўйхатдан фойдаланади (`restaurants`),
// фарқи — `legalType`: `individual` = уй ошпази ([Restaurant.isHomeCook]),
// `yatt`/`llc` = кафе-ресторан.
//
//   тури бўйича ресторани йўқ → рўйхатдан ўтиш (турга мос олдиндан танланган)
//   битта бор                 → шу панел (ҳолат панелнинг ўзида)
//   бир нечта                 → танлов варағи (ҳар бирининг ҳолати билан) + «яна очиш»
// Ҳозирча фақат ЭГА (`ownerUid == мен`); ходимлар — Б2.7.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../data/restaurants_repository.dart';
import '../domain/restaurant_models.dart';
import 'restaurant_panel_screen.dart';
import 'restaurant_register_screen.dart';

/// Эганинг шу турдаги (уй ошпази ёки кафе) заведениялари — битта сўров.
List<Restaurant> restaurantsOfKind(List<Restaurant> mine, {required bool homeCook}) =>
    mine.where((r) => r.isHomeCook == homeCook).toList(growable: false);

Future<void> openRestaurantBusiness(
  BuildContext context, {
  required String ownerUid,
  required bool homeCook,
  RestaurantsRepository? repository,
}) async {
  final repo = repository ?? RestaurantsRepository();
  List<Restaurant> mine;
  try {
    mine = restaurantsOfKind(
      await repo.watchMine(ownerUid).first.timeout(const Duration(seconds: 8)),
      homeCook: homeCook,
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('restaurants_err_generic'))),
      );
    }
    return;
  }
  if (!context.mounted) return;

  Future<void> register() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RestaurantRegisterScreen(repository: repo, homeCook: homeCook),
        ),
      );
  Future<void> panel(Restaurant r) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RestaurantPanelScreen(restaurantId: r.id, repository: repo),
        ),
      );

  if (mine.isEmpty) {
    await register();
    return;
  }
  if (mine.length == 1) {
    await panel(mine.first);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              ctx.tr('restaurants_m_choose_cafe'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          for (final r in mine)
            ListTile(
              leading: const Icon(Icons.restaurant_rounded),
              title: Text(r.name),
              subtitle: Text(ctx.tr('restaurants_m_status_${r.status}')),
              onTap: () {
                Navigator.pop(ctx);
                panel(r);
              },
            ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: Text(ctx.tr(homeCook ? 'home_create_home_cook' : 'restaurants_m_open_cafe')),
            onTap: () {
              Navigator.pop(ctx);
              register();
            },
          ),
        ],
      ),
    ),
  );
}

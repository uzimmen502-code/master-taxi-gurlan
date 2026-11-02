// «Менинг бизнесим» овқатланиш объекти → ресторан бўлими (меню, буюртма, курьер) занжири (эга, 2026-11-03:
// «қўшилгандан кейин занжир охиригача», «харитада битта белги»).
//
//   объект уланган ([Business.hasRestaurant])  → ресторан панели, «Меню» таби
//   уланмаган, эганинг мос ресторани бор      → варақ: шу ресторанни улаш ёки «Янги меню очиш»
//   уланмаган, мос ресторан йўқ               → рўйхатдан ўтиш (объектдан олдиндан тўлдирилган) → улаш → «Меню»
//
// Янги тизим ЭМАС: мавжуд `restaurants` модули ([RestaurantRegisterScreen], [RestaurantPanelScreen]) ва сервер
// `linkBusinessRestaurant` ([BusinessRepository.linkRestaurant]) ишлатилади. Улашни фақат сервер ёзади ва
// текширади (18-банд); бу ерда фақат танлов ва навигация.

import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../restaurants/data/restaurants_repository.dart';
import '../restaurants/domain/restaurant_models.dart';
import '../restaurants/domain/venue_type.dart';
import '../restaurants/merchant/restaurant_entry_flow.dart' show restaurantsOfKind;
import '../restaurants/merchant/restaurant_panel_screen.dart';
import '../restaurants/merchant/restaurant_register_form.dart';
import '../restaurants/merchant/restaurant_register_screen.dart';
import 'data/business_repository.dart';
import 'domain/business.dart';
import 'domain/business_category.dart';
import 'domain/business_subtypes.dart';

/// Менюга уланадиган объект: овқатланиш тури, харитада жойи бор (онлайн эмас) ва ҳақиқий объект (эганинг
/// «ўз дўкони» эмас). Сервер ҳам шуни текширади (`BUSINESS_NOT_FOOD`, `BUSINESS_ONLINE`).
bool businessCanHaveMenu(Business b) => b.category == BusinessCategory.food && !b.online && !b.isOwnShop;

/// «Аниқроқ тури» — [BusinessSubtypes] даги овқатланиш тайёр тури (ўзбекча кирилл номи бўйича) ми. Сақланган
/// матн исталган тилда/ёзувда бўлиши мумкин ([BusinessSubtypes.norm]).
bool _foodSubtypeIs(String stored, String uzCyrl) {
  final n = BusinessSubtypes.norm(stored);
  if (n.isEmpty) return false;
  for (final e in BusinessSubtypes.data[BusinessCategory.food] ?? const <(String, String)>[]) {
    if (e.$1 == uzCyrl) return n == BusinessSubtypes.norm(e.$1) || n == BusinessSubtypes.norm(e.$2);
  }
  return false;
}

/// Уй ошпази тури (ресторан бўлимида `legalType: individual`, [Restaurant.isHomeCook]). Қолган овқатланиш
/// объектлари — кафе-ресторан.
const kHomeCookFoodSubtypes = ['Уй ошпази', 'Уйда овқат тайёрлаш'];

bool isHomeCookBusiness(Business b) => kHomeCookFoodSubtypes.any((s) => _foodSubtypeIs(b.subtype, s));

/// Рўйхатдан ўтиш формасидаги муассаса тури ([VenueType]): «Ресторан» → ресторан, «Чойхона» → чойхона, бошқа
/// овқатланиш тури → кафе; уй ошпази — `null` (сервер `home` ни ўзи қўяди). Эга формада ўзгартира олади.
String? venueTypeForBusiness(Business b) {
  if (isHomeCookBusiness(b)) return null;
  if (_foodSubtypeIs(b.subtype, 'Ресторан')) return VenueType.restaurant;
  if (_foodSubtypeIs(b.subtype, 'Чойхона')) return VenueType.chaikhana;
  return VenueType.cafe;
}

/// Объектнинг «Иш вақти» эркин матни (масалан «09:00–21:00») → `HH:MM` жуфтлиги; тушунилмаса — `null` (формада
/// «доим очиқ» қолади). Чегаралар сервер `hhmmToMin` билан бир хил (соат ≤ 23, дақиқа ≤ 59).
({String open, String close})? parseBusinessHours(String raw) {
  final m = RegExp(r'^\s*(\d{1,2})[:.](\d{2})\s*[-–—]\s*(\d{1,2})[:.](\d{2})\s*$').firstMatch(raw);
  if (m == null) return null;
  String? hhmm(String h, String mi) {
    final hh = int.parse(h);
    final mm = int.parse(mi);
    if (hh > 23 || mm > 59) return null;
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  final open = hhmm(m.group(1)!, m.group(2)!);
  final close = hhmm(m.group(3)!, m.group(4)!);
  if (open == null || close == null) return null;
  return (open: open, close: close);
}

/// Объект маълумотлари → ресторан рўйхатдан ўтиш формаси (эга такрор ёзмасин).
RestaurantRegisterPrefill restaurantPrefillFromBusiness(Business b) {
  final hours = parseBusinessHours(b.openingHours);
  return RestaurantRegisterPrefill(
    name: b.name,
    description: b.description,
    address: b.address,
    contactPhone: b.phone,
    lat: b.lat,
    lng: b.lng,
    venueType: venueTypeForBusiness(b),
    openTime: hours?.open,
    closeTime: hours?.close,
  );
}

/// Варақдаги «Янги меню очиш» танлови (ресторан ID'лари билан тўқнашмайди).
const _kNewMenu = '+';

/// «Меню» занжири. [linkedRestaurantIds] — эганинг БОШҚА объектларига уланган ресторанлар (таклиф қилинмайди;
/// сервер ҳам `RESTAURANT_ALREADY_LINKED` билан рад этади). Менюга уланмайдиган объект ([businessCanHaveMenu]) —
/// ҳеч нарса қилинмайди.
Future<void> openBusinessMenuFlow(
  BuildContext context,
  Business b, {
  BusinessRepository? businessRepo,
  RestaurantsRepository? restaurantsRepo,
  Set<String> linkedRestaurantIds = const {},
}) async {
  if (!businessCanHaveMenu(b)) return;
  void snack(String key) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr(key))));
  Future<void> panel(String restaurantId, RestaurantsRepository? repo) => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RestaurantPanelScreen(
            restaurantId: restaurantId,
            repository: repo,
            initialTab: RestaurantPanelScreen.menuTab,
          ),
        ),
      );

  if (b.hasRestaurant) {
    await panel(b.restaurantId, restaurantsRepo);
    return;
  }

  final bRepo = businessRepo ?? BusinessRepository();
  final rRepo = restaurantsRepo ?? RestaurantsRepository();
  final homeCook = isHomeCookBusiness(b);
  List<Restaurant> mine;
  try {
    mine = await rRepo.watchMine(b.ownerId).first.timeout(const Duration(seconds: 8));
  } catch (e) {
    // Ўқиб бўлмади — мавжуд ресторан таклиф қилинмайди, янги меню очилади (эга қарори; рўйхатдан ўтишни сервер
    // текширади).
    debugPrint('[BusinessMenu] my restaurants not loaded: $e');
    mine = const [];
  }
  if (!context.mounted) return;
  final candidates = [
    for (final r in restaurantsOfKind(mine, homeCook: homeCook))
      if (!linkedRestaurantIds.contains(r.id)) r,
  ];

  var picked = _kNewMenu;
  if (candidates.isNotEmpty) {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                ctx.tr('bizmap_menu_sheet_title'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            for (final r in candidates)
              ListTile(
                key: ValueKey('biz_menu_pick_${r.id}'),
                leading: Icon(homeCook ? Icons.soup_kitchen_rounded : Icons.restaurant_rounded),
                title: Text(r.name),
                subtitle: Text(ctx.tr('restaurants_m_status_${r.status}')),
                onTap: () => Navigator.pop(ctx, r.id),
              ),
            ListTile(
              key: const ValueKey('biz_menu_new'),
              leading: const Icon(Icons.add_rounded),
              title: Text(ctx.tr('bizmap_menu_new')),
              onTap: () => Navigator.pop(ctx, _kNewMenu),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    picked = choice;
  }

  if (picked != _kNewMenu) {
    try {
      await bRepo.linkRestaurant(b.id, picked);
    } catch (e) {
      // Фойдаланувчига оддий жумла (25-банд); диагностика коди — `errorCode` логида.
      final code = BusinessRepository.errorCode(e);
      debugPrint('[BusinessMenu] link ${b.id} -> $picked failed: ${code.isEmpty ? 'UNKNOWN' : code}');
      if (context.mounted) {
        snack(code == 'RESTAURANT_ALREADY_LINKED' ? 'bizmap_menu_already_linked' : 'bizmap_menu_link_failed');
      }
      return;
    }
    if (!context.mounted) return;
    snack('bizmap_menu_linked');
    await panel(picked, rRepo);
    return;
  }

  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => RestaurantRegisterScreen(
        repository: rRepo,
        homeCook: homeCook,
        prefill: restaurantPrefillFromBusiness(b),
        // Ресторан очилгач дарров объектга уланади; хато бўлса экран огоҳлантиради ва панелга ўтади.
        onRegistered: (rid) => bRepo.linkRestaurant(b.id, rid),
        panelInitialTab: RestaurantPanelScreen.menuTab,
      ),
    ),
  );
}

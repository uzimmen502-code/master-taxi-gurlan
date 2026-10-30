import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/service_config_holder.dart';
import '../home/home_module_gate.dart';
import '../home/widgets/ava_business_sheet.dart';
import 'my_shop_presence.dart';
import 'screens/main_shop_screen.dart';
import 'screens/my_shop_screen.dart';

/// Экранни очувчи (чақирувчининг ўз навигацияси: бош саҳифада `_push`, лентада
/// `Navigator.push`).
typedef MyShopPush = Future<void> Function(Widget screen);

/// «Менинг дўконим»га кириш — ЯГОНА оқим. Икки жойдан чақирилади:
///  · «＋» → «Онлайн Дўкон очиш» / «Менинг дўконим»;
///  · AVAGram видеосидаги «Дўкон» тугмаси (эганинг ўз видеоси).
///
/// Дўкони бор эга ([MyShopPresence.any]) — дўконлар рўйхатига ([MyShopScreen]);
/// қўшимча дўкон очиш ёпиқ ва бошқа дўкони йўқ бўлса — тўғридан-тўғри асосий
/// дўконга. [preferMain] (видеодаги «Дўкон» тугмаси) — ҳар доим тўғридан-тўғри
/// асосий дўконга (бошқа дўконлар рўйхатисиз). Дўкони йўқ эга — биринчи кириш: ном (ихтиёрий)
/// + «қаерга қўшамиз?», кейин асосий дўкон (Аҳоли бозорида форма дарҳол
/// очилади, ёпилгач рўйхат ва «Янги маҳсулот» тугмаси турибди).
///
/// [phone] — каноник телефон (9+ рақам); текширувни чақирувчи қилади.
/// `canCreateShop`, `shopTargets`, `askFirstShop`, `saveName` — тест учун.
/// [shopTargets] — биринчи киришда танлаш мумкин бўлган бозорлар; берилмаса
/// модул ҳолатидан ([HomeModuleGate.canOpen]) ҳисобланади (аудит Н-4).
Future<void> openMyShop(
  BuildContext context, {
  required String phone,
  required MyShopPresence presence,
  required MyShopPush push,
  bool preferMain = false,
  bool? canCreateShop,
  Set<AvaShopTarget>? shopTargets,
  Future<AvaFirstShop?> Function(BuildContext context, Set<AvaShopTarget> allowed)?
      askFirstShop,
  Future<void> Function(String phone, String name)? saveName,
}) async {
  if (presence.any) {
    // Бизнес харитаси модули ёпиқ бўлса «Янги дўкон» чиқмайди.
    final canCreate = canCreateShop ?? ServiceConfigHolder.isVisible('business_map');
    if (preferMain) {
      // Видеодаги «Дўкон» тугмаси: рўйхатсиз, тўғридан-тўғри асосий дўкон.
      await push(MainShopScreen(phone: phone, initialSegment: presence.initialSegment));
    } else if (canCreate || presence.otherShops > 0) {
      await push(MyShopScreen(
        phone: phone,
        initialSegment: presence.initialSegment,
        canCreateShop: canCreate,
      ));
    } else {
      await push(MainShopScreen(
        phone: phone,
        initialSegment: presence.initialSegment,
      ));
    }
    return;
  }

  final allowed = shopTargets ?? avaOpenableShopTargets(HomeModuleGate.canOpen);
  if (allowed.isEmpty) {
    // Ҳимоя: «＋» қатори `AvaCreateGates` да аслида қулф; бошқа йўлдан келса —
    // модул хабари (Тез кунда / мавжуд эмас), варақ очилмайди.
    HomeModuleGate.onTapBlocked(context, kAvaShopTargetModules[AvaShopTarget.retail]!);
    return;
  }
  final first = await (askFirstShop ??
      (ctx, a) => showAvaFirstShopSheet(ctx, allowed: a))(context, allowed);
  if (first == null || !context.mounted) return;
  // Ҳимоя: рухсат этилмаган бозор қайтса (бўлмаслиги керак) — очилмайди.
  if (!allowed.contains(first.target)) return;
  if (first.name.isNotEmpty) {
    try {
      await (saveName ?? saveMainShopName)(phone, first.name);
    } catch (e) {
      // Ном асосий иш эмас: ёзилмаса ҳам дўкон очилади, ном кейин қўйилади.
      debugPrint('[OpenMyShop] name save failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('my_shop_name_save_failed'))),
        );
      }
    }
  }
  if (!context.mounted) return;
  final retail = first.target == AvaShopTarget.retail;
  await push(MainShopScreen(
    phone: phone,
    initialSegment: retail ? 0 : 1,
    openAddOnStart: retail,
  ));
}

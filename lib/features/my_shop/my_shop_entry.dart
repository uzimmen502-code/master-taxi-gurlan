import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/service_config_holder.dart';
import '../../core/utils/formatters.dart';
import '../business_map/domain/business.dart';
import '../business_map/screens/business_product_form_screen.dart';
import 'my_shop_presence.dart';
import 'open_my_shop.dart';
import 'screens/main_shop_screen.dart';

/// Аҳоли бозоридан («＋» ва «Менинг дўконим» тугмалари) дўконга кириш йўллари. Ягона омбор
/// (`tv_shop_items`): бозордаги «＋» ҳам, дўкондаги «Маҳсулот қўшиш» ҳам БИР ХИЛ форма.

Future<String> _ownPhone() async {
  final prefs = await SharedPreferences.getInstance();
  return canonicalPhoneId(prefs.getString('user_phone') ?? '');
}

void _needPhone(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.tr('need_phone_profile'))),
  );
}

/// Янги маҳсулот формаси (эганинг ўз дўкони). Телефон йўқ бўлса — содда хабар.
/// `ownPhone`, `loadName`, `push` — тест учун.
Future<void> openNewProduct(
  BuildContext context, {
  Future<String> Function()? ownPhone,
  Future<String> Function(String phone)? loadName,
  MyShopPush? push,
}) async {
  final phone = await (ownPhone ?? _ownPhone)();
  if (!context.mounted) return;
  if (phoneDigits(phone).length < 9) {
    _needPhone(context);
    return;
  }
  var name = '';
  try {
    name = await (loadName ?? loadMainShopName)(phone);
  } catch (e) {
    // Ном ҳамроҳ маълумот: ўқилмаса форма «Менинг дўконим» номи билан очилади.
    debugPrint('[OpenNewProduct] shop name unavailable: $e');
  }
  if (!context.mounted) return;
  final screen = BusinessProductFormScreen(
    business: Business.ownShop(
      ownerId: phone,
      name: name.isNotEmpty ? name : context.tr('my_shop_title'),
      districtId: ServiceConfigHolder.districtId.trim(),
    ),
  );
  await (push ?? (s) => _push(context, s))(screen);
}

/// «Менинг дўконим» (дўконлар рўйхати ёки биринчи кириш) — бозор экранидан.
Future<void> openMyShopFromMarket(
  BuildContext context, {
  Future<String> Function()? ownPhone,
  Future<MyShopPresence> Function(String phone)? loadPresence,
  MyShopPush? push,
}) async {
  final phone = await (ownPhone ?? _ownPhone)();
  if (!context.mounted) return;
  if (phoneDigits(phone).length < 9) {
    _needPhone(context);
    return;
  }
  final presence = await (loadPresence ?? MyShopPresence.load)(phone);
  if (!context.mounted) return;
  await openMyShop(
    context,
    phone: phone,
    presence: presence,
    push: push ?? (s) => _push(context, s),
  );
}

Future<void> _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));

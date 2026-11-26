import 'package:flutter/material.dart';

import '../../markets/open_market.dart';
import '../domain/sm_holiday.dart';
import 'sm_basket_screen.dart';

/// Байрам/туғилган кун контекстидан саватчани очиш (эга 2026-11-28): аввалги байрамлар рўйхати ва 3 тайёр саватча
/// ЎРНИГА — ягона «Менинг ҳафталик харид саватчам» (сарлавҳа туғилган кун олдидан ўзгаради). Буюртма манбаи
/// 'holiday'. [gift] — совға олдиндан тўлдирилади (қариндош телефони бўлса) ёки push «совға» режими.
/// [occasionId] — буюртмага ёзилади (аналитика); [birthday] — фақат мослик учун (сарлавҳани сана ҳал қилади).
Future<void> openHolidayBasket(
  NavigatorState nav, {
  String? occasionId,
  bool birthday = false,
  SmHolidayCheckout? gift,
}) =>
    openSmBasket(nav, holiday: true, checkout: holidayBasketCheckout(occasionId: occasionId, birthday: birthday, gift: gift));

/// Байрам контекстидан расмийлаштириш маълумоти (тоза — тест учун): совға сақланади, байрам id — берилгани ёки
/// туғилган кунда `birthday`; манба — 'holiday'.
SmHolidayCheckout holidayBasketCheckout({String? occasionId, bool birthday = false, SmHolidayCheckout? gift}) {
  final occ = occasionId ?? (birthday ? kHolidayKindBirthday : '');
  final base = (gift ?? const SmHolidayCheckout()).copyWith(origin: 'holiday');
  return occ.isEmpty ? base : base.copyWith(occasionId: occ);
}

/// Байрам мақсади бозор бўлса (Қурбон ҳайит → Мол бозори, эга 2026-11-27, ўзгармаган) — мавжуд [openMarket]
/// (модул дарвозаси шу ерда).
Future<void> openHolidayMarketTarget(BuildContext context, HolidayTarget t, {bool replace = false}) => openMarket(
      context,
      t.market,
      initialCategory: t.initialCategory,
      push: replace ? (s) => Navigator.of(context).pushReplacement<void, void>(MaterialPageRoute(builder: (_) => s)) : null,
    );

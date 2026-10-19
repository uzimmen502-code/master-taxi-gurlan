// Муассаса тури (D-REST-41, эга 2026-10-19): уй ошпази учун фақат «Уй таоми» (автомат); кафе-ресторан эгаси
// Кафе / Ресторан / Чойхона дан бирини ўзи танлайди. Фақат ЯНГИ рўйхатдан ўтганларга; эски ҳужжатларда майдон
// ЙЎҚ — ёрлиқ кўрсатилмайди. Қиймат серверда (`functions/restaurant_orders.js` `VENUE_CHOICES`, индекс
// `VENUE_TYPES`) ва `firestore.rules` да ҳам шу рўйхат; мослик тест билан қулфланган.

abstract final class VenueType {
  static const home = 'home';
  static const cafe = 'cafe';
  static const restaurant = 'restaurant';
  static const chaikhana = 'chaikhana';

  /// Барча тўғри қийматлар (индекс ва `restaurants` ҳужжатида).
  static const all = [home, cafe, restaurant, chaikhana];

  /// Кафе-ресторан эгаси танлайдиганлар (уй ошпази автомат `home`).
  static const choices = [cafe, restaurant, chaikhana];

  static bool isValid(String? v) => v != null && all.contains(v);

  /// Матн калити (3 тилда): `restaurants_venue_<тур>`.
  static String l10nKey(String type) => 'restaurants_venue_$type';

  /// Ҳужжатдаги қиймат: тўғри бўлса ўзи, акс ҳолда бўш (ёрлиқ йўқ).
  static String parse(Object? v) => v is String && isValid(v) ? v : '';
}

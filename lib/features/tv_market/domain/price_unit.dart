// Таклиф (маҳсулот/хизмат) нархининг бирлиги — «Менинг бизнесим» занжири S0 шартномаси (2026-11-03).
//
// Ҳолат: МОДЕЛ + ФОРМАТТЕР. `tv_shop_items.priceUnit` майдони, форма танлови ва Firestore rules — S2 слайсида
// (бу ерда TvShopItem ва rules ЎЗГАРТИРИЛМАЙДИ). Wire қийматлари S2 rules рўйхати билан бир хил бўлиши шарт:
//   '' (белгиланган нарх) · from · hour · day · month · session · person · kg · m2 · piece · negotiable
// Бўш/номаълум қиймат → [PriceUnit.fixed]: эски ҳужжат ва эски APK бузилмайди (26-банд).
// Пул — бутун сўм (8-банд); валюта белгиси — ягона [kCurrencySum] ([formatMoney]).
//
// Бирликлар рўйхати — PROPOSED (эга кўриб чиқади).

import '../../../core/utils/formatters.dart';

enum PriceUnit {
  /// Белгиланган нарх: «150 000 сўм».
  fixed(''),

  /// Бошланғич нарх: «дан 150 000 сўм» (мавжуд `home_price_from` андозаси — Улгуржи билан бир хил).
  from('from'),
  hour('hour'),
  day('day'),
  month('month'),
  session('session'),
  person('person'),
  kg('kg'),
  m2('m2'),

  /// Дона — мавжуд `piece` калити (дона / dona / шт).
  piece('piece'),

  /// Нарх келишилади (мавжуд `yuk_negotiable` калити).
  negotiable('negotiable');

  const PriceUnit(this.wire);

  /// Firestore'да сақланадиган қиймат (`fixed` — бўш сатр; S2 да бўш бўлса майдон умуман ёзилмайди).
  final String wire;

  /// Танлов рўйхатидаги (форма) номи.
  String get labelKey => 'price_unit_$name';

  /// Нархдан кейинги қисқа қўшимча («/ соат») калити; `fixed`, `from`, `negotiable` учун `null`.
  String? get suffixKey => switch (this) {
        PriceUnit.fixed || PriceUnit.from || PriceUnit.negotiable => null,
        PriceUnit.piece => 'piece',
        _ => 'price_unit_short_$name',
      };

  /// Бўш, `null`, номаълум ёки сатр бўлмаган қиймат — [fixed].
  static PriceUnit fromWire(Object? raw) {
    if (raw is! String) return PriceUnit.fixed;
    final s = raw.trim();
    for (final u in values) {
      if (u.wire == s) return u;
    }
    return PriceUnit.fixed;
  }

  static List<String> get wires => [for (final u in values) u.wire];
}

/// Таклиф нархининг ЯГОНА кўриниши (7-банд) — карточка, варақ, каталог, чат сарлавҳаси шуни ишлатади.
///
/// * `price > 0`: `fixed` → «150 000 сўм»; `from` → «дан 150 000 сўм» (ru «от 150 000 сўм»);
///   бирликли → «150 000 сўм / соат»; `negotiable` → «150 000 сўм · Келишилади».
/// * `price <= 0`: `negotiable` → «Келишилади»; қолганлари → `''` (нарх кўрсатилмайди — ҳозирги хулқ).
///
/// [tr] — `context.tr` (тестда — JSON'дан ўқувчи функция).
String formatOfferPrice(int price, PriceUnit unit, String Function(String key) tr) {
  if (price <= 0) {
    return unit == PriceUnit.negotiable ? tr('yuk_negotiable') : '';
  }
  final money = formatMoney(price);
  switch (unit) {
    case PriceUnit.fixed:
      return money;
    case PriceUnit.from:
      return '${tr('home_price_from')} $money';
    case PriceUnit.negotiable:
      return '$money · ${tr('yuk_negotiable')}';
    default:
      return '$money / ${tr(unit.suffixKey!)}';
  }
}

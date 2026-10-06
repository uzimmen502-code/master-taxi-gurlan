import '../core/utils/formatters.dart';

/// Улгуржи нарх поғонаси: `minQty`дан бошлаб шу нархда сотилади
/// (масалан 1–9 дона — 10 000 сўм, 10+ дона — 9 000 сўм).
///
/// БИТТА таъриф иккала бозор учун (2026-09-29): аввал у фақат
/// `wholesale_product.dart` ичида эди, энди AVA дўкони товари ҳам шу
/// поғоналар билан сотилади ва Улгуржи лентасида кўринади. Иккита
/// нусха бўлса саралаш ва «дан ...» қоидаси иккита жойда айрилиб
/// кетар эди.
class PriceTier {
  const PriceTier({required this.minQty, required this.price});

  final int minQty;
  final int price;

  factory PriceTier.fromMap(Map<String, dynamic> m) => PriceTier(
        minQty: (m['minQty'] as num?)?.toInt() ?? 1,
        price: (m['price'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {'minQty': minQty, 'price': price};

  /// «10+ дона: 9 000 сўм» — қисқа кўриниш (admin/тафсилот учун).
  /// [currency] — Хитой бозорида маҳсулотнинг ўз валютаси.
  String label(String unit, [String currency = kCurrencySum]) =>
      '$minQty+ $unit: ${formatPrice(price)} $currency';
}

/// Поғоналарни `minQty` бўйича ўсиш тартибида саралайди (нотўғри
/// қийматлар четлаб ўтилади).
List<PriceTier> sortPriceTiers(List<PriceTier> tiers) {
  final clean = tiers.where((t) => t.minQty >= 1 && t.price > 0).toList()
    ..sort((a, b) => a.minQty.compareTo(b.minQty));
  return clean;
}

/// AVA дўкони — нарх қоидаси версияси (`orderBase.pricingVersion`).
///
/// 2 — улгуржи поғоналари (1.0.33+). Сервер версиясиз буюртмага (эски
/// илова) эски ягона нархни қўллайди. Қоида:
/// `functions/platform_pricing.js` билан АЙНАН бир хил (паритет тести:
/// `functions/test/fixtures/platform_price_vectors.json`).
const int kPlatformPricingVersion = 2;

/// Ўрта поғона (10–50 дона) бошланиши ва юқори поғона (50+).
const int kPlatformMidMinQty = 10;
const int kPlatformHighMinQty = 50;

/// Ҳисобланган поғоналар ФАҚАТ ЭСКИ товарларга: `createdAt` шу вақтдан
/// ОЛДИН (2026-10-07 00:00 Тошкент) ёки йўқ. Янги товарда поғонани
/// қўшаётган одамнинг ЎЗИ белгилайди (эга қарори, 2026-10-06). Сервер:
/// `DERIVED_TIERS_CUTOFF_MS` (`functions/platform_pricing.js`).
final DateTime kPlatformDerivedTiersCutoff = DateTime.utc(2026, 10, 6, 19);

/// 1–9 дона: +5%, 50+ дона: −5% (эга қарори, 2026-10-06).
const int kPlatformLowMarkupPct = 5;
const int kPlatformHighDiscountPct = 5;

/// ceil(a × num / den) — фақат бутун сонлар.
int _ceilMulDiv(int a, int num, int den) => (a * num + den - 1) ~/ den;

/// Базадаги нарх — ЎРТА поғона (10–50 дона) нархи; қолган иккаласи
/// ундан ҳисобланади, юқорига бутун сўмгача. Нарх йўқ бўлса — бўш.
List<PriceTier> derivedPriceTiers(int midPrice) {
  if (midPrice <= 0) return const [];
  return [
    PriceTier(
      minQty: 1,
      price: _ceilMulDiv(midPrice, 100 + kPlatformLowMarkupPct, 100),
    ),
    PriceTier(minQty: kPlatformMidMinQty, price: midPrice),
    PriceTier(
      minQty: kPlatformHighMinQty,
      price: _ceilMulDiv(midPrice, 100 - kPlatformHighDiscountPct, 100),
    ),
  ];
}

/// Firestore'даги `priceTiers` рўйхатини ўқийди.
List<PriceTier> parsePriceTiers(dynamic raw) {
  if (raw is! List) return const [];
  return sortPriceTiers(
    raw
        .whereType<Map>()
        .map((m) => PriceTier.fromMap(Map<String, dynamic>.from(m)))
        .toList(),
  );
}

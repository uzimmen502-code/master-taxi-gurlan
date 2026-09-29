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

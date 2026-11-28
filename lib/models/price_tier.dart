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

/// [qty] га тўғри келадиган поғона индекси: `qty >= minQty` бўлган ОХИРГИси
/// ([tiers] `minQty` бўйича саралаган). [qty] биринчи поғонадан кичик
/// бўлса — 0 (энг паст поғона). Поғона йўқ бўлса — -1.
///
/// Нарх қоидасининг ЯГОНА нусхаси (CLAUDE.md 7): AVA товари
/// (`PlatformProduct.priceForQty`), сотувчи товари ва сервер
/// (`functions/platform_pricing.js`) шу қоида билан бир хил.
int activeTierIndex(List<PriceTier> tiers, int qty) {
  if (tiers.isEmpty) return -1;
  final i = tiers.lastIndexWhere((t) => qty >= t.minQty);
  return i < 0 ? 0 : i;
}

/// [qty] даги бир дона нархи; поғона йўқ бўлса `null`.
int? tierPriceForQty(List<PriceTier> tiers, int qty) {
  final i = activeTierIndex(tiers, qty);
  return i < 0 ? null : tiers[i].price;
}

/// [qty] дан кейинги (арзонроқ) поғона; охирги поғонада — `null`.
PriceTier? nextTierAfter(List<PriceTier> tiers, int qty) {
  final i = activeTierIndex(tiers, qty);
  if (i < 0 || i + 1 >= tiers.length) return null;
  return tiers[i + 1];
}

/// Поғона оралиғи матни: «1–9», «10–49», охиргиси «50+». Оралиқ кейинги
/// поғона бошланишидан келиб чиқади (`priceForQty` қоидаси: `qty >= minQty`
/// кейинги поғонага ўтади, шунинг учун чегара `minQty − 1`).
String tierRangeText(List<PriceTier> tiers, int i) {
  if (i < 0 || i >= tiers.length) return '';
  final from = tiers[i].minQty;
  if (i + 1 >= tiers.length) return '$from+';
  final to = tiers[i + 1].minQty - 1;
  return to > from ? '$from–$to' : '$from';
}

/// AVA дўкони — илова юборадиган `orderBase.pricingVersion`.
///
/// Эга 2026-11-28: нарх ЯГОНА (ҳисобланган поғоналар 1–9 +5 % / 50+ −5 %
/// олиб ташланди). Сервер (`functions/platform_pricing.js`,
/// SERVER_PRICING_VERSION 3) бу қийматни эътиборсиз қолдиради ва буюртмага
/// ўз версиясини ёзади; қиймат эски сервер билан мослик учун ўзгармади.
const int kPlatformPricingVersion = 2;

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

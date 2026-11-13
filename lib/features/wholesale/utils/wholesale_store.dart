import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/formatters.dart';
import '../models/wholesale_product.dart';
import '../models/wholesale_seller.dart';

/// Улгуржи/Хитой «сотувчи магазини» (эга, 2026-11-13, 1–2-босқич):
/// «Сотувчилар» таби рўйхати ва қидируви. Соф функциялар — Firestore'сиз
/// тестланади. Магазин ичида тартиблаш тугмалари ЙЎҚ (эга, «В»): доим янгиси биринчи.

/// Хитойда «Сотувчилар» таби фақат шунча ва ундан кўп сотувчи бўлса (эга, 2026-11-13).
const int kChinaSellersTabMin = 2;

/// Фаол маҳсулотлардаги турли сотувчилар сони (таб кўринишини ҳал қилиш учун).
int distinctActiveSellers(Iterable<WholesaleProduct> products, {required String market}) => products
    .where((p) => p.isActive && p.belongsToMarket(market))
    .map((p) => canonicalPhoneId(p.sellerId))
    .where((id) => id.isNotEmpty)
    .toSet()
    .length;

/// «Сотувчилар» табидаги битта қатор.
class WholesaleStoreSummary {
  const WholesaleStoreSummary({required this.seller, required this.productCount});

  final WholesaleSeller seller;

  /// Шу бозордаги ФАОЛ маҳсулотлар сони.
  final int productCount;
}

/// «Сотувчилар» таби (эга қарори 2026-11-13): ФАҚАТ тасдиқланган ва шу
/// бозорда камида битта фаол маҳсулоти бор сотувчилар. Тартиб: маҳсулоти
/// кўпи биринчи, кейин ном бўйича.
List<WholesaleStoreSummary> buildStoreSummaries(
  Iterable<WholesaleProduct> products,
  Map<String, WholesaleSeller> sellers, {
  required String market,
}) {
  final counts = <String, int>{};
  for (final p in products) {
    if (!p.isActive || !p.belongsToMarket(market)) continue;
    final id = canonicalPhoneId(p.sellerId);
    if (id.isEmpty) continue;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  final out = <WholesaleStoreSummary>[];
  counts.forEach((id, n) {
    final s = sellers[id];
    if (s == null || !s.isApproved) return;
    out.add(WholesaleStoreSummary(seller: s, productCount: n));
  });
  out.sort((a, b) {
    final byCount = b.productCount.compareTo(a.productCount);
    if (byCount != 0) return byCount;
    return a.seller.companyName.toLowerCase().compareTo(b.seller.companyName.toLowerCase());
  });
  return out;
}

/// Сотувчини номи, эга исми ёки шаҳри бўйича қидириш (кирилл↔лотин —
/// [CatalogSearch]). [placeOf] — сотувчининг вилоят/туман номи (тилга қараб).
List<WholesaleStoreSummary> filterStores(
  List<WholesaleStoreSummary> stores,
  String query,
  String Function(WholesaleSeller s) placeOf,
) {
  if (CatalogSearch.normalize(query).isEmpty) return stores;
  return stores
      .where((e) => CatalogSearch.matches(
            query,
            [e.seller.companyName, e.seller.ownerName, placeOf(e.seller)],
          ))
      .toList(growable: false);
}

/// Логотип ўрнига бош ҳарфлар: «Ун-Савдо» → «УС», «AVA» → «AV».
String storeInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'[\s\-_.]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// «AVA'да 10.2026 дан» учун ой ва йил (ой номлари тилга боғлиқ эмас).
String storeSinceLabel(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  return '${l.month.toString().padLeft(2, '0')}.${l.year}';
}

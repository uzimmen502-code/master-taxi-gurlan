import '../../ads/utils/ad_search_text.dart';
import '../models/wholesale_product.dart';

/// Улгуржи тафсилотидаги «Ўхшаш маҳсулотлар» (бошқа сотувчилар) ва
/// «Сотувчининг бошқа маҳсулотлари» рўйхатлари.
///
/// Рўйхат ЛЕНТАДА аллақачон юкланган каталогдан олинади — қўшимча
/// Firestore сўрови йўқ (CLAUDE.md 36–37).

/// Фақат ФАОЛ ва шу бозордаги (Улгуржи/Хитой аралашмайди) маҳсулотлар.
Iterable<WholesaleProduct> _eligible(
  WholesaleProduct current,
  Iterable<WholesaleProduct> pool,
) =>
    pool.where((p) =>
        p.id != current.id &&
        p.isActive &&
        p.belongsToMarket(current.market));

/// Ўхшаш — БОШҚА сотувчиларнинг шу номли товарлари (нарх солиштириш учун).
/// Ном токенлари (икки ёзувда — кирилл/лотин) кесишиши шарт: алоқасиз товар
/// «ўхшаш» бўлиб чиқмасин. Тартиб: кўпроқ умумий сўз, кейин энг паст поғона
/// нархи арзони, кейин ном.
List<WholesaleProduct> similarWholesale(
  WholesaleProduct current,
  Iterable<WholesaleProduct> pool, {
  int limit = 12,
}) {
  final mine = AdSearchText.buildTokens(current.title, '').toSet();
  if (mine.isEmpty) return const [];
  final scored = <(WholesaleProduct, int)>[];
  for (final p in _eligible(current, pool)) {
    if (p.sellerId == current.sellerId) continue;
    final theirs = AdSearchText.buildTokens(p.title, '');
    final overlap = theirs.where(mine.contains).length;
    if (overlap > 0) scored.add((p, overlap));
  }
  scored.sort((a, b) {
    final byOverlap = b.$2.compareTo(a.$2);
    if (byOverlap != 0) return byOverlap;
    final byPrice = a.$1.basePrice.compareTo(b.$1.basePrice);
    if (byPrice != 0) return byPrice;
    return a.$1.titleLower.compareTo(b.$1.titleLower);
  });
  return scored.take(limit).map((e) => e.$1).toList(growable: false);
}

/// Шу сотувчининг бошқа фаол маҳсулотлари (янгиси биринчи).
List<WholesaleProduct> sellerOthers(
  WholesaleProduct current,
  Iterable<WholesaleProduct> pool, {
  int limit = 12,
}) {
  if (current.sellerId.isEmpty) return const [];
  final out = _eligible(current, pool)
      .where((p) => p.sellerId == current.sellerId)
      .toList()
    ..sort((a, b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
  return out.take(limit).toList(growable: false);
}

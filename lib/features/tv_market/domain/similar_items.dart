import '../../../core/utils/catalog_search.dart';
import '../models/tv_shop.dart';

/// Маҳсулот экранидаги «Ўхшаш маҳсулотлар» (2026-10-25, 3-босқич): ЯНГИ ЎҚИШСИЗ — чақирувчи экранда аллақачон
/// юкланган рўйхатдан ([pool]: Аҳоли бозори лентаси, дўкон каталоги, харита объекти маҳсулотлари) танланади (36-банд).
///
/// Қоида: фақат фаол, ўзидан бошқа, номи/тавсифи бўйича ўхшаши (`CatalogSearch` — бозор қидируви билан бир хил);
/// тенг бўлса шу йўналиш/шу сотувчи ва шу тур олдин. Ўхшаши бўлмаса — бўш (тасодифий тўлдириш йўқ).
List<TvShopItem> similarItems(TvShopItem item, Iterable<TvShopItem> pool, {int max = 10}) {
  // Номнинг ҳар бир маъноли сўзи алоҳида (камида 3 белги): «Қизил кўйлак» → «Кўк кўйлак» ҳам ўхшаш
  // (`CatalogSearch.score` бутун сўровни AND билан текширади — бу ерда сўзлар бўйича йиғинди).
  final words = CatalogSearch.normalize(item.title).split(' ').where((w) => w.length >= 3).toSet();
  if (words.isEmpty) return const [];
  final scored = <(TvShopItem, int)>[];
  final seen = <String>{item.id};
  for (final c in pool) {
    if (!c.isActive || !seen.add(c.id)) continue;
    var s = 0;
    for (final w in words) {
      s += CatalogSearch.score(w, title: c.title, extra: [c.description]);
    }
    if (s <= 0) continue;
    var bonus = 0;
    if (c.kind == item.kind) bonus += 1;
    if (c.ownerPhone == item.ownerPhone) bonus += 1;
    if (c.ownerPhone == item.ownerPhone && c.businessId == item.businessId) bonus += 1;
    scored.add((c, s * 10 + bonus));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final e in scored.take(max)) e.$1];
}

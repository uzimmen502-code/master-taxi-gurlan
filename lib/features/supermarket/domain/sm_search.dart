/// Супермаркет қидируви: гуруҳ номлари (3 тил) + синонимлар + таклиф номлари/навлари.
/// Кирилл ↔ лотин ва янги лотин ҳарфлари мавжуд [CatalogSearch.matches] орқали (4-банд).
library;

import '../../../core/utils/catalog_search.dart';
import 'sm_offer.dart';
import 'sm_taxonomy.dart';

List<SmGroup> smSearchGroups(
  SmTaxonomy taxonomy,
  Map<String, List<SmOffer>> offersByGroup,
  String query,
) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final out = <SmGroup>[];
  for (final c in taxonomy.categories) {
    for (final g in c.groups) {
      final offers = offersByGroup[g.id] ?? const <SmOffer>[];
      if (!offers.any((o) => o.visible)) continue;
      final fields = <String>[
        ...g.names.values,
        ...g.synonyms,
        for (final o in offers)
          if (o.visible) ...[o.name, ...o.varietyNames.values],
      ];
      if (CatalogSearch.matches(q, fields)) out.add(g);
    }
  }
  return out;
}

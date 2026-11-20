/// «Буни ҳам қўшасизми?» (2-босқич, эга 2026-11-21) ва «Тезкор харид» танлови — тоза функциялар.
library;

import 'sm_cart.dart';
import 'sm_offer.dart';
import 'sm_taxonomy.dart';

const int kSmCrossSellMax = 6;

/// Саватдаги гуруҳларнинг `pairs`и → ҳар жуфт гуруҳдан энг арзон мавжуд таклиф; саватдаги таклиф ҳам,
/// саватда аллақачон бор гуруҳ ҳам таклиф қилинмайди. Нарх ўсиши бўйича, кўпи билан [limit] та.
List<SmOffer> smCrossSell(
  SmCart cart, {
  required SmTaxonomy taxonomy,
  required Map<String, SmOffer> offers,
  required Map<String, List<SmOffer>> offersByGroup,
  int limit = kSmCrossSellMax,
}) {
  final inCart = {for (final l in cart.lines) l.productId};
  final cartGroups = {for (final id in inCart) if (offers[id] case final o?) o.groupId};
  final candidates = <String>[];
  for (final g in cartGroups) {
    for (final p in taxonomy.group(g)?.pairs ?? const <String>[]) {
      if (!cartGroups.contains(p) && !candidates.contains(p)) candidates.add(p);
    }
  }
  final out = <SmOffer>[];
  for (final g in candidates) {
    final pool = (offersByGroup[g] ?? const <SmOffer>[]).where((o) => o.available && !inCart.contains(o.id));
    final sorted = smSortOffersAsc(pool);
    if (sorted.isNotEmpty) out.add(sorted.first);
  }
  out.sort((a, b) {
    final c = a.price.compareTo(b.price);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return out.take(limit).toList(growable: false);
}

/// «Тезкор харид»да «＋» қайси таклифни қўшади: 1) шу сессияда танлангани (сотувда бўлса); 2) саватдаги
/// шу гуруҳ таклифи; 3) гуруҳда ягона мавжуд таклиф. Йўқ — `null` (ихчам ойна очилади).
SmOffer? smQuickSelected(
  String groupId, {
  required Map<String, String> picks,
  required SmCart cart,
  required Map<String, SmOffer> offers,
  required Map<String, List<SmOffer>> offersByGroup,
}) {
  final picked = offers[picks[groupId] ?? ''];
  if (picked != null && picked.available && picked.groupId == groupId) return picked;
  for (final l in cart.lines) {
    final o = offers[l.productId];
    if (o != null && o.groupId == groupId && o.available) return o;
  }
  final avail = (offersByGroup[groupId] ?? const <SmOffer>[]).where((o) => o.available).toList();
  return avail.length == 1 ? avail.first : null;
}

/// «Тезкор харид» рўйхати: категория фильтри ([categoryId] бўш — ҳаммаси) ва сотувда таклифи бор гуруҳлар.
List<SmGroup> smQuickGroups(SmTaxonomy tx, Map<String, List<SmOffer>> offersByGroup, {String categoryId = ''}) => [
      for (final c in tx.categories)
        if (categoryId.isEmpty || c.id == categoryId)
          for (final g in c.groups)
            if ((offersByGroup[g.id] ?? const <SmOffer>[]).any((o) => o.visible)) g,
    ];

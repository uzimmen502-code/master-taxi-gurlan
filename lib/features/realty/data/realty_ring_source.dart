import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_districts_cache.dart';
import '../../../core/geo/ring_query.dart';
import '../../../models/realty_listing.dart';

/// Уй-жой бозори — «ҳалқалар» сўрови (7-босқич, эга 2026-11-15; GeoMode.rings).
///
/// Сервер филтри: `status == 'active'` + `tier` (таб: ОДДИЙ/РЕКЛАМА/СРОЧНО) + `districtId in [≤30]` +
/// `orderBy(createdAt desc)` — мавжуд индекс `status+tier+districtId+createdAt` (realty_repository.dart изоҳи).
/// Сотиш/Ижара ва муддати ўтганлар — КЛИЕНТДА (аввалги `_live` қоидаси; янги индекс керак эмас).
@immutable
class RealtyRingFilter {
  const RealtyRingFilter({this.tier, this.deal, this.propertyType});

  /// `null` — барча даражалар (харита; индекс `status+districtId+createdAt`).
  final RealtyTier? tier;

  /// `null` — Сотиш ҳам, Ижара ҳам.
  final RealtyDeal? deal;

  /// `null` — барча турлар. Сотиш/Ижара каби КЛИЕНТДА (эга 2026-11-19):
  /// янги индекс керак эмас; тури кўрсатилмаган эски эълонлар тур
  /// танланганда кўринмайди.
  final String? propertyType;

  Map<String, Object> get equals => {if (tier != null) 'tier': tier!.key};

  /// Клиент филтри — лентада кўринадими.
  bool shows(RealtyListing r, {DateTime? now}) {
    final exp = r.expiresAt;
    if (exp != null && exp.isBefore(now ?? DateTime.now())) return false;
    if (propertyType != null && r.extras.propertyType != propertyType) return false;
    return deal == null || r.deal == deal;
  }

  @override
  bool operator ==(Object other) =>
      other is RealtyRingFilter &&
      other.tier == tier &&
      other.deal == deal &&
      other.propertyType == propertyType;

  @override
  int get hashCode => Object.hash(tier, deal, propertyType);
}

abstract class RealtyListingSource {
  RingFetcher<RealtyListing> fetcher(RealtyRingFilter filter);
  Future<List<String>> districtsOf(String regionId);
}

class FirestoreRealtyListingSource implements RealtyListingSource {
  FirestoreRealtyListingSource({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('realty_listings');

  @override
  RingFetcher<RealtyListing> fetcher(RealtyRingFilter filter) {
    final raw = firestoreRingFetcher(collection: _col, equals: filter.equals);
    return (districtIds, startAfter, limit) async {
      final res = await raw(districtIds, startAfter, limit);
      final out = <RealtyListing>[];
      for (final d in res.items) {
        try {
          out.add(RealtyListing.fromDoc(d));
        } catch (e) {
          debugPrint('[RealtyRings] skip ${d.id}: $e');
        }
      }
      // Курсор — сервер ҳужжати (клиент филтри саҳифа ҳажмини бузмасин: тўлиқ саҳифа қайтади).
      return RingFetchResult(out, res.cursor);
    };
  }

  @override
  Future<List<String>> districtsOf(String regionId) => GeoDistrictsCache.districtIdsOf(regionId);
}

/// Харита учун: ҳалқа тартибида [max] тагача эълон (сукут — Республика, яқиндан узоққа). Ҳар элемент ҳалқа
/// рақами билан — харита камераси фойдаланувчи туманидаги (ring 0) эълонларга қаратилади.
Future<List<RingItem<RealtyListing>>> loadRealtyRings(
  RealtyListingSource source,
  GeoScope scope, {
  RealtyDeal? deal,
  int max = 300,
  int pageSize = 50,
}) async {
  final filter = RealtyRingFilter(deal: deal);
  final pager = RingPager<RealtyListing>(
    plan: ringPlanFor(scope),
    fetch: source.fetcher(filter),
    districtsOf: source.districtsOf,
  );
  final out = <RingItem<RealtyListing>>[];
  while (pager.hasMore && out.length < max) {
    final page = await pager.next(pageSize);
    out.addAll(page.where((r) => filter.shows(r.item)));
  }
  return out.length > max ? out.sublist(0, max) : out;
}

/// Камера қаратиладиган эълонлар: энг яқин бўш бўлмаган ҳалқа (одатда фойдаланувчи тумани).
Set<String> nearestRingIds(List<RingItem<RealtyListing>> items) {
  if (items.isEmpty) return const {};
  var best = items.first.ring;
  for (final r in items) {
    if (r.ring < best) best = r.ring;
  }
  return {for (final r in items) if (r.ring == best) r.item.id};
}
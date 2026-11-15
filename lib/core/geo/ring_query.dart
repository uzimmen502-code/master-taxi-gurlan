/// «Ҳалқалар» сўров мотори (GeoMode.rings, эга 2026-11-15).
///
/// Сукут: БАРЧА эълонлар Республика бўйича, яқиндан узоққа —
///   ring 0: фойдаланувчи тумани;
///   ring 1: вилоятнинг қолган туманлари;
///   ring 2+: бошқа вилоятлар, марказлари орасидаги масофа бўйича
///            ([regionRingOrder]).
/// Фойдаланувчи ҳудудни ЎЗИ танласа (туман/вилоят) — фақат шу ҳудуд (битта ҳалқа).
///
/// Тузилиш: тоза режа ([buildRingPlan] / [ringPlanFor]) → тоза пейжер
/// ([RingPager], сўровни [RingFetcher] орқали чақиради) → юпқа Firestore
/// адаптери ([firestoreRingFetcher]). Ҳалқа ичида тартиб — `orderField` desc.
///
/// Сўров шакли (ҳар бўлак): `status == 'active'` + қўшимча тенглик филтрлари +
/// `<districtField> in [≤30]` + `orderBy(<orderField>, desc)` + `limit`.
/// Туман ID'си йўқ эски ҳужжатлар бу режимда КЎРИНМАЙДИ (geo_query.dart'даги
/// `legacy` оқими бу ерда йўқ).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/geo_area.dart' show GeoDistrict;
import 'geo_context.dart';
import 'geo_districts_cache.dart';
import 'module_geo_policy.dart' show GeoLevel;
import 'region_centers.dart';

/// Режанинг бир қадами. Туманлар рўйхати кеч аниқланади (вилоят туманлари
/// керак бўлгандагина юкланади — 14 вилоятни олдиндан ўқимаслик учун).
class RingStepSpec {
  const RingStepSpec({
    required this.ring,
    required this.regionId,
    this.onlyDistrictId = '',
    this.excludeDistrictId = '',
  });

  /// Ҳалқа рақами (0 — туман, 1 — вилоят қолгани, 2+ — бошқа вилоятлар).
  final int ring;
  final String regionId;

  /// Бўш бўлмаса — қадам фақат шу туман (вилоят юкланмайди).
  final String onlyDistrictId;

  /// Вилоят туманларидан чиқариб ташланадиган туман (ring 0 да олинган).
  final String excludeDistrictId;

  bool get needsRegionDistricts => onlyDistrictId.isEmpty;

  /// Қадам туманлари ([regionDistricts] — вилоятнинг барча туман ID'лари).
  List<String> resolve(List<String> regionDistricts) {
    if (onlyDistrictId.isNotEmpty) return [onlyDistrictId];
    final out = <String>[];
    for (final d in regionDistricts) {
      final id = d.trim();
      if (id.isEmpty || id == excludeDistrictId || out.contains(id)) continue;
      out.add(id);
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is RingStepSpec &&
      other.ring == ring &&
      other.regionId == regionId &&
      other.onlyDistrictId == onlyDistrictId &&
      other.excludeDistrictId == excludeDistrictId;

  @override
  int get hashCode => Object.hash(ring, regionId, onlyDistrictId, excludeDistrictId);

  @override
  String toString() =>
      'RingStepSpec($ring, $regionId, only=$onlyDistrictId, exclude=$excludeDistrictId)';
}

/// Сукут режаси (Республика ҳалқалари). Туман номаълум бўлса ring 0 йўқ;
/// вилоят номаълум бўлса — ring 1 йўқ, бошқа вилоятлар алифбо тартибида.
List<RingStepSpec> buildRingPlan({
  required String userDistrictId,
  required String userRegionId,
}) {
  final district = userDistrictId.trim();
  final region = userRegionId.trim();
  final plan = <RingStepSpec>[];
  if (district.isNotEmpty) {
    plan.add(RingStepSpec(ring: 0, regionId: region, onlyDistrictId: district));
  }
  final order = regionRingOrder(region);
  var ring = 2;
  for (final r in order) {
    if (r.isEmpty) continue;
    if (r == region) {
      plan.add(RingStepSpec(ring: 1, regionId: r, excludeDistrictId: district));
    } else {
      plan.add(RingStepSpec(ring: ring++, regionId: r, excludeDistrictId: district));
    }
  }
  return plan;
}

/// Фойдаланувчи аниқ танлаган ҳудуд — битта ҳалқа (ring 0).
List<RingStepSpec> explicitRingPlan({required String districtId, required String regionId}) {
  final d = districtId.trim();
  final r = regionId.trim();
  if (d.isNotEmpty) return [RingStepSpec(ring: 0, regionId: r, onlyDistrictId: d)];
  if (r.isNotEmpty) return [RingStepSpec(ring: 0, regionId: r)];
  return const [];
}

/// [GeoScope] → режа: `nation` = сукут ҳалқалар (марказ — scope ҳудуди),
/// `region` / `district` = аниқ танлов.
List<RingStepSpec> ringPlanFor(GeoScope scope) {
  final a = scope.area;
  switch (scope.level) {
    case GeoLevel.nation:
      return buildRingPlan(userDistrictId: a.districtId, userRegionId: a.regionId);
    case GeoLevel.region:
      return explicitRingPlan(districtId: '', regionId: a.regionId);
    case GeoLevel.district:
      return explicitRingPlan(districtId: a.districtId, regionId: a.regionId);
  }
}

/// Аниқланган қадам.
class RingStep {
  const RingStep(this.ring, this.districtIds);
  final int ring;
  final List<String> districtIds;

  @override
  String toString() => 'RingStep($ring, $districtIds)';
}

/// Тоза: режа + вилоят→туманлар жадвали → бўш бўлмаган қадамлар.
List<RingStep> buildRingSteps(
  List<RingStepSpec> plan,
  Map<String, List<String>> districtsByRegion,
) {
  final out = <RingStep>[];
  for (final s in plan) {
    final ids = s.resolve(districtsByRegion[s.regionId] ?? const []);
    if (ids.isNotEmpty) out.add(RingStep(s.ring, ids));
  }
  return out;
}

/// Туман ҳужжатларидан вилоят→туманлар жадвали (GeoNames/кеш маълумоти учун).
Map<String, List<String>> districtsByRegionOf(Iterable<GeoDistrict> districts) {
  final m = <String, List<String>>{};
  for (final d in districts) {
    if (d.regionId.isEmpty || d.id.isEmpty) continue;
    (m[d.regionId] ??= []).add(d.id);
  }
  return m;
}

/// Ҳалқа рақами билан элемент.
class RingItem<T> {
  const RingItem(this.item, this.ring);
  final T item;
  final int ring;
}

/// Бир бўлак сўров натижаси. [cursor] — кейинги саҳифа учун (Firestore'да
/// охирги ҳужжат).
class RingFetchResult<T> {
  const RingFetchResult(this.items, this.cursor, {int? rawCount}) : _rawCount = rawCount;
  final List<T> items;
  final Object? cursor;

  /// Сервер қайтарган ХОМ ҳужжатлар сони (адаптер клиентда филтрласа, [items] ундан кам бўлади —
  /// пейжер бўлак тугаганини шу сон бўйича аниқлайди). Сукут — [items] узунлиги.
  final int? _rawCount;
  int get rawCount => _rawCount ?? items.length;
}

/// [districtIds] (≤ chunkSize) бўйича [limit] тагача, [startAfter]дан кейин.
typedef RingFetcher<T> = Future<RingFetchResult<T>> Function(
  List<String> districtIds,
  Object? startAfter,
  int limit,
);

/// Ҳалқама-ҳалқа саҳифалаш: ҳалқа тугаса (сўров [limit]дан кам қайтарса)
/// кейингисига ўтади. Ҳолат фақат муваффақиятли сўровдан кейин ўзгаради —
/// хатода қайта чақириш ўша жойдан давом этади. Параллел [next] чақириқлари
/// навбатга қўйилади.
class RingPager<T> {
  RingPager({
    required this.plan,
    required this.fetch,
    Future<List<String>> Function(String regionId)? districtsOf,
    this.chunkSize = 30,
  }) : districtsOf = districtsOf ?? GeoDistrictsCache.districtIdsOf;

  final List<RingStepSpec> plan;
  final RingFetcher<T> fetch;
  final Future<List<String>> Function(String regionId) districtsOf;
  final int chunkSize;

  int _step = 0;
  List<List<String>>? _chunks;
  int _chunk = 0;
  Object? _cursor;
  Future<void> _queue = Future.value();

  bool get hasMore => _step < plan.length;

  /// Жорий ҳалқа (тугаган бўлса — `null`).
  int? get currentRing => hasMore ? plan[_step].ring : null;

  Future<List<RingItem<T>>> next(int pageSize) {
    final run = _queue.then((_) => _next(pageSize));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<List<RingItem<T>>> _next(int pageSize) async {
    final out = <RingItem<T>>[];
    while (out.length < pageSize && hasMore) {
      final spec = plan[_step];
      final chunks = _chunks ??= chunksOf(
        spec.resolve(spec.needsRegionDistricts ? await districtsOf(spec.regionId) : const []),
        chunkSize,
      );
      if (_chunk >= chunks.length) {
        _step++;
        _chunks = null;
        _chunk = 0;
        _cursor = null;
        continue;
      }
      final want = pageSize - out.length;
      final res = await fetch(chunks[_chunk], _cursor, want);
      out.addAll(res.items.map((i) => RingItem<T>(i, spec.ring)));
      if (res.rawCount < want) {
        _chunk++;
        _cursor = null;
      } else {
        _cursor = res.cursor;
      }
    }
    return out;
  }
}

/// Юпқа Firestore адаптери. [districtField] — коллекцияга қараб
/// (`tv_shop_items`/`wholesale_products`/`realty_listings` — `districtId`);
/// [orderField] — `createdAt` (Улгуржи — `publishedAt`).
RingFetcher<QueryDocumentSnapshot<Map<String, dynamic>>> firestoreRingFetcher({
  required CollectionReference<Map<String, dynamic>> collection,
  String districtField = 'districtId',
  String orderField = 'createdAt',
  String statusValue = 'active',
  Map<String, Object> equals = const {},
}) {
  return (districtIds, startAfter, limit) async {
    Query<Map<String, dynamic>> q = collection.where('status', isEqualTo: statusValue);
    equals.forEach((field, value) => q = q.where(field, isEqualTo: value));
    q = q.where(districtField, whereIn: districtIds).orderBy(orderField, descending: true);
    if (startAfter is DocumentSnapshot) q = q.startAfterDocument(startAfter);
    final snap = await q.limit(limit).get();
    final docs = snap.docs;
    return RingFetchResult(docs, docs.isEmpty ? startAfter : docs.last);
  };
}

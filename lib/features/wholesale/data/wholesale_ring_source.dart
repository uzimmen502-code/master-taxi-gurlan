import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/geo/geo_districts_cache.dart';
import '../../../core/geo/ring_query.dart';
import '../models/wholesale_product.dart';
import '../repositories/wholesale_products_repository.dart';

/// Улгуржи / Хитой бозори — «ҳалқалар» сўрови (7-босқич, эга 2026-11-15; 11-03 даги «ҳудуд фильтри йўқ»
/// қарори ўрнига).
///
/// * Туман — `wholesale_products.districtId` (сервер сотувчининг ЖЎНАТИШ манзилидан ёзади, `wholesale_geo.js`;
///   Хитой сотувчилари ҳам шу — жўнатиш тумани бўйича). Тартиб — `publishedAt desc`.
/// * Хитой: `market == 'china'` серверда (янги индекс: status+market+districtId+publishedAt).
///   Улгуржи: `market` филтри КЛИЕНТДА ([WholesaleProduct.belongsToMarket]) — эски ҳужжатларда майдон йўқ;
///   индекс status+districtId+publishedAt (мавжуд, `getActiveProducts(geo:)` ишлатади).
/// * «Барча ҳудудларда» сотувчилар (`wholesale_sellers.allAreas == true`, эга 2026-11-03) — ҳалқадан ташқари,
///   ҳар доим рўйхат бошида ([mergeAllAreas]); туман танланганда ҳам йўқолмайди.
@immutable
class WholesaleRingFilter {
  const WholesaleRingFilter({required this.market});

  /// [WholesaleProduct.marketWholesale] ёки [WholesaleProduct.marketChina].
  final String market;

  bool get isChina => market == WholesaleProduct.marketChina;

  /// Ҳалқа сўровидаги қўшимча тенглик филтрлари.
  Map<String, Object> get equals => isChina ? const {'market': WholesaleProduct.marketChina} : const {};

  static const orderField = 'publishedAt';

  @override
  bool operator ==(Object other) => other is WholesaleRingFilter && other.market == market;

  @override
  int get hashCode => market.hashCode;
}

abstract class WholesaleListingSource {
  RingFetcher<WholesaleProduct> fetcher(WholesaleRingFilter filter);

  /// Республика бўйича фаол маҳсулотлар сони ([WholesaleProduct.belongsToMarket] қоидасига мос).
  Future<int> count(WholesaleRingFilter filter);

  /// «Барча ҳудудларда» сотувчилар маҳсулотлари (бозор бўйича филтрланган).
  Future<List<WholesaleProduct>> allAreas(WholesaleRingFilter filter);

  Future<List<String>> districtsOf(String regionId);
}

class FirestoreWholesaleListingSource implements WholesaleListingSource {
  FirestoreWholesaleListingSource({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('wholesale_products');

  @override
  RingFetcher<WholesaleProduct> fetcher(WholesaleRingFilter filter) {
    final raw = firestoreRingFetcher(
      collection: _col,
      orderField: WholesaleRingFilter.orderField,
      statusValue: WholesaleProduct.statusActive,
      equals: filter.equals,
    );
    return (districtIds, startAfter, limit) async {
      final res = await raw(districtIds, startAfter, limit);
      final out = <WholesaleProduct>[];
      for (final d in res.items) {
        try {
          final p = WholesaleProduct.fromFirestore(d);
          if (p.belongsToMarket(filter.market)) out.add(p);
        } catch (e) {
          debugPrint('[WholesaleRings] skip ${d.id}: $e');
        }
      }
      // Курсор — сервердаги охирги ҳужжат; Улгуржида Хитой маҳсулоти тушиб қолса саҳифа қисқаради, лекин
      // [RingPager] уни «ҳалқа тугади» деб тушунмаслиги учун хом ҳужжатлар сони узатилади.
      return RingFetchResult(out, res.cursor, rawCount: res.items.length);
    };
  }

  @override
  Future<int> count(WholesaleRingFilter filter) async {
    final china = await _count([('status', WholesaleProduct.statusActive), ('market', WholesaleProduct.marketChina)]);
    if (filter.isChina) return china;
    // Улгуржи = барча фаол − Хитой (эски ҳужжатларда `market` йўқ — улар Улгуржи).
    final all = await _count([('status', WholesaleProduct.statusActive)]);
    return all > china ? all - china : 0;
  }

  Future<int> _count(List<(String, Object)> filters) async {
    Query<Map<String, dynamic>> q = _col;
    for (final (field, value) in filters) {
      q = q.where(field, isEqualTo: value);
    }
    final agg = await q.count().get();
    return agg.count ?? 0;
  }

  @override
  Future<List<WholesaleProduct>> allAreas(WholesaleRingFilter filter) =>
      WholesaleProductsRepository().watchAllAreasProducts(market: filter.market).first;

  @override
  Future<List<String>> districtsOf(String regionId) => GeoDistrictsCache.districtIdsOf(regionId);
}

/// «Барча ҳудудларда» маҳсулотлари БОШИДА, кейин ҳалқа тартиби; такрор (ID) ташланади.
List<WholesaleProduct> mergeAllAreas(List<WholesaleProduct> allAreas, Iterable<WholesaleProduct> ring) {
  final seen = <String>{};
  final out = <WholesaleProduct>[];
  for (final p in [...allAreas, ...ring]) {
    if (seen.add(p.id)) out.add(p);
  }
  return out;
}

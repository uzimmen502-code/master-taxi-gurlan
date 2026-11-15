import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_districts_cache.dart';
import '../../../core/geo/geo_names.dart';
import '../../../core/geo/ring_query.dart';
import '../../../core/service_config_holder.dart';
import '../../../models/geo_area.dart' show GeoDistrict;
import '../../../repositories/service_config_repository.dart';
import '../../tv_market/models/tv_shop.dart';

/// Бозор экранидаги сервер филтри: бозор + (ихтиёрий) бўлим + «Импорт».
/// Нарх филтри — КЛИЕНТДА (юкланган саҳифалар устида; сервер индекси кўпаймаслиги учун).
@immutable
class MarketFilter {
  const MarketFilter({required this.market, this.category = '', this.importedOnly = false});

  final String market;

  /// Бўш — «Барчаси».
  final String category;
  final bool importedOnly;

  /// Ҳалқа сўровидаги қўшимча тенглик филтрлари (`status == 'active'` ва туман — [firestoreRingFetcher]да).
  Map<String, Object> get equals => {
        'market': market,
        if (category.isNotEmpty) 'category': category,
        if (importedOnly) 'imported': true,
      };

  /// `count()` сўрови филтрлари (тартиб — сўровдаги тартиб). Республика бўйича — туман филтри йўқ.
  List<(String, Object)> get countFilters => [
        ('status', 'active'),
        ('market', market),
        if (category.isNotEmpty) ('category', category),
        if (importedOnly) ('imported', true),
      ];

  @override
  bool operator ==(Object other) =>
      other is MarketFilter &&
      other.market == market &&
      other.category == category &&
      other.importedOnly == importedOnly;

  @override
  int get hashCode => Object.hash(market, category, importedOnly);
}

/// Бозор эълонлари манбаи (тестда алмаштирилади).
abstract class MarketListingSource {
  RingFetcher<TvShopItem> fetcher(MarketFilter filter);
  Future<int> count(MarketFilter filter);
  Future<List<String>> districtsOf(String regionId);
}

class FirestoreMarketListingSource implements MarketListingSource {
  FirestoreMarketListingSource({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('tv_shop_items');

  @override
  RingFetcher<TvShopItem> fetcher(MarketFilter filter) {
    final raw = firestoreRingFetcher(collection: _col, equals: filter.equals);
    return (districtIds, startAfter, limit) async {
      final res = await raw(districtIds, startAfter, limit);
      final items = <TvShopItem>[];
      for (final d in res.items) {
        try {
          items.add(TvShopItem.fromFirestore(d));
        } catch (e) {
          // Бузилган ҳужжат рўйхатни тўхтатмасин (диагностика — фақат лог).
          debugPrint('[MarketListings] skip ${d.id}: $e');
        }
      }
      return RingFetchResult(items, res.cursor);
    };
  }

  @override
  Future<int> count(MarketFilter filter) async {
    Query<Map<String, dynamic>> q = _col;
    for (final (field, value) in filter.countFilters) {
      q = q.where(field, isEqualTo: value);
    }
    final agg = await q.count().get();
    return agg.count ?? 0;
  }

  @override
  Future<List<String>> districtsOf(String regionId) => GeoDistrictsCache.districtIdsOf(regionId);
}

/// Эълон туманининг вилояти (`regionId` майдони учун). Тартиб: профил тумани → фаол ҳудуд → `geo_districts/{id}`
/// (битта ўқиш). Аниқланмаса — бўш (майдон ёзилмайди; rules ихтиёрий).
Future<String> resolveRegionIdForDistrict(
  String districtId, {
  Future<GeoDistrict?> Function(String id)? fetchDistrict,
}) async {
  final id = districtId.trim();
  if (id.isEmpty) return '';
  if (id == ServiceConfigHolder.districtId && ServiceConfigHolder.regionId.isNotEmpty) {
    return ServiceConfigHolder.regionId;
  }
  final active = GeoContext.active;
  if (id == active.districtId && active.regionId.isNotEmpty) return active.regionId;
  try {
    final d = await (fetchDistrict ?? ServiceConfigRepository().fetchDistrict)(id);
    if (d != null) GeoNames.remember(districts: [d]);
    return d?.regionId.trim() ?? '';
  } catch (e) {
    debugPrint('[MarketListings] region of $id: $e');
    return '';
  }
}

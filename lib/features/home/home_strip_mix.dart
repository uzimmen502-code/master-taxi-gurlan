import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/geo/geo_context.dart';
import '../../core/geo/module_geo_policy.dart';
import '../../models/realty_listing.dart';
import '../markets/domain/market_taxonomy.dart';
import '../restaurants/domain/restaurant_models.dart';
import '../tv_market/models/tv_shop.dart';
import '../tv_market/repositories/tv_shop_repository.dart';

/// Уйдаги тасмалар аралашмаси (эга 2026-11-16): «Аралаш бозор» тасмасига `tv_shop_items`, «Яқиндаги эълонлар»
/// тасмасига мол/мошина, уй-жой, ишлатилган электроника/маиший техника ва янги уй ошпазлари. Тоза функциялар —
/// тестланади; Firestore ўқиши фақат [HomeShopFeed] да (иккала тасма битта сўровни бўлишади, 37-банд).

/// Таксономияда `showInNearbyAds` калити умуман бўлмаса (эски v3) — шу бўлимлар (эга 2026-11-16).
const kNearbyAdsFallbackCategories = {'livestock.all', 'auto.cars', 'auto.moto', 'auto.tech'};

/// Хусусий сотувчининг (бизнес объектисиз) ишлатилган маҳсулоти «Яқиндаги эълонлар»га чиқадиган бозорлар.
const kNearbyAdsUsedMarkets = {'electronics', 'appliances'};

/// «Янги уй ошпази» карточкаси шунча вақт кўринади (ресторан `createdAt` дан).
const kNewHomeCookWindow = Duration(days: 7);

/// `market.category` калитлари — таксономиядаги `showInNearbyAds == true`; калит ҳеч бир бўлимда бўлмаса —
/// [kNearbyAdsFallbackCategories].
Set<String> nearbyAdsCategories(MarketTaxonomy? t) {
  if (t == null) return kNearbyAdsFallbackCategories;
  var anyKey = false;
  final out = <String>{};
  for (final m in t.markets.values) {
    for (final c in m.categories) {
      if (c.showInNearbyAds != null) anyKey = true;
      if (c.showInNearbyAds == true) out.add('${m.id}.${c.id}');
    }
  }
  if (!anyKey) return kNearbyAdsFallbackCategories;
  // Taxonomy v5 (2026-11-19): Мол бозорида `all` ўрнига cattle/sheep_goat/horse/poultry/other. Эски
  // `livestock.all` ёзувлари (prod'да бор) — Мол бўлимларидан бирортаси белгиланган бўлса, аввалгидек чиқади.
  if (out.any((k) => k.startsWith('$kNearbyAdsLivestockMarket.'))) out.add(kNearbyAdsLegacyLivestockKey);
  return out;
}

const kNearbyAdsLivestockMarket = 'livestock';
const kNearbyAdsLegacyLivestockKey = 'livestock.all';

/// Электроника / маиший техника: сотувчи бизнес объекти эмас (`businessId` бўш) ВА `attrs.condition == used`.
bool isUsedPrivateGadget(TvShopItem i) =>
    kNearbyAdsUsedMarkets.contains(i.market.trim()) &&
    i.businessId.trim().isEmpty &&
    i.attrs['condition'] == 'used';

/// Деҳқон бозори (эга 2026-11-17): бизнес объектисиз (хусусий деҳқон) ЁКИ объект тури `retail` эмас (ферма, боғ,
/// қишлоқ хўжалиги); дўкон (`retail`) — йўқ. [businessCategories] — `businessId → category wire` (аниқланмаган
/// объект: калит йўқ ёки `null` → чиқмайди).
const kNearbyAdsFarmMarket = 'farm';
const kRetailBusinessCategory = 'retail';

bool isNearbyFarmItem(TvShopItem i, Map<String, String?> businessCategories) {
  if (i.market.trim() != kNearbyAdsFarmMarket) return false;
  final bid = i.businessId.trim();
  if (bid.isEmpty) return true;
  final cat = businessCategories[bid];
  return cat != null && cat != kRetailBusinessCategory;
}

/// Деҳқон маҳсулотлари учун аниқлаш керак бўлган объект id лари (такрорсиз).
Set<String> farmBusinessIds(Iterable<TvShopItem> items) => {
      for (final i in items)
        if (i.isActive && i.market.trim() == kNearbyAdsFarmMarket && i.businessId.trim().isNotEmpty) i.businessId.trim(),
    };

/// Хусусий сотувчи маҳсулоти ҳам «Яқиндаги эълонлар»га чиқмайдиган бозорлар (эга 2026-11-19).
const kNearbyAdsPrivateExcludedMarkets = {'meat'};

/// Эга 2026-11-19: хусусий сотувчи (`businessId` бўш) маҳсулоти — ИСТАЛГАН бозорда, жумладан Аралаш
/// (`market == ''`); фақат [kNearbyAdsPrivateExcludedMarkets] (гўшт) — йўқ.
bool isNearbyPrivateItem(TvShopItem i) =>
    i.businessId.trim().isEmpty && !kNearbyAdsPrivateExcludedMarkets.contains(i.market.trim());

/// Маҳсулот «Яқиндаги эълонлар»га тушадими.
bool showsInNearbyAds(TvShopItem i, Set<String> categories, {Map<String, String?> businessCategories = const {}}) =>
    i.isActive &&
    (categories.contains('${i.market.trim()}.${i.category.trim()}') ||
        isUsedPrivateGadget(i) ||
        isNearbyFarmItem(i, businessCategories) ||
        isNearbyPrivateItem(i));

/// «Яқиндаги эълонлар» маҳсулот қатори: сарлавҳа · нарх (+бирлик) · туман — бўшлари ташланади
/// (янги сақланган матн йўқ, эга 2026-11-19).
String nearbyShopRowText({required String title, required String price, required String district}) =>
    [title.trim(), price.trim(), district.trim()].where((s) => s.isNotEmpty).join(' · ');

/// 0 — фойдаланувчи тумани, 1 — вилояти, 2 — бошқа / номаълум.
int proximityRank({
  required String itemDistrictId,
  required String itemRegionId,
  required String userDistrictId,
  required String userRegionId,
}) {
  final d = itemDistrictId.trim();
  final r = itemRegionId.trim();
  if (d.isNotEmpty && d == userDistrictId.trim()) return 0;
  if (r.isNotEmpty && r == userRegionId.trim()) return 1;
  return 2;
}

/// Яқиндан узоққа ([proximityRank]), бир ҳалқада — энг янгиси олдин; тенгларда асл тартиб (барқарор).
List<T> nearestFirst<T>(
  Iterable<T> items, {
  required String Function(T) districtOf,
  required String Function(T) regionOf,
  required DateTime? Function(T) createdOf,
  required String userDistrictId,
  required String userRegionId,
}) {
  final list = items.toList();
  final idx = <T, int>{};
  for (var i = 0; i < list.length; i++) {
    idx.putIfAbsent(list[i], () => i);
  }
  int rank(T x) => proximityRank(
        itemDistrictId: districtOf(x),
        itemRegionId: regionOf(x),
        userDistrictId: userDistrictId,
        userRegionId: userRegionId,
      );
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  list.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final byTime = (createdOf(b) ?? epoch).compareTo(createdOf(a) ?? epoch);
    if (byTime != 0) return byTime;
    return idx[a]!.compareTo(idx[b]!);
  });
  return list;
}

/// Тасма ҳудуди: Республика — ҳаммаси; туман — шу туман ёки ҳудудсиз; вилоят — `regionId` мос, `regionId` йўқ
/// эски ёзувда — ҳудудсиз ёки фойдаланувчи тумани (вилоят туманлари рўйхатини уйда ўқимаймиз, 37-банд).
bool inHomeStripScope({required String districtId, required String regionId, required GeoScope scope}) {
  final d = districtId.trim();
  final r = regionId.trim();
  switch (scope.level) {
    case GeoLevel.nation:
      return true;
    case GeoLevel.district:
      return d.isEmpty || d == scope.area.districtId;
    case GeoLevel.region:
      if (r.isNotEmpty) return r == scope.area.regionId;
      return d.isEmpty || d == scope.area.districtId;
  }
}

/// «Аралаш бозор» тасмаси учун `tv_shop_items`: фаол, такрорсиз, ҳудудда, яқиндан узоққа, [limit] та.
List<TvShopItem> aralashShopItems(
  Iterable<TvShopItem> items, {
  required GeoScope scope,
  required String userDistrictId,
  required String userRegionId,
  required int limit,
}) {
  final byId = <String, TvShopItem>{};
  for (final i in items) {
    if (i.isActive && inHomeStripScope(districtId: i.districtId, regionId: i.regionId, scope: scope)) {
      byId.putIfAbsent(i.id, () => i);
    }
  }
  return nearestFirst<TvShopItem>(
    byId.values,
    districtOf: (i) => i.districtId,
    regionOf: (i) => i.regionId,
    createdOf: (i) => i.createdAt,
    userDistrictId: userDistrictId,
    userRegionId: userRegionId,
  ).take(limit).toList(growable: false);
}

/// «Яқиндаги эълонлар» қўшимча қатори: маҳсулот ёки уй-жой эълони.
class NearbyAdExtra {
  const NearbyAdExtra.shop(TvShopItem this.shop) : realty = null;
  const NearbyAdExtra.realty(RealtyListing this.realty) : shop = null;

  final TvShopItem? shop;
  final RealtyListing? realty;

  String get id => shop != null ? 'shop_${shop!.id}' : 'realty_${realty!.id}';
  String get title => shop?.title.trim() ?? realty!.titleOrText;

  /// Белги калити: `market_short_<market>` ёки `aralash_badge_realty`.
  String get badgeKey => shop != null ? 'market_short_${shop!.market.trim()}' : 'aralash_badge_realty';
  String get districtId => shop?.districtId ?? realty!.districtId;
  String get regionId => shop?.regionId ?? realty!.regionId;
  DateTime? get createdAt => shop != null ? shop!.createdAt : realty!.createdAt;
}

/// Маҳсулотлар ([showsInNearbyAds]) + фаол уй-жой — ҳудудда, такрорсиз, яқиндан узоққа / янгидан, [limit] та.
List<NearbyAdExtra> buildNearbyAdExtras({
  required Iterable<TvShopItem> shop,
  required Iterable<RealtyListing> realty,
  required Set<String> categories,
  Map<String, String?> businessCategories = const {},
  required GeoScope scope,
  required String userDistrictId,
  required String userRegionId,
  required int limit,
}) {
  final byId = <String, NearbyAdExtra>{};
  for (final i in shop) {
    if (showsInNearbyAds(i, categories, businessCategories: businessCategories) &&
        inHomeStripScope(districtId: i.districtId, regionId: i.regionId, scope: scope)) {
      byId.putIfAbsent('shop_${i.id}', () => NearbyAdExtra.shop(i));
    }
  }
  for (final r in realty) {
    if (r.isActive && inHomeStripScope(districtId: r.districtId, regionId: r.regionId, scope: scope)) {
      byId.putIfAbsent('realty_${r.id}', () => NearbyAdExtra.realty(r));
    }
  }
  return nearestFirst<NearbyAdExtra>(
    byId.values,
    districtOf: (e) => e.districtId,
    regionOf: (e) => e.regionId,
    createdOf: (e) => e.createdAt,
    userDistrictId: userDistrictId,
    userRegionId: userRegionId,
  ).take(limit).toList(growable: false);
}

/// Охирги [kNewHomeCookWindow] ичида яратилган, тасдиқланган, намуна бўлмаган уй ошпазлари (энг янгиси олдин).
/// [dismissed] — шу қурилмада аллақачон очилганлар (бир марталик карточка).
List<Restaurant> newHomeCooks(Iterable<Restaurant> list, DateTime now, {Set<String> dismissed = const {}}) {
  final seen = <String>{};
  final out = <Restaurant>[
    for (final r in list)
      if (r.isHomeCook &&
          r.isApproved &&
          !r.isDemo &&
          r.createdAt != null &&
          !r.createdAt!.isAfter(now.add(const Duration(minutes: 5))) &&
          now.difference(r.createdAt!) <= kNewHomeCookWindow &&
          !dismissed.contains(r.id) &&
          seen.add(r.id))
        r,
  ];
  out.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
  return out;
}

/// «Янги: {name} уй таомлари».
String newHomeCookTitle(String template, Restaurant r) => template.replaceAll('{name}', r.name.trim());

/// Объект тури (`businessId → category wire`) — сеанс кеши: ҳар карточкага ўқиш йўқ, фақат янги id лар
/// [loader] орқали (≤30 талик `whereIn` бўлаклар — [BusinessRepository.fetchCategoriesByIds]). Топилмаган id `null`
/// бўлиб сақланади (қайта ўқилмайди, чиқмайди). Юклашда хато — кешга ёзилмайди, маълумлари қайтади.
class HomeBusinessCategoryCache {
  HomeBusinessCategoryCache._();

  static final Map<String, String?> _cache = {};

  @visibleForTesting
  static void debugReset() => _cache.clear();

  static Future<Map<String, String?>> resolve(
    Set<String> ids,
    Future<Map<String, String>> Function(List<String> ids) loader,
  ) async {
    final missing = [for (final id in ids) if (!_cache.containsKey(id)) id];
    if (missing.isNotEmpty) {
      try {
        final found = await loader(missing);
        for (final id in missing) {
          _cache[id] = found[id];
        }
      } catch (e) {
        debugPrint('[HomeStrips] HOME_BUSINESS_CATEGORY_LOAD_FAILED n=${missing.length}: $e');
      }
    }
    return {for (final id in ids) if (_cache.containsKey(id)) id: _cache[id]};
  }
}

/// Иккала уй тасмаси учун битта `tv_shop_items` сўрови (`status == active`, `createdAt desc` — мавжуд индекс),
/// [ttl] давомида кеш. Хато бўлса кеш тозаланади (кейинги очилишда қайта уринади).
class HomeShopFeed {
  HomeShopFeed._();

  static const limit = 60;
  static const ttl = Duration(minutes: 2);

  static Future<List<TvShopItem>>? _future;
  static DateTime? _at;

  @visibleForTesting
  static Future<List<TvShopItem>> Function()? debugLoader;

  @visibleForTesting
  static void debugReset() {
    _future = null;
    _at = null;
  }

  static Future<List<TvShopItem>> recent() {
    final now = DateTime.now();
    final f = _future;
    if (f != null && _at != null && now.difference(_at!) < ttl) return f;
    _at = now;
    final next = (debugLoader ?? () => TvShopRepository().fetchForMarket(limit: limit))();
    _future = next;
    unawaited(next.then((_) {}, onError: (Object e) {
      if (identical(_future, next)) debugReset();
    }));
    return next;
  }
}

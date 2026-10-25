import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_query.dart';
import '../../tv_market/models/tv_shop.dart';

/// Аҳоли бозоридаги онлайн дўкон маҳсулотлари ҳовузи (2026-10-25, 4-босқич): охирги [recent] (лента) + сервер
/// қидирувида топилган [searched] (`searchTokens`, охирги 80 та билан чекланмайди), такрорсиз; ҳудуд — эълонлар
/// билан бир хил қоида (`inGeoScope`: ҳудудсиз эски ёзув туман/вилоятда ҳам кўринади).
List<TvShopItem> marketShopPool(
  Iterable<TvShopItem> recent,
  Iterable<TvShopItem> searched,
  GeoScope scope,
  Set<String> regionDistricts,
) {
  final byId = <String, TvShopItem>{for (final i in recent) i.id: i};
  for (final i in searched) {
    byId.putIfAbsent(i.id, () => i);
  }
  return [
    for (final i in byId.values)
      if (i.isActive && inGeoScope(i.districtId, scope, regionDistricts)) i,
  ];
}

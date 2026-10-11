import 'dart:async';

import '../utils/merged_stream.dart';
import 'geo_context.dart';
import 'geo_districts_cache.dart';
import 'module_geo_policy.dart';

/// Ҳудуд даражасига кўра битта рўйхат оқими (сервер филтри — таклиф
/// шарти: «бутун республика маълумотини телефонга юклаб, кейин яшириш
/// мумкин эмас»).
///
/// - Республика → [nation].
/// - Туман → [byDistricts]([туман]).
/// - Вилоят → [byDistricts](вилоят туманлари, 30 тадан бўлак).
/// - [legacy] — ҳудудсиз эски ёзувлар (backfill'гача йўқолмасин) туман ва
///   вилоят даражасида қўшилади.
Stream<List<T>> geoScopedStream<T>({
  required GeoScope scope,
  required Stream<List<T>> Function() nation,
  required Stream<List<T>> Function(List<String> districtIds) byDistricts,
  Stream<List<T>> Function()? legacy,
  required String Function(T) idOf,
  required int Function(T a, T b) compare,
  required int limit,
  Future<List<String>> Function(String regionId)? districtsOf,
}) {
  List<T> finish(List<T> l) => (l.toList()..sort(compare)).take(limit).toList();

  Stream<List<T>> withLegacy(Stream<List<T>> s) =>
      legacy == null ? s : mergeListStreams(s, legacy(), idOf: idOf);

  Stream<List<T>> forDistricts(List<String> ids) {
    if (ids.isEmpty) return nation().map(finish);
    final parts = chunksOf(ids).map(byDistricts).toList();
    var merged = parts.first;
    for (final p in parts.skip(1)) {
      merged = mergeListStreams(merged, p, idOf: idOf);
    }
    return withLegacy(merged).map(finish);
  }

  switch (scope.level) {
    case GeoLevel.nation:
      return nation().map(finish);
    case GeoLevel.district:
      final id = scope.area.districtId.trim();
      return id.isEmpty ? nation().map(finish) : forDistricts([id]);
    case GeoLevel.region:
      final rid = scope.area.regionId.trim();
      if (rid.isEmpty) return nation().map(finish);
      final load = districtsOf ?? GeoDistrictsCache.districtIdsOf;
      return Stream.fromFuture(load(rid)).asyncExpand(forDistricts);
  }
}

/// Клиент филтри (қидирув ҳовузи учун): ёзув шу ҳудуддами. Ҳудудсиз эски
/// ёзув — туман/вилоятда ҳам кўринади (юқоридаги [legacy] каби).
bool inGeoScope(String districtId, GeoScope scope, Set<String> regionDistricts) {
  final d = districtId.trim();
  switch (scope.level) {
    case GeoLevel.nation:
      return true;
    case GeoLevel.district:
      return d.isEmpty || d == scope.area.districtId;
    case GeoLevel.region:
      return d.isEmpty || regionDistricts.contains(d);
  }
}

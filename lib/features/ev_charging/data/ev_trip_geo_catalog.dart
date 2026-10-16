import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/geo_area.dart';
import '../../../repositories/service_config_repository.dart';
import 'ev_trip_place_search.dart';

/// Тизимдаги БАРЧА вилоят ва туманлар (`geo_regions` + `geo_districts`) —
/// сеанс давомида бир марта юкланади ва хотирада сақланади (қидирувда ҳар
/// ҳарфга сўров йўқ). Номлар қайта ёзилмайди: ҳужжатлар ўқилади.
///
/// Нарх: сеансда бир марта 2 та сўров (вилоятлар + барча туманлар, ~200 та
/// ҳужжат). Хато (офлайн) бўлса кеш ЭСЛАБ ҚОЛИНМАЙДИ — кейинги очилишда
/// қайта уринилади; шу пайтгача фақат қўлда ёзилган шаҳарлар ишлайди.
class EvTripGeoCatalog {
  EvTripGeoCatalog._();

  static Future<EvTripPlaceIndex>? _cached;

  /// Тест учун манба.
  @visibleForTesting
  static Future<({List<GeoRegion> regions, List<GeoDistrict> districts})>
      Function()? loaderOverride;

  static Future<EvTripPlaceIndex> load() {
    return _cached ??= _load();
  }

  static Future<EvTripPlaceIndex> _load() async {
    try {
      final loader = loaderOverride;
      final data = loader != null
          ? await loader()
          : await () async {
              final repo = ServiceConfigRepository();
              final results = await Future.wait([
                repo.fetchRegions(),
                repo.fetchAllDistricts(),
              ]);
              return (
                regions: results[0] as List<GeoRegion>,
                districts: results[1] as List<GeoDistrict>,
              );
            }();
      // Репозиторий хатода бўш рўйхат қайтаради — уни кеш қилмаймиз.
      if (data.regions.isEmpty && data.districts.isEmpty) {
        _cached = null;
        return EvTripPlaceIndex.build();
      }
      return EvTripPlaceIndex.build(
        regions: data.regions,
        districts: data.districts,
      );
    } catch (e) {
      debugPrint('EvTripGeoCatalog: $e');
      _cached = null;
      return EvTripPlaceIndex.build();
    }
  }

  @visibleForTesting
  static void reset() {
    _cached = null;
    loaderOverride = null;
  }
}

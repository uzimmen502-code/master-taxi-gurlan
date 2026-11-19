import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../repositories/service_config_repository.dart';

/// Вилоят → туман ID'лари (сеанс давомида кеш). Вилоят даражасидаги
/// сўровлар `districtId in [...]` билан қилинади: эски ҳужжатларда
/// `regionId` бўлмаслиги мумкин, туман ID эса доим ёзилган — мавжуд
/// (…, districtId, …) индекслари ишлайди.
class GeoDistrictsCache {
  GeoDistrictsCache._();

  static final Map<String, Future<List<String>>> _cache = {};

  /// Барча вилоятлар туманлари — сеансда БИР сўров (эга 2026-11-19, тезлик: «ҳалқалар» ҳар вилоят учун алоҳида
  /// `geo_districts` сўрови қилмасин). Бўш/хато — кешланмайди, вилоят бўйича эски йўлга қайтади.
  static Future<Map<String, List<String>>>? _all;

  /// Тест учун манба (вилоят бўйича).
  @visibleForTesting
  static Future<List<String>> Function(String regionId)? loaderOverride;

  /// Тест учун манба (барча туманлар: вилоят → туман ID'лари).
  @visibleForTesting
  static Future<Map<String, List<String>>> Function()? allLoaderOverride;

  static Future<Map<String, List<String>>> _loadAll() {
    return _all ??= () async {
      Map<String, List<String>> m;
      try {
        final allLoader = allLoaderOverride;
        if (allLoader != null) {
          m = await allLoader();
        } else {
          final list = await ServiceConfigRepository().fetchAllDistricts();
          m = <String, List<String>>{};
          for (final d in list) {
            if (d.regionId.isEmpty || d.id.isEmpty) continue;
            (m[d.regionId] ??= <String>[]).add(d.id);
          }
        }
      } catch (e) {
        debugPrint('GeoDistrictsCache(all): $e');
        m = const {};
      }
      if (m.isEmpty) _all = null;
      return m;
    }();
  }

  static Future<List<String>> districtIdsOf(String regionId) {
    final id = regionId.trim();
    if (id.isEmpty) return Future.value(const []);
    return _cache[id] ??= () async {
      try {
        final loader = loaderOverride;
        if (loader != null) return await loader(id);
        final all = await _loadAll();
        // Барча туманлар юкланган — вилоят йўқ бўлса ҳам қўшимча сўров йўқ (туманлари йўқ).
        if (all.isNotEmpty) return List<String>.unmodifiable(all[id] ?? const <String>[]);
        final list = await ServiceConfigRepository().fetchDistricts(id);
        return list.map((d) => d.id).toList(growable: false);
      } catch (e) {
        _cache.remove(id);
        debugPrint('GeoDistrictsCache($id): $e');
        return const <String>[];
      }
    }();
  }

  @visibleForTesting
  static void clear() {
    _cache.clear();
    _all = null;
    loaderOverride = null;
    allLoaderOverride = null;
  }
}

/// Firestore `in` чеклови — 30 та қиймат. Каттароқ рўйхат бўлакларга.
List<List<T>> chunksOf<T>(List<T> list, [int size = 30]) {
  final out = <List<T>>[];
  for (var i = 0; i < list.length; i += size) {
    out.add(list.sublist(i, i + size > list.length ? list.length : i + size));
  }
  return out;
}

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

  /// Тест учун манба.
  @visibleForTesting
  static Future<List<String>> Function(String regionId)? loaderOverride;

  static Future<List<String>> districtIdsOf(String regionId) {
    final id = regionId.trim();
    if (id.isEmpty) return Future.value(const []);
    return _cache[id] ??= () async {
      try {
        final loader = loaderOverride;
        if (loader != null) return await loader(id);
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
    loaderOverride = null;
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

import 'package:flutter/foundation.dart';

import '../../models/geo_area.dart';
import '../../repositories/service_config_repository.dart';
import '../brand_labels.dart';
import 'geo_context.dart';

/// Ҳудуд ID → фойдаланувчи тилидаги қисқа ном (фақат КЎРСАТИШ учун).
///
/// НЕГА (2026-10-11): туман ёрлиқлари (`ServiceConfigHolder.districtLabel`,
/// TV клип/витрина `districtLabel`, `GeoArea` ёрлиқлари) кириллда
/// сақланади — улар ҳужжатларга ёзилади ва бошқа фойдаланувчиларга ҳам
/// кўринади, шунинг учун тилга қараб ЎЗГАРТИРИЛМАЙДИ. Кўрсатишда эса ID
/// бўйича шу ердан тилли ном олинади; сақланган ёрлиқ — fallback.
///
/// Нарх: кирилл (`uz_Cyrl`) фойдаланувчиси учун ёрлиқ бор бўлса Firestore
/// ўқилмайди (олдинги хулқ). Рус/лотин учун ҳар ID сеансда бир марта
/// (`geo_regions/{id}` ёки `geo_districts/{id}`), хотирада кешланади.
/// Ном келгач [revision] ошади — тингловчи виджетлар қайта чизилади.
class GeoNames {
  GeoNames._();

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static final Map<String, GeoRegion> _regions = {};
  static final Map<String, GeoDistrict> _districts = {};
  static final Set<String> _inflight = {};

  /// Хато (офлайн) бўлса — шу вақтгача қайта уринилмайди.
  static final Map<String, DateTime> _retryAfter = {};
  static const _retryDelay = Duration(seconds: 60);

  @visibleForTesting
  static ServiceConfigRepository? repository;
  static ServiceConfigRepository get _repo =>
      repository ??= ServiceConfigRepository();

  /// Бошқа жойда ўқилган ҳужжатларни кешга қўшиш (ортиқча ўқишсиз).
  static void remember({
    Iterable<GeoRegion> regions = const [],
    Iterable<GeoDistrict> districts = const [],
  }) {
    for (final r in regions) {
      _regions[r.id] = r;
    }
    for (final d in districts) {
      _districts[d.id] = d;
    }
  }

  /// Туман қисқа номи («Гурлан» / «Gurlan» / «Гурлен»). Номаълум бўлса —
  /// [fallback] (сақланган ёрлиқ) қайтади ва ном фонда юкланади.
  static String district(String id, String lang, {String fallback = ''}) {
    final key = id.trim();
    if (key.isEmpty) return fallback;
    if (lang == 'uz_Cyrl' && fallback.trim().isNotEmpty) return fallback;
    final d = _districts[key];
    if (d != null) {
      final s = shortDistrict(d, lang);
      return s.isEmpty ? fallback : s;
    }
    _load('d', key);
    return fallback;
  }

  /// Вилоят номи. Номаълум бўлса — [fallback].
  static String region(String id, String lang, {String fallback = ''}) {
    final key = id.trim();
    if (key.isEmpty) return fallback;
    if (lang == 'uz_Cyrl' && fallback.trim().isNotEmpty) return fallback;
    final r = _regions[key];
    if (r != null) {
      final s = shortRegion(r, lang);
      return s.isEmpty ? fallback : s;
    }
    _load('r', key);
    return fallback;
  }

  /// «Гурлан, Хоразм» — [GeoArea.label]нинг тилли шакли.
  static String area(GeoArea a, String lang) {
    final d = district(a.districtId, lang, fallback: a.districtLabel).trim();
    final r = region(a.regionId, lang, fallback: a.regionLabel).trim();
    if (d.isEmpty) return r;
    if (r.isEmpty) return d;
    return '$d, $r';
  }

  /// Туман ҳужжатидан қисқа ном: рус — `nameRuShort` → `nameRu`
  /// («город » олиб ташланади) → кирилл; ўзбек — «тумани/шаҳри»сиз.
  static String shortDistrict(GeoDistrict d, String lang) {
    if (lang == 'ru') {
      if (d.nameRuShort.isNotEmpty) return d.nameRuShort;
      if (d.nameRu.isNotEmpty) return _stripCity(d.nameRu);
    }
    return BrandLabels.shortDistrictName(d.nameFor(lang == 'ru' ? 'uz_Cyrl' : lang));
  }

  /// Вилоят: рус — `nameRuShort` → `nameRu` («город » олиб ташланади);
  /// ўзбек — тўлиқ ном (олдингидек, `displayName`).
  static String shortRegion(GeoRegion r, String lang) {
    if (lang == 'ru') {
      if (r.nameRuShort.isNotEmpty) return r.nameRuShort;
      if (r.nameRu.isNotEmpty) return _stripCity(r.nameRu);
      return r.displayName;
    }
    return r.nameFor(lang);
  }

  static String _stripCity(String s) {
    const prefix = 'город ';
    return s.startsWith(prefix) ? s.substring(prefix.length).trim() : s;
  }

  static void _load(String kind, String id) {
    final key = '$kind:$id';
    if (_inflight.contains(key)) return;
    final wait = _retryAfter[key];
    if (wait != null && DateTime.now().isBefore(wait)) return;
    _inflight.add(key);
    () async {
      try {
        // Репозиторий хатода ҳам `null` қайтаради (офлайн ≠ «йўқ»), шунинг
        // учун `null` кешланмайди — [_retryDelay]дан кейин қайта уринилади.
        if (kind == 'd') {
          final d = await _repo.fetchDistrict(id);
          if (d != null) _districts[id] = d;
        } else {
          final r = await _repo.fetchRegion(id);
          if (r != null) _regions[id] = r;
        }
        final found = kind == 'd' ? _districts.containsKey(id) : _regions.containsKey(id);
        if (found) {
          _retryAfter.remove(key);
          revision.value++;
        } else {
          _retryAfter[key] = DateTime.now().add(_retryDelay);
        }
      } catch (e) {
        _retryAfter[key] = DateTime.now().add(_retryDelay);
        debugPrint('GeoNames($key): $e');
      } finally {
        _inflight.remove(key);
      }
    }();
  }

  @visibleForTesting
  static void reset() {
    _regions.clear();
    _districts.clear();
    _inflight.clear();
    _retryAfter.clear();
    repository = null;
  }
}

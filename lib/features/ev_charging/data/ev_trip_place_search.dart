// ⚡ EV сафар ёрдамчиси — манзил қидируви (тоза Dart, плагинсиз тестланади).
//
// Манба (иккита, такрорсиз):
//   1. [EvTripDestination.all] — қўлда ёзилган 22 шаҳар МАРКАЗИ, координатаси
//      билан (офлайн, аниқ);
//   2. тизимда МАВЖУД `geo_regions` / `geo_districts` ҳужжатлари (номлар
//      қайта ёзилмайди). Уларда координата ЙЎҚ (id, regionId, name, nameUz,
//      nameRu, nameRuShort, code, active, order) — шунинг учун ўйлаб топилган
//      координата ишлатилмайди; бундай манзил "Ҳисоблаш" босилганда Google
//      Directions'га МАТН бўлиб берилади ([EvTripPlace.routeText]).
//
// Қидирув хотирада, тармоқ сўровисиз; уч тилдаги ном бўйича ва катта-кичик
// ҳарфга бефарқ: кирилл фойдаланувчи лотинда ёзса ҳам топилади.

import '../../../core/geo/geo_names.dart';
import '../../../models/geo_area.dart';
import 'ev_trip_destinations.dart';

enum EvTripPlaceKind { curated, region, district }

/// Иловадаги тил кодлари — `GeoRegion.nameFor` / `_langCode()` билан бир хил.
const List<String> evTripLangs = ['uz_Cyrl', 'uz_Latn', 'ru'];

/// Қидирув учун ёзув: кичик ҳарф, апостроф турлари олиб ташланади
/// (`Qo'qon` = `Qoqon` = `Qo‘qon`), `ё` = `е`, ортиқча бўшлиқлар йиғилади.
String evTripNormalize(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp("[ʻʼ’‘`´']"), '')
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Шаҳар типидаги туман ҳужжати ("… шаҳри", "… shahri", "город …").
bool _isCityDistrict(GeoDistrict d) {
  for (final n in [d.name, d.nameUz, d.nameRu]) {
    final s = n.trim().toLowerCase();
    if (s.endsWith(' шаҳри') ||
        s.endsWith(' shahri') ||
        s.endsWith(' шахри') ||
        s.startsWith('город ')) {
      return true;
    }
  }
  return false;
}

/// Қидирувда танланадиган манзил.
class EvTripPlace {
  EvTripPlace._({
    required this.id,
    required this.kind,
    required Map<String, String> display,
    required List<String> ownNames,
    required Map<String, List<String>> ownNamesByLang,
    this.qualifierNames = const [],
    this.lat,
    this.lng,
    this.routeText,
  })  : _display = display,
        _ownNames = ownNames,
        _ownNamesByLang = ownNamesByLang;

  /// Тайёр координатали (қўлда ёзилган) шаҳар.
  factory EvTripPlace.curated(EvTripDestination d) {
    return EvTripPlace._(
      id: 'c:${d.id}',
      kind: EvTripPlaceKind.curated,
      display: {for (final l in evTripLangs) l: d.nameFor(l)},
      ownNames: [
        for (final l in evTripLangs) evTripNormalize(d.nameFor(l)),
      ],
      ownNamesByLang: {
        for (final l in evTripLangs) l: [evTripNormalize(d.nameFor(l))],
      },
      lat: d.lat,
      lng: d.lng,
    );
  }

  /// Вилоят маркази (координатасиз — матн бўйича аниқланади).
  factory EvTripPlace.region(GeoRegion r) {
    final byLang = <String, List<String>>{
      for (final l in evTripLangs)
        l: {
          evTripNormalize(GeoNames.shortRegion(r, l)),
          evTripNormalize(r.nameFor(l)),
        }.where((s) => s.isNotEmpty).toList(),
    };
    return EvTripPlace._(
      id: 'r:${r.id}',
      kind: EvTripPlaceKind.region,
      display: {for (final l in evTripLangs) l: GeoNames.shortRegion(r, l)},
      ownNames: {for (final l in evTripLangs) ...byLang[l]!}.toList(),
      ownNamesByLang: byLang,
      routeText: _routeText([_Part(r.name, r.nameUz)]),
    );
  }

  /// Туман: "Вилоят • Туман" (иловa тилида). [useFullName] — қисқа ном
  /// ("Урганч") бир вилоятда икки марта учраса ёки шаҳар номи билан
  /// чалкашса, тўлиқ ном ("Урганч тумани") кўрсатилади.
  factory EvTripPlace.district(
    GeoDistrict d,
    GeoRegion? region, {
    bool useFullName = false,
  }) {
    String districtName(String l) =>
        useFullName ? d.nameFor(l) : GeoNames.shortDistrict(d, l);
    String display(String l) {
      final dn = districtName(l);
      if (region == null) return dn;
      return '${GeoNames.shortRegion(region, l)} • $dn';
    }

    final byLang = <String, List<String>>{
      for (final l in evTripLangs)
        l: {
          evTripNormalize(GeoNames.shortDistrict(d, l)),
          evTripNormalize(d.nameFor(l)),
        }.where((s) => s.isNotEmpty).toList(),
    };
    final qualifiers = <String>{
      if (region != null)
        for (final l in evTripLangs) ...[
          evTripNormalize(GeoNames.shortRegion(region, l)),
          evTripNormalize(region.nameFor(l)),
        ],
    }.where((s) => s.isNotEmpty).toList();

    return EvTripPlace._(
      id: 'd:${d.id}',
      kind: EvTripPlaceKind.district,
      display: {for (final l in evTripLangs) l: display(l)},
      ownNames: {for (final l in evTripLangs) ...byLang[l]!}.toList(),
      ownNamesByLang: byLang,
      qualifierNames: qualifiers,
      routeText: _routeText([
        _Part(d.name, d.nameUz),
        if (region != null) _Part(region.name, region.nameUz),
      ]),
    );
  }

  final String id;
  final EvTripPlaceKind kind;

  /// Тайёр координата — фақат қўлда ёзилган шаҳарларда.
  final double? lat;
  final double? lng;

  /// Координата йўқ бўлса Directions'га бериладиган матн
  /// (`Gurlan tumani, Xorazm, Uzbekistan`).
  final String? routeText;

  /// Туманда — вилоят номлари (пастроқ мартабали мослик учун).
  final List<String> qualifierNames;

  final Map<String, String> _display;
  final List<String> _ownNames;
  final Map<String, List<String>> _ownNamesByLang;

  bool get hasCoords => lat != null && lng != null;

  /// Иловa тилидаги кўриниш (`uz_Cyrl` / `uz_Latn` / `ru`).
  String displayFor(String lang) => _display[lang] ?? _display['uz_Cyrl']!;

  /// Барча тилдаги хом (нормаллашган) ном — тест ва дедупликация учун.
  List<String> get normalizedNames => List.unmodifiable(_ownNames);

  /// Мослик даражаси (кичикроқ — яхшироқ); мос эмас — `null`.
  /// 0 тўлиқ тенг · 1 бошидан · 2 сўз бошидан · 3 ичида · 4 вилоят номи
  /// бўйича. Иловa тилидаги мослик бошқа тилдагидан бир поғона юқори.
  int? matchScore(String normalizedQuery, String lang) {
    int? tierOf(String name) {
      if (name == normalizedQuery) return 0;
      if (name.startsWith(normalizedQuery)) return 1;
      if (name.contains(' $normalizedQuery') ||
          name.contains('-$normalizedQuery')) {
        return 2;
      }
      if (name.contains(normalizedQuery)) return 3;
      return null;
    }

    int? best;
    void consider(int? tier, bool inUserLang) {
      if (tier == null) return;
      final score = tier * 2 + (inUserLang ? 0 : 1);
      if (best == null || score < best!) best = score;
    }

    final userNames = _ownNamesByLang[lang] ?? const <String>[];
    for (final n in _ownNames) {
      consider(tierOf(n), userNames.contains(n));
    }
    if (best != null) return best;

    for (final n in qualifierNames) {
      if (n.contains(normalizedQuery)) return 4 * 2;
    }
    return null;
  }
}

class _Part {
  const _Part(this.latin, this.cyrillic);
  final String latin;
  final String cyrillic;
}

/// Directions учун матн: ҳамма бўлакда лотин ном бўлса — лотин
/// (`Gurlan tumani, Xorazm, Uzbekistan`), акс ҳолда кирилл
/// (`…, Ўзбекистон`); иккаласи ҳам бўш бўлак — `null`.
/// Вилоят киритилади: бир хил номли туманлар аралашмасин.
String? _routeText(List<_Part> parts) {
  final latin = parts.map((p) => p.latin.trim()).toList();
  if (latin.every((s) => s.isNotEmpty)) {
    return '${latin.join(', ')}, Uzbekistan';
  }
  final cyr = parts
      .map((p) =>
          p.cyrillic.trim().isNotEmpty ? p.cyrillic.trim() : p.latin.trim())
      .toList();
  if (cyr.every((s) => s.isNotEmpty)) {
    return '${cyr.join(', ')}, Ўзбекистон';
  }
  return null;
}

/// Қидирув индекси: қўлда ёзилган шаҳарлар + вилоят марказлари + туманлар.
class EvTripPlaceIndex {
  EvTripPlaceIndex._(this.places);

  /// Тартиб: қўлда ёзилганлар · вилоятлар · туманлар (вилоят `order`и бўйича).
  final List<EvTripPlace> places;

  /// Ёзилаётганда кўрсатиладиган таклифлар сони.
  static const int typedLimit = 8;

  factory EvTripPlaceIndex.build({
    List<EvTripDestination> curated = EvTripDestination.all,
    List<GeoRegion> regions = const [],
    List<GeoDistrict> districts = const [],
  }) {
    final out = <EvTripPlace>[
      for (final d in curated) EvTripPlace.curated(d),
    ];
    final curatedNames = <String>{
      for (final p in out) ...p.normalizedNames,
    };

    // Вилоят марказлари (қўлда ёзилган шаҳар билан бир номлилари тушади).
    final regionById = <String, GeoRegion>{};
    final regionOrder = <String, int>{};
    for (final r in regions) {
      if (!r.active) continue;
      regionById[r.id] = r;
      regionOrder[r.id] = regionOrder.length;
      final p = EvTripPlace.region(r);
      if (p.normalizedNames.any(curatedNames.contains)) continue;
      out.add(p);
    }

    // Туманлар: вилоят тартиби, ичида `order` (репозиторий сортлаган).
    final sorted = [
      for (final d in districts)
        if (d.active) d,
    ]..sort((a, b) {
        final ra = regionOrder[a.regionId] ?? 1 << 20;
        final rb = regionOrder[b.regionId] ?? 1 << 20;
        return ra.compareTo(rb);
      });

    // Бир вилоятда қисқа ном такрорланиши (Урганч шаҳри / Урганч тумани).
    final shortCount = <String, int>{};
    String shortKey(GeoDistrict d, String l) =>
        '${d.regionId}|${evTripNormalize(GeoNames.shortDistrict(d, l))}';
    for (final d in sorted) {
      // Bir hujjatning o'zi turli tilda bir xil qisqa nom bersa (Kitob = Kitob)
      // to'qnashuv emas - har kalit hujjat uchun bir marta sanaladi.
      for (final k in {for (final l in evTripLangs) shortKey(d, l)}) {
        shortCount[k] = (shortCount[k] ?? 0) + 1;
      }
    }

    final seenIds = <String>{};
    for (final d in sorted) {
      if (!seenIds.add(d.id)) continue;
      final shortNames = [
        for (final l in evTripLangs)
          evTripNormalize(GeoNames.shortDistrict(d, l)),
      ];
      final sameAsCurated = shortNames.any(curatedNames.contains);

      // Шаҳар типидаги туман қўлда ёзилган шаҳар билан бир ном — қўлда
      // ёзилгани (координатали) қолади.
      if (sameAsCurated && _isCityDistrict(d)) continue;

      final collides =
          evTripLangs.any((l) => (shortCount[shortKey(d, l)] ?? 0) > 1);
      out.add(EvTripPlace.district(
        d,
        regionById[d.regionId],
        useFullName: collides || sameAsCurated,
      ));
    }
    return EvTripPlaceIndex._(out);
  }

  /// Таклифлар. Бўш сўров — қўлда ёзилган шаҳарлар рўйхати. Сўров бор —
  /// мослик даражаси, кейин тур (шаҳар · вилоят · туман), кейин тартиб.
  List<EvTripPlace> search(String query, String lang, {int? limit}) {
    final q = evTripNormalize(query);
    if (q.isEmpty) {
      final curated = places.where((p) => p.kind == EvTripPlaceKind.curated);
      return limit == null ? curated.toList() : curated.take(limit).toList();
    }
    final scored = <({EvTripPlace place, int score, int index})>[];
    for (var i = 0; i < places.length; i++) {
      final s = places[i].matchScore(q, lang);
      if (s != null) scored.add((place: places[i], score: s, index: i));
    }
    scored.sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      if (byScore != 0) return byScore;
      final byKind = a.place.kind.index.compareTo(b.place.kind.index);
      if (byKind != 0) return byKind;
      return a.index.compareTo(b.index);
    });
    final take = limit ?? typedLimit;
    return scored.take(take).map((e) => e.place).toList();
  }
}

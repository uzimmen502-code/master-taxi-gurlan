// Бўлимлар (S3, D-REST-16/19/20/33; docs/kafe_restoran_taklifi_uz.md §10.1): таомлар мижоз мақсади
// бўйича — «Арзон», «Миллий», «Дунё», «Фаст-фуд», «Енгил», «Болалар», «Нонушта», «Тунги».
//
// Бўлимга КИРИШ қоидаси ШУ ЕРДА ЭМАС: уни сервер ҳисоблайди (`functions/restaurant_dish_index.js`,
// `sectionsOf`) ва индекс ҳужжатига `sections` массиви сифатида ёзади — клиент уни ўқийди ва
// такрорламайди (7-қоида). Бу ерда: бўлимлар рўйхати, созлама (`settings/restaurant_sections`),
// индекс ҳужжатининг модели ва ТАРТИБЛАШ («Янги» тепада, «Арзон» поғонаси).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'dish_facts.dart';
import 'restaurant_models.dart';

/// Бўлимлар — тартиб мижозга кўрсатиладиган тартиб. `key` — сервердаги `SECTION` қийматлари билан бир
/// хил (мослик тест билан қулфланган); матн калити `restaurants_section_<key>` (3 тилда).
enum RestaurantSection {
  /// «Овқатлар» — яқин атрофдаги ҲАР БИР таом лентаси (D-REST-40): «Барчаси» экранининг асосий кўриниши. Оч одам
  /// рестораннинг эмас, овқатнинг ўзини кўради. Бўлим босқичи (`all`) шу лентанинг feature flag'и.
  all('all'),
  cheap('cheap'),
  office('office'),
  national('national'),
  world('world'),
  fast('fast'),
  light('light'),
  dastarxon('dastarxon'),
  kids('kids'),
  breakfast('breakfast'),
  night('night'),
  seasonal('seasonal');

  const RestaurantSection(this.key);

  final String key;

  String get l10nKey => this == all ? 'restaurants_section_dishes' : 'restaurants_section_$key';

  /// Ичида кухна фильтри бор бўлимлар (D-REST-16: «Миллий» ва «Дунё» алоҳида, ҳар бирида фильтр).
  bool get hasCuisineFilter => this == national || this == world;

  /// Ичида мавсум фильтри бор бўлим (S7): ҳозир очиқ мавсумлар чиплар сифатида.
  bool get hasSeasonFilter => this == seasonal;

  /// Олдиндан буюртмага таянган бўлимлар (Офис, Дастурхон — D-REST-21): картада «Олдиндан буюртма» белгиси.
  bool get isPreorderBased => this == office || this == dastarxon;

  static RestaurantSection? fromKey(String? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// Бўлим босқичи (42-қоида): `off` · `internal` (синовчилар) · `public`.
abstract final class SectionStage {
  static const off = 'off';
  static const internal = 'internal';
  static const public = 'public';
}

/// `settings/restaurant_sections`. Ҳужжат йўқ ёки бузилган бўлса — ҳамма бўлим ЎЧИҚ (сервер ҳам
/// ўзи ҳеч нарсани ёқмайди). Сон қийматлар — эга тасдиқлаган бошланғич қийматлар (сервердаги
/// `DEFAULTS` нусхаси; мослик тест билан қулфланган).
class RestaurantSectionsConfig {
  const RestaurantSectionsConfig({
    this.version = 0,
    this.stages = const {},
    this.testerIds = const [],
    this.cheapRatingThreshold = defaultCheapRatingThreshold,
    this.newMaxRatings = defaultNewMaxRatings,
    this.newMaxDays = defaultNewMaxDays,
    this.newPerRestaurantPerSection = defaultNewPerRestaurantPerSection,
  });

  static const defaultCheapRatingThreshold = 5.0;
  static const defaultNewMaxRatings = 5;
  static const defaultNewMaxDays = 30;
  static const defaultNewPerRestaurantPerSection = 3;

  static const off = RestaurantSectionsConfig();

  final int version;
  final Map<String, String> stages;
  final List<String> testerIds;

  /// «Арзон»: ўртача баҳоси шу чегарадан КАМ БЎЛМАГАН таомлар юқори қаторда (эга: 5.0).
  final double cheapRatingThreshold;

  /// «Янги»: шунча баҳодан кам, шунча кундан ошмаган, ресторандан бўлим бошига шунча таомгача.
  final int newMaxRatings;
  final int newMaxDays;
  final int newPerRestaurantPerSection;

  String stageOf(RestaurantSection s) {
    final v = stages[s.key];
    return v == SectionStage.public || v == SectionStage.internal ? v! : SectionStage.off;
  }

  /// Мижозга кўринадими (`uid` — 12 рақамли; `internal` фақат синовчига). Фақат UI дарвозаси —
  /// индекс ҳужжатлари оммавий, махфий нарса йўқ.
  bool isVisible(RestaurantSection s, String? uid) {
    final st = stageOf(s);
    if (st == SectionStage.public) return true;
    if (st == SectionStage.internal) return uid != null && uid.isNotEmpty && testerIds.contains(uid);
    return false;
  }

  List<RestaurantSection> visibleFor(String? uid) => [
        for (final s in RestaurantSection.values)
          if (isVisible(s, uid)) s,
      ];

  factory RestaurantSectionsConfig.fromMap(Map<String, dynamic>? d) {
    if (d == null) return off;
    int intIn(Object? v, int def, int lo, int hi) => v is num && v == v.truncate() && v >= lo && v <= hi ? v.toInt() : def;
    final raw = d['sections'];
    final stages = <String, String>{
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && (e.value == SectionStage.internal || e.value == SectionStage.public)) e.key as String: e.value as String,
    };
    final t = d['cheapRatingThreshold'];
    return RestaurantSectionsConfig(
      version: intIn(d['version'], 0, 0, 1 << 30),
      stages: stages,
      testerIds: d['testerIds'] is List ? (d['testerIds'] as List).whereType<String>().toList() : const [],
      cheapRatingThreshold: t is num && t >= 1 && t <= 5 ? t.toDouble() : defaultCheapRatingThreshold,
      newMaxRatings: intIn(d['newMaxRatings'], defaultNewMaxRatings, 1, 100),
      newMaxDays: intIn(d['newMaxDays'], defaultNewMaxDays, 1, 365),
      newPerRestaurantPerSection: intIn(d['newPerRestaurantPerSection'], defaultNewPerRestaurantPerSection, 1, 20),
    );
  }
}

DateTime? _ts(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

int _int(dynamic v, [int def = 0]) => v is num ? v.toInt() : def;

String _str(dynamic v) => v is String ? v : '';

/// `restaurant_dish_index/{rid}_{iid}` — бўлим рўйхатидаги битта таом (сервер тайёрлаган кўриниш).
class SectionDish {
  const SectionDish({
    required this.restaurantId,
    required this.itemId,
    required this.name,
    required this.price,
    required this.restaurantName,
    this.photoUrl = '',
    this.pricePerPerson,
    this.servings,
    this.kcal,
    this.protein,
    this.fat,
    this.carbs,
    this.cuisineGroup,
    this.cuisineId,
    this.tags = const [],
    this.sections = const [],
    this.seasons = const [],
    this.restaurantLat,
    this.restaurantLng,
    this.prepTimeMin = 20,
    this.ratingSum = 0,
    this.ratingCount = 0,
    this.listedAt,
    this.stopUntil,
    this.openingHours,
    this.pausedUntil,
  });

  final String restaurantId;
  final String itemId;
  final String name;
  final String photoUrl;
  final int price;

  /// Бир кишилик нарх (`ceil(нарх / порция)`) — порцияси йўқ таомда `null`.
  final int? pricePerPerson;
  final int? servings;
  final int? kcal;
  final int? protein;
  final int? fat;
  final int? carbs;
  final String? cuisineGroup;
  final String? cuisineId;
  final List<String> tags;
  final List<String> sections;

  /// Таомнинг мавсум теглари (ramadan, …) — мавсумий бўлимда ҳозир очиқ мавсум бўйича фильтрланади.
  final List<String> seasons;
  final String restaurantName;
  final double? restaurantLat;
  final double? restaurantLng;
  final int prepTimeMin;

  /// Таом баҳоси агрегати: бутун йиғинди ва сони (ўртача ҳисобда чиқарилади).
  final int ratingSum;
  final int ratingCount;

  /// Таом меню қўшилган вақт («Янги» 30 кун шундан); йўқ бўлса «янги» ҳисобланмайди.
  final DateTime? listedAt;
  final DateTime? stopUntil;
  final OpeningHours? openingHours;
  final DateTime? pausedUntil;

  String get key => '${restaurantId}_$itemId';

  bool get hasNutrition => kcal != null && protein != null && fat != null && carbs != null;

  /// Ўртача баҳо (1..5); баҳо йўқ бўлса 0.
  double get ratingAvg => ratingCount > 0 ? ratingSum / ratingCount : 0;

  bool isAvailableAt(DateTime at) => stopUntil == null || !stopUntil!.isAfter(at);

  /// Ресторан ҳозир буюртма олиши мумкинми (пауза + иш вақти). Ҳақиқий текширув — серверда
  /// (`placeRestaurantOrder`); бу фақат тартиб/хиралаштириш учун.
  bool isRestaurantOpenAt(DateTime at) =>
      (pausedUntil == null || !pausedUntil!.isAfter(at)) && (openingHours?.isOpenAt(at) ?? true);

  double? distanceKmFrom(double? lat, double? lng) {
    final rl = restaurantLat;
    final rg = restaurantLng;
    if (lat == null || lng == null || rl == null || rg == null) return null;
    return haversineMeters(lat, lng, rl, rg) / 1000;
  }

  /// «Янги»: баҳолари созламадаги сондан кам ВА қўшилганига созламадаги кундан ошмаган (D-REST-19).
  bool isNewAt(DateTime at, RestaurantSectionsConfig cfg) {
    final l = listedAt;
    if (l == null || ratingCount >= cfg.newMaxRatings) return false;
    return at.difference(l) <= Duration(days: cfg.newMaxDays);
  }

  /// Рейтинг чегарага етганми — БУТУН сонлар билан (float тенглик хатосисиз): `сумма/сони ≥ чегара`.
  bool meetsRating(double threshold) {
    if (ratingCount <= 0) return false;
    final t100 = (threshold * 100).round();
    return ratingSum * 100 >= t100 * ratingCount;
  }

  factory SectionDish.fromMap(Map<String, dynamic> d) {
    int? optInt(String k, int lo, int hi) {
      final v = d[k];
      if (v is! num || v != v.truncate()) return null;
      final n = v.toInt();
      return n >= lo && n <= hi ? n : null;
    }

    final group = d['cuisineGroup'];
    final cid = d['cuisineId'];
    final cuisineOk = group is String && CuisineGroup.all.contains(group) && cid is String && cid.isNotEmpty;
    final count = _int(d['ratingCount']);
    final sum = _int(d['ratingSum']);
    final valid = count > 0 && sum >= count && sum <= count * 5;
    return SectionDish(
      restaurantId: _str(d['restaurantId']),
      itemId: _str(d['itemId']),
      name: _str(d['name']),
      photoUrl: _str(d['photoUrl']),
      price: _int(d['price']),
      pricePerPerson: optInt('pricePerPerson', 1, 50000000),
      servings: optInt('servings', 1, DishFacts.maxServings),
      kcal: optInt('kcal', 0, DishFacts.maxKcal),
      protein: optInt('protein', 0, DishFacts.maxMacroG),
      fat: optInt('fat', 0, DishFacts.maxMacroG),
      carbs: optInt('carbs', 0, DishFacts.maxMacroG),
      cuisineGroup: cuisineOk ? group : null,
      cuisineId: cuisineOk ? cid : null,
      tags: d['tags'] is List ? (d['tags'] as List).whereType<String>().toList() : const [],
      sections: d['sections'] is List ? (d['sections'] as List).whereType<String>().toList() : const [],
      seasons: d['seasons'] is List ? (d['seasons'] as List).whereType<String>().toList() : const [],
      restaurantName: _str(d['restaurantName']),
      restaurantLat: d['restaurantLat'] is num ? (d['restaurantLat'] as num).toDouble() : null,
      restaurantLng: d['restaurantLng'] is num ? (d['restaurantLng'] as num).toDouble() : null,
      prepTimeMin: optInt('prepTimeMin', 5, 180) ?? 20,
      // Бузилган агрегат (сумма диапазондан ташқари) — «баҳо йўқ»: ўртача 1..5 дан чиқмасин.
      ratingSum: valid ? sum : 0,
      ratingCount: valid ? count : 0,
      listedAt: _ts(d['listedAt']),
      stopUntil: _ts(d['stopUntil']),
      openingHours: OpeningHours.fromMap(d['openingHours'] is Map ? Map<String, dynamic>.from(d['openingHours'] as Map) : null),
      pausedUntil: _ts(d['pausedUntil']),
    );
  }

  factory SectionDish.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) => SectionDish.fromMap(doc.data() ?? const {});
}

/// Тартибланган рўйхатдаги элемент: [isNew] — «Янги» блокидаги таом («Янги» белгиси шунга).
class RankedDish {
  const RankedDish(this.dish, {this.isNew = false, this.isClosed = false});

  final SectionDish dish;
  final bool isNew;

  /// Ресторан ҳозир ёпиқ/пауза — рўйхат охирида, хира.
  final bool isClosed;
}

/// Бўлим рўйхатини тартиблаш (D-REST-19, D-REST-20). Соф функция.
///
/// 1. «Янги» блок (тепада): баҳоси кам ва 30 кундан ошмаган; бир ресторандан бўлим бошига энг кўпи
///    [RestaurantSectionsConfig.newPerRestaurantPerSection] (ресторан ичида энг янгилари); блок ичида
///    бўлимнинг ўз калити: «Арзон» — бир кишилик нарх ўсиши, «Фаст-фуд» — тайёрлаш вақти, қолганлари — энг
///    янгиси олдин (PROPOSED). Лимитдан ошганлари асосий рўйхатга тушади.
/// 2. Асосий рўйхат: «Арзон» — рейтинги чегарадан кам бўлмаганлар бир кишилик нарх бўйича, кейин қолганлар
///    шу тартибда (ҳеч ким чиқарилмайди); «Фаст-фуд» — тайёрлаш вақти, кейин рейтинг; қолганлар — рейтинг
///    (PROPOSED). Тенгликда: масофа, кейин ном.
/// 3. Ёпиқ ресторан таомлари ҲАММАСИДАН кейин (PROPOSED), ичида ўша тартиб.
/// Тўхтатилган (`stopUntil`) таомлар рўйхатга кирмайди.
List<RankedDish> rankSectionDishes(
  List<SectionDish> input, {
  required RestaurantSection section,
  required RestaurantSectionsConfig config,
  required DateTime now,
  double? lat,
  double? lng,
}) {
  final dishes = input.where((d) => d.isAvailableAt(now)).toList();

  int byDistanceName(SectionDish a, SectionDish b) {
    final da = a.distanceKmFrom(lat, lng);
    final db = b.distanceKmFrom(lat, lng);
    if (da != null && db != null && da != db) return da.compareTo(db);
    if (da == null && db != null) return 1;
    if (da != null && db == null) return -1;
    final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return n != 0 ? n : a.key.compareTo(b.key);
  }

  int cmpRating(SectionDish a, SectionDish b) {
    // Баҳоси борлар олдин; ўртача (крест-кўпайтириш: сумма·сони, float йўқ), кейин сони.
    if (a.ratingCount == 0 && b.ratingCount == 0) return 0;
    if (a.ratingCount == 0) return 1;
    if (b.ratingCount == 0) return -1;
    final c = (b.ratingSum * a.ratingCount).compareTo(a.ratingSum * b.ratingCount);
    return c != 0 ? c : b.ratingCount.compareTo(a.ratingCount);
  }

  // Бир кишилик нарх «Арзон»да сервер томонидан кафолатланади; бўлмаса — энг охирга.
  int cmpPrice(SectionDish a, SectionDish b) =>
      (a.pricePerPerson ?? (1 << 30)).compareTo(b.pricePerPerson ?? (1 << 30));

  /// Бўлимнинг ўз калити (асосий рўйхат ва «Янги» блоки учун).
  int Function(SectionDish, SectionDish) sectionKey() {
    switch (section) {
      case RestaurantSection.cheap:
        return (a, b) {
          final c = cmpPrice(a, b);
          return c != 0 ? c : byDistanceName(a, b);
        };
      case RestaurantSection.all:
        // Оч одам учун: энг яқини олдин, кейин рейтинг (D-REST-40).
        return (a, b) {
          final da = a.distanceKmFrom(lat, lng);
          final db = b.distanceKmFrom(lat, lng);
          if (da != null && db != null && da != db) return da.compareTo(db);
          if (da == null && db != null) return 1;
          if (da != null && db == null) return -1;
          final r = cmpRating(a, b);
          return r != 0 ? r : byDistanceName(a, b);
        };
      case RestaurantSection.fast:
        return (a, b) {
          final c = a.prepTimeMin.compareTo(b.prepTimeMin);
          if (c != 0) return c;
          final r = cmpRating(a, b);
          return r != 0 ? r : byDistanceName(a, b);
        };
      default:
        return (a, b) {
          final c = cmpRating(a, b);
          return c != 0 ? c : byDistanceName(a, b);
        };
    }
  }

  /// «Янги» блоки ичида: «Арзон»/«Фаст» — ўз калити; қолганлари — энг янгиси олдин.
  int Function(SectionDish, SectionDish) newKey() {
    if (section == RestaurantSection.cheap || section == RestaurantSection.fast) return sectionKey();
    return (a, b) {
      final c = (b.listedAt ?? DateTime(0)).compareTo(a.listedAt ?? DateTime(0));
      return c != 0 ? c : byDistanceName(a, b);
    };
  }

  // 1. «Янги» блок: ресторан бошига чегара (ресторан ичида энг янгилари), ёпиқлар кейинга қолади.
  final open = dishes.where((d) => d.isRestaurantOpenAt(now)).toList();
  final closed = dishes.where((d) => !d.isRestaurantOpenAt(now)).toList();

  List<SectionDish> pickNew(List<SectionDish> group) {
    final byRest = <String, List<SectionDish>>{};
    for (final d in group.where((d) => d.isNewAt(now, config))) {
      byRest.putIfAbsent(d.restaurantId, () => []).add(d);
    }
    final picked = <SectionDish>[];
    for (final list in byRest.values) {
      list.sort((a, b) {
        final c = (b.listedAt ?? DateTime(0)).compareTo(a.listedAt ?? DateTime(0));
        return c != 0 ? c : a.key.compareTo(b.key);
      });
      picked.addAll(list.take(config.newPerRestaurantPerSection));
    }
    picked.sort(newKey());
    return picked;
  }

  List<SectionDish> mainOrder(List<SectionDish> rest) {
    final list = List<SectionDish>.of(rest);
    if (section == RestaurantSection.cheap) {
      final high = list.where((d) => d.meetsRating(config.cheapRatingThreshold)).toList()..sort(sectionKey());
      final low = list.where((d) => !d.meetsRating(config.cheapRatingThreshold)).toList()..sort(sectionKey());
      return [...high, ...low];
    }
    return list..sort(sectionKey());
  }

  final out = <RankedDish>[];
  final newOpen = pickNew(open);
  final taken = {for (final d in newOpen) d.key};
  out.addAll(newOpen.map((d) => RankedDish(d, isNew: true)));
  out.addAll(mainOrder(open.where((d) => !taken.contains(d.key)).toList()).map(RankedDish.new));
  // Ёпиқ ресторанлар: «Янги» блоки йўқ (буюртма бериб бўлмайди) — оддий тартибда охирида.
  out.addAll(mainOrder(closed).map((d) => RankedDish(d, isClosed: true)));
  return out;
}

/// Кухна фильтри чиплари: таомлар орасида учрайдиган кухналар (камида битта таоми борлари) ва сони —
/// мижозга бўш чип кўрсатилмайди (D-REST-24). Сони бўйича камайиш, тенгликда id.
List<({String id, int count})> cuisinesIn(Iterable<SectionDish> dishes) {
  final counts = <String, int>{};
  for (final d in dishes) {
    final id = d.cuisineId;
    if (id != null) counts[id] = (counts[id] ?? 0) + 1;
  }
  final out = [for (final e in counts.entries) (id: e.key, count: e.value)];
  out.sort((a, b) => a.count != b.count ? b.count.compareTo(a.count) : a.id.compareTo(b.id));
  return out;
}

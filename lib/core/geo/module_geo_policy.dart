/// Ҳар модулнинг ҳудуд қоидаси — ЯГОНА МАНБА (docs/hudud_geo_tizimi_uz.md,
/// эга қарорлари D-GEO-1…15, 2026-10-11). Модул экранлари ва бош саҳифа
/// бўлимлари ҳудудни шу жадвалга қараб танлайди; қоида бошқа жойда
/// такрорланмайди (7-банд).
library;

/// Кўриниш даражаси.
enum GeoLevel { district, region, nation }

/// Модул ҳудудни қандай ишлатади.
enum GeoMode {
  /// Доим бутун Республика (Хитой бозори).
  nationwide,

  /// Фойдаланувчи даражани ўзи танлайди: Республика / вилоят / туман
  /// (Улгуржи — ҳар сафар Республикадан, D-GEO-10).
  chooser,

  /// Аввал туман, кейин «Вилоят бўйича», «Бутун Ўзбекистон» тугмалари
  /// (Аҳоли бозори, Эълонлар, Хизматлар, Кўчмас мулк, AVAGram).
  tiered,

  /// GPS масофаси ва радиус (такси, кафе, курьер, EV) — туман чегараси
  /// шарт эмас (D-GEO-2).
  distance,

  /// Маршрут: қаердан → қаерга → қачон (шаҳарлараро такси ва юк).
  route,

  /// Ҳудуд ишида қатнашмайди (Танишув — Telegram бот, D-GEO-5).
  none,

  /// «Ҳалқалар» (эга, 2026-11-15): сукут — БАРЧА эълонлар Республика бўйича,
  /// яқиндан узоққа: 1-ҳалқа фойдаланувчи тумани → 2-ҳалқа вилоятнинг қолган
  /// туманлари → 3+ бошқа вилоятлар (вилоят марказлари орасидаги масофа бўйича,
  /// `region_centers.dart`). Фойдаланувчи ҳудудни ўзи танласа — фақат шу ҳудуд.
  /// Мотор: `ring_query.dart`. Бозорлар + Улгуржи + Хитой + Кўчмас мулк.
  ///
  /// ЎТИШ ДАВРИ (3+4-босқич): Улгуржи/Хитой/Кўчмас мулк экранлари ҳали
  /// `mode`ни ўқимайди — улар `levels`/`defaultLevel`/`persistSelection` бўйича
  /// аввалгидек ишлайди (қийматлар ўзгармаган). Ҳалқаларга кейинги босқичда ўтади.
  rings,
}

class ModuleGeoPolicy {
  const ModuleGeoPolicy({
    required this.moduleId,
    required this.mode,
    this.levels = const [GeoLevel.district, GeoLevel.region, GeoLevel.nation],
    this.defaultLevel = GeoLevel.district,
    this.persistSelection = true,
    this.usesLocation = false,
  });

  final String moduleId;
  final GeoMode mode;

  /// Фойдаланувчига очиқ даражалар (тартиб — тугмалар тартиби).
  final List<GeoLevel> levels;

  /// Модул очилганда даража.
  final GeoLevel defaultLevel;

  /// Танланган ҳудуд/даража кейинги киришда сақланадими (D-GEO-1;
  /// Улгуржида — йўқ, D-GEO-10).
  final bool persistSelection;

  /// Жорий локация ишлатиладими (GPS масофаси ёки локация таклифи).
  final bool usesLocation;
}

const _all = [GeoLevel.district, GeoLevel.region, GeoLevel.nation];

/// Бозорлар: `nation` = ҳалқалар (сукут), region/district = аниқ танлов.
const _marketLevels = [GeoLevel.nation, GeoLevel.region, GeoLevel.district];

/// Модул ID'лари — `kKnownModuleIds` / бош экран модуллари билан бир хил.
const Map<String, ModuleGeoPolicy> kModuleGeoPolicies = {
  // 2026-11-15: china/wholesale/realty → `rings` (аввал nationwide/chooser/tiered).
  // levels/defaultLevel/persistSelection ЎЗГАРМАГАН — экранлар аввалгидек.
  'china_market': ModuleGeoPolicy(
    moduleId: 'china_market',
    mode: GeoMode.rings, // аввал: nationwide
    // 7-босқич (эга, 2026-11-15): вилоят/туман танлови ҳам (сотувчининг жўнатиш тумани бўйича).
    levels: _marketLevels,
    defaultLevel: GeoLevel.nation,
    persistSelection: false,
  ),
  'wholesale_market': ModuleGeoPolicy(
    moduleId: 'wholesale_market',
    mode: GeoMode.rings, // аввал: chooser
    levels: [GeoLevel.nation, GeoLevel.region, GeoLevel.district],
    defaultLevel: GeoLevel.nation,
    persistSelection: false, // D-GEO-10: ҳар сафар «Бутун Ўзбекистон»
  ),
  'cheap_products_home': ModuleGeoPolicy(
    moduleId: 'cheap_products_home',
    mode: GeoMode.tiered,
    levels: _all,
  ),
  'jobs': ModuleGeoPolicy(
    moduleId: 'jobs',
    mode: GeoMode.tiered,
    levels: _all,
    usesLocation: true,
  ),
  'realty': ModuleGeoPolicy(
    moduleId: 'realty',
    mode: GeoMode.rings, // аввал: tiered
    // 7-босқич (эга, 2026-11-15): сукут — Республика ҳалқалари, танлов САҚЛАНМАЙДИ (аввал: туман, сақланарди).
    // Бош саҳифа бўлими аввалгидек туман — home_realty_section.dart аниқ туман scope беради.
    levels: _marketLevels,
    defaultLevel: GeoLevel.nation,
    persistSelection: false,
    usesLocation: true,
  ),
  // «Бозорлар» (эга, 2026-11-15): сукут — Республика ҳалқалари; танлов
  // сақланмайди (PROPOSED: ҳар киришда яна ҳалқалар).
  'livestock_market': ModuleGeoPolicy(
    moduleId: 'livestock_market',
    mode: GeoMode.rings,
    levels: _marketLevels,
    defaultLevel: GeoLevel.nation,
    persistSelection: false,
  ),
  'auto_market': ModuleGeoPolicy(
    moduleId: 'auto_market',
    mode: GeoMode.rings,
    levels: _marketLevels,
    defaultLevel: GeoLevel.nation,
    persistSelection: false,
  ),
  'meat_market': ModuleGeoPolicy(
    moduleId: 'meat_market',
    mode: GeoMode.rings,
    levels: _marketLevels,
    defaultLevel: GeoLevel.nation,
    persistSelection: false,
  ),
  'farm_market': ModuleGeoPolicy(
    moduleId: 'farm_market',
    mode: GeoMode.rings,
    levels: _marketLevels,
    defaultLevel: GeoLevel.nation,
    persistSelection: false,
  ),
  'tv_market': ModuleGeoPolicy(
    moduleId: 'tv_market',
    mode: GeoMode.tiered,
    levels: _all,
  ),
  'yuk_local': ModuleGeoPolicy(
    moduleId: 'yuk_local',
    mode: GeoMode.tiered,
    levels: [GeoLevel.district, GeoLevel.region], // D-GEO-6
    usesLocation: true,
  ),
  'local_taxi': ModuleGeoPolicy(
    moduleId: 'local_taxi',
    mode: GeoMode.distance,
    levels: [GeoLevel.district],
    usesLocation: true,
  ),
  'marshrut': ModuleGeoPolicy(
    moduleId: 'marshrut',
    mode: GeoMode.distance,
    levels: [GeoLevel.district],
    usesLocation: true,
  ),
  'restaurants': ModuleGeoPolicy(
    moduleId: 'restaurants',
    mode: GeoMode.distance, // D-GEO-4: яқиндагилар; ном бўйича қидирув — Республика
    levels: [GeoLevel.district],
    usesLocation: true,
  ),
  'courier': ModuleGeoPolicy(
    moduleId: 'courier',
    mode: GeoMode.distance, // D-GEO-3: GPS + 15 км
    levels: [GeoLevel.district],
    usesLocation: true,
  ),
  'ev_charging': ModuleGeoPolicy(
    moduleId: 'ev_charging',
    mode: GeoMode.distance,
    levels: _all,
    usesLocation: true,
  ),
  'intercity': ModuleGeoPolicy(
    moduleId: 'intercity',
    mode: GeoMode.route,
    levels: [GeoLevel.district, GeoLevel.region],
    usesLocation: true,
  ),
  'yuk_intercity': ModuleGeoPolicy(
    moduleId: 'yuk_intercity',
    mode: GeoMode.route,
    levels: [GeoLevel.district, GeoLevel.region],
    usesLocation: true,
  ),
  'dating': ModuleGeoPolicy(
    moduleId: 'dating',
    mode: GeoMode.none, // D-GEO-5
    levels: [],
    persistSelection: false,
  ),
};

/// Жадвалда йўқ модул — ҳудудсиз (ҳеч нарса яширилмайди).
ModuleGeoPolicy geoPolicyFor(String moduleId) =>
    kModuleGeoPolicies[moduleId] ??
    ModuleGeoPolicy(
      moduleId: moduleId,
      mode: GeoMode.none,
      levels: const [],
      persistSelection: false,
    );

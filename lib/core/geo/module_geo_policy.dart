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

/// Модул ID'лари — `kKnownModuleIds` / бош экран модуллари билан бир хил.
const Map<String, ModuleGeoPolicy> kModuleGeoPolicies = {
  'china_market': ModuleGeoPolicy(
    moduleId: 'china_market',
    mode: GeoMode.nationwide,
    levels: [GeoLevel.nation],
    defaultLevel: GeoLevel.nation,
    persistSelection: false,
  ),
  'wholesale_market': ModuleGeoPolicy(
    moduleId: 'wholesale_market',
    mode: GeoMode.chooser,
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
    mode: GeoMode.tiered,
    levels: _all,
    usesLocation: true, // D-GEO-11/15: истаган ҳудуд, танлов сақланади
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

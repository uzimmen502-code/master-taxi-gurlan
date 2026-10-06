// ТАЛАБ → ТАКЛИФ ядроси — режим, статус ва модул энумлари.
//
// Бу файлда ТАШҚИ боғламлар йўқ (Firestore эмас) — шунинг учун
// `flutter test`да плагинсиз ишлайди.
//
// Сервердаги манба: `functions_demand/core/state_machine.js`.
// Иккисининг ажралиб кетмаслиги `test/features/demand_offer/
// demand_parity_test.dart` билан қулфланган: сервер ва илова бир хил
// сатрларни ишлатиши ШАРТ, акс ҳолда статус «номаълум» бўлиб қолади.

/// Талаб қандай ишлайди. Фойдаланувчи буни ТАНЛАМАЙДИ — модул эълон
/// қилади (сервердаги adapter). Шунинг учун `createDemand` юкламасида
/// `mode` майдони умуман йўқ ва схема уни рад этади.
enum DemandMode {
  /// Битта ижрочи сониялар ичида керак. Биринчи «Қабул қилиш» ғолиб.
  dispatch,

  /// Таклифлар йиғилади, харидор танлайди.
  quote,

  /// Мос эълон ёки таклифчи пайдо бўлса хабар беради.
  alert,

  /// Жадвал ёки обуна бўйича.
  recurring;

  static DemandMode? tryParse(String? v) {
    for (final m in DemandMode.values) {
      if (m.name == v) return m;
    }
    return null;
  }

  /// `in_progress` статуси шу режимда ишлатиладими.
  ///
  /// `alert` ва `recurring`да «бажариш» тушунчаси бошқа, шунинг учун
  /// улар `accepted`дан тўғридан-тўғри `completed`га ўтади.
  bool get usesInProgress => this == DemandMode.dispatch || this == DemandMode.quote;
}

/// Талаб статуси. Фақат СЕРВЕР ўзгартиради.
///
/// Концепциядаги `matched` статуси ЙЎҚ: у статус эмас, matching ҳолати
/// эди ва [DemandMatchingState]га кўчирилди.
enum DemandStatus {
  draft,
  active,
  accepted,
  inProgress,
  completed,
  cancelled,
  expired,
  disputed;

  /// Сервердаги сатр шакли (`snake_case`).
  String get wire {
    switch (this) {
      case DemandStatus.inProgress:
        return 'in_progress';
      default:
        return name;
    }
  }

  static DemandStatus? tryParse(String? v) {
    if (v == null) return null;
    for (final s in DemandStatus.values) {
      if (s.wire == v) return s;
    }
    return null;
  }

  /// Бошқа ўтиш йўқ (ёки фақат низо).
  bool get isTerminal =>
      this == DemandStatus.completed || this == DemandStatus.cancelled;

  /// Ҳали таклиф кутяптими.
  bool get isOpenForOffers => this == DemandStatus.active;

  /// Фойдаланувчи кўрадиган матн калити (`assets/lang/*.json`).
  ///
  /// ДИҚҚАТ: техник сўзлар («Demand», «Талаб яратиш») ҲЕЧ ҚАЧОН
  /// кўрсатилмайди — концепциянинг ўзгармайдиган қоидаси.
  String get l10nKey => 'demand_status_$wire';
}

/// Matching ҳолати — статусдан БУТУНЛАЙ ажратилган майдон.
enum DemandMatchingState {
  pending,
  running,
  done,
  noProviders,
  failed;

  String get wire {
    switch (this) {
      case DemandMatchingState.noProviders:
        return 'no_providers';
      default:
        return name;
    }
  }

  static DemandMatchingState? tryParse(String? v) {
    if (v == null) return null;
    for (final s in DemandMatchingState.values) {
      if (s.wire == v) return s;
    }
    return null;
  }

  /// «Ҳозирча мос таклифчи йўқ. Пайдо бўлса, хабар берамиз».
  ///
  /// Концепция талаби: мижоз бўш экранни кўрмайди ва талаб `active`
  /// ҳолатда қолади.
  bool get showsWaitingMessage => this == DemandMatchingState.noProviders;
}

/// Таклиф статуси.
enum OfferStatus {
  active,
  withdrawn,
  accepted,
  rejected,
  expired;

  String get wire => name;

  static OfferStatus? tryParse(String? v) {
    for (final s in OfferStatus.values) {
      if (s.name == v) return s;
    }
    return null;
  }
}

/// Ядрога уланган модуллар.
///
/// Рўйхат сервердаги `demand_input.schema.json` билан бир хил бўлиши
/// ШАРТ — акс ҳолда илова сервер қабул қилмайдиган модул юборади.
enum DemandModule {
  service,
  courier,
  intercityTaxi,
  localTaxi,
  freightLocal,
  freightIntercity,
  sell,
  market,
  platformStore,
  realty,
  food,
  oilChange,
  carpetWash,
  bread,
  agroPickup,

  /// AVA Logistics (Relay) — LEG = `demands` ҳужжати. ФАҚАТ сервер
  /// яратади (`createLogisticsOrder`); `createDemand` схемасида АТАЙЛАБ
  /// йўқ — мижоз жўнатмани буюртма/тўлов орқали беради, талаб орқали эмас.
  logistics;

  /// Сервер томонидан яратиладиган модул — мижоз «сўров» сифатида кўрмайди.
  bool get isServerOnly => this == DemandModule.logistics;

  String get wire {
    switch (this) {
      case DemandModule.intercityTaxi:
        return 'intercity_taxi';
      case DemandModule.localTaxi:
        return 'local_taxi';
      case DemandModule.freightLocal:
        return 'freight_local';
      case DemandModule.freightIntercity:
        return 'freight_intercity';
      case DemandModule.platformStore:
        return 'platform_store';
      case DemandModule.oilChange:
        return 'oil_change';
      case DemandModule.carpetWash:
        return 'carpet_wash';
      case DemandModule.agroPickup:
        return 'agro_pickup';
      default:
        return name;
    }
  }

  static DemandModule? tryParse(String? v) {
    if (v == null) return null;
    for (final m in DemandModule.values) {
      if (m.wire == v) return m;
    }
    return null;
  }
}

/// Мос таклифчилар сонининг «панжараси».
///
/// Т-8: аниқ рақам ҲЕЧ КИМГА кўрсатилмайди — харидорнинг ўзи рақобатчи
/// бўлиши мумкин. Сервер фақат шу сатрларни беради.
class MatchedBucket {
  const MatchedBucket._(this.wire);

  final String wire;

  static const none = MatchedBucket._('0');
  static const few = MatchedBucket._('1-2');
  static const some = MatchedBucket._('3-5');
  static const several = MatchedBucket._('6-10');
  static const many = MatchedBucket._('10+');
  static const lots = MatchedBucket._('30+');
  static const crowd = MatchedBucket._('100+');

  static const all = <MatchedBucket>[
    none, few, some, several, many, lots, crowd,
  ];

  static MatchedBucket parse(String? v) {
    for (final b in all) {
      if (b.wire == v) return b;
    }
    return none;
  }

  bool get isEmpty => wire == '0';

  @override
  String toString() => wire;

  @override
  bool operator ==(Object other) =>
      other is MatchedBucket && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

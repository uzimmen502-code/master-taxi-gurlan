// ⚡ EV сафар ёрдамчиси — «Қаерга борамиз?» режасининг моделлари.
//
// Бу файлда ТАШҚИ боғламлар йўқ (Firestore/Google Maps эмас) — режа
// ҳисоби тоза Dart, шунинг учун `flutter test`да плагинсиз ишлайди.
// Станциялар базаси БИЗНИНГ (`ev_charging_stations`); бу модел фақат
// «қайси нуқтада тўхтаймиз» саволига жавоб беради.

import '../../../models/ev_charging_station.dart';

/// Фойдаланувчининг автомобили — «Менинг автомобилларим»да бир марта
/// сақланади, кейин ҳар сафарда қайта сўралмайди.
class EvCarSpec {
  const EvCarSpec({
    required this.usableBatteryKwh,
    required this.consumptionKwhPer100Km,
    this.connectors = const [],
    this.reservePercent = 10,
    this.chargeToPercent = 80,
  });

  /// ФОЙДАЛАНИЛАДИГАН батарея сиғими (kWh) — паспортдаги тўлиқ сиғим эмас
  /// (одатда унинг ~92–96%). Фойдаланувчи паспорт қийматини ёзса ҳам режа
  /// хавфсиз томонга оғиши учун [reservePercent] бор.
  final double usableBatteryKwh;

  /// Реал сарф (kWh/100 км) — тезлик, иситиш ва юкка қараб ўзгаради.
  final double consumptionKwhPer100Km;

  /// Машинанинг разъёмлари (`CCS2`, `Type 2`, `GB/T`, `CHAdeMO`).
  /// Бўш бўлса — станциялар разъём бўйича филтрланмайди (маълумот йўқ
  /// деб ҳисобланади, нотўғри филтрлаб керакли станцияни яшириб
  /// қўйишдан кўра кўрсатиш хавфсизроқ).
  final List<String> connectors;

  /// Заҳира — режа ҳеч қачон батареяни бу фоиздан пастга туширмайди.
  final int reservePercent;

  /// Станцияда қанчага зарядлаш режалаштирилади. 100% эмас: DC'да охирги
  /// 20% энг секин зарядланади, шунинг учун default 80%.
  final int chargeToPercent;

  bool get isValid =>
      usableBatteryKwh > 0 &&
      consumptionKwhPer100Km > 0 &&
      reservePercent >= 0 &&
      reservePercent < 100 &&
      chargeToPercent > reservePercent &&
      chargeToPercent <= 100;

  /// Берилган заряд фоизида юриладиган масофа (км).
  double rangeKmAt(num socPercent) {
    if (!isValid || socPercent <= 0) return 0;
    final kwh = usableBatteryKwh * socPercent / 100;
    return kwh / consumptionKwhPer100Km * 100;
  }

  /// Заҳирани ҳисобга олган ҲАҚИҚИЙ юриш масофаси.
  double usableRangeKmAt(num socPercent) =>
      rangeKmAt((socPercent - reservePercent).clamp(0, 100));

  EvCarSpec copyWith({
    double? usableBatteryKwh,
    double? consumptionKwhPer100Km,
    List<String>? connectors,
    int? reservePercent,
    int? chargeToPercent,
  }) {
    return EvCarSpec(
      usableBatteryKwh: usableBatteryKwh ?? this.usableBatteryKwh,
      consumptionKwhPer100Km:
          consumptionKwhPer100Km ?? this.consumptionKwhPer100Km,
      connectors: connectors ?? this.connectors,
      reservePercent: reservePercent ?? this.reservePercent,
      chargeToPercent: chargeToPercent ?? this.chargeToPercent,
    );
  }

  Map<String, dynamic> toMap() => {
        'usableBatteryKwh': usableBatteryKwh,
        'consumptionKwhPer100Km': consumptionKwhPer100Km,
        'connectors': connectors,
        'reservePercent': reservePercent,
        'chargeToPercent': chargeToPercent,
      };

  factory EvCarSpec.fromMap(Map<String, dynamic>? json) {
    final d = json ?? const <String, dynamic>{};
    return EvCarSpec(
      usableBatteryKwh: (d['usableBatteryKwh'] as num?)?.toDouble() ?? 0,
      consumptionKwhPer100Km:
          (d['consumptionKwhPer100Km'] as num?)?.toDouble() ?? 0,
      connectors: List<String>.from(d['connectors'] as List? ?? const []),
      reservePercent: (d['reservePercent'] as num?)?.toInt() ?? 10,
      chargeToPercent: (d['chargeToPercent'] as num?)?.toInt() ?? 80,
    );
  }
}

/// Маршрут коридорига тушган станция — йўл бошидан [alongKm] да, йўл
/// чизиғидан [offRouteKm] четда.
class EvCorridorStation {
  const EvCorridorStation({
    required this.station,
    required this.alongKm,
    required this.offRouteKm,
  });

  final EvChargingStation station;
  final double alongKm;
  final double offRouteKm;
}

/// Заҳира вариант — асосий станция мос келмаса ёки заряд кутилгандан тез
/// тушса ишлатилади.
class EvTripBackup {
  const EvTripBackup({
    required this.station,
    required this.alongKm,
    required this.offRouteKm,
    required this.deltaKm,
  });

  final EvChargingStation station;
  final double alongKm;
  final double offRouteKm;

  /// Асосий станцияга нисбатан: манфий — ундан ОЛДИН, мусбат — КЕЙИН.
  final double deltaKm;

  /// Асосийдан олдинги заҳира — заряд кутилгандан тез тушса шу ишлатилади,
  /// шунинг учун бу «хавфсиз» заҳира.
  bool get isBefore => deltaKm < 0;
}

/// Режадаги битта тўхташ.
class EvTripStop {
  const EvTripStop({
    required this.station,
    required this.alongKm,
    required this.offRouteKm,
    required this.legKm,
    required this.arriveSocPercent,
    required this.departSocPercent,
    required this.backups,
  });

  final EvChargingStation station;

  /// Йўл бошидан бу станциягача (км).
  final double alongKm;
  final double offRouteKm;

  /// Олдинги тўхташдан (ёки йўл бошидан) бу станциягача — «станциялар
  /// орасидаги масофа».
  final double legKm;

  final int arriveSocPercent;
  final int departSocPercent;

  final List<EvTripBackup> backups;

  bool get hasBackup => backups.isNotEmpty;

  /// Асосий станциядан ОЛДИН турган заҳиралар — заряд тез тушса керак
  /// бўладиганлар.
  List<EvTripBackup> get backupsBefore =>
      backups.where((b) => b.isBefore).toList();

  /// Бу нуқтага ишонч даражаси — жойида текширилганми.
  bool get isVerified =>
      station.verificationStatus == 'verified' ||
      station.verificationStatus == 'operator_verified';

  /// Фақат очиқ манбадан импорт, ҳеч ким тасдиқламаган — ҳайдовчига
  /// «бу текширилмаган» деб кўрсатилиши ШАРТ.
  bool get isUnverifiedImport =>
      station.isImported &&
      station.confirmationCount == 0 &&
      station.status == 'unknown';
}

enum EvTripPlanStatus {
  /// Режа тузилди.
  ok,

  /// Зарядлашга ҳожат йўқ — ҳозирги заряд етади.
  noChargingNeeded,

  /// Маршрутда станциялар орасидаги узилиш машина имкониятидан катта —
  /// режа ЎЙЛАБ ТОПИЛМАЙДИ, ҳайдовчига очиқ айтилади.
  gapTooLarge,

  /// Автомобил маълумоти тўлиқ эмас/нотўғри.
  invalidCar,

  /// Маршрут геометрияси олинмади.
  noRoute,
}

/// Огоҳлантириш кодлари — UI'да уч тилга таржима қилинади (l10n калити
/// сифатида ишлатилади, матн бу ерда сақланмайди).
class EvTripWarning {
  static const unverifiedStops = 'ev_trip_warn_unverified_stops';
  static const noBackup = 'ev_trip_warn_no_backup';
  static const startSocBelowReserve = 'ev_trip_warn_start_soc_below_reserve';
  static const connectorUnknown = 'ev_trip_warn_connector_unknown';
  static const slowAcOnly = 'ev_trip_warn_slow_ac_only';
}

class EvTripPlan {
  const EvTripPlan({
    required this.status,
    required this.stops,
    required this.totalKm,
    required this.arrivalSocPercent,
    this.warnings = const [],
    this.gapFromKm,
    this.gapReachKm,
    this.gapNextStationKm,
  });

  final EvTripPlanStatus status;
  final List<EvTripStop> stops;
  final double totalKm;

  /// Манзилга етиб келгандаги кутилган заряд (%).
  final int arrivalSocPercent;

  final List<String> warnings;

  /// [EvTripPlanStatus.gapTooLarge] да: қаердан бошлаб йўл узилган (км),
  /// машина қаергача етади ва кейинги станция қаерда.
  final double? gapFromKm;
  final double? gapReachKm;
  final double? gapNextStationKm;

  bool get isOk =>
      status == EvTripPlanStatus.ok ||
      status == EvTripPlanStatus.noChargingNeeded;

  int get chargeStopCount => stops.length;

  /// Энг узун босқич — ҳайдовчи учун асосий хавф кўрсаткичи.
  double get longestLegKm {
    var longest = 0.0;
    for (final s in stops) {
      if (s.legKm > longest) longest = s.legKm;
    }
    final lastAlong = stops.isEmpty ? 0.0 : stops.last.alongKm;
    final tail = totalKm - lastAlong;
    return tail > longest ? tail : longest;
  }

  static const EvTripPlan empty = EvTripPlan(
    status: EvTripPlanStatus.noRoute,
    stops: [],
    totalKm: 0,
    arrivalSocPercent: 0,
  );
}

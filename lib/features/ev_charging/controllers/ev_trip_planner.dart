import 'dart:math' as math;

import '../../../models/ev_charging_station.dart';
import '../models/ev_trip_plan.dart';

/// Маршрут чизиғининг битта нуқтаси. `google_maps_flutter`'нинг `LatLng`
/// ўрнига ўз типи — планер тоза Dart бўлиб қолиши учун (плагинсиз
/// `flutter test`да ишлайди).
class EvRoutePoint {
  const EvRoutePoint(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// Нуқтанинг маршрутдаги энг яқин жойи ([EvTripPlanner.locate] натижаси).
class EvRouteLocation {
  const EvRouteLocation({
    required this.segmentIndex,
    required this.fractionInSegment,
    required this.alongKm,
    required this.offRouteKm,
    required this.lat,
    required this.lng,
  });

  /// Энг яқин сегмент: `route[segmentIndex]` → `route[segmentIndex + 1]`.
  final int segmentIndex;

  /// Сегмент ичидаги жой (0 — боши, 1 — охири).
  final double fractionInSegment;

  /// Чизиқ боши ВА шу нуқта орасидаги масофа (км, геометрия бўйича).
  final double alongKm;

  /// Нуқта чизиқдан қанча узоқда (км).
  final double offRouteKm;

  /// Нуқтанинг чизиққа проекцияси.
  final double lat;
  final double lng;
}

/// ⚡ EV сафар ёрдамчиси — ҳисоб ядроси.
///
/// Иккита алоҳида босқич:
///   1. [corridor] — 456 та станциядан маршрут яқинидагиларини ажратиш ва
///      ҳар бирини йўл бўйлаб масофага проекция қилиш. ТАШҚИ СЎРОВ ЙЎҚ:
///      база аллақачон хотирада (`watchAllActive`), шунинг учун бу ҳисоб
///      телефонда, бепул ва офлайн бажарилади.
///   2. [plan] — заряд ҳисоби билан асосий ва заҳира тўхташларни танлаш.
///
/// Муҳим қоида: режа ЎЙЛАБ ТОПИЛМАЙДИ. Станция етмаса
/// [EvTripPlanStatus.gapTooLarge] қайтади ва ҳайдовчига узилиш қаерда
/// эканлиги кўрсатилади — «режа бор» деб чўлда қолдиришдан кўра яхши.
class EvTripPlanner {
  const EvTripPlanner._();

  /// Йўл чизиғидан қанча четдаги станциялар ҳисобга олинади.
  /// 5 км — overview polyline соддалаштирилганини (вершиналар орасида
  /// 1–3 км) ҳисобга олган эҳтиёткор қиймат.
  static const double defaultCorridorKm = 5;

  /// Ҳар тўхташ учун кўрсатиладиган заҳира сони.
  static const int maxBackupsPerStop = 3;

  /// Чексиз цикл ва маъносиз узун режалардан ҳимоя.
  static const int maxStops = 12;

  /// Асосий станцияни танлашда «эрта тўхташ»дан қочиш: етиб бориш
  /// мумкин бўлган масофанинг шу фоизидан кейинги станциялар устун
  /// кўрилади (яъни имкониятнинг охирги 35%и).
  static const double _preferTailFraction = 0.65;

  // ---------------------------------------------------------------------
  // 1-босқич: коридор
  // ---------------------------------------------------------------------

  /// Маршрут яқинидаги станциялар — йўл бўйлаб масофа бўйича тартибланган.
  ///
  /// Такрорлар (бир станция икки марта) бўлмайди: ҳар станция учун энг
  /// яқин сегмент танланади.
  static List<EvCorridorStation> corridor({
    required List<EvRoutePoint> route,
    required List<EvChargingStation> stations,
    double corridorKm = defaultCorridorKm,
  }) {
    if (route.length < 2 || stations.isEmpty) return const [];

    // Ҳар вершинагача жамланган масофа — проекцияда ишлатилади.
    final cumKm = List<double>.filled(route.length, 0);
    for (var i = 1; i < route.length; i++) {
      cumKm[i] = cumKm[i - 1] + _distanceKm(route[i - 1], route[i]);
    }

    final result = <EvCorridorStation>[];
    for (final s in stations) {
      var bestOffKm = double.infinity;
      var bestAlongKm = 0.0;

      for (var i = 0; i < route.length - 1; i++) {
        final seg = _projectOnSegment(
          lat: s.latitude,
          lng: s.longitude,
          a: route[i],
          b: route[i + 1],
        );
        if (seg.offKm < bestOffKm) {
          bestOffKm = seg.offKm;
          bestAlongKm = cumKm[i] + seg.alongKm;
        }
      }

      if (bestOffKm <= corridorKm) {
        result.add(EvCorridorStation(
          station: s,
          alongKm: bestAlongKm,
          offRouteKm: bestOffKm,
        ));
      }
    }

    result.sort((a, b) => a.alongKm.compareTo(b.alongKm));
    return result;
  }

  /// Маршрут чизиғининг тўлиқ узунлиги (км) — Directions'даги
  /// `distanceKm` бўлмаса шу ишлатилади.
  static double routeLengthKm(List<EvRoutePoint> route) {
    if (route.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < route.length; i++) {
      total += _distanceKm(route[i - 1], route[i]);
    }
    return total;
  }

  /// Нуқтанинг маршрут чизиғидаги энг яқин жойи — "машина йўлнинг қаерида"
  /// (босиб ўтилган/қолган қисмни ажратиш учун). Ҳисоб [corridor] билан
  /// бир хил проекция ([_projectOnSegment]) ва бир хил масофа ўлчови.
  ///
  /// [fromSegment] — қидирув шу сегментдан бошланади: чизиқ ўзининг
  /// олдинги қисмига яқин қайтса (U-шакл), машина "орқага сакраб" кетмасин
  /// деб чақирувчи охирги маълум сегментни беради. Тенг масофада ОЛДИНГИ
  /// сегмент танланади.
  static EvRouteLocation? locate({
    required List<EvRoutePoint> route,
    required double lat,
    required double lng,
    int fromSegment = 0,
  }) {
    if (route.length < 2) return null;
    final lastSegment = route.length - 2;
    final start = fromSegment.clamp(0, lastSegment);

    // Ҳар вершинагача жамланган масофа ([corridor]даги каби).
    final cumKm = List<double>.filled(route.length, 0);
    for (var i = 1; i < route.length; i++) {
      cumKm[i] = cumKm[i - 1] + _distanceKm(route[i - 1], route[i]);
    }

    var bestSeg = start;
    var bestOffKm = double.infinity;
    var bestAlongInSeg = 0.0;
    for (var i = start; i <= lastSegment; i++) {
      final p = _projectOnSegment(
        lat: lat,
        lng: lng,
        a: route[i],
        b: route[i + 1],
      );
      if (p.offKm < bestOffKm) {
        bestOffKm = p.offKm;
        bestSeg = i;
        bestAlongInSeg = p.alongKm;
      }
    }

    final a = route[bestSeg];
    final b = route[bestSeg + 1];
    final segKm = _distanceKm(a, b);
    final fraction = segKm > 0 ? (bestAlongInSeg / segKm).clamp(0.0, 1.0) : 0.0;
    return EvRouteLocation(
      segmentIndex: bestSeg,
      fractionInSegment: fraction,
      alongKm: cumKm[bestSeg] + fraction * segKm,
      offRouteKm: bestOffKm,
      lat: a.lat + (b.lat - a.lat) * fraction,
      lng: a.lng + (b.lng - a.lng) * fraction,
    );
  }

  // ---------------------------------------------------------------------
  // 2-босқич: режа
  // ---------------------------------------------------------------------

  /// Асосий + заҳира тўхташлар режаси.
  ///
  /// [startSocPercent] — ҳозирги заряд (%). Заряд кутилгандан тез тушса,
  /// шу метод янги [startSocPercent] ва [fromAlongKm] билан ҚАЙТА
  /// чақирилади — заҳира ўз-ўзидан асосийга айланади.
  ///
  /// [forcedStopIds] — ҳайдовчи ҚАТЪИЙ танлаган станциялар (ҳозирча
  /// «Алмаштириш»). Улар йўл бўйича тартибда ИСТАЛГАН ҲОЛДА тўхташ бўлади:
  /// навбатдаги мажбурий станция машина етадиган масофада бўлса — ўша
  /// ерда тўхталади, акс ҳолда [EvTripPlanStatus.gapTooLarge] қайтади
  /// (бошқа станция «ўйлаб топилмайди»). Мажбурий станциялар тугагач —
  /// одатдаги танлов. Йўлда қолган (`fromAlongKm` орқасидаги) ёки яроқсиз
  /// (ишламайди/разъём мос эмас) станция ID'лари ҳисобга олинмайди.
  ///
  /// [excludedStationIds] — ҳайдовчи рад этган станциялар: улар АСОСИЙ
  /// қилиб танланмайди (заҳира сифатида кўрсатилиши мумкин, мажбурий
  /// рўйхатдагилар бундан мустасно).
  static EvTripPlan plan({
    required List<EvCorridorStation> corridorStations,
    required double totalKm,
    required EvCarSpec car,
    required int startSocPercent,
    double fromAlongKm = 0,
    List<String> forcedStopIds = const [],
    Set<String> excludedStationIds = const {},
  }) {
    if (totalKm <= 0) {
      return EvTripPlan.empty;
    }
    if (!car.isValid) {
      return EvTripPlan(
        status: EvTripPlanStatus.invalidCar,
        stops: const [],
        totalKm: totalKm,
        arrivalSocPercent: 0,
        startSocPercent: startSocPercent,
        fromAlongKm: fromAlongKm,
      );
    }

    final warnings = <String>{};
    if (car.connectors.isEmpty) warnings.add(EvTripWarning.connectorUnknown);
    if (startSocPercent <= car.reservePercent) {
      warnings.add(EvTripWarning.startSocBelowReserve);
    }

    // Фақат олдинда турган ва фойдали станциялар.
    final usable = corridorStations
        .where((c) => c.alongKm > fromAlongKm + 0.5)
        .where((c) => c.alongKm <= totalKm + 0.5)
        .where((c) => c.station.status != 'not_working')
        .where((c) => _connectorOk(c.station, car))
        .toList();

    // Ҳайдовчи мажбурий қилган станциялар (йўл бўйича тартибда).
    final forced = <EvCorridorStation>[];
    if (forcedStopIds.isNotEmpty) {
      final byId = {for (final c in usable) c.station.id: c};
      final seen = <String>{};
      for (final id in forcedStopIds) {
        final c = byId[id];
        if (c != null && seen.add(id)) forced.add(c);
      }
      forced.sort((a, b) => a.alongKm.compareTo(b.alongKm));
    }

    final stops = <EvTripStop>[];
    var position = fromAlongKm;
    var soc = startSocPercent.toDouble();

    EvTripPlan gap(double limit) {
      // Узилиш — ўйлаб топмаймиз, очиқ айтамиз.
      final next = forced.isNotEmpty
          ? forced.first
          : usable.firstWhere(
              (c) => c.alongKm > limit,
              orElse: () => const EvCorridorStation(
                station: _noStation,
                alongKm: -1,
                offRouteKm: 0,
              ),
            );
      return EvTripPlan(
        status: EvTripPlanStatus.gapTooLarge,
        stops: stops,
        totalKm: totalKm,
        arrivalSocPercent: 0,
        warnings: _finalWarnings(warnings, stops),
        gapFromKm: position,
        gapReachKm: limit,
        gapNextStationKm: next.alongKm < 0 ? null : next.alongKm,
        startSocPercent: startSocPercent,
        fromAlongKm: fromAlongKm,
      );
    }

    while (stops.length < maxStops) {
      // Мажбурий станциялардан орқада қолганлари (аллақачон ўтилган).
      while (forced.isNotEmpty && forced.first.alongKm <= position) {
        forced.removeAt(0);
      }
      final reachKm = car.usableRangeKmAt(soc);
      final limit = position + reachKm;

      // Манзилга етадими? (мажбурий тўхташ қолмаган бўлса)
      if (forced.isEmpty && position + reachKm >= totalKm) {
        final remainingKm = totalKm - position;
        final arrival = soc - socForKm(remainingKm, car);
        return EvTripPlan(
          status: stops.isEmpty
              ? EvTripPlanStatus.noChargingNeeded
              : EvTripPlanStatus.ok,
          stops: stops,
          totalKm: totalKm,
          arrivalSocPercent: arrival.round().clamp(0, 100),
          warnings: _finalWarnings(warnings, stops),
          startSocPercent: startSocPercent,
          fromAlongKm: fromAlongKm,
        );
      }

      final candidates =
          usable.where((c) => c.alongKm > position && c.alongKm <= limit).toList();

      final EvCorridorStation primary;
      if (forced.isNotEmpty) {
        // Ҳайдовчи танлаган станция: етса — шу ерда тўхтаймиз, етмаса —
        // очиқ узилиш (бошқасини ўзбошимчалик билан қўймаймиз).
        if (forced.first.alongKm > limit) return gap(limit);
        primary = forced.removeAt(0);
      } else {
        final pool = candidates
            .where((c) => !excludedStationIds.contains(c.station.id))
            .toList();
        if (pool.isEmpty) return gap(limit);
        primary = _pickPrimary(pool, position, reachKm);
      }
      final legKm = primary.alongKm - position;
      final arriveSoc = soc - socForKm(legKm, car);
      final departSoc = math.max(car.chargeToPercent.toDouble(), arriveSoc);

      stops.add(EvTripStop(
        station: primary.station,
        alongKm: primary.alongKm,
        offRouteKm: primary.offRouteKm,
        legKm: legKm,
        arriveSocPercent: arriveSoc.round().clamp(0, 100),
        departSocPercent: departSoc.round().clamp(0, 100),
        backups: _pickBackups(candidates, primary),
      ));

      position = primary.alongKm;
      soc = departSoc;
    }

    // maxStops тугади — бу ҳолатда ҳам «тайёр» деб кўрсатмаймиз.
    return EvTripPlan(
      status: EvTripPlanStatus.gapTooLarge,
      stops: stops,
      totalKm: totalKm,
      arrivalSocPercent: 0,
      warnings: _finalWarnings(warnings, stops),
      gapFromKm: position,
      gapReachKm: position + car.usableRangeKmAt(soc),
      startSocPercent: startSocPercent,
      fromAlongKm: fromAlongKm,
    );
  }

  /// Режадаги [stopIndex]-тўхташни [replacement] станцияга алмаштириб,
  /// режани ҚАЙТА ҳисоблайди (тоза функция; ҳайдовчи қарори — иловa фақат
  /// ҳисоблайди).
  ///
  /// * [stopIndex]дан ОЛДИНГИ тўхташлар ўзгармайди (мажбурий қилиб
  ///   қайта ҳисобланади — шунда улар ҳам, заряд ҳам аввалгидек қолади);
  /// * алмаштирилган станция ўрнига [replacement] қўйилади; ундан кейинги
  ///   қисм шу нуқтадан қайта режалаштирилади;
  /// * эски станция қолган қисмда АСОСИЙ қилиб танланмайди (ҳайдовчи уни
  ///   рад этди), [pinnedStationIds]даги (илгари ҳайдовчи танлаган) станциялар
  ///   эса сақланади;
  /// * [replacement]га етиб бўлмаса — натижа `gapTooLarge` (узилиш), бошқа
  ///   станция ўйлаб топилмайди.
  ///
  /// Режа бошланғич шартлари ([EvTripPlan.startSocPercent]) номаълум ёки
  /// индекс нотўғри бўлса — `null`.
  static EvTripPlan? replaceStop({
    required EvTripPlan current,
    required int stopIndex,
    required String replacementId,
    required List<EvCorridorStation> corridorStations,
    required EvCarSpec car,
    Set<String> excludedStationIds = const {},
    Set<String> pinnedStationIds = const {},
  }) {
    final startSoc = current.startSocPercent;
    if (startSoc == null) return null;
    if (stopIndex < 0 || stopIndex >= current.stops.length) return null;
    final oldId = current.stops[stopIndex].station.id;
    if (oldId == replacementId) return current;

    // Almashtirilgan stansiya koridorda bo'lishi shart.
    double? replacementAlong;
    for (final c in corridorStations) {
      if (c.station.id == replacementId) replacementAlong = c.alongKm;
    }
    if (replacementAlong == null) return null;
    // Oldingi to'xtashdan orqada turgan stansiya "o'rniga" bo'la olmaydi
    // (tartib buziladi).
    if (stopIndex > 0 &&
        replacementAlong <= current.stops[stopIndex - 1].alongKm) {
      return null;
    }

    // Oldin haydovchi tanlagan, ALMASHTIRILGAN stansiyadan keyingi stansiyalar
    // saqlanadi (oldingilari prefiksda yoki o'tib ketgan).
    final pinnedAhead = [
      for (final c in corridorStations)
        if (pinnedStationIds.contains(c.station.id) &&
            c.alongKm > replacementAlong)
          c.station.id,
    ];

    return plan(
      corridorStations: corridorStations,
      totalKm: current.totalKm,
      car: car,
      startSocPercent: startSoc,
      fromAlongKm: current.fromAlongKm,
      forcedStopIds: [
        for (var i = 0; i < stopIndex; i++) current.stops[i].station.id,
        replacementId,
        ...pinnedAhead,
      ],
      excludedStationIds: {...excludedStationIds, oldId}
        ..removeAll(pinnedAhead),
    );
  }

  // ---------------------------------------------------------------------
  // Танлаш мантиғи
  // ---------------------------------------------------------------------

  /// Асосий станция: имкониятнинг охирги қисмидагилар устун (камроқ
  /// тўхташ), улар орасида эса сифати баландроғи.
  static EvCorridorStation _pickPrimary(
    List<EvCorridorStation> candidates,
    double position,
    double reachKm,
  ) {
    final tailStart = position + reachKm * _preferTailFraction;
    final tail = candidates.where((c) => c.alongKm >= tailStart).toList();
    final pool = tail.isNotEmpty ? tail : candidates;

    pool.sort((a, b) {
      final byScore = _score(b.station).compareTo(_score(a.station));
      if (byScore != 0) return byScore;
      // Тенг сифатда — узоқроғи (камроқ тўхташ).
      return b.alongKm.compareTo(a.alongKm);
    });
    return pool.first;
  }

  /// Заҳиралар — асосийга энг яқинлари. Асосийдан ОЛДИН турганлари устун:
  /// заряд кутилгандан тез тушса айнан улар керак бўлади.
  static List<EvTripBackup> _pickBackups(
    List<EvCorridorStation> candidates,
    EvCorridorStation primary,
  ) {
    final others = candidates
        .where((c) => c.station.id != primary.station.id)
        .map((c) => EvTripBackup(
              station: c.station,
              alongKm: c.alongKm,
              offRouteKm: c.offRouteKm,
              deltaKm: c.alongKm - primary.alongKm,
            ))
        .toList();

    others.sort((a, b) {
      // Олдиндагилар биринчи, кейин асосийга яқинлиги бўйича.
      if (a.isBefore != b.isBefore) return a.isBefore ? -1 : 1;
      return a.deltaKm.abs().compareTo(b.deltaKm.abs());
    });

    return others.take(maxBackupsPerStop).toList();
  }

  /// Станция сифати — DC, қувват, текширилганлик ва жамоа сигналлари.
  static int _score(EvChargingStation s) {
    var score = 0;

    final isDc = s.chargingTypes.contains('DC') || s.chargingTypes.contains('AC+DC');
    if (isDc) score += 40;

    final power = (s.powerKw ?? s.sitePowerKw ?? 0).toDouble();
    score += (power.clamp(0, 150) / 150 * 30).round();

    switch (s.verificationStatus) {
      case 'operator_verified':
        score += 25;
      case 'verified':
        score += 20;
      case 'community':
        score += 10;
      default:
        break; // imported — қўшимча ишонч йўқ
    }

    if (s.status == 'working') score += 15;
    if (s.status == 'partially_working') score += 5;

    switch (s.occupancyState) {
      case 'free':
        score += 10;
      case 'busy':
        score -= 15;
      default:
        break;
    }

    if (s.confirmationCount > 0) score += 5;
    if (s.reportCount > 0) score -= 10;

    return score;
  }

  /// Станция режага ярайдими: ишламайдиганлар ва машина разъёмига мос
  /// келмайдиганлар олинмайди ([plan]даги қоида билан БИР ХИЛ; «Алмаштириш»
  /// рўйхати ҳам шундан фойдаланади).
  static bool isStationUsable(EvChargingStation s, EvCarSpec car) =>
      s.status != 'not_working' && _connectorOk(s, car);

  static bool _connectorOk(EvChargingStation s, EvCarSpec car) {
    if (car.connectors.isEmpty) return true;
    // Станцияда разъём ёзилмаган — рад этмаймиз (маълумот тўлиқ эмас),
    // лекин сифат балли ҳам ошмайди.
    if (s.connectors.isEmpty) return true;
    return s.connectors.any(car.connectors.contains);
  }

  static List<String> _finalWarnings(
    Set<String> warnings,
    List<EvTripStop> stops,
  ) {
    final out = {...warnings};
    if (stops.any((s) => s.isUnverifiedImport)) {
      out.add(EvTripWarning.unverifiedStops);
    }
    if (stops.any((s) => !s.hasBackup)) {
      out.add(EvTripWarning.noBackup);
    }
    if (stops.any((s) =>
        !s.station.chargingTypes.contains('DC') &&
        !s.station.chargingTypes.contains('AC+DC') &&
        s.station.chargingTypes.isNotEmpty)) {
      out.add(EvTripWarning.slowAcOnly);
    }
    return out.toList();
  }

  /// Берилган масофа учун сарфланадиган заряд (%).
  static double socForKm(double km, EvCarSpec car) {
    if (km <= 0) return 0;
    final kwh = km / 100 * car.consumptionKwhPer100Km;
    return kwh / car.usableBatteryKwh * 100;
  }

  // ---------------------------------------------------------------------
  // Геометрия
  // ---------------------------------------------------------------------

  static const double _earthRadiusKm = 6371.0088;

  static double _distanceKm(EvRoutePoint a, EvRoutePoint b) =>
      _haversineKm(a.lat, a.lng, b.lat, b.lng);

  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * _earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Нуқтани [a]–[b] сегментига проекция қилиш. Кичик масофаларда
  /// эквиректангуляр яқинлаштириш етарли аниқ (бир сегмент 1–3 км).
  static ({double offKm, double alongKm}) _projectOnSegment({
    required double lat,
    required double lng,
    required EvRoutePoint a,
    required EvRoutePoint b,
  }) {
    final latScale = math.cos(_rad((a.lat + b.lat) / 2));
    final ax = 0.0;
    final ay = 0.0;
    final bx = _rad(b.lng - a.lng) * latScale * _earthRadiusKm;
    final by = _rad(b.lat - a.lat) * _earthRadiusKm;
    final px = _rad(lng - a.lng) * latScale * _earthRadiusKm;
    final py = _rad(lat - a.lat) * _earthRadiusKm;

    final segLenSq = (bx - ax) * (bx - ax) + (by - ay) * (by - ay);
    if (segLenSq == 0) {
      return (offKm: _haversineKm(lat, lng, a.lat, a.lng), alongKm: 0);
    }

    var t = ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / segLenSq;
    t = t.clamp(0.0, 1.0);

    final projX = ax + t * (bx - ax);
    final projY = ay + t * (by - ay);
    final offKm = math.sqrt(
        (px - projX) * (px - projX) + (py - projY) * (py - projY));
    final segLenKm = math.sqrt(segLenSq);

    return (offKm: offKm, alongKm: t * segLenKm);
  }

  static double _rad(double deg) => deg * math.pi / 180;
}

/// `orElse` учун сентинел — ҳақиқий станция эмас, фақат «топилмади»
/// ҳолатини белгилайди.
const _noStation = EvChargingStation(
  id: '',
  latitude: 0,
  longitude: 0,
  geohash: '',
  chargingTypes: [],
  connectors: [],
  status: 'unknown',
  verificationStatus: 'community',
  confirmationCount: 0,
  reportCount: 0,
  createdBy: '',
  isActive: false,
);

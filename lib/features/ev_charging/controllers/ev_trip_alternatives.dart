// ⚡ EV сафар — режадаги битта тўхташ учун «Алмаштириш» рўйхати (эга
// қарори, 2026-10-16: ҳайдовчи қарор қилади, илова фақат тавсия қилади).
//
// ТОЗА Dart (плагинсиз). Рўйхат мавжуд коридор маълумотидан тузилади
// (янги сўров йўқ): аввал режанинг заҳиралари, кейин тўхташ атрофидаги
// ([windowKm] ичидаги) бошқа станциялар. Ҳар бир вариантнинг сафарга таъсири
// режани ҲАҚИҚАТАН қайта ҳисоблаб топилади ([EvTripPlanner.replaceStop]),
// тахмин қилинмайди.
//
// Чекловлар (ҳисоботда ҳам айтилган):
//  * «Етиб келганда %» ва тўхташлар сони — планер натижаси (машина сарфи
//    ўртача қиймат, ҳақиқий йўл шароити билан фарқ қилиши мумкин);
//  * «Зарядлаш вақти» фарқи — «камида» вақтлар фарқи (станция қуввати ÷
//    энергия); машинанинг DC қабул қилиш қуввати БАЗАДА ЙЎҚ. Фақат ҳар икки
//    режадаги БАРЧА тўхташда станция қуввати маълум бўлсагина кўрсатилади;
//  * четга бурилиш (йўл вақти) ҲИСОБЛАНМАЙДИ — фақат четга км кўрсатилади.

import '../../../models/ev_charging_station.dart';
import '../models/ev_trip_plan.dart';
import 'ev_trip_planner.dart';
import 'ev_trip_summary.dart';

/// «Алмаштириш» рўйхатининг битта қатори: ҳозирги тўхташ ёки алтернатива.
class EvTripAlternative {
  const EvTripAlternative({
    required this.entry,
    required this.isCurrent,
    required this.deltaKm,
    required this.plan,
    required this.feasible,
    required this.powerKnown,
    this.arrivalSocPercent,
    this.arrivalDeltaPercent,
    this.stopCount,
    this.stopCountDelta,
    this.chargeMinutesDelta,
    this.isBest = false,
  });

  /// Станция + йўл бошидан масофа + йўлдан четлик.
  final EvCorridorStation entry;

  /// Режадаги ҳозирги тўхташ (иловaнинг ўз танлови).
  final bool isCurrent;

  /// Ҳозирги тўхташга нисбатан: манфий — олдин, мусбат — кейин (км).
  final double deltaKm;

  /// Шу станцияни танлаганда ҳосил бўладиган режа (ҳозиргисида — жорий режа).
  final EvTripPlan plan;

  /// Танлангач режа тайёр (манзилгача станциялар орасида узилиш йўқ).
  final bool feasible;

  /// Станциянинг қуввати (kW) маълум.
  final bool powerKnown;

  /// Манзилга етиб келганда заряд (%) ва ҳозирги режага нисбатан фарқи.
  /// Режа тайёр эмас — `null`.
  final int? arrivalSocPercent;
  final int? arrivalDeltaPercent;

  /// Тўхташлар сони ва ҳозирги режага нисбатан фарқи.
  final int? stopCount;
  final int? stopCountDelta;

  /// «Камида» зарядлаш вақти фарқи (дақиқа, мусбат — узунроқ). Ҳисоблаш
  /// мумкин бўлмаса `null` (қатор кўрсатилмайди).
  final int? chargeMinutesDelta;

  /// Энг яхши вариант — «Тавсия» белгиси.
  final bool isBest;

  EvChargingStation get station => entry.station;
  double get offRouteKm => entry.offRouteKm;
  double get alongKm => entry.alongKm;

  EvTripAlternative copyWith({bool? isBest}) => EvTripAlternative(
        entry: entry,
        isCurrent: isCurrent,
        deltaKm: deltaKm,
        plan: plan,
        feasible: feasible,
        powerKnown: powerKnown,
        arrivalSocPercent: arrivalSocPercent,
        arrivalDeltaPercent: arrivalDeltaPercent,
        stopCount: stopCount,
        stopCountDelta: stopCountDelta,
        chargeMinutesDelta: chargeMinutesDelta,
        isBest: isBest ?? this.isBest,
      );
}

class EvTripAlternatives {
  const EvTripAlternatives._();

  /// Ҳозирги тўхташдан йўл бўйлаб шунча км олдин/кейинги станциялар
  /// алтернатива бўла олади (заҳиралар бундан мустасно — улар планернинг ўз
  /// танлови).
  static const double windowKm = 40;

  /// Рўйхатдаги алтернативалар сони (ҳозирги тўхташдан ташқари).
  static const int maxAlternatives = 5;

  /// Машина ортида қолган станцияларга шунча км гача чидамлилик (GPS шовқини).
  static const double behindToleranceKm = 0.5;

  /// «Тавсия»да «камида» вақт фарқи шундан кам бўлса — юмалоқлаш шовқини
  /// деб ҳисобланади ва ҳисобга олинмайди (ҳозирги тўхташ ўз ўрнини сақлайди).
  static const int bestMinutesMargin = 3;

  /// [plan]даги [stopIndex]-тўхташ учун рўйхат: БИРИНЧИСИ — ҳозирги тўхташ,
  /// кейин алтернативалар (ҳозиргидан йўл бўйича масофа, кейин четлик
  /// бўйича). Режа бошланғич шартлари номаълум ([EvTripPlan.canReplan]) ёки
  /// индекс нотўғри бўлса — бўш.
  static List<EvTripAlternative> build({
    required EvTripPlan plan,
    required int stopIndex,
    required List<EvCorridorStation> corridor,
    required EvCarSpec car,
    Set<String> excludedStationIds = const {},
    Set<String> pinnedStationIds = const {},
    double? carAlongKm,
  }) {
    if (!plan.canReplan) return const [];
    if (stopIndex < 0 || stopIndex >= plan.stops.length) return const [];

    final current = plan.stops[stopIndex];
    final planIds = {for (final s in plan.stops) s.station.id};
    final byId = {for (final c in corridor) c.station.id: c};

    // Алтернатива камида шу жойдан кейин бўлиши керак: олдинги тўхташдан
    // ва машина ортида қолмаган.
    var lowerBound = stopIndex > 0
        ? plan.stops[stopIndex - 1].alongKm
        : plan.fromAlongKm;
    if (carAlongKm != null) {
      final behind = carAlongKm - behindToleranceKm;
      if (behind > lowerBound) lowerBound = behind;
    }

    bool eligible(EvCorridorStation c) =>
        !planIds.contains(c.station.id) &&
        c.alongKm > lowerBound &&
        c.alongKm <= plan.totalKm + 0.5 &&
        EvTripPlanner.isStationUsable(c.station, car);

    // 1) Заҳиралар (планернинг ўз танлови) — коридордаги ёзув устун.
    final picked = <EvCorridorStation>[];
    final seen = <String>{};
    for (final b in current.backups) {
      final c = byId[b.station.id] ??
          EvCorridorStation(
            station: b.station,
            alongKm: b.alongKm,
            offRouteKm: b.offRouteKm,
          );
      if (eligible(c) && seen.add(c.station.id)) picked.add(c);
    }

    // 2) Атрофдаги бошқа станциялар: ҳозиргидан йўл бўйлаб ±windowKm.
    final others = <EvCorridorStation>[
      for (final c in corridor)
        if (!seen.contains(c.station.id) &&
            (c.alongKm - current.alongKm).abs() <= windowKm &&
            eligible(c))
          c,
    ]..sort((a, b) {
        final r = (a.alongKm - current.alongKm)
            .abs()
            .compareTo((b.alongKm - current.alongKm).abs());
        return r != 0 ? r : a.offRouteKm.compareTo(b.offRouteKm);
      });
    for (final c in others) {
      if (picked.length >= maxAlternatives) break;
      picked.add(c);
    }
    if (picked.length > maxAlternatives) {
      picked.removeRange(maxAlternatives, picked.length);
    }

    // Тартиб: ҳозиргидан масофа, кейин четлик (барқарор).
    final indexed = [for (var i = 0; i < picked.length; i++) (i, picked[i])]
      ..sort((a, b) {
        final r = (a.$2.alongKm - current.alongKm)
            .abs()
            .compareTo((b.$2.alongKm - current.alongKm).abs());
        if (r != 0) return r;
        final o = a.$2.offRouteKm.compareTo(b.$2.offRouteKm);
        return o != 0 ? o : a.$1.compareTo(b.$1);
      });

    final base = _Outcome.of(plan, car);

    final rows = <EvTripAlternative>[
      _row(
        entry: EvCorridorStation(
          station: current.station,
          alongKm: current.alongKm,
          offRouteKm: current.offRouteKm,
        ),
        isCurrent: true,
        currentAlong: current.alongKm,
        plan: plan,
        outcome: base,
        base: base,
      ),
    ];

    for (final e in indexed) {
      final c = e.$2;
      final next = EvTripPlanner.replaceStop(
        current: plan,
        stopIndex: stopIndex,
        replacementId: c.station.id,
        corridorStations: _withEntry(corridor, c),
        car: car,
        excludedStationIds: excludedStationIds,
        pinnedStationIds: pinnedStationIds,
      );
      if (next == null) continue;
      rows.add(_row(
        entry: c,
        isCurrent: false,
        currentAlong: current.alongKm,
        plan: next,
        outcome: _Outcome.of(next, car),
        base: base,
      ));
    }

    return _markBest(rows);
  }

  /// Заҳира коридорда бўлмаса (тест, эскирган рўйхат) режа ичида ишлатиш
  /// учун қўшилади.
  static List<EvCorridorStation> _withEntry(
    List<EvCorridorStation> corridor,
    EvCorridorStation c,
  ) {
    if (corridor.any((e) => e.station.id == c.station.id)) return corridor;
    return [...corridor, c]..sort((a, b) => a.alongKm.compareTo(b.alongKm));
  }

  static EvTripAlternative _row({
    required EvCorridorStation entry,
    required bool isCurrent,
    required double currentAlong,
    required EvTripPlan plan,
    required _Outcome outcome,
    required _Outcome base,
  }) {
    final feasible = outcome.feasible;
    final comparable = feasible && base.feasible;

    int? minutesDelta;
    if (comparable && outcome.minutesKnown && base.minutesKnown) {
      minutesDelta = outcome.minutes - base.minutes;
    }

    return EvTripAlternative(
      entry: entry,
      isCurrent: isCurrent,
      deltaKm: entry.alongKm - currentAlong,
      plan: plan,
      feasible: feasible,
      powerKnown: evStationPowerKw(entry.station) != null,
      arrivalSocPercent: feasible ? plan.arrivalSocPercent : null,
      arrivalDeltaPercent:
          comparable && !isCurrent ? plan.arrivalSocPercent - base.arrival : null,
      stopCount: feasible ? plan.stops.length : null,
      stopCountDelta:
          comparable && !isCurrent ? plan.stops.length - base.stops : null,
      chargeMinutesDelta: isCurrent ? null : minutesDelta,
    );
  }

  /// «Тавсия»: тайёр вариантлар орасида энг кам тўхташ, кейин етиб келганда
  /// энг юқори заряд, кейин (маълум бўлса) энг қисқа «камида» вақт, кейин
  /// ҳозиргидан энг яқини. Тенг бўлса — ҳозирги тўхташ (планернинг ўз танлови
  /// биринчи ўринда қолади). Тайёр вариант йўқ — ҳеч бири белгиланмайди.
  static List<EvTripAlternative> _markBest(List<EvTripAlternative> rows) {
    EvTripAlternative? best;
    for (final r in rows) {
      if (!r.feasible) continue;
      if (best == null || _better(r, best)) best = r;
    }
    if (best == null) return rows;
    return [
      for (final r in rows) identical(r, best) ? r.copyWith(isBest: true) : r,
    ];
  }

  static bool _better(EvTripAlternative a, EvTripAlternative b) {
    final stops = a.stopCount!.compareTo(b.stopCount!);
    if (stops != 0) return stops < 0;
    final arrival = b.arrivalSocPercent!.compareTo(a.arrivalSocPercent!);
    if (arrival != 0) return arrival < 0;
    // Вақт фарқи ҳозиргига нисбатан; ҳозирги учун 0.
    final am = a.isCurrent ? 0 : a.chargeMinutesDelta;
    final bm = b.isCurrent ? 0 : b.chargeMinutesDelta;
    if (am != null && bm != null && (am - bm).abs() >= bestMinutesMargin) {
      return am < bm;
    }
    // Тўлиқ тенг: ҳозирги (биринчи) ўз ўрнини сақлайди.
    return false;
  }
}

class _Outcome {
  const _Outcome({
    required this.feasible,
    required this.arrival,
    required this.stops,
    required this.minutes,
    required this.minutesKnown,
  });

  final bool feasible;
  final int arrival;
  final int stops;
  final int minutes;

  /// Барча тўхташда қувват маълум — вақт йиғиндиси солиштиришга яроқли.
  final bool minutesKnown;

  static _Outcome of(EvTripPlan plan, EvCarSpec car) {
    final t = evPlanMinChargeMinutes(plan, car);
    return _Outcome(
      feasible: plan.isOk,
      arrival: plan.arrivalSocPercent,
      stops: plan.stops.length,
      minutes: t.minutes,
      minutesKnown: t.knownStops == t.totalStops,
    );
  }
}

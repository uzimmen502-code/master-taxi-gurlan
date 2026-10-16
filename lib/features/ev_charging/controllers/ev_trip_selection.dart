// ⚡ EV сафар — ҳайдовчи танлаган тўхташлар (харита экранидаги «Навигация»).
//
// Тоза Dart (плагинсиз): `flutter test`да тўғридан-тўғри текширилади.
//
// Қоида (эга қарори, 2026-10-16):
//  * Йўл бўйидаги БАРЧА станциялар харитада кўринади ва ҳар бирини ҳайдовчи
//    режага қўша олади ёки олиб ташлай олади; илова фақат ТАВСИЯ қилади.
//  * Бошида тавсия этилган (асосий) тўхташлар танланган, лекин ҳайдовчи
//    улардан исталганини олиб ташлай олади.
//  * Google Maps'да ҳар оралиқ нуқта МАЖБУРИЙ тўхташ ва сони чекланган
//    (мобил веб 3, бошқа 9 — `mapsMaxWaypoints()`, ЯГОНА манба). Чекловдан
//    ошса, илова ўзбошимчалик билан қирқмайди: ҳайдовчи ўзи камайтиради.
//  * Танланганлар йўл бошидан масофа бўйича тартибланади; рақамлар шу
//    тартибда (1, 2, 3...).

import 'package:flutter/foundation.dart';

import '../../../core/utils/map_launcher.dart' show mapsMaxWaypoints;
import '../../../models/ev_charging_station.dart';
import '../models/ev_trip_plan.dart';

/// Битта оралиқ нуқта (`stops` параметри `openMapsEvTripRoute` билан бир хил).
typedef EvWaypoint = ({double lat, double lng});

/// Харитадаги станция тури.
enum EvTripMarkerKind {
  /// Режадаги асосий (тавсия этилган) тўхташ.
  primary,

  /// Заҳира вариант.
  backup,

  /// Маршрут бўйидаги бошқа станция — режага кирмаган.
  other,
}

/// Йўл бўйидаги битта станция: ҳайдовчи танлаши мумкин бўлган номзод.
class EvTripCandidate {
  const EvTripCandidate({
    required this.station,
    required this.alongKm,
    required this.offRouteKm,
    required this.kind,
  });

  final EvChargingStation station;

  /// Йўл бошидан шу станциягача (км).
  final double alongKm;

  /// Йўл чизиғидан четда (км).
  final double offRouteKm;

  final EvTripMarkerKind kind;

  String get id => station.id;
}

/// ~0.1 м аниқликда бир хил координата калити.
String _coordKey(EvChargingStation s) =>
    '${s.latitude.toStringAsFixed(6)},${s.longitude.toStringAsFixed(6)}';

/// Станция ID → тури (асосий заҳирани босиб кетади).
Map<String, EvTripMarkerKind> evTripMarkerKinds(EvTripPlan plan) {
  final kinds = <String, EvTripMarkerKind>{};
  for (final stop in plan.stops) {
    for (final b in stop.backups) {
      kinds[b.station.id] = EvTripMarkerKind.backup;
    }
  }
  // Асосийлар охирида — заҳира белгисини босиб кетади.
  for (final stop in plan.stops) {
    kinds[stop.station.id] = EvTripMarkerKind.primary;
  }
  return kinds;
}

/// Йўл бўйидаги БАРЧА станциялар (коридор), йўл бошидан масофа бўйича.
///
/// Режадаги асосий ва заҳира станциялар коридордан келади; коридорда
/// бўлмаса (тест, эскирган рўйхат) режанинг ўз маълумоти қўшилади — шунда
/// харитада кўринган ҳар бир станция танланадиган бўлади. Бир станция
/// бир марта (id бўйича).
List<EvTripCandidate> evTripCandidates(
  EvTripPlan plan,
  List<EvCorridorStation> corridor,
) {
  final kinds = evTripMarkerKinds(plan);
  final seen = <String>{};
  final out = <EvTripCandidate>[];

  void add(EvChargingStation s, double along, double off) {
    if (!seen.add(s.id)) return;
    out.add(EvTripCandidate(
      station: s,
      alongKm: along,
      offRouteKm: off,
      kind: kinds[s.id] ?? EvTripMarkerKind.other,
    ));
  }

  for (final c in corridor) {
    add(c.station, c.alongKm, c.offRouteKm);
  }
  for (final s in plan.stops) {
    add(s.station, s.alongKm, s.offRouteKm);
    for (final b in s.backups) {
      add(b.station, b.alongKm, b.offRouteKm);
    }
  }

  // sort барқарор эмас — индекс билан барқарорлаштирамиз.
  final indexed = [for (var i = 0; i < out.length; i++) (i, out[i])];
  indexed.sort((a, b) {
    final r = a.$2.alongKm.compareTo(b.$2.alongKm);
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Ҳайдовчи танлаган тўхташлар ҳолати.
class EvTripSelection extends ChangeNotifier {
  /// [initialIds] — аввалдан танланганлар (номзодлар орасида йўқлари
  /// ҳисобга олинмайди). [maxWaypoints] берилмаса — `mapsMaxWaypoints()`.
  EvTripSelection({
    required List<EvTripCandidate> candidates,
    Iterable<String> initialIds = const [],
    int? maxWaypoints,
  })  : candidates = List.unmodifiable(candidates),
        maxWaypoints = maxWaypoints ?? mapsMaxWaypoints() {
    final byId = {for (final c in candidates) c.id: c};
    for (final id in initialIds) {
      if (byId.containsKey(id)) _ids.add(id);
    }
  }

  /// Бошланғич ҳолат: режа тайёр бўлса — тавсия этилган (асосий) тўхташлар
  /// танланган. Режа тайёр эмас (узилиш, нотўғри автомобил, маршрут йўқ) —
  /// ҳеч нарса танланмаган (ҳайдовчи ўзи қўшиши мумкин).
  ///
  /// Бир хил координатали икки асосий станциядан фақат биринчиси (битта
  /// оралиқ нуқта).
  factory EvTripSelection.recommended(
    EvTripPlan plan,
    List<EvCorridorStation> corridor, {
    int? maxWaypoints,
  }) {
    final candidates = evTripCandidates(plan, corridor);
    final ids = <String>[];
    if (plan.isOk) {
      final seenCoords = <String>{};
      // Режа тартибида (йўл бўйича ўсиш).
      for (final s in plan.stops) {
        if (seenCoords.add(_coordKey(s.station))) ids.add(s.station.id);
      }
    }
    return EvTripSelection(
      candidates: candidates,
      initialIds: ids,
      maxWaypoints: maxWaypoints,
    );
  }

  /// Йўл бўйидаги барча станциялар, йўл бошидан масофа бўйича.
  final List<EvTripCandidate> candidates;

  /// Google Maps қабул қиладиган оралиқ нуқталарнинг энг кўп сони.
  final int maxWaypoints;

  final Set<String> _ids = <String>{};

  int get count => _ids.length;

  bool isSelected(String id) => _ids.contains(id);

  /// Чекловга етдик — яна қўшиб бўлмайди.
  bool get isFull => count >= maxWaypoints;

  /// Танланганлар чекловдан кўп (бошланғич тавсия мобил веб'да 3 дан
  /// кўп бўлиши мумкин) — навигацияни очишдан олдин камайтириш керак.
  bool get isOverLimit => count > maxWaypoints;

  bool canAdd(String id) => isSelected(id) || !isFull;

  EvTripCandidate? candidateById(String id) {
    for (final c in candidates) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Танланганлар, йўл бошидан масофа бўйича.
  List<EvTripCandidate> get selected => [
        for (final c in candidates)
          if (_ids.contains(c.id)) c,
      ];

  /// Станция ID → тартиб рақами (1'дан), йўл бўйича.
  Map<String, int> get numbers {
    final map = <String, int>{};
    var n = 0;
    for (final c in candidates) {
      if (_ids.contains(c.id)) map[c.id] = ++n;
    }
    return map;
  }

  /// Танловни ўзгартириш. Қўшиш чекловга тўсқинлик қилса — `false`
  /// (ҳолат ўзгармайди). Номаълум станция — `false`.
  bool toggle(String id) {
    if (candidateById(id) == null) return false;
    if (_ids.contains(id)) {
      _ids.remove(id);
    } else {
      if (isFull) return false;
      _ids.add(id);
    }
    notifyListeners();
    return true;
  }

  /// Навигация учун оралиқ нуқталар: танланганлар йўл бўйича; бир хил
  /// координата битта марта. Бўш танлов — бўш рўйхат (фақат манзилга).
  List<EvWaypoint> get waypoints {
    final seen = <String>{};
    final out = <EvWaypoint>[];
    for (final c in selected) {
      if (seen.add(_coordKey(c.station))) {
        out.add((lat: c.station.latitude, lng: c.station.longitude));
      }
    }
    return out;
  }
}

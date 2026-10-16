// ⚡ EV сафар — харита экранидаги «Навигация» тугмаси учун оралиқ нуқталар.
//
// Тоза Dart (плагинсиз): `flutter test`да тўғридан-тўғри текширилади.
//
// Қоида (эга қарори, 2026-10-16):
//  * Режадаги БАРЧА асосий станциялар доим оралиқ нуқта (мажбурий).
//  * Заҳира станциялар ИХТИЁРИЙ: Google Maps'да "ихтиёрий нуқта" тушунчаси
//    йўқ (ҳар оралиқ нуқта мажбурий тўхташ). Шунинг учун ихтиёрийлик
//    ИЛОВА ичида ҳал қилинади — ҳайдовчи «Навигация»ни босганда қайси
//    заҳираларни қўшишни ўзи танлайди (барчаси ЎЧИҚ), фақат танланганлари
//    оралиқ нуқтага айланади.

import '../../../core/utils/map_launcher.dart' show mapsMaxWaypoints;
import '../models/ev_trip_plan.dart';

/// Битта оралиқ нуқта (`stops` параметри `openMapsEvTripRoute` билан бир хил).
typedef EvWaypoint = ({double lat, double lng});

/// Танлаш варағидаги битта заҳира: станция ва у қайси асосий тўхташга тегишли.
class EvNavigationBackupOption {
  const EvNavigationBackupOption({required this.backup, required this.stop});

  final EvTripBackup backup;

  /// Шу заҳира тавсия қилинган асосий тўхташ.
  final EvTripStop stop;

  /// Танлов калити (станция идентификатори).
  String get id => backup.station.id;
}

/// ~0.1 м аниқликда бир хил координата калити.
String _coordKey(double lat, double lng) =>
    '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

/// Координата бўйича такрорсиз асосий тўхташлар, йўл бўйича (ўсиш).
List<EvTripStop> _uniquePrimaries(EvTripPlan plan) {
  final seen = <String>{};
  final list = <EvTripStop>[];
  for (final s in plan.stops) {
    if (seen.add(_coordKey(s.station.latitude, s.station.longitude))) {
      list.add(s);
    }
  }
  // sort барқарор эмас — индекс билан барқарорлаштирамиз.
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final r = a.$2.alongKm.compareTo(b.$2.alongKm);
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Танлаш учун таклиф қилинадиган заҳиралар: тайёр режада, асосий
/// станция билан бир хил координатали ва такрорларсиз, йўл бўйича тартибда.
List<EvNavigationBackupOption> evNavigationBackupOptions(EvTripPlan plan) {
  if (!plan.isOk) return const [];
  final seen = <String>{
    for (final s in plan.stops) _coordKey(s.station.latitude, s.station.longitude),
  };
  final options = <EvNavigationBackupOption>[];
  for (final s in plan.stops) {
    for (final b in s.backups) {
      if (seen.add(_coordKey(b.station.latitude, b.station.longitude))) {
        options.add(EvNavigationBackupOption(backup: b, stop: s));
      }
    }
  }
  final indexed = [for (var i = 0; i < options.length; i++) (i, options[i])];
  indexed.sort((a, b) {
    final r = a.$2.backup.alongKm.compareTo(b.$2.backup.alongKm);
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Асосийлардан сўнг заҳиралар учун қолган жой сони (≥ 0). [max] берилмаса —
/// платформага қараб `mapsMaxWaypoints()` (мобил веб 3, бошқа 9).
int evNavigationBackupCapacity(
  EvTripPlan plan, {
  int? max,
}) {
  max ??= mapsMaxWaypoints();
  if (max <= 0 || !plan.isOk) return 0;
  final room = max - _uniquePrimaries(plan).length;
  return room < 0 ? 0 : room;
}

/// Навигация учун оралиқ нуқталар рўйхати.
///
///  * Режа тайёр эмас (`!plan.isOk`: узилиш, нотўғри автомобил, маршрут
///    йўқ) — бўш рўйхат.
///  * Асосий тўхташлар доим киради; тартиб — йўл бошидан масофа
///    ([EvTripStop.alongKm] / [EvTripBackup.alongKm], иккаласи бир шкалада:
///    заҳиранинг `alongKm`и = асосий + `deltaKm`) ўсиши бўйича.
///  * Заҳиралардан фақат [selectedBackupIds] (станция id'лари) қўшилади;
///    бўш тўплам = фақат асосийлар.
///  * Бир хил координата битта марта (асосий ғолиб).
///  * Чеклов [max] (берилмаса `mapsMaxWaypoints()`: мобил веб 3, бошқа 9):
///    асосийлар устувор. Улар сиғса — қолган жойга танланган
///    заҳиралар ўз асосийсига яқинлиги (|Δ| кичик) бўйича қўшилади; ортиқчаси
///    тушиб қолади. Асосийларнинг ўзи [max]дан кўп бўлса — маршрут бўйича
///    биринчи [max] таси. Натижа ҳеч қачон [max]дан ошмайди.
///  * Танловдан кейин тартиб яна маршрут бўйича.
List<EvWaypoint> evNavigationWaypoints(
  EvTripPlan plan, {
  Set<String> selectedBackupIds = const {},
  int? max,
}) {
  max ??= mapsMaxWaypoints();
  if (max <= 0 || !plan.isOk) return const [];

  final primaries = _uniquePrimaries(plan);
  final chosen = <({double lat, double lng, double along, int rank})>[];

  if (primaries.length >= max) {
    for (final s in primaries.take(max)) {
      chosen.add((
        lat: s.station.latitude,
        lng: s.station.longitude,
        along: s.alongKm,
        rank: 0,
      ));
    }
  } else {
    for (final s in primaries) {
      chosen.add((
        lat: s.station.latitude,
        lng: s.station.longitude,
        along: s.alongKm,
        rank: 0,
      ));
    }
    final selected = [
      for (final o in evNavigationBackupOptions(plan))
        if (selectedBackupIds.contains(o.id)) o,
    ];
    // Жой етмаса — асосийга энг яқинлари қолади (тенгда: йўл бўйича олдин).
    final byCloseness = [for (var i = 0; i < selected.length; i++) (i, selected[i])]
      ..sort((a, b) {
        final r = a.$2.backup.deltaKm.abs().compareTo(b.$2.backup.deltaKm.abs());
        return r != 0 ? r : a.$1.compareTo(b.$1);
      });
    for (final e in byCloseness.take(max - primaries.length)) {
      final b = e.$2.backup;
      chosen.add((
        lat: b.station.latitude,
        lng: b.station.longitude,
        along: b.alongKm,
        rank: 1,
      ));
    }
  }

  final indexed = [for (var i = 0; i < chosen.length; i++) (i, chosen[i])];
  indexed.sort((a, b) {
    var r = a.$2.along.compareTo(b.$2.along);
    if (r != 0) return r;
    r = a.$2.rank.compareTo(b.$2.rank);
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) (lat: e.$2.lat, lng: e.$2.lng)];
}

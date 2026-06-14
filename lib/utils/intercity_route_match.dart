import 'intercity_places.dart';

/// Йўловчи қидирувида ҳайдовчи маршрути билан мосликни текширади.
///
/// Масалан ҳайдовчи: Тошкент → Тўрткўл → Ургенч
/// Йўловчи: Самарқанд → Ургенч — мос келмайди.
/// Йўловчи: Тўрткўл → Ургенч — мос келади.
class IntercityRouteMatch {
  IntercityRouteMatch._();

  /// [driverStops] — ketma-ket: from, ...mid, to.
  static bool matchesSegment({
    required List<String> driverStops,
    required String passengerFrom,
    required String passengerTo,
  }) {
    if (driverStops.length < 2) return false;
    final fromVariants = _variants(passengerFrom);
    final toVariants = _variants(passengerTo);
    if (fromVariants.isEmpty || toVariants.isEmpty) return false;
    if (fromVariants.any((f) => toVariants.any((t) => f == t))) return false;

    final chain = driverStops
        .expand((s) => _variants(s))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (chain.length < 2) return false;

    int fromIdx = -1;
    for (var i = 0; i < driverStops.length; i++) {
      if (_stopMatches(driverStops[i], fromVariants)) {
        fromIdx = i;
        break;
      }
    }
    int toIdx = -1;
    for (var i = driverStops.length - 1; i >= 0; i--) {
      if (_stopMatches(driverStops[i], toVariants)) {
        toIdx = i;
        break;
      }
    }
    if (fromIdx < 0 || toIdx < 0) return false;
    return fromIdx < toIdx;
  }

  static List<String> _variants(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty) return const [];
    final canonical =
        IntercityPlaces.normalizeLocation(raw).toLowerCase();
    final city = IntercityPlaces.extractCity(raw).toLowerCase();
    final cityCanon =
        IntercityPlaces.normalizeLocation(city).toLowerCase();
    return {t, canonical, city, cityCanon}
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static bool _stopMatches(String stop, List<String> passengerVariants) {
    final stopVars = _variants(stop);
    for (final p in passengerVariants) {
      for (final s in stopVars) {
        if (s == p || s.contains(p) || p.contains(s)) return true;
      }
    }
    return false;
  }

  static String routeLabel(List<String> stops) {
    if (stops.isEmpty) return '';
    if (stops.length == 1) return stops.first;
    return stops.join(' → ');
  }
}

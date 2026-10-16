import 'ev_trip_planner.dart';

/// ⚡ Сафар харитаси: машина маршрутнинг қаерида — босиб ўтилган қисм хира,
/// қолган қисм маршрут рангида. ТОЗА ҳисоб (плагинсиз тестланади): энг яқин
/// нуқта [EvTripPlanner.locate] орқали (режа коридори билан бир хил
/// проекция), бу ерда фақат чизиқни иккига бўлиш.
class EvRouteProgress {
  const EvRouteProgress({
    required this.location,
    required this.passed,
    required this.remaining,
    required this.totalKm,
  });

  /// Машинанинг чизиқдаги энг яқин нуқтаси.
  final EvRouteLocation location;

  /// Босиб ўтилган қисм: чизиқ боши → машина. 2 тадан кам нуқта — ўтилгани йўқ.
  final List<EvRoutePoint> passed;

  /// Қолган қисм: машина → чизиқ охири. 2 тадан кам нуқта — етиб келган.
  final List<EvRoutePoint> remaining;

  /// Чизиқнинг геометрик узунлиги (км).
  final double totalKm;

  double get alongKm => location.alongKm;
  double get offRouteKm => location.offRouteKm;

  /// 0..1 — маршрутнинг қанча қисми босиб ўтилган.
  double get fraction => totalKm > 0 ? (alongKm / totalKm).clamp(0.0, 1.0) : 0;

  bool get hasPassed => passed.length >= 2;
  bool get hasRemaining => remaining.length >= 2;

  /// Машина йўлдан шунчадан узоқда бўлса, "йўлда" ҳисобланмайди (масалан,
  /// режа бошқа жойда кўриляпти) — хиралаштириш қўлланмайди. Қиймат
  /// режа коридори билан бир хил: станцияга бурилиш шу ичида.
  static const double onRouteThresholdKm = EvTripPlanner.defaultCorridorKm;

  /// Машина маршрутга яқинми ([onRouteThresholdKm] ичида).
  bool get isOnRoute => offRouteKm <= onRouteThresholdKm;

  /// [lat]/[lng] — машина. [fromSegment] — қаранг: [EvTripPlanner.locate].
  /// Маршрут бўш/битта нуқта бўлса `null`.
  static EvRouteProgress? compute({
    required List<EvRoutePoint> route,
    required double lat,
    required double lng,
    int fromSegment = 0,
  }) {
    final loc = EvTripPlanner.locate(
      route: route,
      lat: lat,
      lng: lng,
      fromSegment: fromSegment,
    );
    if (loc == null) return null;

    final snapped = EvRoutePoint(loc.lat, loc.lng);
    final seg = loc.segmentIndex;

    bool same(EvRoutePoint a, EvRoutePoint b) =>
        (a.lat - b.lat).abs() < 1e-9 && (a.lng - b.lng).abs() < 1e-9;

    final passed = <EvRoutePoint>[...route.sublist(0, seg + 1)];
    if (!same(passed.last, snapped)) passed.add(snapped);

    final remaining = <EvRoutePoint>[snapped];
    for (final p in route.sublist(seg + 1)) {
      if (!same(remaining.last, p)) remaining.add(p);
    }

    return EvRouteProgress(
      location: loc,
      passed: passed,
      remaining: remaining,
      totalKm: EvTripPlanner.routeLengthKm(route),
    );
  }
}

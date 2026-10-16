import 'package:ava_gurlan/features/ev_charging/controllers/ev_route_progress.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:flutter_test/flutter_test.dart';

// Маршрут бўйлаб ўтилган масофа: бошланишдан олдин, ўртада, охиридан кейин,
// йўлдан четда. Чизиқ — шимолга 10 км (ҳар 1 км да вершина), lng = 60.

const double _kmPerDegLat = 111.1949;
const double _baseLat = 41.0;
const double _baseLng = 60.0;

double _lat(double km) => _baseLat + km / _kmPerDegLat;

List<EvRoutePoint> _straight([int km = 10]) =>
    [for (var i = 0; i <= km; i++) EvRoutePoint(_lat(i.toDouble()), _baseLng)];

/// U-шакл: 10 км шимолга (lng 60.000), сўнг ~100 м шарқда 10 км жанубга.
List<EvRoutePoint> _uShape() => [
      for (var i = 0; i <= 10; i++) EvRoutePoint(_lat(i.toDouble()), 60.0),
      for (var i = 10; i >= 0; i--) EvRoutePoint(_lat(i.toDouble()), 60.001),
    ];

void main() {
  group('EvTripPlanner.locate', () {
    test('бошланишдан ОЛДИН (орқада) — 0 км, йўлдан узоқлиги ўлчанади', () {
      final loc = EvTripPlanner.locate(
          route: _straight(), lat: _lat(-5), lng: _baseLng)!;
      expect(loc.segmentIndex, 0);
      expect(loc.alongKm, closeTo(0, 0.01));
      expect(loc.offRouteKm, closeTo(5, 0.05));
      expect(loc.lat, closeTo(_lat(0), 1e-6));
    });

    test('ўртада: 5.5 км', () {
      final loc = EvTripPlanner.locate(
          route: _straight(), lat: _lat(5.5), lng: _baseLng)!;
      expect(loc.segmentIndex, 5);
      expect(loc.fractionInSegment, closeTo(0.5, 0.01));
      expect(loc.alongKm, closeTo(5.5, 0.02));
      expect(loc.offRouteKm, closeTo(0, 0.01));
    });

    test('охиридан КЕЙИН — 10 км, охирги сегмент', () {
      final loc = EvTripPlanner.locate(
          route: _straight(), lat: _lat(14), lng: _baseLng)!;
      expect(loc.segmentIndex, 9);
      expect(loc.fractionInSegment, closeTo(1, 1e-6));
      expect(loc.alongKm, closeTo(10, 0.02));
      expect(loc.offRouteKm, closeTo(4, 0.05));
    });

    test('йўлдан четда: энг яқин нуқта бўйича (4.2 км, 3 км шарқда)', () {
      // 3 км шарққа ≈ 3 / (111.19 * cos 41°) градус.
      final dLng = 3 / (_kmPerDegLat * 0.7547);
      final loc = EvTripPlanner.locate(
          route: _straight(), lat: _lat(4.2), lng: _baseLng + dLng)!;
      expect(loc.alongKm, closeTo(4.2, 0.05));
      expect(loc.offRouteKm, closeTo(3, 0.1));
    });

    test('бўш ёки битта нуқтали маршрут — null', () {
      expect(EvTripPlanner.locate(route: const [], lat: 1, lng: 1), isNull);
      expect(
          EvTripPlanner.locate(
              route: const [EvRoutePoint(1, 1)], lat: 1, lng: 1),
          isNull);
    });

    test('U-шакл: одатда олдинги сегмент, fromSegment билан қайтиш йўли', () {
      final route = _uShape();
      // Йўлга 44 м (lng 60.0004): чиқиш чизиғига яқинроқ.
      const lng = 60.0004;
      final a = EvTripPlanner.locate(route: route, lat: _lat(1), lng: lng)!;
      expect(a.segmentIndex, lessThan(10)); // чиқиш
      expect(a.alongKm, closeTo(1, 0.05));

      final b = EvTripPlanner.locate(
          route: route, lat: _lat(1), lng: 60.001 - 0.0004, fromSegment: 10)!;
      expect(b.segmentIndex, greaterThanOrEqualTo(10)); // қайтиш
      expect(b.alongKm, greaterThan(15)); // 10 + 10 - 1 км атрофида
    });

    test('fromSegment чегарадан ошса — охирги сегментга қисқартирилади', () {
      final loc = EvTripPlanner.locate(
          route: _straight(), lat: _lat(5), lng: _baseLng, fromSegment: 999)!;
      expect(loc.segmentIndex, 9);
    });
  });

  group('EvRouteProgress.compute', () {
    test('бошланишдан олдин: ўтилгани йўқ, қолгани — бутун чизиқ', () {
      final p = EvRouteProgress.compute(
          route: _straight(), lat: _lat(-4), lng: _baseLng)!;
      expect(p.hasPassed, isFalse);
      expect(p.hasRemaining, isTrue);
      expect(p.remaining.length, 11);
      expect(p.fraction, closeTo(0, 0.01));
      expect(p.isOnRoute, isTrue); // 4 км — коридор ичида
    });

    test('ўртада: ўтилган ва қолган қисмлар учрашади ва бир-бирини қоплайди',
        () {
      final route = _straight();
      final p =
          EvRouteProgress.compute(route: route, lat: _lat(5.5), lng: _baseLng)!;
      expect(p.hasPassed, isTrue);
      expect(p.hasRemaining, isTrue);
      // 0..5 вершина + машина; машина + 6..10 вершина.
      expect(p.passed.length, 7);
      expect(p.remaining.length, 6);
      expect(p.passed.last.lat, closeTo(p.remaining.first.lat, 1e-9));
      expect(p.passed.last.lng, closeTo(p.remaining.first.lng, 1e-9));
      expect(p.passed.first.lat, route.first.lat);
      expect(p.remaining.last.lat, route.last.lat);
      expect(p.fraction, closeTo(0.55, 0.01));
      expect(p.alongKm, closeTo(5.5, 0.02));
      expect(p.totalKm, closeTo(10, 0.02));
    });

    test('охиридан кейин: бутун чизиқ ўтилган, қолгани йўқ', () {
      final p = EvRouteProgress.compute(
          route: _straight(), lat: _lat(14), lng: _baseLng)!;
      expect(p.hasPassed, isTrue);
      expect(p.hasRemaining, isFalse);
      expect(p.passed.length, 11);
      expect(p.fraction, closeTo(1, 0.01));
    });

    test('йўлдан 5 км дан узоқда "йўлда эмас" — хиралаштириш қўлланмайди', () {
      final far = EvRouteProgress.compute(
          route: _straight(), lat: _lat(5), lng: _baseLng + 0.2)!; // ~17 км
      expect(far.offRouteKm, greaterThan(EvRouteProgress.onRouteThresholdKm));
      expect(far.isOnRoute, isFalse);

      final near = EvRouteProgress.compute(
          route: _straight(), lat: _lat(5), lng: _baseLng + 0.02)!; // ~1.7 км
      expect(near.isOnRoute, isTrue);
    });

    test('вершинада турган машина: нуқталар такрорланмайди', () {
      final p = EvRouteProgress.compute(
          route: _straight(), lat: _lat(3), lng: _baseLng)!;
      for (var i = 1; i < p.passed.length; i++) {
        final same = (p.passed[i].lat - p.passed[i - 1].lat).abs() < 1e-9 &&
            (p.passed[i].lng - p.passed[i - 1].lng).abs() < 1e-9;
        expect(same, isFalse);
      }
      for (var i = 1; i < p.remaining.length; i++) {
        final same = (p.remaining[i].lat - p.remaining[i - 1].lat).abs() < 1e-9;
        expect(same, isFalse);
      }
      // 0..3 = 4 нуқта; 3..10 = 8 нуқта.
      expect(p.passed.length, 4);
      expect(p.remaining.length, 8);
    });

    test('бўш маршрут — null', () {
      expect(EvRouteProgress.compute(route: const [], lat: 1, lng: 1), isNull);
    });
  });
}

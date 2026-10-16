import 'package:ava_gurlan/features/ev_charging/controllers/ev_route_progress.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_map_view.dart';
import 'package:flutter_test/flutter_test.dart';

// Chiziqni chizish uchun bo'laklar: yo'lda bo'lsa o'tilgani xira, qolgani
// marshrut rangida; yo'lda emas yoki GPS yo'q bo'lsa - butun marshrut.

const double _kmPerDegLat = 111.1949;
double _lat(double km) => 41.0 + km / _kmPerDegLat;

List<EvRoutePoint> _route() =>
    [for (var i = 0; i <= 10; i++) EvRoutePoint(_lat(i.toDouble()), 60.0)];

void main() {
  test('GPS yo\'q (progress null): butun marshrut, xiralash yo\'q', () {
    final route = _route();
    final parts = EvTripMapGeometry.routeParts(route, null);
    expect(parts.passed, isNull);
    expect(parts.remaining, same(route));
  });

  test('yo\'lda: o\'tilgan va qolgan qism', () {
    final route = _route();
    final p = EvRouteProgress.compute(route: route, lat: _lat(5.5), lng: 60.0);
    final parts = EvTripMapGeometry.routeParts(route, p);
    expect(parts.passed, isNotNull);
    expect(parts.passed!.length, 7);
    expect(parts.remaining.length, 6);
  });

  test('yo\'ldan uzoqda: xiralash qo\'llanmaydi, butun marshrut', () {
    final route = _route();
    final p = EvRouteProgress.compute(route: route, lat: _lat(5), lng: 61.0);
    expect(p!.isOnRoute, isFalse);
    final parts = EvTripMapGeometry.routeParts(route, p);
    expect(parts.passed, isNull);
    expect(parts.remaining, same(route));
  });

  test(
      'boshlanishdan oldin: xira qism yo\'q; oxiridan keyin: qolgan qism yo\'q',
      () {
    final route = _route();
    final before = EvTripMapGeometry.routeParts(
        route, EvRouteProgress.compute(route: route, lat: _lat(-3), lng: 60.0));
    expect(before.passed, isNull);
    expect(before.remaining.length, 11);

    final after = EvTripMapGeometry.routeParts(
        route, EvRouteProgress.compute(route: route, lat: _lat(13), lng: 60.0));
    expect(after.passed, isNotNull);
    expect(after.remaining, isEmpty);
  });
}

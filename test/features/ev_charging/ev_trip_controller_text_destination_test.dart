import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_controller.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/models/directions_result.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:ava_gurlan/services/google_directions_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Matnli manzil (tuman/viloyat - koordinatasiz): kontroller Directions'ga
// matn beradi va Google topgan tugash nuqtasini oladi.

/// Google polyline kodlash (haqiqiy PolylineDecoder sinaladi, mock emas).
String _encode(List<List<double>> points) {
  final sb = StringBuffer();
  var prevLat = 0;
  var prevLng = 0;
  void value(int v) {
    var x = v < 0 ? ~(v << 1) : (v << 1);
    while (x >= 0x20) {
      sb.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    sb.writeCharCode(x + 63);
  }

  for (final p in points) {
    final lat = (p[0] * 1e5).round();
    final lng = (p[1] * 1e5).round();
    value(lat - prevLat);
    value(lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return sb.toString();
}

/// (41.0, 60.0) -> (41.5, 60.0) -> (42.0, 60.0).
final _poly = _encode([
  [41.0, 60.0],
  [41.5, 60.0],
  [42.0, 60.0],
]);

class _Fake extends GoogleDirectionsService {
  _Fake({this.textResult, this.coordResult, this.error});

  final DirectionsResult? textResult;
  final DirectionsResult? coordResult;
  final Object? error;

  int coordCalls = 0;
  int textCalls = 0;
  String? lastText;
  double? lastOriginLat;

  @override
  Future<DirectionsResult> fetchSimpleRoute({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    coordCalls++;
    if (error != null) throw error!;
    return coordResult!;
  }

  @override
  Future<DirectionsResult> fetchSimpleRouteToText({
    required double originLat,
    required double originLng,
    required String destinationText,
  }) async {
    textCalls++;
    lastText = destinationText;
    lastOriginLat = originLat;
    if (error != null) throw error!;
    return textResult!;
  }
}

const _car = EvCarSpec(
  usableBatteryKwh: 60,
  consumptionKwhPer100Km: 15,
  connectors: ['CCS2'],
);

Future<EvTripController> _run(
  _Fake fake, {
  double? lat,
  double? lng,
  String? text,
}) async {
  final c = EvTripController(directions: fake);
  await c.planTrip(
    originLat: 41,
    originLng: 60,
    destinationLat: lat,
    destinationLng: lng,
    destinationText: text,
    car: _car,
    socPercent: 80,
    stations: const <EvChargingStation>[],
  );
  return c;
}

void main() {
  test('matnli manzil: matn Directions\'ga ketadi, tugash nuqtasi end_location',
      () async {
    final fake = _Fake(
      textResult: DirectionsResult(
        distanceKm: 120,
        durationMin: 90,
        polyline: _poly,
        endLat: 41.9,
        endLng: 60.1,
      ),
    );
    final c = await _run(fake, text: 'Gurlan tumani, Xorazm, Uzbekistan');

    expect(fake.textCalls, 1);
    expect(fake.coordCalls, 0);
    expect(fake.lastText, 'Gurlan tumani, Xorazm, Uzbekistan');
    expect(fake.lastOriginLat, 41);
    expect(c.error, isNull);
    expect(c.plan, isNotNull);
    expect(c.destinationLat, 41.9);
    expect(c.destinationLng, 60.1);
    expect(c.hasDestination, isTrue);
    expect(c.routePoints.length, 3);
  });

  test('end_location yo\'q - marshrut chizig\'ining oxirgi nuqtasi', () async {
    final fake = _Fake(
      textResult:
          DirectionsResult(distanceKm: 100, durationMin: 60, polyline: _poly),
    );
    final c = await _run(fake, text: 'Xiva tumani, Xorazm, Uzbekistan');
    expect(c.error, isNull);
    expect(c.destinationLat, closeTo(42.0, 1e-6));
    expect(c.destinationLng, closeTo(60.0, 1e-6));
  });

  test('tayyor koordinata: eski yo\'l ishlaydi, matn so\'ralmaydi', () async {
    final fake = _Fake(
      coordResult: DirectionsResult(
        distanceKm: 100,
        durationMin: 60,
        polyline: _poly,
        endLat: 99, // koordinata berilgan bo'lsa, o'shanisi ustun
        endLng: 99,
      ),
    );
    final c = await _run(fake, lat: 42.0, lng: 60.0);
    expect(fake.coordCalls, 1);
    expect(fake.textCalls, 0);
    expect(c.destinationLat, 42.0);
    expect(c.destinationLng, 60.0);
  });

  test('Google yo\'l topmadi - ev_trip_error_geometry uchun kod', () async {
    final fake = _Fake(
      error: const DirectionsNoRouteException('Directions API: ZERO_RESULTS'),
    );
    final c = await _run(fake, text: 'Nowhere, Uzbekistan');
    expect(c.error, 'route_geometry_missing');
    expect(c.plan, isNull);
    expect(c.hasDestination, isFalse);
    expect(c.loading, isFalse);
  });

  test('tarmoq xatosi - route_request_failed (xom xato ko\'rsatilmaydi)',
      () async {
    final fake = _Fake(error: Exception('SocketException: boom'));
    final c = await _run(fake, text: 'Gurlan tumani, Xorazm, Uzbekistan');
    expect(c.error, 'route_request_failed');
    expect(c.error, isNot(contains('Socket')));
  });

  test('na koordinata, na matn - so\'rovsiz friendly xato', () async {
    final fake = _Fake();
    final c = await _run(fake);
    expect(fake.coordCalls + fake.textCalls, 0);
    expect(c.error, 'route_geometry_missing');
    expect(c.loading, isFalse);
  });

  test('bo\'sh matn (faqat bo\'shliq) - so\'rovsiz friendly xato', () async {
    final fake = _Fake();
    final c = await _run(fake, text: '   ');
    expect(fake.textCalls, 0);
    expect(c.error, 'route_geometry_missing');
  });

  test('clear() manzil koordinatasini ham tozalaydi', () async {
    final fake = _Fake(
      textResult: DirectionsResult(
          distanceKm: 100,
          durationMin: 60,
          polyline: _poly,
          endLat: 1,
          endLng: 2),
    );
    final c = await _run(fake, text: 'X, Uzbekistan');
    expect(c.hasDestination, isTrue);
    c.clear();
    expect(c.hasDestination, isFalse);
    expect(c.destinationLat, isNull);
  });

  test('yangi hisob oldingi manzil koordinatasini qoldirmaydi', () async {
    final fake = _Fake(
      textResult: DirectionsResult(
          distanceKm: 100,
          durationMin: 60,
          polyline: _poly,
          endLat: 1,
          endLng: 2),
    );
    final c = await _run(fake, text: 'X, Uzbekistan');
    expect(c.destinationLat, 1);

    final failing = _Fake(error: Exception('x'));
    final c2 = EvTripController(directions: failing);
    await c2.planTrip(
      originLat: 41,
      originLng: 60,
      destinationText: 'Y',
      car: _car,
      socPercent: 80,
      stations: const [],
    );
    expect(c2.destinationLat, isNull);
  });
}

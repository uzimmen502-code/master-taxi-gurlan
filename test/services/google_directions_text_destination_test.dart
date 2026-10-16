import 'dart:convert';

import 'package:ava_gurlan/models/directions_result.dart';
import 'package:ava_gurlan/services/google_directions_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Matnli manzil: so'rov qurilishi va javobdan tugash nuqtasini olish.
// HTTP klienti soxta (MockClient) - tarmoq va kalit ishlatilmaydi;
// so'rovdagi `key` qiymati tekshirilmaydi va chop etilmaydi.

String _ok({
  double? endLat = 41.8,
  double? endLng = 60.4,
  bool twoLegs = false,
}) {
  Map<String, dynamic> leg(int meters, int secs, double? lat, double? lng) => {
        'distance': {'value': meters},
        'duration': {'value': secs},
        if (lat != null && lng != null)
          'end_location': {'lat': lat, 'lng': lng},
      };
  return jsonEncode({
    'status': 'OK',
    'routes': [
      {
        'legs': twoLegs
            ? [leg(1000, 600, 1.0, 2.0), leg(2000, 1200, endLat, endLng)]
            : [leg(120000, 5400, endLat, endLng)],
        'overview_polyline': {'points': '_p~iF~ps|U_ulLnnqC'},
      },
    ],
  });
}

GoogleDirectionsService _svc(
  http.Response Function(http.Request) handler, {
  List<http.Request>? log,
}) {
  return GoogleDirectionsService(
    client: MockClient((req) async {
      log?.add(req);
      return handler(req);
    }),
  );
}

void main() {
  group('fetchSimpleRouteToText - so\'rov qurilishi', () {
    test('manzil matn bo\'lib, origin koordinata, region=uz', () async {
      final log = <http.Request>[];
      final s = _svc((_) => http.Response(_ok(), 200), log: log);

      await s.fetchSimpleRouteToText(
        originLat: 41.55,
        originLng: 60.63,
        destinationText: 'Gurlan tumani, Xorazm, Uzbekistan',
      );

      expect(log, hasLength(1));
      final q = log.single.url.queryParameters;
      expect(log.single.url.host, 'maps.googleapis.com');
      expect(log.single.url.path, '/maps/api/directions/json');
      expect(q['origin'], '41.55,60.63');
      expect(q['destination'], 'Gurlan tumani, Xorazm, Uzbekistan');
      expect(q['region'], 'uz');
      expect(q['mode'], 'driving');
      expect(q.containsKey('waypoints'), isFalse);
      expect(q.containsKey('key'), isTrue);
    });

    test('kirill manzil va apostrof to\'g\'ri kodlanadi', () async {
      final log = <http.Request>[];
      final s = _svc((_) => http.Response(_ok(), 200), log: log);
      await s.fetchSimpleRouteToText(
        originLat: 1,
        originLng: 2,
        destinationText: 'Қўшкўпир тумани, Хоразм, Ўзбекистон',
      );
      expect(log.single.url.queryParameters['destination'],
          'Қўшкўпир тумани, Хоразм, Ўзбекистон');
    });

    test('manzil atrofidagi bo\'shliq olib tashlanadi', () async {
      final log = <http.Request>[];
      final s = _svc((_) => http.Response(_ok(), 200), log: log);
      await s.fetchSimpleRouteToText(
        originLat: 1,
        originLng: 2,
        destinationText: '  Xiva tumani, Xorazm, Uzbekistan \n',
      );
      expect(log.single.url.queryParameters['destination'],
          'Xiva tumani, Xorazm, Uzbekistan');
    });

    test('bo\'sh matn - so\'rov yuborilmaydi, "yo\'l yo\'q" xatosi', () async {
      final log = <http.Request>[];
      final s = _svc((_) => http.Response(_ok(), 200), log: log);
      await expectLater(
        s.fetchSimpleRouteToText(
            originLat: 1, originLng: 2, destinationText: '   '),
        throwsA(isA<DirectionsNoRouteException>()),
      );
      expect(log, isEmpty);
    });
  });

  group('javobni o\'qish', () {
    test('tugash nuqtasi = oxirgi leg end_location', () async {
      final s = _svc((_) => http.Response(_ok(), 200));
      final r = await s.fetchSimpleRouteToText(
        originLat: 41.55,
        originLng: 60.63,
        destinationText: 'Gurlan tumani, Xorazm, Uzbekistan',
      );
      expect(r.endLat, 41.8);
      expect(r.endLng, 60.4);
      expect(r.hasEnd, isTrue);
      expect(r.distanceKm, 120);
      expect(r.durationMin, 90);
      expect(r.polyline, isNotEmpty);
    });

    test('bir nechta leg bo\'lsa - oxirgisi', () async {
      final s = _svc((_) => http.Response(_ok(twoLegs: true), 200));
      final r = await s.fetchSimpleRouteToText(
          originLat: 1, originLng: 2, destinationText: 'X, Uzbekistan');
      expect(r.endLat, 41.8);
      expect(r.endLng, 60.4);
      expect(r.distanceKm, 3);
    });

    test('end_location yo\'q - null (o\'ylab topilmaydi)', () async {
      final s =
          _svc((_) => http.Response(_ok(endLat: null, endLng: null), 200));
      final r = await s.fetchSimpleRouteToText(
          originLat: 1, originLng: 2, destinationText: 'X, Uzbekistan');
      expect(r.endLat, isNull);
      expect(r.endLng, isNull);
      expect(r.hasEnd, isFalse);
    });

    test(
        'ZERO_RESULTS / NOT_FOUND / bo\'sh routes - DirectionsNoRouteException',
        () async {
      for (final body in [
        jsonEncode({'status': 'ZERO_RESULTS', 'routes': []}),
        jsonEncode({'status': 'NOT_FOUND', 'routes': []}),
        jsonEncode({'status': 'OK', 'routes': []}),
      ]) {
        final s = _svc((_) => http.Response(body, 200));
        await expectLater(
          s.fetchSimpleRouteToText(
              originLat: 1, originLng: 2, destinationText: 'Nowhere'),
          throwsA(isA<DirectionsNoRouteException>()),
          reason: body,
        );
      }
    });

    test('kalit/kvota xatosi va HTTP xato - oddiy Exception (yo\'l yo\'q emas)',
        () async {
      final denied = _svc((_) => http.Response(
          jsonEncode({'status': 'REQUEST_DENIED', 'error_message': 'bad key'}),
          200));
      await expectLater(
        denied.fetchSimpleRouteToText(
            originLat: 1, originLng: 2, destinationText: 'X'),
        throwsA(
            allOf(isA<Exception>(), isNot(isA<DirectionsNoRouteException>()))),
      );

      final http500 = _svc((_) => http.Response('oops', 500));
      await expectLater(
        http500.fetchSimpleRouteToText(
            originLat: 1, originLng: 2, destinationText: 'X'),
        throwsA(
            allOf(isA<Exception>(), isNot(isA<DirectionsNoRouteException>()))),
      );
    });

    test('DirectionsNoRouteException oddiy Exception sifatida ham ushlanadi',
        () {
      const e = DirectionsNoRouteException('x');
      expect(e, isA<Exception>());
      expect(e.toString(), 'Exception: x');
    });
  });

  group('mavjud koordinatali chaqiruv buzilmagan', () {
    test('fetchSimpleRoute: origin/destination koordinata, region yo\'q',
        () async {
      final log = <http.Request>[];
      final s = _svc((_) => http.Response(_ok(), 200), log: log);
      final DirectionsResult r = await s.fetchSimpleRoute(
        originLat: 41.55,
        originLng: 60.63,
        destinationLat: 39.65,
        destinationLng: 66.96,
      );
      final q = log.single.url.queryParameters;
      expect(q['origin'], '41.55,60.63');
      expect(q['destination'], '39.65,66.96');
      expect(q.containsKey('region'), isFalse);
      expect(r.distanceKm, 120);
      // End koordinata endi bu yo'lda ham qaytadi (qo'shimcha, buzmaydi).
      expect(r.endLat, 41.8);
    });

    test('DirectionsResult: yangi maydonlar ixtiyoriy', () {
      const r = DirectionsResult(distanceKm: 1, durationMin: 2, polyline: 'x');
      expect(r.endLat, isNull);
      expect(r.hasEnd, isFalse);
      expect(r.waypointOrder, isEmpty);
    });
  });
}

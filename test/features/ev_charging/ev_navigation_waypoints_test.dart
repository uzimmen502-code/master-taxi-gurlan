import 'package:ava_gurlan/core/utils/map_launcher.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_navigation_waypoints.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Тоза функция: харита/плагин керак эмас. Координатани таниш учун станция
// кенглиги = 40 + along/1000 (ҳар км учун ўзига хос).

double _lat(double along) => 40 + along / 1000;

EvChargingStation _st(String id, double lat, [double lng = 60.0]) =>
    EvChargingStation(
      id: id,
      latitude: lat,
      longitude: lng,
      geohash: '',
      chargingTypes: const ['DC'],
      connectors: const ['CCS2'],
      powerKw: 120,
      status: 'working',
      verificationStatus: 'verified',
      confirmationCount: 2,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
      name: id,
    );

EvTripBackup _b(String id, double stopAlong, double delta) => EvTripBackup(
      station: _st(id, _lat(stopAlong + delta)),
      alongKm: stopAlong + delta,
      offRouteKm: 1,
      deltaKm: delta,
    );

EvTripStop _stop(String id, double along, [List<EvTripBackup> b = const []]) =>
    EvTripStop(
      station: _st(id, _lat(along)),
      alongKm: along,
      offRouteKm: 0,
      legKm: along,
      arriveSocPercent: 18,
      departSocPercent: 80,
      backups: b,
    );

EvTripPlan _plan(List<EvTripStop> stops,
        {EvTripPlanStatus status = EvTripPlanStatus.ok}) =>
    EvTripPlan(
      status: status,
      stops: stops,
      totalKm: 900,
      arrivalSocPercent: 20,
    );

List<double> _lats(List<EvWaypoint> w) => [for (final p in w) p.lat];

void main() {
  group('mapsMaxWaypoints - platformaga qarab chegara (yagona manba)', () {
    test('native / desktop - 9', () {
      expect(kMapsMaxWaypoints, 9);
      expect(
          mapsMaxWaypoints(isWeb: false, platform: TargetPlatform.android), 9);
      expect(mapsMaxWaypoints(isWeb: false, platform: TargetPlatform.iOS), 9);
      expect(
          mapsMaxWaypoints(isWeb: false, platform: TargetPlatform.windows), 9);
    });

    test('mobil brauzer (web + Android/iOS) - 3', () {
      expect(kMapsMobileWebMaxWaypoints, 3);
      expect(
          mapsMaxWaypoints(isWeb: true, platform: TargetPlatform.android), 3);
      expect(mapsMaxWaypoints(isWeb: true, platform: TargetPlatform.iOS), 3);
    });

    test('desktop brauzer - 9', () {
      expect(
          mapsMaxWaypoints(isWeb: true, platform: TargetPlatform.windows), 9);
      expect(mapsMaxWaypoints(isWeb: true, platform: TargetPlatform.macOS), 9);
      expect(mapsMaxWaypoints(isWeb: true, platform: TargetPlatform.linux), 9);
    });

    test('testda (web emas) default 9', () {
      expect(mapsMaxWaypoints(), 9);
    });
  });

  group('evNavigationWaypoints', () {
    test('bo\'sh reja - bo\'sh ro\'yxat', () {
      expect(evNavigationWaypoints(EvTripPlan.empty), isEmpty);
      expect(evNavigationWaypoints(_plan(const [])), isEmpty);
      expect(
          evNavigationWaypoints(
              _plan(const [], status: EvTripPlanStatus.noChargingNeeded)),
          isEmpty);
    });

    test('faqat asosiy to\'xtashlar: yo\'l bo\'ylab tartibda', () {
      // Ataylab tartibsiz berildi - natija alongKm o'sishi bo'yicha.
      final w = evNavigationWaypoints(
          _plan([_stop('b', 400), _stop('a', 150), _stop('c', 700)]));
      expect(_lats(w), [_lat(150), _lat(400), _lat(700)]);
      expect(w.first.lng, 60.0);
    });

    test('zaxiralar tanlanmasa (default) - faqat asosiylar', () {
      final plan = _plan([
        _stop('a', 200, [_b('a-', 200, -30), _b('a+', 200, 25)]),
        _stop('b', 500, [_b('b-', 500, -10)]),
      ]);
      expect(_lats(evNavigationWaypoints(plan)), [_lat(200), _lat(500)]);
      expect(_lats(evNavigationWaypoints(plan, selectedBackupIds: const {})),
          [_lat(200), _lat(500)]);
      // Noma'lum id e'tiborga olinmaydi.
      expect(
          _lats(evNavigationWaypoints(plan, selectedBackupIds: {'nope'})),
          [_lat(200), _lat(500)]);
    });

    test('tanlangan zaxira yo\'l bo\'yicha o\'z o\'rniga qo\'shiladi', () {
      final plan = _plan([
        _stop('a', 200, [_b('a-', 200, -30), _b('a+', 200, 25)]),
        _stop('b', 500, [_b('b-', 500, -10)]),
      ]);
      expect(
        _lats(evNavigationWaypoints(plan, selectedBackupIds: {'b-', 'a-'})),
        [
          _lat(170), // a- (tanlangan, a'dan oldin)
          _lat(200), // a
          _lat(490), // b- (tanlangan)
          _lat(500), // b
        ],
      );
      // Hammasi tanlansa - barchasi, tartib bilan.
      expect(
        _lats(evNavigationWaypoints(plan,
            selectedBackupIds: {'a-', 'a+', 'b-'})),
        [_lat(170), _lat(200), _lat(225), _lat(490), _lat(500)],
      );
    });

    test('zaxiraning masofasi stop.along + delta bilan mos (bitta shkala)', () {
      final stop = _stop('a', 300, [_b('x', 300, 40)]);
      final b = stop.backups.single;
      expect(b.alongKm, stop.alongKm + b.deltaKm);
    });

    test('chegara oshsa: asosiylar ustuvor, tanlangan zaxiralar eng yaqinidan',
        () {
      final plan = _plan([
        _stop('a', 100, [_b('a1', 100, -50), _b('a2', 100, 5)]),
        _stop('b', 300, [_b('b1', 300, 20)]),
        _stop('c', 500, [_b('c1', 500, -3)]),
      ]);
      // 3 asosiy + 4 tanlangan zaxira = 7, chegara 5 -> 3 asosiy + 2 yaqin.
      final w = evNavigationWaypoints(plan,
          selectedBackupIds: {'a1', 'a2', 'b1', 'c1'}, max: 5);
      expect(w, hasLength(5));
      expect(_lats(w), [
        _lat(100), // a
        _lat(105), // a2 (|5|)
        _lat(300), // b
        _lat(497), // c1 (|3|)
        _lat(500), // c
      ]);
      expect(_lats(w), isNot(contains(_lat(50))), reason: 'a1 (-50) tushdi');
      expect(_lats(w), isNot(contains(_lat(320))), reason: 'b1 (+20) tushdi');
    });

    test('asosiylar chegaraga teng yoki ko\'p: zaxira yo\'q, chegaradan oshmaydi',
        () {
      final stops = [
        for (var i = 1; i <= 12; i++)
          _stop('s$i', i * 50.0, [_b('z$i', i * 50.0, 1)]),
      ];
      final plan = _plan(stops);
      final all = {for (var i = 1; i <= 12; i++) 'z$i'};

      final w = evNavigationWaypoints(plan, selectedBackupIds: all);
      expect(w, hasLength(9));
      expect(_lats(w), [for (var i = 1; i <= 9; i++) _lat(i * 50.0)]);

      final exact = evNavigationWaypoints(_plan(stops.take(9).toList()),
          selectedBackupIds: all, max: 9);
      expect(exact, hasLength(9));
      expect(_lats(exact), [for (var i = 1; i <= 9; i++) _lat(i * 50.0)]);
    });

    test('mobil veb (max 3): asosiylar birinchi, tartib saqlanadi', () {
      final mobile = mapsMaxWaypoints(
          isWeb: true, platform: TargetPlatform.android); // 3
      final plan = _plan([
        for (var i = 1; i <= 5; i++)
          _stop('s$i', i * 100.0, [_b('z$i', i * 100.0, -4)]),
      ]);
      final w = evNavigationWaypoints(plan,
          selectedBackupIds: {'z1', 'z5'}, max: mobile);
      expect(w, hasLength(3));
      // 5 asosiy bor, faqat birinchi 3 tasi (yo'l tartibida); zaxira kirmaydi.
      expect(_lats(w), [_lat(100), _lat(200), _lat(300)]);

      // 2 asosiy + tanlangan 2 zaxira, chegara 3 -> 1 ta zaxira (yaqini).
      final small = _plan([
        _stop('a', 100, [_b('a1', 100, -40)]),
        _stop('b', 400, [_b('b1', 400, 7)]),
      ]);
      final w2 = evNavigationWaypoints(small,
          selectedBackupIds: {'a1', 'b1'}, max: mobile);
      expect(w2, hasLength(3));
      expect(_lats(w2), [_lat(100), _lat(400), _lat(407)]);
    });

    test('capacity: chegara - asosiylar (>= 0)', () {
      final plan = _plan([_stop('a', 100), _stop('b', 200)]);
      expect(evNavigationBackupCapacity(plan, max: 9), 7);
      expect(evNavigationBackupCapacity(plan, max: 3), 1);
      expect(evNavigationBackupCapacity(plan, max: 2), 0);
      expect(evNavigationBackupCapacity(plan, max: 1), 0);
      expect(evNavigationBackupCapacity(plan, max: 0), 0);
      expect(evNavigationBackupCapacity(EvTripPlan.empty), 0);
    });

    test('dublikat koordinata bitta marta; asosiy zaxiradan ustun', () {
      final dupPrimary = _stop('a', 200, [
        // Asosiyning aynan o'zi, boshqa id bilan zaxira sifatida.
        EvTripBackup(
          station: _st('a-copy', _lat(200)),
          alongKm: 200,
          offRouteKm: 0,
          deltaKm: 0,
        ),
        _b('a+', 200, 10),
      ]);
      final other = _stop('b', 300, [
        // a+ ning aynan o'zi (boshqa stop'ning zaxirasi sifatida).
        EvTripBackup(
          station: _st('a+dup', _lat(210)),
          alongKm: 210,
          offRouteKm: 0,
          deltaKm: -90,
        ),
      ]);
      final plan = _plan([dupPrimary, other]);
      final w = evNavigationWaypoints(plan,
          selectedBackupIds: {'a-copy', 'a+', 'a+dup'});
      expect(_lats(w), [_lat(200), _lat(210), _lat(300)]);
      expect(w.map((p) => '${p.lat},${p.lng}').toSet(), hasLength(w.length));

      // Taklif ro'yxatida ham dublikat/asosiyning nusxasi yo'q.
      final options = evNavigationBackupOptions(plan);
      expect(options.map((o) => o.id).toList(), ['a+']);
    });

    test('tayyor bo\'lmagan reja (uzilish, noto\'g\'ri avto, marshrut yo\'q): '
        'oraliq nuqta ham, taklif ham yo\'q', () {
      for (final s in [
        EvTripPlanStatus.gapTooLarge,
        EvTripPlanStatus.invalidCar,
        EvTripPlanStatus.noRoute,
      ]) {
        final p = _plan([
          _stop('a', 100, [_b('a1', 100, 3)])
        ], status: s);
        expect(evNavigationWaypoints(p, selectedBackupIds: {'a1'}), isEmpty,
            reason: '$s');
        expect(evNavigationBackupOptions(p), isEmpty, reason: '$s');
        expect(evNavigationBackupCapacity(p), 0, reason: '$s');
      }
    });

    test('max <= 0 - bo\'sh; manfiy va nol xavfsiz', () {
      final p = _plan([_stop('a', 100)]);
      expect(evNavigationWaypoints(p, max: 0), isEmpty);
      expect(evNavigationWaypoints(p, max: -3), isEmpty);
      expect(evNavigationWaypoints(p, max: 1), hasLength(1));
    });
  });

  group('evNavigationBackupOptions', () {
    test('yo\'l bo\'yicha tartib; har biri o\'z asosiy to\'xtashiga bog\'langan',
        () {
      final a = _stop('a', 200, [_b('a+', 200, 25), _b('a-', 200, -30)]);
      final b = _stop('b', 500, [_b('b-', 500, -10)]);
      final options = evNavigationBackupOptions(_plan([a, b]));
      expect(options.map((o) => o.id).toList(), ['a-', 'a+', 'b-']);
      expect(options.map((o) => o.stop.station.id).toList(), ['a', 'a', 'b']);
    });

    test('zaxira yo\'q - bo\'sh', () {
      expect(evNavigationBackupOptions(_plan([_stop('a', 100)])), isEmpty);
    });
  });
}

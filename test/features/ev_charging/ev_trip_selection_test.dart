import 'package:ava_gurlan/core/utils/map_launcher.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_nav_relay.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_selection.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Toza mantiq: xarita/plagin kerak emas. Koordinatani tanish uchun stansiya
// kengligi = 40 + along/1000 (har km uchun o'ziga xos).

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

EvCorridorStation _c(String id, double along, [double off = 0.5]) =>
    EvCorridorStation(
        station: _st(id, _lat(along)), alongKm: along, offRouteKm: off);

EvTripCandidate _cand(String id, double along, {double? lat}) => EvTripCandidate(
      station: _st(id, lat ?? _lat(along)),
      alongKm: along,
      offRouteKm: 0,
      kind: EvTripMarkerKind.other,
    );

List<double> _lats(List<EvWaypoint> w) => [for (final p in w) p.lat];
List<String> _ids(EvTripSelection s) => [for (final c in s.selected) c.id];

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

  group('evTripCandidates - yo\'l bo\'yidagi BARCHA stansiyalar', () {
    test('koridor stansiyalarining hammasi, yo\'l bo\'yicha tartib, turlari',
        () {
      final plan = _plan([
        _stop('p1', 200, [_b('b1', 200, 30)]),
        _stop('p2', 400),
      ]);
      final corridor = [
        _c('x9', 500),
        _c('p2', 400),
        _c('b1', 230),
        _c('p1', 200),
        _c('x1', 50),
      ];
      final list = evTripCandidates(plan, corridor);
      expect([for (final c in list) c.id], ['x1', 'p1', 'b1', 'p2', 'x9']);
      expect(list.map((c) => c.kind).toList(), [
        EvTripMarkerKind.other,
        EvTripMarkerKind.primary,
        EvTripMarkerKind.backup,
        EvTripMarkerKind.primary,
        EvTripMarkerKind.other,
      ]);
      // Koridor ma'lumoti (along/off) saqlanadi.
      expect(list.first.alongKm, 50);
      expect(list.first.offRouteKm, 0.5);
    });

    test('koridorda yo\'q reja stansiyalari qo\'shiladi, takror yo\'q', () {
      final plan = _plan([
        _stop('p1', 200, [_b('b1', 200, -20)]),
      ]);
      final list = evTripCandidates(plan, [_c('p1', 200)]);
      expect([for (final c in list) c.id], ['b1', 'p1']);
      expect(list.first.kind, EvTripMarkerKind.backup);
      expect(list.first.alongKm, 180);
    });

    test('bo\'sh reja va bo\'sh koridor - bo\'sh', () {
      expect(evTripCandidates(EvTripPlan.empty, const []), isEmpty);
    });
  });

  group('EvTripSelection.recommended - boshlang\'ich tanlov', () {
    test('tavsiya etilgan asosiylar tanlangan, zaxira va boshqalar yo\'q', () {
      final plan = _plan([
        _stop('p2', 400),
        _stop('p1', 200, [_b('b1', 200, 20)]),
      ]);
      final s = EvTripSelection.recommended(
        plan,
        [_c('p1', 200), _c('b1', 220), _c('p2', 400), _c('x', 300)],
        maxWaypoints: 9,
      );
      expect(_ids(s), ['p1', 'p2'], reason: 'yo\'l bo\'yicha');
      expect(s.count, 2);
      expect(s.isSelected('b1'), isFalse);
      expect(s.isSelected('x'), isFalse);
      expect(s.numbers, {'p1': 1, 'p2': 2});
    });

    test('reja tayyor emas (uzilish): hech narsa tanlanmagan', () {
      final plan =
          _plan([_stop('p1', 200)], status: EvTripPlanStatus.gapTooLarge);
      final s =
          EvTripSelection.recommended(plan, [_c('p1', 200)], maxWaypoints: 9);
      expect(s.count, 0);
      expect(s.waypoints, isEmpty);
      // Haydovchi baribir qo'sha oladi.
      expect(s.toggle('p1'), isTrue);
      expect(s.count, 1);
    });

    test('zarur emas (noChargingNeeded) va bo\'sh reja: bo\'sh', () {
      final s1 = EvTripSelection.recommended(
          _plan(const [], status: EvTripPlanStatus.noChargingNeeded),
          [_c('x', 100)],
          maxWaypoints: 9);
      expect(s1.count, 0);
      expect(s1.waypoints, isEmpty);
      final s2 = EvTripSelection.recommended(EvTripPlan.empty, const [],
          maxWaypoints: 9);
      expect(s2.count, 0);
      expect(s2.candidates, isEmpty);
    });

    test('bir xil koordinatali ikki asosiy - bitta tanlov', () {
      final a = _stop('a', 200);
      final dup = EvTripStop(
        station: _st('a2', _lat(200)), // xuddi shu koordinata
        alongKm: 200,
        offRouteKm: 0,
        legKm: 10,
        arriveSocPercent: 18,
        departSocPercent: 80,
        backups: const [],
      );
      final s = EvTripSelection.recommended(
          _plan([a, dup, _stop('c', 400)]), const [],
          maxWaypoints: 9);
      expect(_ids(s), ['a', 'c']);
    });
  });

  group('EvTripSelection - qo\'shish / olib tashlash / tartib', () {
    EvTripSelection make({int max = 9}) {
      final plan = _plan([
        _stop('p1', 200, [_b('b1', 200, -20), _b('b2', 200, 20)]),
        _stop('p2', 400),
      ]);
      return EvTripSelection.recommended(
        plan,
        [
          _c('x0', 50),
          _c('b1', 180),
          _c('p1', 200),
          _c('b2', 220),
          _c('x1', 300),
          _c('p2', 400),
          _c('x2', 600),
        ],
        maxWaypoints: max,
      );
    }

    test('har qanday stansiyani qo\'shish va olib tashlash mumkin', () {
      final s = make();
      var notified = 0;
      s.addListener(() => notified++);

      expect(s.toggle('x1'), isTrue); // boshqa
      expect(s.toggle('b2'), isTrue); // zaxira
      expect(s.toggle('p1'), isTrue); // tavsiya etilganni olib tashlash
      expect(s.isSelected('p1'), isFalse);
      expect(_ids(s), ['b2', 'x1', 'p2']);
      expect(notified, 3);

      expect(s.toggle('p1'), isTrue); // qaytarish
      expect(_ids(s), ['p1', 'b2', 'x1', 'p2']);
    });

    test('raqamlar tanlanganlar orasida yo\'l bo\'yicha 1,2,3...', () {
      final s = make();
      s.toggle('x0');
      s.toggle('b2');
      expect(s.numbers, {'x0': 1, 'p1': 2, 'b2': 3, 'p2': 4});
      s.toggle('p1');
      expect(s.numbers, {'x0': 1, 'b2': 2, 'p2': 3});
    });

    test('waypoints: yo\'l tartibida, qo\'shish tartibiga bog\'liq emas', () {
      final s = make();
      s.toggle('x2');
      s.toggle('x0');
      s.toggle('b1');
      expect(_lats(s.waypoints),
          [_lat(50), _lat(180), _lat(200), _lat(400), _lat(600)]);
    });

    test('bo\'sh tanlov = faqat manzilga (waypoints bo\'sh)', () {
      final s = make();
      s.toggle('p1');
      s.toggle('p2');
      expect(s.count, 0);
      expect(s.waypoints, isEmpty);
      expect(s.numbers, isEmpty);
    });

    test('noma\'lum stansiya: false, holat o\'zgarmaydi, xabar yo\'q', () {
      final s = make();
      var notified = 0;
      s.addListener(() => notified++);
      expect(s.toggle('nope'), isFalse);
      expect(s.count, 2);
      expect(notified, 0);
    });

    test('bir xil koordinatali ikki tanlov - bitta oraliq nuqta', () {
      final s = EvTripSelection(
        candidates: [_cand('a', 100), _cand('a-copy', 100)],
        initialIds: const ['a', 'a-copy'],
        maxWaypoints: 9,
      );
      expect(s.count, 2);
      expect(s.waypoints, hasLength(1));
      expect(s.navigable, hasLength(1));
      expect(s.navigable.single.id, 'a');
    });

    test('navigable: yo\'l tartibida, waypoints bilan bir xil koordinatalar',
        () {
      final s = make();
      s.toggle('x2');
      s.toggle('x0');
      expect([for (final c in s.navigable) c.id], ['x0', 'p1', 'p2', 'x2']);
      expect(_lats(s.waypoints), _lats(evWaypointsOf(s.navigable)));
    });
  });

  group('EvTripSelection - chegara (mobil veb 3 / native 9)', () {
    List<EvTripCandidate> many(int n) =>
        [for (var i = 0; i < n; i++) _cand('s$i', i * 10.0)];

    test('chegara platformadan: web+mobil 3, native 9, berilmasa default', () {
      final mobile =
          mapsMaxWaypoints(isWeb: true, platform: TargetPlatform.android);
      final native =
          mapsMaxWaypoints(isWeb: false, platform: TargetPlatform.android);
      expect(
          EvTripSelection(candidates: many(12), maxWaypoints: mobile)
              .maxWaypoints,
          3);
      expect(
          EvTripSelection(candidates: many(12), maxWaypoints: native)
              .maxWaypoints,
          9);
      expect(EvTripSelection(candidates: many(12)).maxWaypoints,
          mapsMaxWaypoints());
    });

    test('3 ga yetgach yangisini qo\'shib bo\'lmaydi; olib tashlash mumkin',
        () {
      final s = EvTripSelection(candidates: many(8), maxWaypoints: 3);
      expect(s.toggle('s0'), isTrue);
      expect(s.toggle('s1'), isTrue);
      expect(s.isFull, isFalse);
      expect(s.toggle('s2'), isTrue);
      expect(s.isFull, isTrue);
      expect(s.canAdd('s3'), isFalse);
      expect(s.canAdd('s2'), isTrue,
          reason: 'tanlangan - olib tashlash mumkin');

      var notified = 0;
      s.addListener(() => notified++);
      expect(s.toggle('s3'), isFalse, reason: 'rad etildi');
      expect(s.count, 3);
      expect(notified, 0);

      expect(s.toggle('s1'), isTrue);
      expect(s.isFull, isFalse);
      expect(s.toggle('s3'), isTrue);
      expect(_ids(s), ['s0', 's2', 's3']);
    });

    test('9 (native): to\'qqizinchi qo\'shiladi, o\'ninchi yo\'q', () {
      final s = EvTripSelection(candidates: many(12), maxWaypoints: 9);
      for (var i = 0; i < 9; i++) {
        expect(s.toggle('s$i'), isTrue, reason: 's$i');
      }
      expect(s.toggle('s9'), isFalse);
      expect(s.count, 9);
      expect(s.waypoints, hasLength(9));
    });

    test(
        'tavsiyalar chegaradan ko\'p (mobil veb 3, 4 asosiy): tanlov '
        'kesilmaydi - ular bo\'laklab yuboriladi', () {
      final plan = _plan([
        _stop('p1', 100),
        _stop('p2', 200),
        _stop('p3', 300),
        _stop('p4', 400),
      ]);
      final s = EvTripSelection.recommended(plan, const [], maxWaypoints: 3);
      expect(s.count, 4, reason: 'avtomatik kesilmaydi');
      expect(s.isFull, isTrue);
      expect(s.canAdd('p1'), isTrue); // olib tashlash mumkin
      // Navigatsiya bloklanmaydi: birinchi 3 ta yuboriladi, 1 ta qoladi.
      final chunk = evNavigationChunk(s.navigable, s.maxWaypoints);
      expect([for (final c in chunk.sent) c.id], ['p1', 'p2', 'p3']);
      expect([for (final c in chunk.remaining) c.id], ['p4']);

      expect(s.toggle('p2'), isTrue);
      expect(s.count, 3);
      expect(s.isFull, isTrue);
      expect(evNavigationChunk(s.navigable, s.maxWaypoints).remaining, isEmpty,
          reason: 'aniq chegarada - hammasi birdan');
      expect(_lats(s.waypoints), [_lat(100), _lat(300), _lat(400)]);
    });

    test('aniq chegarada (3/3): to\'ldi, lekin ortiqcha emas', () {
      final s = EvTripSelection(
          candidates: many(5),
          initialIds: const ['s0', 's1', 's2'],
          maxWaypoints: 3);
      expect(s.isFull, isTrue);
      expect(evNavigationChunk(s.navigable, s.maxWaypoints).remaining, isEmpty);
    });

    test('boshlang\'ich id lar orasida noma\'lumlari tashlab yuboriladi', () {
      final s = EvTripSelection(
          candidates: many(3),
          initialIds: const ['s1', 'ghost'],
          maxWaypoints: 3);
      expect(s.count, 1);
    });
  });
}

import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_controller.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_selection.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter_test/flutter_test.dart';

// Majburiy / rad etilgan to'xtashlar (planner), stansiyani almashtirish,
// "Qaytarish" (controller) va tanlovning yangi rejaga ergashishi. Toza mantiq,
// plaginsiz.
//
// Mashina: 60 kWh, 20 kWh/100 km, zaxira 10%, 80% gacha zaryad:
//   100% da yetadi 270 km, 80% da (zaxiradan keyin) 210 km.

const _car = EvCarSpec(
  usableBatteryKwh: 60,
  consumptionKwhPer100Km: 20,
  connectors: ['CCS2'],
);

EvChargingStation _st(
  String id, {
  String status = 'working',
  List<String> connectors = const ['CCS2'],
}) =>
    EvChargingStation(
      id: id,
      latitude: 41.0,
      // Har id uchun o'ziga xos koordinata (tanlovda koordinata bo'yicha
      // takrorlar birlashtiriladi).
      longitude: 60.0 + id.codeUnits.fold<int>(0, (a, b) => a + b) / 10000,
      geohash: '',
      chargingTypes: const ['DC'],
      connectors: connectors,
      powerKw: 120,
      status: status,
      verificationStatus: 'verified',
      confirmationCount: 2,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
      name: id,
    );

EvCorridorStation _cs(String id, double along,
        {String status = 'working', List<String> connectors = const ['CCS2']}) =>
    EvCorridorStation(
      station: _st(id, status: status, connectors: connectors),
      alongKm: along,
      offRouteKm: 0.5,
    );

EvTripPlan _plan(
  List<EvCorridorStation> corridor, {
  double totalKm = 600,
  int soc = 100,
  double from = 0,
  List<String> forced = const [],
  Set<String> excluded = const {},
}) =>
    EvTripPlanner.plan(
      corridorStations: corridor,
      totalKm: totalKm,
      car: _car,
      startSocPercent: soc,
      fromAlongKm: from,
      forcedStopIds: forced,
      excludedStationIds: excluded,
    );

List<String> _ids(EvTripPlan p) => [for (final s in p.stops) s.station.id];

/// Asosiy reja: 100% dan [b@265, c@430] (eng uzoq - bir xil sifatda kam to'xtash).
List<EvCorridorStation> _corridor() => [
      _cs('a', 100),
      _cs('a2', 230),
      _cs('d', 250),
      _cs('b', 265),
      _cs('e', 300),
      _cs('c', 430),
    ];

void main() {
  group('EvTripPlanner.plan - boshlang\'ich shartlar rejada saqlanadi', () {
    test('startSocPercent va fromAlongKm rejaga yoziladi (barcha holatlarda)',
        () {
      final ok = _plan(_corridor(), soc: 90, from: 10);
      expect(ok.startSocPercent, 90);
      expect(ok.fromAlongKm, 10);
      expect(ok.canReplan, isTrue);

      final gap = _plan([_cs('x', 500)], soc: 100);
      expect(gap.status, EvTripPlanStatus.gapTooLarge);
      expect(gap.startSocPercent, 100);

      // Qo'lda qurilgan reja - noma'lum.
      expect(EvTripPlan.empty.canReplan, isFalse);
    });
  });

  group('EvTripPlanner.plan - majburiy to\'xtashlar', () {
    test('asosiy reja (kutilgan baza): [b, c]', () {
      final p = _plan(_corridor());
      expect(p.status, EvTripPlanStatus.ok);
      expect(_ids(p), ['b', 'c']);
    });

    test('yetadigan majburiy stansiya shu yerda to\'xtash bo\'ladi', () {
      final p = _plan(_corridor(), forced: ['a']);
      expect(p.status, EvTripPlanStatus.ok);
      expect(p.stops.first.station.id, 'a');
      expect(p.stops.first.alongKm, 100);
    });

    test('majburiy stansiya manzilga yetadigan joyda ham to\'xtash bo\'ladi',
        () {
      // 150 km yo'l: 100% zaryad yetadi, lekin haydovchi 'a' da to'xtashni tanlagan.
      final p = _plan([_cs('a', 100)], totalKm: 150, forced: ['a']);
      expect(p.status, EvTripPlanStatus.ok);
      expect(_ids(p), ['a']);
      expect(_plan([_cs('a', 100)], totalKm: 150).status,
          EvTripPlanStatus.noChargingNeeded);
    });

    test('yetib bo\'lmaydigan majburiy stansiya - uzilish (boshqasi tanlanmaydi)',
        () {
      final p = _plan(_corridor(), forced: ['e']); // 300 > 270
      expect(p.status, EvTripPlanStatus.gapTooLarge);
      expect(p.stops, isEmpty, reason: 'jimgina boshqa stansiya qo\'yilmaydi');
      expect(p.gapFromKm, 0);
      expect(p.gapReachKm, closeTo(270, 0.01));
      expect(p.gapNextStationKm, 300);
    });

    test('majburiy stansiyalar yo\'l bo\'yicha tartibda ishlatiladi', () {
      final p = _plan(_corridor(), forced: ['b', 'a']);
      expect(_ids(p).take(2), ['a', 'b']);
      // 'c' (430) a dan keyin 310 km chegarasidan uzoq: uzilish.
      final far = _plan(_corridor(), forced: ['c', 'a']);
      expect(far.status, EvTripPlanStatus.gapTooLarge);
      expect(_ids(far), ['a']);
    });

    test('noma\'lum, o\'tib ketgan yoki yaroqsiz majburiy ID e\'tiborga olinmaydi',
        () {
      final base = _ids(_plan(_corridor()));
      expect(_ids(_plan(_corridor(), forced: ['yo\'q'])), base);
      // 'a' (100 km) allaqachon o'tib ketgan (from = 120).
      final fromPassed = _plan(_corridor(), from: 120, forced: ['a']);
      expect(_ids(fromPassed), isNot(contains('a')));
      // Ishlamaydigan stansiya majburiy bo'la olmaydi.
      final broken = [..._corridor(), _cs('z', 150, status: 'not_working')];
      expect(_ids(_plan(broken, forced: ['z'])), isNot(contains('z')));
    });
  });

  group('EvTripPlanner.plan - rad etilgan (excluded) stansiyalar', () {
    test('rad etilgan stansiya asosiy qilib tanlanmaydi', () {
      final p = _plan(_corridor(), excluded: {'b'});
      expect(_ids(p), isNot(contains('b')));
      expect(p.status, EvTripPlanStatus.ok);
    });

    test('rad etilgan stansiya zaxira sifatida qolishi mumkin', () {
      final p = _plan(_corridor(), excluded: {'b'});
      final backupIds = [
        for (final s in p.stops) for (final b in s.backups) b.station.id
      ];
      expect(backupIds, contains('b'));
    });

    test('faqat rad etilganlar qolsa - uzilish (jimgina qaytarilmaydi)', () {
      final only = [_cs('b', 265), _cs('c', 430)];
      final p = _plan(only, excluded: {'b'});
      expect(p.status, EvTripPlanStatus.gapTooLarge);
    });
  });

  group('EvTripPlanner.replaceStop', () {
    test('mumkin: eski stansiya yangisiga almashadi, keyingi qism qayta hisob',
        () {
      final base = _plan(_corridor());
      final next = EvTripPlanner.replaceStop(
        current: base,
        stopIndex: 0,
        replacementId: 'a2',
        corridorStations: _corridor(),
        car: _car,
      )!;
      expect(next.status, EvTripPlanStatus.ok);
      expect(_ids(next).first, 'a2');
      expect(_ids(next), isNot(contains('b')),
          reason: 'eski stansiya qolgan qismda tanlanmaydi');
      expect(next.startSocPercent, base.startSocPercent);
      expect(next.fromAlongKm, base.fromAlongKm);
      // 230 km: 100% - 76.7% = 23% ga kelamiz.
      expect(next.stops.first.arriveSocPercent, 23);
    });

    test('oldingi to\'xtashlar o\'zgarmaydi, faqat tanlangani almashadi', () {
      final corridor = [
        _cs('s1', 200),
        _cs('s2', 380),
        _cs('s2b', 360),
        _cs('x', 590),
      ];
      final base = _plan(corridor, totalKm: 700);
      expect(_ids(base).take(2), ['s1', 's2']);
      final next = EvTripPlanner.replaceStop(
        current: base,
        stopIndex: 1,
        replacementId: 's2b',
        corridorStations: corridor,
        car: _car,
      )!;
      expect(next.stops.first.station.id, 's1');
      expect(next.stops.first.arriveSocPercent,
          base.stops.first.arriveSocPercent);
      expect(next.stops[1].station.id, 's2b');
      expect(next.stops[1].alongKm, 360);
    });

    test('yetib bo\'lmaydi: uzilish holati, boshqa stansiya o\'ylab topilmaydi',
        () {
      final base = _plan(_corridor());
      final next = EvTripPlanner.replaceStop(
        current: base,
        stopIndex: 0,
        replacementId: 'e', // 300 km > 270 km
        corridorStations: _corridor(),
        car: _car,
      )!;
      expect(next.status, EvTripPlanStatus.gapTooLarge);
      expect(next.isOk, isFalse);
      expect(next.gapNextStationKm, 300);
      // Asl reja o'zgarmagan (o'zgarmas obyekt).
      expect(base.status, EvTripPlanStatus.ok);
      expect(_ids(base), ['b', 'c']);
    });

    test('noma\'lum holatlar: null (boshlang\'ich shart yo\'q, indeks, koridorda yo\'q, orqada)',
        () {
      final base = _plan(_corridor());
      EvTripPlan? call(EvTripPlan p, int i, String id) =>
          EvTripPlanner.replaceStop(
            current: p,
            stopIndex: i,
            replacementId: id,
            corridorStations: _corridor(),
            car: _car,
          );
      expect(call(base, 5, 'a2'), isNull);
      expect(call(base, -1, 'a2'), isNull);
      expect(call(base, 0, 'yo\'q'), isNull);
      const manual = EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [],
        totalKm: 100,
        arrivalSocPercent: 50,
      );
      expect(call(manual, 0, 'a2'), isNull);
      // 1-to'xtash (c@430) ni 'a'(100) bilan: oldingi to'xtash (b@265) dan orqada.
      expect(call(base, 1, 'a'), isNull);
    });

    test('bir xil stansiyaga almashtirish - reja o\'zgarmaydi', () {
      final base = _plan(_corridor());
      final same = EvTripPlanner.replaceStop(
        current: base,
        stopIndex: 0,
        replacementId: 'b',
        corridorStations: _corridor(),
        car: _car,
      );
      expect(identical(same, base), isTrue);
    });

    test('passedKm: o\'tilgan joydan qayta hisoblanganda faqat oldingi stansiyalar',
        () {
      final base = _plan(_corridor());
      // 240 km da, haqiqiy zaryad 25%: faqat 240 dan keyingi to'xtashlar.
      final live = _plan(_corridor(), soc: 25, from: 240);
      expect(live.fromAlongKm, 240);
      expect(live.stops.every((s) => s.alongKm > 240), isTrue);
      expect(live.stops, isNotEmpty);
      expect(base.stops.first.alongKm, 265);
    });
  });

  group('EvTripController - almashtirish va "Qaytarish"', () {
    EvTripController build({List<EvCorridorStation>? corridor, int soc = 100}) {
      final c = corridor ?? _corridor();
      return EvTripController.seeded(
        plan: _plan(c, soc: soc),
        route: const [],
        corridor: c,
      );
    }

    test('seeded: reja bor, tarmoq so\'rovi yo\'q, qaytarish yo\'q', () {
      final c = build();
      expect(c.hasPlan, isTrue);
      expect(c.canUndo, isFalse);
      expect(c.corridorStations, hasLength(6));
    });

    test('replaceStop: reja yangilanadi, kuzatuvchilarga xabar beriladi', () {
      final c = build();
      var notified = 0;
      c.addListener(() => notified++);
      final r = c.replaceStop(stopIndex: 0, newStationId: 'a2', car: _car);
      expect(r, EvReplaceResult.replaced);
      expect(_ids(c.plan!).first, 'a2');
      expect(notified, 1);
      expect(c.canUndo, isTrue);
    });

    test('undo: aynan oldingi reja qaytadi (bir bosqich)', () {
      final c = build();
      final before = c.plan!;
      c.replaceStop(stopIndex: 0, newStationId: 'a2', car: _car);
      expect(c.undo(), isTrue);
      expect(identical(c.plan, before), isTrue);
      expect(c.canUndo, isFalse);
      expect(c.undo(), isFalse);
      // Qaytarilgach tanlovlar ham tozalanadi: 'b' yana tanlanadi.
      c.replan(car: _car, socPercent: 100, passedKm: 0);
      expect(_ids(c.plan!), ['b', 'c']);
    });

    test('yetib bo\'lmaydigan almashtirish: uzilish ko\'rsatiladi va qaytariladi',
        () {
      final c = build();
      final before = c.plan!;
      final r = c.replaceStop(stopIndex: 0, newStationId: 'e', car: _car);
      expect(r, EvReplaceResult.infeasible);
      expect(c.plan!.status, EvTripPlanStatus.gapTooLarge);
      expect(c.plan!.gapNextStationKm, 300);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(identical(c.plan, before), isTrue);
      expect(c.plan!.status, EvTripPlanStatus.ok);
    });

    test('unavailable: noto\'g\'ri indeks/stansiya hech narsani o\'zgartirmaydi',
        () {
      final c = build();
      final before = c.plan!;
      var notified = 0;
      c.addListener(() => notified++);
      expect(c.replaceStop(stopIndex: 9, newStationId: 'a2', car: _car),
          EvReplaceResult.unavailable);
      expect(c.replaceStop(stopIndex: 0, newStationId: 'yo\'q', car: _car),
          EvReplaceResult.unavailable);
      expect(identical(c.plan, before), isTrue);
      expect(c.canUndo, isFalse);
      expect(notified, 0);
    });

    test('haydovchi tanlovi keyingi qayta hisobda ham saqlanadi (zaryad yangilansa)',
        () {
      final c = build();
      c.replaceStop(stopIndex: 0, newStationId: 'a2', car: _car);
      // Haydovchi 0 km da zaryadni yangiladi - tanlagan 'a2' qoladi.
      c.replan(car: _car, socPercent: 100, passedKm: 0);
      expect(_ids(c.plan!).first, 'a2');
      expect(_ids(c.plan!), isNot(contains('b')));
    });

    test('replan(passedKm): qolgan to\'xtashlar mashina o\'rnidan, undo qaytaradi',
        () {
      final c = build();
      final before = c.plan!;
      c.replan(car: _car, socPercent: 30, passedKm: 240);
      expect(c.plan!.fromAlongKm, 240);
      expect(c.plan!.startSocPercent, 30);
      expect(c.plan!.stops.every((s) => s.alongKm > 240), isTrue);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(identical(c.plan, before), isTrue);
    });

    test('rejectStation: bitta undo bilan to\'liq qaytadi (koridor ham)', () {
      final c = build();
      final before = c.plan!;
      c.rejectStation(stationId: 'b', car: _car, socPercent: 100);
      expect(c.corridorStations.map((s) => s.station.id), isNot(contains('b')));
      c.undo();
      expect(identical(c.plan, before), isTrue);
      expect(c.corridorStations.map((s) => s.station.id), contains('b'));
    });

    test('clear() almashtirish tarixini ham tozalaydi', () {
      final c = build();
      c.replaceStop(stopIndex: 0, newStationId: 'a2', car: _car);
      c.clear();
      expect(c.canUndo, isFalse);
      expect(c.hasPlan, isFalse);
    });
  });

  group('EvTripSelection.followPlan', () {
    test('almashtirilgan to\'xtash tanlovda almashadi, qo\'lda qo\'shilgani qoladi',
        () {
      final corridor = _corridor();
      final base = _plan(corridor);
      final prev = EvTripSelection.recommended(base, corridor, maxWaypoints: 9)
        ..toggle('d'); // haydovchi qo'lda qo'shgan
      expect({for (final c in prev.selected) c.id}, {'b', 'c', 'd'});

      final next = EvTripPlanner.replaceStop(
        current: base,
        stopIndex: 0,
        replacementId: 'a2',
        corridorStations: corridor,
        car: _car,
      )!;
      final sel = EvTripSelection.followPlan(
        previous: prev,
        previousPlan: base,
        nextPlan: next,
        corridor: corridor,
        replacedOldId: 'b',
        replacedNewId: 'a2',
      );
      final ids = {for (final c in sel.selected) c.id};
      expect(ids, contains('a2'));
      expect(ids, isNot(contains('b')));
      expect(ids, contains('d'), reason: 'qo\'lda qo\'shilgan qoladi');
      expect(ids, contains('c'));
      expect(sel.maxWaypoints, 9);
    });

    test('haydovchi olib tashlagan tavsiya yangi rejada ham tanlanmagan qoladi',
        () {
      final corridor = _corridor();
      final base = _plan(corridor);
      final prev = EvTripSelection.recommended(base, corridor, maxWaypoints: 9)
        ..toggle('c'); // 'c' ni olib tashladi
      final next = EvTripPlanner.replaceStop(
        current: base,
        stopIndex: 0,
        replacementId: 'a2',
        corridorStations: corridor,
        car: _car,
      )!;
      expect(_ids(next), contains('c'));
      final sel = EvTripSelection.followPlan(
        previous: prev,
        previousPlan: base,
        nextPlan: next,
        corridor: corridor,
        replacedOldId: 'b',
        replacedNewId: 'a2',
      );
      expect({for (final c in sel.selected) c.id}, {'a2'});
    });

    test('yangi reja tayyor emas (uzilish): faqat almashtirilgan yangilanadi',
        () {
      final corridor = _corridor();
      final base = _plan(corridor);
      final prev = EvTripSelection.recommended(base, corridor, maxWaypoints: 9);
      final gap = EvTripPlanner.replaceStop(
        current: base,
        stopIndex: 0,
        replacementId: 'e',
        corridorStations: corridor,
        car: _car,
      )!;
      final sel = EvTripSelection.followPlan(
        previous: prev,
        previousPlan: base,
        nextPlan: gap,
        corridor: corridor,
        replacedOldId: 'b',
        replacedNewId: 'e',
      );
      expect({for (final c in sel.selected) c.id}, {'c', 'e'});
    });

    test('zaryad yangilandi (almashtirishsiz): o\'tib ketgan to\'xtash o\'z holicha',
        () {
      final corridor = _corridor();
      final base = _plan(corridor);
      final prev = EvTripSelection.recommended(base, corridor, maxWaypoints: 9);
      final live = _plan(corridor, soc: 30, from: 266);
      final sel = EvTripSelection.followPlan(
        previous: prev,
        previousPlan: base,
        nextPlan: live,
        corridor: corridor,
      );
      final ids = {for (final c in sel.selected) c.id};
      expect(ids, contains('b'), reason: '265 km - o\'tib ketgan, raqami saqlanadi');
      for (final s in live.stops) {
        expect(ids, contains(s.station.id));
      }
    });
  });
}

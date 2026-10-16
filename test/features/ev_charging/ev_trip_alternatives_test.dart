import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_alternatives.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_summary.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter_test/flutter_test.dart';

// "Almashtirish" ro'yxatini tuzish (sof mantiq): oyna, istisnolar, tartib,
// soni, ta'sir hisobi va "Tavsiya" belgisi.
//
// Mashina: 60 kWh, 20 kWh/100 km, zaxira 10%, 80% gacha zaryad (100% da
// 270 km, 80% da 210 km). Asosiy reja (100%, 600 km): [b@265, c@430].

const _car = EvCarSpec(
  usableBatteryKwh: 60,
  consumptionKwhPer100Km: 20,
  connectors: ['CCS2'],
);

EvCorridorStation _cs(
  String id,
  double along, {
  double off = 0.5,
  num? power = 120,
  String status = 'working',
  List<String> connectors = const ['CCS2'],
  String? occupancy,
}) =>
    EvCorridorStation(
      station: EvChargingStation(
        id: id,
        latitude: 41.0,
        longitude: 60.0 + id.codeUnits.fold<int>(0, (a, b) => a + b) / 10000,
        geohash: '',
        chargingTypes: const ['DC'],
        connectors: connectors,
        powerKw: power,
        status: status,
        verificationStatus: 'verified',
        confirmationCount: 2,
        reportCount: 0,
        createdBy: 'u1',
        isActive: true,
        name: id,
        occupancy: occupancy,
        occupancyAt: occupancy == null ? null : DateTime.now(),
      ),
      alongKm: along,
      offRouteKm: off,
    );

List<EvCorridorStation> _corridor() => [
      _cs('a', 100),
      _cs('a2', 230),
      _cs('d', 250),
      _cs('b', 265),
      _cs('e', 300),
      _cs('c', 430),
    ];

EvTripPlan _plan(List<EvCorridorStation> corridor,
        {double from = 0, int soc = 100}) =>
    EvTripPlanner.plan(
      corridorStations: corridor,
      totalKm: 600,
      car: _car,
      startSocPercent: soc,
      fromAlongKm: from,
    );

List<EvTripAlternative> _build(
  EvTripPlan plan,
  List<EvCorridorStation> corridor, {
  int index = 0,
  double? carAlongKm,
}) =>
    EvTripAlternatives.build(
      plan: plan,
      stopIndex: index,
      corridor: corridor,
      car: _car,
      carAlongKm: carAlongKm,
    );

List<String> _ids(List<EvTripAlternative> l) => [for (final a in l) a.station.id];

void main() {
  group('sozlamalar', () {
    test('nomlangan doimiylar: oyna 40 km, 5 ta alternativa', () {
      expect(EvTripAlternatives.windowKm, 40);
      expect(EvTripAlternatives.maxAlternatives, 5);
    });
  });

  group('build - umumiy', () {
    test('boshlang\'ich shart noma\'lum yoki indeks noto\'g\'ri - bo\'sh', () {
      final c = _corridor();
      const manual = EvTripPlan(
          status: EvTripPlanStatus.ok,
          stops: [],
          totalKm: 600,
          arrivalSocPercent: 20);
      expect(_build(manual, c), isEmpty);
      final plan = _plan(c);
      expect(_build(plan, c, index: 7), isEmpty);
      expect(_build(plan, c, index: -1), isEmpty);
    });

    test('birinchi qator - hozirgi to\'xtash (planerning o\'z tanlovi)', () {
      final c = _corridor();
      final plan = _plan(c);
      final rows = _build(plan, c);
      expect(rows.first.isCurrent, isTrue);
      expect(rows.first.station.id, 'b');
      expect(rows.first.deltaKm, 0);
      expect(rows.skip(1).every((r) => !r.isCurrent), isTrue);
      // Hozirgi qatorda "farq" yo'q, lekin absolyut qiymat bor.
      expect(rows.first.arrivalDeltaPercent, isNull);
      expect(rows.first.arrivalSocPercent, plan.arrivalSocPercent);
    });
  });

  group('build - tanlash qoidalari', () {
    test('zaxiralar oynadan tashqarida bo\'lsa ham qo\'shiladi; oddiylari faqat ±40 km',
        () {
      // Hozirgi b@265: zaxiralar d@250, a2@230, a@100 (a: -165 km, oynadan tashqari).
      final extra = [..._corridor(), _cs('far', 320), _cs('near', 300.5)];
      final plan = _plan(extra);
      expect(plan.stops.first.station.id, isNot('far'));
      final rows = _build(plan, extra);
      final ids = _ids(rows);
      expect(ids, contains('a'), reason: 'zaxira - oynadan tashqarida ham bor');
      expect(ids, isNot(contains('far')),
          reason: '320-265=55 > 40 va zaxira emas');
    });

    test('oyna chegarasi: +39 km kiradi, +41 km kirmaydi (zaxira bo\'lmaganlar)',
        () {
      // Hozirgi to'xtash x@200; zaxiralar 3 ta (p1..p3), boshqalar zaxira emas.
      final corridor = [
        _cs('p1', 190),
        _cs('p2', 185),
        _cs('p3', 180),
        _cs('x', 200),
        _cs('in', 239), // +39
        _cs('out', 241), // +41
        _cs('back', 160), // -40 -> chegarada: kiradi (<= 40)
      ];
      // x ni majburan tanlaymiz: shu to'xtashni 0-indeks qilish uchun
      // 200 km dan oldin boshqa stansiya yo'q deb olamiz.
      final plan = EvTripPlanner.plan(
        corridorStations: corridor,
        totalKm: 400,
        car: _car,
        startSocPercent: 100,
        forcedStopIds: const ['x'],
      );
      expect(plan.stops.first.station.id, 'x');
      final rows = _build(plan, corridor);
      final ids = _ids(rows);
      expect(ids, contains('in'));
      expect(ids, isNot(contains('out')));
      expect(ids, contains('back'));
    });

    test('rejadagi boshqa to\'xtash, ishlamaydigan va razyomi mos kelmaydigan chiqarib tashlanadi',
        () {
      final corridor = [
        ..._corridor(),
        _cs('broken', 262, status: 'not_working'),
        _cs('chademo', 263, connectors: const ['CHAdeMO']),
      ];
      final plan = _plan(corridor);
      final ids = _ids(_build(plan, corridor));
      expect(ids, isNot(contains('broken')));
      expect(ids, isNot(contains('chademo')));
      expect(ids, isNot(contains('c')), reason: 'c - rejadagi 2-to\'xtash');
    });

    test('mashina ortida qolgan stansiyalar chiqarib tashlanadi', () {
      final c = _corridor();
      final plan = _plan(c);
      final all = _ids(_build(plan, c));
      expect(all, containsAll(['a', 'a2', 'd']));
      final ahead = _ids(_build(plan, c, carAlongKm: 240));
      expect(ahead, isNot(contains('a')));
      expect(ahead, isNot(contains('a2')));
      expect(ahead, contains('d'));
    });

    test('ko\'pi bilan 5 ta alternativa (+ hozirgi)', () {
      final corridor = [
        for (var i = 0; i < 9; i++) _cs('n$i', 240 + i * 3.0),
        _cs('c', 430),
      ];
      final plan = _plan(corridor);
      final rows = _build(plan, corridor);
      expect(rows.where((r) => !r.isCurrent), hasLength(5));
      expect(rows, hasLength(6));
    });

    test('tartib: hozirgi birinchi, keyin hozirgidan masofa, keyin yo\'ldan chetlik',
        () {
      final corridor = [
        _cs('cur', 250),
        _cs('r', 270, off: 3),
        _cs('s', 270, off: 1), // r bilan bir xil masofa, chetligi kam
        _cs('t', 255),
        _cs('u', 220),
      ];
      final plan = EvTripPlanner.plan(
        corridorStations: corridor,
        totalKm: 400,
        car: _car,
        startSocPercent: 100,
        forcedStopIds: const ['cur'],
      );
      final rows = _build(plan, corridor);
      expect(_ids(rows).first, 'cur');
      // Zaxiralar (planner tanlovi, max 3) + qolganlar -> tartib baribir
      // |delta| bo'yicha: t(5), u(30), s(20) va r(20): t, s, r, u.
      expect(_ids(rows).skip(1), ['t', 's', 'r', 'u']);
    });
  });

  group('build - ta\'sir hisobi (haqiqiy qayta hisob)', () {
    test('har bir qatorning rejasi replaceStop natijasi bilan bir xil', () {
      final c = _corridor();
      final plan = _plan(c);
      for (final r in _build(plan, c).skip(1)) {
        final direct = EvTripPlanner.replaceStop(
          current: plan,
          stopIndex: 0,
          replacementId: r.station.id,
          corridorStations: c,
          car: _car,
        )!;
        expect(r.plan.status, direct.status, reason: r.station.id);
        expect(r.feasible, direct.isOk, reason: r.station.id);
        if (direct.isOk) {
          expect(r.arrivalSocPercent, direct.arrivalSocPercent);
          expect(r.arrivalDeltaPercent,
              direct.arrivalSocPercent - plan.arrivalSocPercent);
          expect(r.stopCount, direct.stops.length);
          expect(r.stopCountDelta, direct.stops.length - plan.stops.length);
        }
      }
    });

    test('tayyor bo\'lmagan variant: uzilish, ta\'sir qiymatlari yo\'q, tavsiya emas',
        () {
      final c = _corridor();
      final plan = _plan(c);
      final e = _build(plan, c).firstWhere((r) => r.station.id == 'e');
      expect(e.feasible, isFalse);
      expect(e.plan.status, EvTripPlanStatus.gapTooLarge);
      expect(e.arrivalSocPercent, isNull);
      expect(e.arrivalDeltaPercent, isNull);
      expect(e.stopCount, isNull);
      expect(e.chargeMinutesDelta, isNull);
      expect(e.isBest, isFalse);
    });

    test('zaryad vaqti farqi: barcha to\'xtashda quvvat ma\'lum bo\'lsagina', () {
      final c = _corridor();
      final plan = _plan(c);
      final rows = _build(plan, c);
      final a2 = rows.firstWhere((r) => r.station.id == 'a2');
      final direct = EvTripPlanner.replaceStop(
        current: plan,
        stopIndex: 0,
        replacementId: 'a2',
        corridorStations: c,
        car: _car,
      )!;
      final expected = evPlanMinChargeMinutes(direct, _car).minutes -
          evPlanMinChargeMinutes(plan, _car).minutes;
      expect(a2.chargeMinutesDelta, expected);
      expect(a2.powerKnown, isTrue);

      // Biror to'xtashda quvvat noma'lum - hisoblab bo'lmaydi, qator yo'q.
      final unknown = [
        for (final e in c)
          e.station.id == 'a2' ? _cs('a2', 230, power: null) : e,
      ];
      final plan2 = _plan(unknown);
      final rows2 = _build(plan2, unknown);
      final a2u = rows2.firstWhere((r) => r.station.id == 'a2');
      expect(a2u.powerKnown, isFalse);
      expect(a2u.chargeMinutesDelta, isNull);
    });
  });

  group('build - "Tavsiya" (isBest)', () {
    test('teng bo\'lsa planerning o\'z tanlovi (hozirgi) tavsiya', () {
      final c = _corridor();
      final plan = _plan(c);
      final rows = _build(plan, c);
      expect(rows.where((r) => r.isBest), hasLength(1));
      expect(rows.first.isBest, isTrue);
    });

    test('alternativa kamroq to\'xtash bilan yetsa - tavsiya unga o\'tadi', () {
      final c = _corridor();
      final base = _plan(c);
      // Haydovchi oldin 'a' ni tanlagan: [a, e, c] - 3 to'xtash.
      final worse = EvTripPlanner.replaceStop(
        current: base,
        stopIndex: 0,
        replacementId: 'a',
        corridorStations: c,
        car: _car,
      )!;
      expect(worse.stops.length, 3);
      final rows = _build(worse, c);
      final best = rows.singleWhere((r) => r.isBest);
      expect(best.isCurrent, isFalse);
      expect(best.stopCount, lessThan(worse.stops.length));
      expect(best.stopCountDelta, isNegative);
      expect(rows.first.isBest, isFalse);
      expect(rows.first.isCurrent, isTrue,
          reason: 'hozirgi baribir birinchi qatorda');
    });

    test('hech biri tayyor emas - tavsiya belgisi yo\'q', () {
      // Hozirgi rejaning o'zi uzilish: faqat bitta stansiya 300 km da.
      final c = [_cs('only', 300)];
      final gap = EvTripPlanner.plan(
        corridorStations: c,
        totalKm: 600,
        car: _car,
        startSocPercent: 100,
      );
      expect(gap.status, EvTripPlanStatus.gapTooLarge);
      expect(_build(gap, c), isEmpty, reason: 'to\'xtash yo\'q - indeks bo\'sh');
    });

    test('band belgisi stansiyada saqlanadi (ro\'yxat UI ishlatadi)', () {
      final c = [
        for (final e in _corridor())
          e.station.id == 'a2' ? _cs('a2', 230, occupancy: 'free') : e,
      ];
      final plan = _plan(c);
      final a2 = _build(plan, c).firstWhere((r) => r.station.id == 'a2');
      expect(a2.station.occupancyState, 'free');
    });
  });
}

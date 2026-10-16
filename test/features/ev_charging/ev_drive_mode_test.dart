import 'package:ava_gurlan/features/ev_charging/controllers/ev_drive_mode.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter_test/flutter_test.dart';

// "Yo'l rejimi" mantig'i (sof): tezlik gisterezisi (soxta soat bilan), qo'lda
// yoqish, navbatdagi to'xtash va masofa, "Yetib keldingiz", o'tib ketganlar,
// tasdiqlanganlar va rejadagi kutilgan zaryad.

const double _kmPerDegLat = 111.1949;
double _lat(double km) => 41.0 + km / _kmPerDegLat;

/// Km/soat -> m/s.
double _v(double kmh) => kmh / 3.6;

EvChargingStation _st(String id, double along) => EvChargingStation(
      id: id,
      latitude: _lat(along),
      longitude: 60.0,
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

EvTripStop _stop(String id, double along,
        {int arrive = 18, int depart = 80}) =>
    EvTripStop(
      station: _st(id, along),
      alongKm: along,
      offRouteKm: 0,
      legKm: along,
      arriveSocPercent: arrive,
      departSocPercent: depart,
      backups: const [],
    );

EvTripPlan _plan({int? startSoc = 100, double from = 0}) => EvTripPlan(
      status: EvTripPlanStatus.ok,
      stops: [_stop('s1', 100, arrive: 33), _stop('s2', 300, arrive: 20)],
      totalKm: 600,
      arrivalSocPercent: 25,
      startSocPercent: startSoc,
      fromAlongKm: from,
    );

const _car = EvCarSpec(usableBatteryKwh: 60, consumptionKwhPer100Km: 20);

void main() {
  group('EvDriveModeMachine - tezlik gisterezisi', () {
    late DateTime now;
    late EvDriveModeMachine m;
    setUp(() {
      now = DateTime(2026, 10, 16, 12);
      m = EvDriveModeMachine(clock: () => now);
    });

    test('doimiylar nomlangan: 8 / 4 km/soat, 3 / 3 nuqta, 20 soniya', () {
      expect(EvDriveModeMachine.enterKmh, 8);
      expect(EvDriveModeMachine.exitKmh, 4);
      expect(EvDriveModeMachine.enterFixes, 3);
      expect(EvDriveModeMachine.exitFixes, 3);
      expect(EvDriveModeMachine.staleAfter, const Duration(seconds: 20));
    });

    test('boshida yo\'l rejimi yoqilmagan', () {
      expect(m.driving, isFalse);
      expect(m.autoDriving, isFalse);
      expect(m.manual, isNull);
    });

    test('8 km/soatdan yuqori 3 ta KETMA-KET nuqta - yoqiladi (2 ta yetmaydi)',
        () {
      expect(m.onFix(_v(30)), isFalse);
      expect(m.onFix(_v(30)), isFalse);
      expect(m.driving, isFalse, reason: '2 ta nuqta - hali yo\'q');
      expect(m.onFix(_v(30)), isTrue, reason: 'holat o\'zgardi');
      expect(m.driving, isTrue);
    });

    test('chegara: 8.0 km/soat hisoblanadi, 7.9 hisoblanmaydi', () {
      for (var i = 0; i < 5; i++) {
        m.onFix(_v(7.9));
      }
      expect(m.driving, isFalse);
      for (var i = 0; i < 3; i++) {
        m.onFix(_v(8.0));
      }
      expect(m.driving, isTrue);
    });

    test('ketma-ketlik uzilsa hisob qaytadan boshlanadi', () {
      m.onFix(_v(30));
      m.onFix(_v(30));
      m.onFix(_v(2)); // sekin nuqta - hisob nolga tushdi
      m.onFix(_v(30));
      m.onFix(_v(30));
      expect(m.driving, isFalse);
      m.onFix(_v(30));
      expect(m.driving, isTrue);
    });

    test('gisterezis: 4..8 km/soat orasida holat o\'zgarmaydi (yonib-o\'chmaydi)',
        () {
      for (var i = 0; i < 3; i++) {
        m.onFix(_v(30));
      }
      expect(m.driving, isTrue);
      for (var i = 0; i < 20; i++) {
        m.onFix(_v(6)); // 4 dan yuqori, 8 dan past
      }
      expect(m.driving, isTrue, reason: 'o\'chmaydi');

      // To'xtab turgan holat ham 6 km/soat bilan yonmaydi.
      final fresh = EvDriveModeMachine(clock: () => now);
      for (var i = 0; i < 20; i++) {
        fresh.onFix(_v(6));
      }
      expect(fresh.driving, isFalse, reason: 'yonmaydi');
    });

    test('4 km/soatdan past 3 ta ketma-ket nuqta - o\'chadi; oradagi tez nuqta '
        'hisobni nolga tushiradi', () {
      for (var i = 0; i < 3; i++) {
        m.onFix(_v(30));
      }
      m.onFix(_v(1));
      m.onFix(_v(1));
      m.onFix(_v(30)); // hisob uzildi
      m.onFix(_v(1));
      m.onFix(_v(1));
      expect(m.driving, isTrue);
      expect(m.onFix(_v(1)), isTrue);
      expect(m.driving, isFalse);
    });

    test('noma\'lum tezlik (null / manfiy / NaN) hisobga olinmaydi', () {
      m.onFix(_v(30));
      m.onFix(null);
      m.onFix(-1);
      m.onFix(double.nan);
      m.onFix(_v(30));
      expect(m.driving, isFalse, reason: '2 ta haqiqiy nuqta');
      m.onFix(_v(30));
      expect(m.driving, isTrue);
    });

    test('yangi nuqta kelmasa 20 soniyadan keyin to\'xtadi (10 m filtr)', () {
      for (var i = 0; i < 3; i++) {
        m.onFix(_v(30));
      }
      expect(m.driving, isTrue);
      now = now.add(const Duration(seconds: 20));
      expect(m.tick(), isFalse, reason: 'aynan 20 soniya - hali yo\'q');
      expect(m.driving, isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(m.tick(), isTrue);
      expect(m.driving, isFalse);
      expect(m.tick(), isFalse, reason: 'qayta o\'zgarish yo\'q');
    });

    test('yangi nuqta kelib tursa vaqt tekshiruvi o\'chirmaydi', () {
      for (var i = 0; i < 3; i++) {
        m.onFix(_v(30));
      }
      for (var i = 0; i < 6; i++) {
        now = now.add(const Duration(seconds: 15));
        m.onFix(_v(30));
        expect(m.tick(), isFalse);
      }
      expect(m.driving, isTrue);
    });

    test('qo\'lda yoqish/o\'chirish, keyingi avtomatik o\'zgarish uni bekor qiladi',
        () {
      m.toggleManual();
      expect(m.driving, isTrue);
      expect(m.autoDriving, isFalse);
      m.toggleManual();
      expect(m.driving, isFalse);

      // Avtomatik yoqilgach qo'lda o'chiriladi.
      for (var i = 0; i < 3; i++) {
        m.onFix(_v(30));
      }
      m.toggleManual();
      expect(m.driving, isFalse);
      expect(m.autoDriving, isTrue);

      // Mashina to'xtadi (avto) - qo'lda tanlov bekor.
      for (var i = 0; i < 3; i++) {
        m.onFix(_v(0));
      }
      expect(m.manual, isNull);
      expect(m.driving, isFalse);
    });

    test('qo\'lda yoqilgan holat vaqt tekshiruvidan o\'chmaydi (GPS bor, '
        'avtomatik emas)', () {
      m.toggleManual();
      now = now.add(const Duration(minutes: 5));
      expect(m.tick(), isFalse);
      expect(m.driving, isTrue);
    });

    test('reset: hamma narsa o\'chadi', () {
      for (var i = 0; i < 3; i++) {
        m.onFix(_v(30));
      }
      m.toggleManual();
      m.reset();
      expect(m.driving, isFalse);
      expect(m.manual, isNull);
    });
  });

  group('EvDriveNext.next - navbatdagi to\'xtash', () {
    EvDriveTarget? next(double along,
            {double? lat, Set<String> acked = const {}, EvTripPlan? plan}) =>
        EvDriveNext.next(
          plan: plan ?? _plan(),
          carAlongKm: along,
          carLat: lat ?? _lat(along),
          carLng: 60.0,
          acknowledgedIds: acked,
        );

    test('yo\'l bo\'yicha masofa va rejadagi zaryad (reja qiymati)', () {
      final t = next(50)!;
      expect(t.stop.station.id, 's1');
      expect(t.stopIndex, 0);
      expect(t.distanceKm, closeTo(50, 1e-9));
      expect(t.arrived, isFalse);
      expect(t.arriveSocPercent, 33);
    });

    test('o\'tib ketgan to\'xtash yashiriladi - keyingisi ko\'rinadi', () {
      final t = next(140)!; // s1 (100) dan 40 km o'tdi
      expect(t.stop.station.id, 's2');
      expect(t.stopIndex, 1);
      expect(t.distanceKm, closeTo(160, 1e-9));
    });

    test('hammasi o\'tib ketgan bo\'lsa - null', () {
      expect(next(450), isNull);
    });

    test('150 m ichida - "Yetib keldingiz" (mavjud hasArrived asosida)', () {
      final near = next(99.9)!; // ~100 m
      expect(near.stop.station.id, 's1');
      expect(near.arrived, isTrue);
      final far = next(99.7)!; // ~300 m
      expect(far.arrived, isFalse);
      expect(EvDriveNext.arrivalRadiusM, 150);
    });

    test('stansiyadan 300 m o\'tib ketgan (0.5 km ichida): hali navbatdagi, '
        'masofa manfiy emas', () {
      final t = next(100.3)!;
      expect(t.stop.station.id, 's1');
      expect(t.distanceKm, 0);
      expect(t.arrived, isFalse);
    });

    test('0.5 km dan ko\'p o\'tib ketsa - keyingisiga o\'tadi', () {
      expect(next(100.6)!.stop.station.id, 's2');
    });

    test('"Zaryadlash boshlandi" bosilgan to\'xtash qayta chiqmaydi', () {
      final t = next(99.9, acked: {'s1'})!;
      expect(t.stop.station.id, 's2');
      expect(t.arrived, isFalse);
    });

    test('yetib kelgan paytda mashina marshrutdan sal yonda (lat farqi) ham '
        'hisoblanadi', () {
      final t = next(99.0, lat: _lat(100) + 0.0005)!; // ~55 m shimol
      expect(t.arrived, isTrue);
    });

    test('hammasi tasdiqlangan - null', () {
      expect(next(50, acked: {'s1', 's2'}), isNull);
    });
  });

  group('evPredictedSocAt - "Zaryadni yangilash" boshlang\'ich qiymati', () {
    test('birinchi to\'xtashgacha: boshlang\'ich zaryaddan sarf ayriladi', () {
      // 60 kWh, 20 kWh/100km: 50 km = 10 kWh = 16.7% -> 100 - 16.7 = 83
      expect(evPredictedSocAt(_plan(), _car, 50), 83);
    });

    test('to\'xtashdan keyin: chiqish zaryadidan', () {
      // s1 da 80% ga zaryadlandi; 100 -> 150 km: 50 km = 16.7% -> 63
      expect(evPredictedSocAt(_plan(), _car, 150), 63);
    });

    test('qayta hisoblangan reja (fromAlongKm): shu joydan boshlanadi', () {
      final p = EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [_stop('s2', 300)],
        totalKm: 600,
        arrivalSocPercent: 25,
        startSocPercent: 40,
        fromAlongKm: 200,
      );
      // 200 -> 230: 30 km = 10% -> 30
      expect(evPredictedSocAt(p, _car, 230), 30);
    });

    test('5..100 ga qisqartiriladi; boshlang\'ich shart noma\'lum - null', () {
      expect(evPredictedSocAt(_plan(startSoc: 12), _car, 90), 5);
      expect(evPredictedSocAt(_plan(startSoc: null), _car, 10), isNull);
    });
  });
}

import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_summary.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter_test/flutter_test.dart';

// Toza hisob: yo'l vaqti formati, tanlangan to'xtashda qo'shiladigan energiya
// va HALOL "kamida" zaryadlash vaqti (energiya / stansiya quvvati).

EvChargingStation _station({num? powerKw, num? sitePowerKw}) =>
    EvChargingStation(
      id: 's',
      latitude: 41,
      longitude: 60,
      geohash: '',
      chargingTypes: const ['DC'],
      connectors: const ['CCS2'],
      powerKw: powerKw,
      sitePowerKw: sitePowerKw,
      status: 'working',
      verificationStatus: 'verified',
      confirmationCount: 1,
      reportCount: 0,
      createdBy: 'u',
      isActive: true,
    );

EvTripStop _stop({
  num? powerKw,
  num? sitePowerKw,
  int arrive = 18,
  int depart = 80,
}) =>
    EvTripStop(
      station: _station(powerKw: powerKw, sitePowerKw: sitePowerKw),
      alongKm: 300,
      offRouteKm: 0,
      legKm: 300,
      arriveSocPercent: arrive,
      departSocPercent: depart,
      backups: const [],
    );

const _car = EvCarSpec(usableBatteryKwh: 60, consumptionKwhPer100Km: 17);

String _dur(int m) => evFormatDuration(m, hourUnit: 'с', minuteUnit: 'дақ');

void main() {
  group('evFormatDuration', () {
    test('nol / manfiy / noma\'lum - bo\'sh matn', () {
      expect(_dur(0), '');
      expect(_dur(-5), '');
    });

    test('1 soatdan kam - faqat daqiqa', () {
      expect(_dur(1), '1 дақ');
      expect(_dur(45), '45 дақ');
      expect(_dur(59), '59 дақ');
    });

    test('to\'la soat - faqat soat; aks holda soat va daqiqa', () {
      expect(_dur(60), '1 с');
      expect(_dur(61), '1 с 1 дақ');
      expect(_dur(790), '13 с 10 дақ', reason: 'owner namunasi');
      expect(_dur(1440), '24 с');
    });

    test('birliklar tashqaridan: har tilda o\'zi (qattiq h/min yo\'q)', () {
      expect(
          evFormatDuration(790, hourUnit: 'ч', minuteUnit: 'мин'), '13 ч 10 мин');
      expect(
          evFormatDuration(790, hourUnit: 's', minuteUnit: 'daq'), '13 s 10 daq');
      expect(_dur(790), isNot(contains('h')));
      expect(_dur(790), isNot(contains('min')));
    });
  });

  group('evStopEnergyKwh', () {
    test('(chiqish - kelish)% x foydalaniladigan batareya', () {
      // 18% -> 80% = 62% x 60 kWh = 37.2 kWh.
      expect(evStopEnergyKwh(_stop(), _car), closeTo(37.2, 1e-9));
    });

    test('chegara: 0 farq, teskari farq, yaroqsiz sig\'im - nol', () {
      expect(evStopEnergyKwh(_stop(arrive: 50, depart: 50), _car), 0);
      expect(evStopEnergyKwh(_stop(arrive: 80, depart: 20), _car), 0);
      expect(
          evStopEnergyKwh(
              _stop(),
              const EvCarSpec(
                  usableBatteryKwh: 0, consumptionKwhPer100Km: 17)),
          0);
    });

    test('boshqa batareya - mutanosib', () {
      expect(
          evStopEnergyKwh(
              _stop(arrive: 10, depart: 60),
              const EvCarSpec(
                  usableBatteryKwh: 82, consumptionKwhPer100Km: 17)),
          closeTo(41, 1e-9));
    });
  });

  group('evMinChargeMinutes - "kamida" vaqt', () {
    test('energiya / quvvat, yuqoriga yaxlitlanadi', () {
      // 37.2 / 120 = 0.31 soat = 18.6 daq -> 19
      expect(evMinChargeMinutes(energyKwh: 37.2, powerKw: 120), 19);
      // 37.2 / 60 = 37.2 daq -> 38
      expect(evMinChargeMinutes(energyKwh: 37.2, powerKw: 60), 38);
    });

    test('aniq chegaralar: butun daqiqa +1 qo\'shilmaydi', () {
      expect(evMinChargeMinutes(energyKwh: 60, powerKw: 60), 60);
      expect(evMinChargeMinutes(energyKwh: 30, powerKw: 45), 40);
      expect(evMinChargeMinutes(energyKwh: 1, powerKw: 60), 1);
    });

    test('juda kichik energiya - kamida 1 daqiqa', () {
      expect(evMinChargeMinutes(energyKwh: 0.01, powerKw: 150), 1);
    });

    test('quvvat noma\'lum yoki <= 0, energiya <= 0 - null (vaqt o\'ylab '
        'topilmaydi)', () {
      expect(evMinChargeMinutes(energyKwh: 37, powerKw: null), isNull);
      expect(evMinChargeMinutes(energyKwh: 37, powerKw: 0), isNull);
      expect(evMinChargeMinutes(energyKwh: 37, powerKw: -50), isNull);
      expect(evMinChargeMinutes(energyKwh: 0, powerKw: 100), isNull);
    });

    test('quvvat oshsa vaqt kamayadi (monoton)', () {
      var prev = 1 << 30;
      for (final kw in [7, 22, 50, 120, 180, 350]) {
        final m = evMinChargeMinutes(energyKwh: 40, powerKw: kw)!;
        expect(m, lessThanOrEqualTo(prev), reason: '$kw kW');
        prev = m;
      }
    });
  });

  group('evStationPowerKw', () {
    test('powerKw ustun, bo\'lmasa sitePowerKw, ikkalasi ham yo\'q - null', () {
      expect(evStationPowerKw(_station(powerKw: 120, sitePowerKw: 240)), 120);
      expect(evStationPowerKw(_station(sitePowerKw: 240)), 240);
      expect(evStationPowerKw(_station()), isNull);
    });
  });

  group('evStopCharge', () {
    test('avtomobil yo\'q - null', () {
      expect(evStopCharge(_stop(powerKw: 120), null), isNull);
    });

    test('quvvat ma\'lum: energiya va kamida vaqt', () {
      final c = evStopCharge(_stop(powerKw: 120), _car)!;
      expect(c.energyKwh, closeTo(37.2, 1e-9));
      expect(c.minMinutes, 19);
    });

    test('stansiya quvvati sitePowerKw dan', () {
      expect(evStopCharge(_stop(sitePowerKw: 60), _car)!.minMinutes, 38);
    });

    test('quvvat noma\'lum: faqat energiya, vaqt null', () {
      final c = evStopCharge(_stop(), _car)!;
      expect(c.energyKwh, closeTo(37.2, 1e-9));
      expect(c.minMinutes, isNull);
    });

    test('energiya nol - null (qator ko\'rinmaydi)', () {
      expect(evStopCharge(_stop(arrive: 80, depart: 80, powerKw: 100), _car),
          isNull);
    });
  });

  group('evPlanMinChargeMinutes - yig\'indi (quyi chegara)', () {
    EvTripPlan plan(List<EvTripStop> stops) => EvTripPlan(
          status: EvTripPlanStatus.ok,
          stops: stops,
          totalKm: 900,
          arrivalSocPercent: 25,
        );

    test('hammasining quvvati ma\'lum - yig\'indi', () {
      final r = evPlanMinChargeMinutes(
          plan([_stop(powerKw: 120), _stop(powerKw: 60)]), _car);
      expect(r.minutes, 19 + 38);
      expect(r.knownStops, 2);
      expect(r.totalStops, 2);
    });

    test('ayrimlarining quvvati noma\'lum - ular yig\'indiga kirmaydi, nol deb '
        'ham sanalmaydi', () {
      final r = evPlanMinChargeMinutes(
          plan([_stop(powerKw: 120), _stop(), _stop(powerKw: 60)]), _car);
      expect(r.minutes, 19 + 38);
      expect(r.knownStops, 2);
      expect(r.totalStops, 3);
    });

    test('hech birining quvvati yo\'q - knownStops 0 (vaqt ko\'rsatilmaydi)',
        () {
      final r = evPlanMinChargeMinutes(plan([_stop(), _stop()]), _car);
      expect(r.knownStops, 0);
      expect(r.minutes, 0);
    });

    test('avtomobil yo\'q yoki to\'xtash yo\'q - hammasi nol', () {
      expect(evPlanMinChargeMinutes(plan([_stop(powerKw: 100)]), null).knownStops,
          0);
      expect(evPlanMinChargeMinutes(plan(const []), _car).totalStops, 0);
    });
  });

  group('evFormatKwh', () {
    test('10 dan katta - butun; kichik - bitta o\'nlik', () {
      expect(evFormatKwh(37.2), '37');
      expect(evFormatKwh(10), '10');
      expect(evFormatKwh(9.96), '10');
      expect(evFormatKwh(4.0), '4');
      expect(evFormatKwh(0.6), '0.6');
    });
  });
}

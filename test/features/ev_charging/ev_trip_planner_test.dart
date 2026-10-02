import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter_test/flutter_test.dart';

/// Синтетик маршрут — 60.0 меридиани бўйлаб шимолга. Бир даража кенглик
/// ≈ 111.195 км, шунинг учун километрни кенгликка айлантириш осон ва
/// текширувдаги рақамлар қўлда ҳисобланади.
const double _degPerKm = 1 / 111.1949;
const double _baseLat = 41.0;
const double _baseLng = 60.0;

double _latAtKm(double km) => _baseLat + km * _degPerKm;

List<EvRoutePoint> _route({double totalKm = 1200, double stepKm = 10}) {
  final points = <EvRoutePoint>[];
  for (var km = 0.0; km <= totalKm; km += stepKm) {
    points.add(EvRoutePoint(_latAtKm(km), _baseLng));
  }
  return points;
}

EvChargingStation _station(
  String id,
  double atKm, {
  List<String> chargingTypes = const ['AC'],
  List<String> connectors = const [],
  num? powerKw,
  String status = 'unknown',
  String verificationStatus = 'community',
  int confirmationCount = 0,
  double lngOffset = 0,
  String? sourceType,
}) {
  return EvChargingStation(
    id: id,
    latitude: _latAtKm(atKm),
    longitude: _baseLng + lngOffset,
    geohash: '',
    chargingTypes: chargingTypes,
    connectors: connectors,
    powerKw: powerKw,
    status: status,
    verificationStatus: verificationStatus,
    confirmationCount: confirmationCount,
    reportCount: 0,
    createdBy: 'u1',
    isActive: true,
    sourceType: sourceType,
  );
}

/// Тез DC станция — сифат балли энг баланд бўлиши учун.
EvChargingStation _dc(String id, double atKm, {List<String> connectors = const ['CCS2']}) =>
    _station(id, atKm,
        chargingTypes: const ['DC'],
        connectors: connectors,
        powerKw: 120,
        status: 'working',
        verificationStatus: 'verified',
        confirmationCount: 3);

List<EvCorridorStation> _corridorOf(List<EvChargingStation> stations) =>
    EvTripPlanner.corridor(route: _route(), stations: stations);

/// 60 kWh, 20 kWh/100km → тўлиқ 300 км, заҳира 10% билан 270 км.
const _car = EvCarSpec(
  usableBatteryKwh: 60,
  consumptionKwhPer100Km: 20,
  connectors: ['CCS2'],
);

void main() {
  group('EvTripPlanner.corridor', () {
    test('йўл устидаги станция — тўғри масофа билан киритилади', () {
      final result = _corridorOf([_station('a', 300)]);

      expect(result, hasLength(1));
      expect(result.first.offRouteKm, lessThan(0.5));
      expect(result.first.alongKm, closeTo(300, 3));
    });

    test('коридордан узоқдаги станция чиқариб ташланади', () {
      // ~50 км ғарбда (41.5° кенгликда 1° узунлик ≈ 83 км).
      final result = _corridorOf([_station('far', 300, lngOffset: 0.6)]);
      expect(result, isEmpty);
    });

    test('коридор ичидаги четдаги станция қолади ва чети ўлчанади', () {
      final result = _corridorOf([_station('near', 300, lngOffset: 0.036)]);

      expect(result, hasLength(1));
      expect(result.first.offRouteKm, closeTo(3, 1));
    });

    test('натижа йўл бўйлаб тартибланади', () {
      final result = _corridorOf([
        _station('c', 800),
        _station('a', 100),
        _station('b', 400),
      ]);

      expect(result.map((c) => c.station.id), ['a', 'b', 'c']);
    });

    test('routeLengthKm — маршрут узунлиги', () {
      expect(EvTripPlanner.routeLengthKm(_route(totalKm: 500)), closeTo(500, 2));
    });
  });

  group('EvTripPlanner.plan — асосий ҳолатлар', () {
    test('заряд етади — тўхташ режалаштирилмайди', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([_station('a', 100)]),
        totalKm: 200,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.status, EvTripPlanStatus.noChargingNeeded);
      expect(plan.stops, isEmpty);
      // 200 км × 20 kWh/100 = 40 kWh → 60 kWh батареядан 66.7%.
      expect(plan.arrivalSocPercent, closeTo(33, 1));
    });

    test('узун маршрут — занжир тузилади, босқичлар кетма-кет', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([
          _station('s200', 200),
          _dc('s260', 260),
          _station('s440', 440),
          _dc('s460', 460),
          _dc('s660', 660),
          _dc('s850', 850),
        ]),
        totalKm: 900,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.status, EvTripPlanStatus.ok);
      expect(plan.stops.map((s) => s.station.id),
          ['s260', 's460', 's660', 's850']);

      // Босқичлар ўсиб борадиган `alongKm` ва мусбат `legKm` билан.
      var prev = 0.0;
      for (final stop in plan.stops) {
        expect(stop.alongKm, greaterThan(prev));
        expect(stop.legKm, greaterThan(0));
        expect(stop.legKm, closeTo(stop.alongKm - prev, 0.01));
        prev = stop.alongKm;
      }

      // Ҳар тўхташда заҳира 10% дан пастга тушмайди.
      expect(plan.stops.every((s) => s.arriveSocPercent >= 10), isTrue);
      expect(plan.stops.every((s) => s.departSocPercent == 80), isTrue);
      expect(plan.arrivalSocPercent, greaterThanOrEqualTo(10));
    });

    test('энг узун босқич машина имкониятидан ошмайди', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([
          _dc('a', 250),
          _dc('b', 450),
          _dc('c', 650),
          _dc('d', 830),
        ]),
        totalKm: 900,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.status, EvTripPlanStatus.ok);
      // Биринчи босқич 100% дан — 270 км. Кейингилари 80% дан:
      // (80 − 10 заҳира) × 300 км / 100 = 210 км.
      expect(plan.longestLegKm, lessThanOrEqualTo(270.5));
      expect(plan.stops.skip(1).every((s) => s.legKm <= 210.5), isTrue);
    });
  });

  group('EvTripPlanner.plan — узилиш очиқ айтилади', () {
    test('станциялар орасидаги масофа катта — режа ўйлаб топилмайди', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([
          _dc('a', 200),
          _dc('b', 600),
        ]),
        totalKm: 900,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.status, EvTripPlanStatus.gapTooLarge);
      expect(plan.isOk, isFalse);
      // Биринчи тўхташ тузилган, иккинчисига етиб бўлмайди.
      expect(plan.stops.map((s) => s.station.id), ['a']);
      expect(plan.gapFromKm, closeTo(200, 3));
      expect(plan.gapReachKm, closeTo(410, 4));
      expect(plan.gapNextStationKm, closeTo(600, 3));
    });

    test('маршрутда умуман станция йўқ', () {
      final plan = EvTripPlanner.plan(
        corridorStations: const [],
        totalKm: 900,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.status, EvTripPlanStatus.gapTooLarge);
      expect(plan.stops, isEmpty);
      expect(plan.gapNextStationKm, isNull);
    });
  });

  group('EvTripPlanner.plan — заҳира вариантлар', () {
    test('асосийдан олдинги заҳиралар устун ва яқинлиги бўйича', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([
          _station('far', 240),
          _station('near', 255),
          _dc('primary', 260),
        ]),
        totalKm: 400,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.stops, hasLength(1));
      final stop = plan.stops.first;
      expect(stop.station.id, 'primary');
      expect(stop.hasBackup, isTrue);
      expect(stop.backups.map((b) => b.station.id), ['near', 'far']);
      expect(stop.backups.first.deltaKm, closeTo(-5, 1));
      expect(stop.backups.every((b) => b.isBefore), isTrue);
      expect(stop.backupsBefore, hasLength(2));
    });

    test('заҳира йўқ бўлса огоҳлантириш чиқади', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([_dc('only', 260)]),
        totalKm: 400,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.stops.first.hasBackup, isFalse);
      expect(plan.warnings, contains(EvTripWarning.noBackup));
    });
  });

  group('EvTripPlanner.plan — қайта ҳисоб (заряд тез тушди)', () {
    test('паст заряд билан қайта ҳисоблаганда яқинроқ станция танланади', () {
      final stations = _corridorOf([
        _station('km60', 60),
        _station('km80', 80),
        _station('km200', 200),
        _dc('km260', 260),
      ]);

      final full = EvTripPlanner.plan(
        corridorStations: stations,
        totalKm: 900,
        car: _car,
        startSocPercent: 100,
      );
      final drained = EvTripPlanner.plan(
        corridorStations: stations,
        totalKm: 900,
        car: _car,
        startSocPercent: 40,
      );

      expect(full.stops.first.station.id, 'km260');
      // 40% − 10% заҳира = 30% × 300 км = 90 км → 80 км даги нуқта.
      expect(drained.stops.first.station.id, 'km80');
    });

    test('fromAlongKm — йўлнинг ўтилган қисми ҳисобга олинмайди', () {
      final stations = _corridorOf([_dc('a', 100), _dc('b', 500)]);

      final plan = EvTripPlanner.plan(
        corridorStations: stations,
        totalKm: 900,
        car: _car,
        startSocPercent: 100,
        fromAlongKm: 300,
      );

      expect(plan.stops.map((s) => s.station.id), ['b']);
      expect(plan.stops.first.legKm, closeTo(200, 3));
    });
  });

  group('EvTripPlanner.plan — станция филтрлари', () {
    test('ишламайдиган станция режага кирмайди', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([
          _dc('good', 200),
          _station('broken', 260,
              chargingTypes: const ['DC'],
              connectors: const ['CCS2'],
              powerKw: 150,
              status: 'not_working'),
        ]),
        totalKm: 400,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.stops.map((s) => s.station.id), ['good']);
    });

    test('мос келмайдиган разъём режага кирмайди', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([
          _dc('ccs', 200),
          _dc('chademo', 260, connectors: const ['CHAdeMO']),
        ]),
        totalKm: 400,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.stops.map((s) => s.station.id), ['ccs']);
    });

    test('разъёми ёзилмаган станция рад этилмайди', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([
          _station('unknown_connector', 260, chargingTypes: const ['DC']),
        ]),
        totalKm: 400,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.stops.map((s) => s.station.id), ['unknown_connector']);
    });

    test('машина разъёми маълум эмас — филтр йўқ, огоҳлантириш бор', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([
          _dc('chademo', 260, connectors: const ['CHAdeMO']),
        ]),
        totalKm: 400,
        car: EvCarSpec(
          usableBatteryKwh: _car.usableBatteryKwh,
          consumptionKwhPer100Km: _car.consumptionKwhPer100Km,
        ),
        startSocPercent: 100,
      );

      expect(plan.stops.map((s) => s.station.id), ['chademo']);
      expect(plan.warnings, contains(EvTripWarning.connectorUnknown));
    });

    test('сифати баландроғи танланади (DC + текширилган)', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([
          _dc('dc_verified', 230),
          _station('ac_import', 265,
              chargingTypes: const ['AC'],
              connectors: const ['CCS2'],
              powerKw: 7,
              verificationStatus: 'imported',
              sourceType: 'import'),
        ]),
        totalKm: 400,
        car: _car,
        startSocPercent: 100,
      );

      // Узоқроғи 265 да, лекин сифати паст — текширилган DC танланади.
      expect(plan.stops.map((s) => s.station.id), ['dc_verified']);
    });
  });

  group('EvTripPlanner.plan — огоҳлантиришлар ва нотўғри киритма', () {
    test('текширилмаган импорт нуқтаси огоҳлантириш беради', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([
          _station('imported', 260,
              chargingTypes: const ['DC'],
              connectors: const ['CCS2'],
              powerKw: 60,
              verificationStatus: 'imported',
              sourceType: 'import'),
        ]),
        totalKm: 400,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.stops.first.isUnverifiedImport, isTrue);
      expect(plan.warnings, contains(EvTripWarning.unverifiedStops));
    });

    test('автомобил маълумоти тўлиқ эмас', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([_dc('a', 200)]),
        totalKm: 900,
        car: const EvCarSpec(
            usableBatteryKwh: 0, consumptionKwhPer100Km: 20),
        startSocPercent: 100,
      );

      expect(plan.status, EvTripPlanStatus.invalidCar);
      expect(plan.stops, isEmpty);
    });

    test('заряд заҳирадан паст — огоҳлантириш', () {
      final plan = EvTripPlanner.plan(
        corridorStations: _corridorOf([_dc('a', 200)]),
        totalKm: 900,
        car: _car,
        startSocPercent: 5,
      );

      expect(plan.warnings, contains(EvTripWarning.startSocBelowReserve));
      expect(plan.status, EvTripPlanStatus.gapTooLarge);
    });

    test('маршрут узунлиги йўқ — бўш режа', () {
      final plan = EvTripPlanner.plan(
        corridorStations: const [],
        totalKm: 0,
        car: _car,
        startSocPercent: 100,
      );

      expect(plan.status, EvTripPlanStatus.noRoute);
    });
  });

  group('EvCarSpec', () {
    test('rangeKmAt / usableRangeKmAt', () {
      expect(_car.rangeKmAt(100), closeTo(300, 0.1));
      expect(_car.rangeKmAt(50), closeTo(150, 0.1));
      // Заҳира 10% — ҳақиқий юриш масофаси.
      expect(_car.usableRangeKmAt(100), closeTo(270, 0.1));
      expect(_car.usableRangeKmAt(10), closeTo(0, 0.1));
      expect(_car.usableRangeKmAt(5), closeTo(0, 0.1));
    });

    test('isValid — нотўғри қийматлар', () {
      expect(_car.isValid, isTrue);
      expect(
          const EvCarSpec(usableBatteryKwh: 60, consumptionKwhPer100Km: 0)
              .isValid,
          isFalse);
      expect(
          const EvCarSpec(
                  usableBatteryKwh: 60,
                  consumptionKwhPer100Km: 20,
                  reservePercent: 90,
                  chargeToPercent: 80)
              .isValid,
          isFalse);
    });

    test('toMap / fromMap айлана', () {
      final restored = EvCarSpec.fromMap(_car.toMap());
      expect(restored.usableBatteryKwh, _car.usableBatteryKwh);
      expect(restored.consumptionKwhPer100Km, _car.consumptionKwhPer100Km);
      expect(restored.connectors, _car.connectors);
      expect(restored.reservePercent, _car.reservePercent);
      expect(restored.chargeToPercent, _car.chargeToPercent);
    });
  });
}

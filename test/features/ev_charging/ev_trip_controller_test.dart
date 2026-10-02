import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_controller.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/models/directions_result.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:ava_gurlan/models/oil_vehicle.dart';
import 'package:ava_gurlan/services/google_directions_service.dart';
import 'package:flutter_test/flutter_test.dart';

const double _degPerKm = 1 / 111.1949;
const double _baseLat = 41.0;
const double _baseLng = 60.0;

double _latAtKm(double km) => _baseLat + km * _degPerKm;

/// Google polyline форматига кодлаш — тестда ҳақиқий `PolylineDecoder`
/// ишлатилиши учун (mock қилинмайди, реал декодер синалади).
String _encodePolyline(List<List<double>> points) {
  final sb = StringBuffer();
  var prevLat = 0;
  var prevLng = 0;
  for (final p in points) {
    final lat = (p[0] * 1e5).round();
    final lng = (p[1] * 1e5).round();
    _encodeValue(sb, lat - prevLat);
    _encodeValue(sb, lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return sb.toString();
}

void _encodeValue(StringBuffer sb, int v) {
  var value = v < 0 ? ~(v << 1) : (v << 1);
  while (value >= 0x20) {
    sb.writeCharCode((0x20 | (value & 0x1f)) + 63);
    value >>= 5;
  }
  sb.writeCharCode(value + 63);
}

String _straightRoute({double totalKm = 1000, double stepKm = 10}) {
  final pts = <List<double>>[];
  for (var km = 0.0; km <= totalKm; km += stepKm) {
    pts.add([_latAtKm(km), _baseLng]);
  }
  return _encodePolyline(pts);
}

class _FakeDirections extends GoogleDirectionsService {
  _FakeDirections({this.result, this.throwError = false});

  final DirectionsResult? result;
  final bool throwError;
  int calls = 0;

  @override
  Future<DirectionsResult> fetchSimpleRoute({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    calls++;
    if (throwError) throw Exception('network down');
    return result!;
  }
}

EvChargingStation _dc(String id, double atKm) => EvChargingStation(
      id: id,
      latitude: _latAtKm(atKm),
      longitude: _baseLng,
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
    );

const _car = EvCarSpec(
  usableBatteryKwh: 60,
  consumptionKwhPer100Km: 20,
  connectors: ['CCS2'],
);

Future<EvTripController> _planned({
  required List<EvChargingStation> stations,
  double distanceKm = 1000,
  int socPercent = 100,
}) async {
  final controller = EvTripController(
    directions: _FakeDirections(
      result: DirectionsResult(
        distanceKm: distanceKm,
        durationMin: 720,
        polyline: _straightRoute(),
      ),
    ),
  );
  await controller.planTrip(
    originLat: _baseLat,
    originLng: _baseLng,
    destinationLat: _latAtKm(1000),
    destinationLng: _baseLng,
    car: _car,
    socPercent: socPercent,
    stations: stations,
  );
  return controller;
}

void main() {
  group('EvTripController.planTrip', () {
    test('маршрут + коридор + режа бирга ишлайди', () async {
      final c = await _planned(stations: [
        _dc('a', 250),
        _dc('b', 450),
        _dc('c', 650),
        _dc('d', 850),
      ]);

      expect(c.error, isNull);
      expect(c.loading, isFalse);
      expect(c.plan, isNotNull);
      expect(c.plan!.status, EvTripPlanStatus.ok);
      expect(c.routeKm, closeTo(1000, 1));
      expect(c.routeMinutes, 720);
      expect(c.routePoints.length, greaterThan(50));
      expect(c.corridorStations, hasLength(4));
      expect(c.navigationStops, hasLength(c.plan!.stops.length));
    });

    test('маршрут бўйидаги режага кирмаган станциялар ҳам сақланади', () async {
      final c = await _planned(stations: [
        _dc('a', 250),
        _dc('a2', 260),
        _dc('b', 450),
        _dc('c', 650),
        _dc('d', 850),
      ]);

      // Коридорда 5 та, режада камроқ — қолганлари харитада кўринади.
      expect(c.corridorStations, hasLength(5));
      expect(c.plan!.stops.length, lessThan(5));
    });

    test('коридордан узоқдаги станция ҳисобга олинмайди', () async {
      final far = EvChargingStation(
        id: 'far',
        latitude: _latAtKm(400),
        longitude: _baseLng + 0.6, // ~50 км четда
        geohash: '',
        chargingTypes: const ['DC'],
        connectors: const ['CCS2'],
        status: 'working',
        verificationStatus: 'verified',
        confirmationCount: 0,
        reportCount: 0,
        createdBy: 'u1',
        isActive: true,
      );

      final c = await _planned(stations: [_dc('a', 250), far]);
      expect(c.corridorStations.map((s) => s.station.id), ['a']);
    });

    test('масофа масштабланади — йўл масофаси Google бўйича', () async {
      // Геометрия ~1000 км, Google эса 1100 км деса — alongKm шунга мос
      // келтирилади, акс ҳолда охирида «фантом» 100 км пайдо бўларди.
      final c = await _planned(
        stations: [_dc('mid', 500)],
        distanceKm: 1100,
      );

      expect(c.routeKm, 1100);
      expect(c.corridorStations.first.alongKm, closeTo(550, 6));
    });

    test('тармоқ хатоси — ярим режа кўрсатилмайди', () async {
      final c = EvTripController(directions: _FakeDirections(throwError: true));
      await c.planTrip(
        originLat: _baseLat,
        originLng: _baseLng,
        destinationLat: _latAtKm(1000),
        destinationLng: _baseLng,
        car: _car,
        socPercent: 100,
        stations: [_dc('a', 250)],
      );

      expect(c.error, 'route_request_failed');
      expect(c.plan, isNull);
      expect(c.loading, isFalse);
    });

    test('маршрут геометрияси бўш — хато', () async {
      final c = EvTripController(
        directions: _FakeDirections(
          result: const DirectionsResult(
              distanceKm: 1000, durationMin: 700, polyline: ''),
        ),
      );
      await c.planTrip(
        originLat: _baseLat,
        originLng: _baseLng,
        destinationLat: _latAtKm(1000),
        destinationLng: _baseLng,
        car: _car,
        socPercent: 100,
        stations: [_dc('a', 250)],
      );

      expect(c.error, 'route_geometry_missing');
      expect(c.plan, isNull);
    });
  });

  group('EvTripController.replan', () {
    test('заряд тез тушди — тармоқ сўровисиз қайта ҳисоб', () async {
      final fake = _FakeDirections(
        result: DirectionsResult(
          distanceKm: 1000,
          durationMin: 720,
          polyline: _straightRoute(),
        ),
      );
      final c = EvTripController(directions: fake);
      await c.planTrip(
        originLat: _baseLat,
        originLng: _baseLng,
        destinationLat: _latAtKm(1000),
        destinationLng: _baseLng,
        car: _car,
        socPercent: 100,
        stations: [_dc('near', 60), _dc('far', 250)],
      );

      expect(fake.calls, 1);
      expect(c.plan!.stops.first.station.id, 'far');

      c.replan(car: _car, socPercent: 30, passedKm: 0);

      // Directions қайта чақирилмади.
      expect(fake.calls, 1);
      // 30% − 10% заҳира = 20% × 300 км = 60 км → яқин нуқта.
      expect(c.plan!.stops.first.station.id, 'near');
    });

    test('rejectStation — рад этилган нуқта бошқа таклиф қилинмайди', () async {
      final c = await _planned(stations: [
        _dc('a', 200),
        _dc('b', 260),
        _dc('c', 450),
        _dc('d', 650),
        _dc('e', 850),
      ]);

      final first = c.plan!.stops.first.station.id;
      c.rejectStation(stationId: first, car: _car, socPercent: 100);

      expect(c.plan!.stops.first.station.id, isNot(first));
      expect(c.corridorStations.any((s) => s.station.id == first), isFalse);
    });

    test('clear — ҳолат тозаланади', () async {
      final c = await _planned(stations: [_dc('a', 250)]);
      expect(c.hasPlan, isTrue);

      c.clear();

      expect(c.hasPlan, isFalse);
      expect(c.corridorStations, isEmpty);
      expect(c.routePoints, isEmpty);
      expect(c.routeKm, 0);
      expect(c.navigationStops, isEmpty);
    });
  });

  group('OilVehicleEvSpec', () {
    test('электромобил — спецификация ажратилади', () {
      const v = OilVehicle(
        id: 'v1',
        model: 'BYD Song',
        color: 'oq',
        plate: '95A000AA',
        fuelType: 'ev',
        evBatteryKwh: 71.8,
        evConsumptionKwhPer100Km: 18.5,
        evConnectors: ['CCS2', 'GB/T'],
      );

      expect(v.isElectric, isTrue);
      expect(v.hasEvSpec, isTrue);
      final spec = v.evSpec;
      expect(spec, isNotNull);
      expect(spec!.usableBatteryKwh, 71.8);
      expect(spec.consumptionKwhPer100Km, 18.5);
      expect(spec.connectors, ['CCS2', 'GB/T']);
      expect(spec.isValid, isTrue);
    });

    test('маълумот тўлиқ эмас — null (режа ўйлаб топилмайди)', () {
      const noBattery = OilVehicle(
        id: 'v2',
        model: 'BYD',
        color: '',
        plate: '',
        fuelType: 'ev',
        evConsumptionKwhPer100Km: 18.5,
      );
      expect(noBattery.hasEvSpec, isFalse);
      expect(noBattery.evSpec, isNull);

      const petrol = OilVehicle(
        id: 'v3',
        model: 'Cobalt',
        color: '',
        plate: '',
        fuelType: 'petrol',
        evBatteryKwh: 60,
        evConsumptionKwhPer100Km: 18,
      );
      expect(petrol.isElectric, isFalse);
      expect(petrol.evSpec, isNull);
    });

    test('EV майдонлари toMap/fromMap орқали сақланади', () {
      const v = OilVehicle(
        id: 'v1',
        model: 'BYD',
        color: '',
        plate: '',
        fuelType: 'ev',
        evBatteryKwh: 60,
        evConsumptionKwhPer100Km: 18,
        evConnectors: ['CCS2'],
      );
      final map = v.toMap();
      expect(map['evBatteryKwh'], 60);
      expect(map['evConsumptionKwhPer100Km'], 18);
      expect(map['evConnectors'], ['CCS2']);
      expect(map['fuelType'], 'ev');
    });

    test('copyWith EV майдонларини сақлайди', () {
      const v = OilVehicle(
        id: 'v1',
        model: 'BYD',
        color: '',
        plate: '',
        fuelType: 'ev',
        evBatteryKwh: 60,
        evConsumptionKwhPer100Km: 18,
        evConnectors: ['CCS2'],
      );
      final renamed = v.copyWith(model: 'BYD Song');
      expect(renamed.evBatteryKwh, 60);
      expect(renamed.evConsumptionKwhPer100Km, 18);
      expect(renamed.evConnectors, ['CCS2']);
    });

    test('fuelLabelUz — электр', () {
      const v = OilVehicle(
          id: 'v1', model: '', color: '', plate: '', fuelType: 'ev');
      expect(v.fuelLabelUz, 'Электр');
    });
  });
}

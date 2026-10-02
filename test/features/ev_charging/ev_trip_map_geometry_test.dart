import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_map_view.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter_test/flutter_test.dart';

EvChargingStation _station(String id) => EvChargingStation(
      id: id,
      latitude: 41,
      longitude: 60,
      geohash: '',
      chargingTypes: const ['DC'],
      connectors: const ['CCS2'],
      status: 'working',
      verificationStatus: 'verified',
      confirmationCount: 1,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
    );

EvTripStop _stop(String id, {List<String> backupIds = const []}) => EvTripStop(
      station: _station(id),
      alongKm: 300,
      offRouteKm: 0,
      legKm: 300,
      arriveSocPercent: 18,
      departSocPercent: 80,
      backups: [
        for (final b in backupIds)
          EvTripBackup(
            station: _station(b),
            alongKm: 260,
            offRouteKm: 0,
            deltaKm: -40,
          ),
      ],
    );

void main() {
  group('EvTripMapGeometry.boundsFor', () {
    test('маршрутни тўлиқ қамрайди', () {
      final bounds = EvTripMapGeometry.boundsFor(const [
        EvRoutePoint(41.55, 60.63),
        EvRoutePoint(39.65, 66.96),
        EvRoutePoint(41.30, 69.24),
      ]);

      expect(bounds, isNotNull);
      expect(bounds!.southwest.latitude, 39.65);
      expect(bounds.southwest.longitude, 60.63);
      expect(bounds.northeast.latitude, 41.55);
      expect(bounds.northeast.longitude, 69.24);
    });

    test('бўш маршрут — null', () {
      expect(EvTripMapGeometry.boundsFor(const []), isNull);
    });

    test('битта нуқта — йиғилган тўртбурчак', () {
      final bounds =
          EvTripMapGeometry.boundsFor(const [EvRoutePoint(41.3, 69.2)]);
      expect(bounds!.southwest, bounds.northeast);
    });
  });

  group('EvTripMapGeometry.markerKinds', () {
    test('асосий, заҳира ва қолганлар ажратилади', () {
      final plan = EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [
          _stop('p1', backupIds: ['b1', 'b2']),
          _stop('p2', backupIds: ['b3']),
        ],
        totalKm: 900,
        arrivalSocPercent: 25,
      );

      final kinds = EvTripMapGeometry.markerKinds(plan);

      expect(kinds['p1'], EvTripMarkerKind.primary);
      expect(kinds['p2'], EvTripMarkerKind.primary);
      expect(kinds['b1'], EvTripMarkerKind.backup);
      expect(kinds['b3'], EvTripMarkerKind.backup);
      // Рўйхатда йўқ станция — харитада «қолганлар» сифатида чиқади.
      expect(kinds['x9'], isNull);
    });

    test('бир станция ҳам асосий, ҳам заҳира бўлса — асосий устун', () {
      // 2-тўхташнинг заҳираси 1-тўхташнинг айни ўзи бўлиб қолиши мумкин.
      final plan = EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [_stop('a'), _stop('b', backupIds: ['a'])],
        totalKm: 900,
        arrivalSocPercent: 25,
      );

      expect(EvTripMapGeometry.markerKinds(plan)['a'],
          EvTripMarkerKind.primary);
    });

    test('бўш режа — бўш харита белгилари', () {
      const plan = EvTripPlan(
        status: EvTripPlanStatus.noChargingNeeded,
        stops: [],
        totalKm: 200,
        arrivalSocPercent: 40,
      );
      expect(EvTripMapGeometry.markerKinds(plan), isEmpty);
      expect(EvTripMapGeometry.stopNumbers(plan), isEmpty);
    });
  });

  group('EvTripMapGeometry.stopNumbers', () {
    test('тартиб рақами 1 дан бошланади', () {
      final plan = EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [_stop('a'), _stop('b'), _stop('c')],
        totalKm: 900,
        arrivalSocPercent: 25,
      );

      final numbers = EvTripMapGeometry.stopNumbers(plan);
      expect(numbers['a'], 1);
      expect(numbers['b'], 2);
      expect(numbers['c'], 3);
    });
  });
}

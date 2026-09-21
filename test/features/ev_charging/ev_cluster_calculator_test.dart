import 'package:flutter_test/flutter_test.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_cluster_calculator.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';

EvChargingStation _station(String id, double lat, double lng) => EvChargingStation(
      id: id,
      latitude: lat,
      longitude: lng,
      geohash: '',
      chargingTypes: const [],
      connectors: const [],
      status: 'unknown',
      verificationStatus: 'community',
      confirmationCount: 0,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
    );

void main() {
  group('EvClusterCalculator.build', () {
    test('threshold ichida — har bir stansiya alohida marker', () {
      final stations = [
        _station('a', 41.55, 60.60),
        _station('b', 41.56, 60.61),
      ];
      final clusters = EvClusterCalculator.build(stations, threshold: 50, zoom: 14);
      expect(clusters.length, 2);
      expect(clusters.every((c) => c.isSingle), isTrue);
    });

    test('threshold oshganda — geohash katakchasi bo\'yicha birlashtiriladi', () {
      final stations = List.generate(
        60,
        (i) => _station('s$i', 41.55 + i * 0.0001, 60.60 + i * 0.0001),
      );
      final clusters = EvClusterCalculator.build(stations, threshold: 50, zoom: 14);
      expect(clusters.length, lessThan(stations.length));
      final total = clusters.fold<int>(0, (sum, c) => sum + c.count);
      expect(total, stations.length);
    });

    test('bir-biridan uzoq nuqtalar alohida klaster hosil qiladi', () {
      final stations = List.generate(60, (i) => _station('s$i', 41.55, 60.60))
        ..add(_station('far', 10.0, 10.0));
      final clusters = EvClusterCalculator.build(stations, threshold: 50, zoom: 14);
      final farCluster = clusters.firstWhere((c) => c.stations.any((s) => s.id == 'far'));
      expect(farCluster.stations.length, 1);
    });
  });
}

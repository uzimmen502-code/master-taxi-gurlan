import 'package:ava_gurlan/features/home/widgets/home_ev_section.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter_test/flutter_test.dart';

EvChargingStation _station({
  String? occupancy,
  DateTime? at,
  double lat = 41.55,
  double lng = 60.38,
}) =>
    EvChargingStation(
      id: 's1',
      latitude: lat,
      longitude: lng,
      geohash: 'x',
      chargingTypes: const [],
      connectors: const [],
      status: 'working',
      verificationStatus: 'community',
      confirmationCount: 0,
      reportCount: 0,
      createdBy: 'u',
      isActive: true,
      occupancy: occupancy,
      occupancyAt: at,
    );

void main() {
  group('EvChargingStation.occupancyState', () {
    test('belgilanmagan — unknown', () {
      expect(_station().occupancyState, 'unknown');
    });

    test('yangi belgi — o‘sha holat', () {
      final now = DateTime.now();
      expect(_station(occupancy: 'busy', at: now).occupancyState, 'busy');
      expect(_station(occupancy: 'free', at: now).occupancyState, 'free');
    });

    test('eskirgan belgi — yana unknown', () {
      // 30 daqiqadan keyin belgi hisobga olinmaydi.
      final old = DateTime.now().subtract(const Duration(minutes: 31));
      expect(_station(occupancy: 'busy', at: old).occupancyState, 'unknown');
    });

    test('chegaradan sal beri — hali amal qiladi', () {
      final recent = DateTime.now().subtract(const Duration(minutes: 29));
      expect(_station(occupancy: 'busy', at: recent).occupancyState, 'busy');
    });

    test('vaqtsiz qiymat hisobga olinmaydi', () {
      expect(_station(occupancy: 'busy').occupancyState, 'unknown');
    });

    test('occupancy `status` dan mustaqil', () {
      // `status` = stansiya umuman ishlaydimi; `occupancy` = hozir bandmi.
      final s = _station(occupancy: 'busy', at: DateTime.now());
      expect(s.status, 'working');
      expect(s.occupancyState, 'busy');
    });
  });

  group('staticMapUrl', () {
    test('asosiy parametrlar bor', () {
      final url = staticMapUrl(
        apiKey: 'KEY',
        lat: 41.55,
        lng: 60.38,
        width: 400,
        height: 140,
      );
      expect(url, startsWith('https://maps.googleapis.com/maps/api/staticmap?'));
      expect(url, contains('center=41.55,60.38'));
      expect(url, contains('size=400x140'));
      expect(url, contains('key=KEY'));
    });

    test('markerlar qo‘shiladi va 10 tadan oshmaydi', () {
      final many = List.generate(15, (i) => _station(lat: 41.0 + i, lng: 60.0));
      final url = staticMapUrl(
        apiKey: 'KEY',
        lat: 41.0,
        lng: 60.0,
        width: 400,
        height: 140,
        markers: many,
      );
      expect(url, contains('markers='));
      // URL cheksiz uzaymasin — 10 ta nuqta, ya'ni 9 ta ajratuvchi.
      final markerPart = url.split('markers=').last;
      expect('%7C'.allMatches(markerPart).length, lessThanOrEqualTo(11));
    });

    test('marker yo‘q bo‘lsa markers parametri ham yo‘q', () {
      final url = staticMapUrl(
        apiKey: 'KEY',
        lat: 41.0,
        lng: 60.0,
        width: 400,
        height: 140,
      );
      expect(url.contains('markers='), isFalse);
    });
  });
}

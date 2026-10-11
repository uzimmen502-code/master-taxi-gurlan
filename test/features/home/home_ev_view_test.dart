import 'package:ava_gurlan/features/home/widgets/home_ev_section.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter_test/flutter_test.dart';

/// Геo 4-босқич: бош саҳифа EV блоки — фойдаланувчи атрофи. Жонли харита
/// ўзгармайди (эга қарори 2026-09-22: барча нуқталар).
EvChargingStation _s(String id, double lat, double lng) => EvChargingStation(
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
  // Гурлан ~ (41.84, 60.39); Тошкент ~ (41.31, 69.28).
  final tashkent = _s('tash', 41.31, 69.28);
  final gurlanFar = _s('gFar', 41.84 + 0.1795, 60.39); // ~19.96 км
  final gurlanOut = _s('gOut', 41.84 + 0.1805, 60.39); // ~20.07 км
  final gurlanNear = _s('gNear', 41.845, 60.39);

  test('бўш рўйхат — null', () {
    expect(EvHomeView.of(const [], lat: 41.84, lng: 60.39), isNull);
  });

  test('координата йўқ — аввалги ҳолат: биринчи станция, бутун саноқ', () {
    final v = EvHomeView.of([tashkent, gurlanNear])!;
    expect(v.nearby, isFalse);
    expect(v.centerLat, tashkent.latitude);
    expect(v.counted, hasLength(2));
  });

  test('координата бор — марказ фойдаланувчи; 20 км чегара; яқини биринчи', () {
    final v = EvHomeView.of([tashkent, gurlanOut, gurlanFar, gurlanNear],
        lat: 41.84, lng: 60.39)!;
    expect(v.nearby, isTrue);
    expect((v.centerLat, v.centerLng), (41.84, 60.39));
    expect(v.counted.map((s) => s.id), ['gNear', 'gFar']);
    expect(v.markers.first.id, 'gNear');
  });

  test('радиусда йўқ — марказ энг яқин станция, саноқ бутун рўйхат', () {
    final v = EvHomeView.of([tashkent, gurlanNear], lat: 40.0, lng: 71.0)!;
    expect(v.nearby, isFalse);
    expect(v.centerLat, tashkent.latitude);
    expect(v.counted, hasLength(2));
    expect(v.markers.first.id, 'tash');
  });
}

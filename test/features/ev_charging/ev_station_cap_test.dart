import 'dart:io';

import 'package:ava_gurlan/features/ev_charging/controllers/ev_station_cap.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter_test/flutter_test.dart';

EvChargingStation _st(String id, double lat, double lng) => EvChargingStation(
      id: id,
      latitude: lat,
      longitude: lng,
      geohash: 'tn',
      chargingTypes: const [],
      connectors: const [],
      status: 'working',
      verificationStatus: 'community',
      confirmationCount: 0,
      reportCount: 0,
      createdBy: 'u',
      isActive: true,
    );

void main() {
  test('чегара 400: кам бўлса ўзгаришсиз, аниқ 400 бўлса ҳам, 401 бўлса энг узоқдагиси тушади', () {
    expect(kEvMapMaxMarkers, 400);
    final few = [for (var i = 0; i < 5; i++) _st('s$i', 41 + i * 0.01, 60)];
    expect(identical(capNearestStations(few, 41, 60), few), isTrue, reason: 'ортиқча нусха яратилмайди');
    final exact = [for (var i = 0; i < 400; i++) _st('s$i', 41 + i * 0.001, 60)];
    expect(capNearestStations(exact, 41, 60).length, 400);
    final over = [for (var i = 0; i < 401; i++) _st('s$i', 41 + i * 0.001, 60)];
    final r = capNearestStations(over, 41, 60);
    expect(r.length, 400);
    expect(r.any((s) => s.id == 's400'), isFalse, reason: 'марказдан энг узоқдагиси тушиб қолади');
    expect(r.first.id, 's0', reason: 'энг яқини биринчи');
  });

  test('марказга яқинлари қолади (марказ ўзгарса — тўплам ҳам ўзгаради); масофа тенг бўлса тартиб барқарор', () {
    final all = [
      _st('west', 41, 58),
      _st('mid1', 41, 60),
      _st('mid2', 41, 60), // mid1 билан бир нуқта
      _st('east', 41, 62),
    ];
    expect(capNearestStations(all, 41, 60, cap: 2).map((s) => s.id), ['mid1', 'mid2']);
    expect(capNearestStations(all, 41, 62, cap: 1).map((s) => s.id), ['east']);
    expect(capNearestStations(all, 41, 58, cap: 1).map((s) => s.id), ['west']);
  });

  test('бўш рўйхат — бўш', () {
    expect(capNearestStations(const [], 41, 60), isEmpty);
  });

  test('EV харита кодида кластер қолмаган, ўрнига чегара ва «яқинлаштиринг» хабари бор', () {
    final src = File('lib/features/ev_charging/widgets/ev_map_view.dart').readAsStringSync();
    expect(src.contains('EvClusterCalculator'), isFalse);
    expect(src.contains('InfoWindow'), isFalse, reason: '«⚡ N нуқта» кластер маркери олиб ташланган');
    expect(src.contains('capNearestStations'), isTrue);
    expect(src.contains('ev_map_zoom_in'), isTrue);
    expect(src.contains('ViewportCells.forBounds'), isTrue);
  });
}

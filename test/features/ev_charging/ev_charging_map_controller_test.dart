import 'dart:async';

import 'package:ava_gurlan/features/ev_charging/controllers/ev_charging_map_controller.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:ava_gurlan/repositories/ev_station_repository.dart';
import 'package:ava_gurlan/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements EvStationRepository {
  final ctrl = StreamController<List<EvChargingStation>>.broadcast();
  int watchCalls = 0;

  @override
  Stream<List<EvChargingStation>> watchAllActive() {
    watchCalls++;
    return ctrl.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Loc implements LocationService {
  _Loc({this.fail = false, this.allowed});
  final bool fail;

  /// `getCoordsIfAllowed` натижаси: `null` — GPS/рухсат ҳали йўқ (хабар қолади). Тест ичида ўзгартирилади.
  LocationCoords? allowed;

  @override
  Future<LocationCoords?> getCoordsIfAllowed({Duration timeout = const Duration(seconds: 6)}) async => allowed;

  @override
  Future<LocationCoords> getCurrentCoords({
    Duration mediumTimeout = const Duration(seconds: 5),
    Duration highTimeout = const Duration(seconds: 10),
  }) async {
    if (fail) throw const LocationException(LocationErrorKind.permissionDenied);
    return const LocationCoords(lat: 41.6, lng: 60.6);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Geo аудит, 0-босқич: GPS бўлмаса ҳам станциялар юкланади (аввал
/// `_watchStations` чақирилмас, экранда фақат хато матни қоларди).
void main() {
  test('GPS рад этилса ҳам станциялар оқими очилади, марказ — мамлакат ўртаси', () async {
    final repo = _FakeRepo();
    final c = EvChargingMapController(repository: repo, locationService: _Loc(fail: true));
    await c.init();
    expect(repo.watchCalls, 1);
    expect(c.error, isNotNull);
    expect(c.loading, isFalse);
    expect(c.hasLocation, isFalse);
    expect(c.centerLat, EvChargingMapController.fallbackLat);
    expect(c.centerLng, EvChargingMapController.fallbackLng);
    c.dispose();
  });

  test('GPS ёқилгандан кейин refreshLocation «GPS ўчиқ» хабарини ўчиради ва маркази GPS бўлади', () async {
    final repo = _FakeRepo();
    final loc = _Loc(fail: true); // аввал GPS ўчиқ
    final c = EvChargingMapController(repository: repo, locationService: loc);
    await c.init();
    expect(c.error, isNotNull);

    // GPS ҳали ўчиқ: хабар қолади, координата йўқ.
    expect(await c.refreshLocation(), isFalse);
    expect(c.error, isNotNull);
    expect(c.hasLocation, isFalse);

    // Фойдаланувчи GPS'ни ёқди.
    loc.allowed = const LocationCoords(lat: 41.5, lng: 60.4);
    var notified = 0;
    c.addListener(() => notified++);
    expect(await c.refreshLocation(), isTrue);
    expect(c.error, isNull, reason: 'GPS ёқилгач хабар ўчиши шарт');
    expect(c.hasLocation, isTrue);
    expect(c.centerLat, 41.5);
    expect(c.centerLng, 60.4);
    expect(notified, 1, reason: 'экран қайта чизилсин');
    expect(repo.watchCalls, 1, reason: 'станциялар оқими қайта очилмайди (ортиқча Firestore ўқиш йўқ)');
    c.dispose();
  });

  test('recenterOnGps ҳам эски «GPS ўчиқ» хабарини ўчиради', () async {
    final c = EvChargingMapController(repository: _FakeRepo(), locationService: _Loc(fail: true));
    await c.init();
    expect(c.error, isNotNull);
    c.recenterOnGps(41.2, 60.1);
    expect(c.error, isNull);
    expect(c.hasLocation, isTrue);
    c.dispose();
  });

  test('refreshLocation контроллер ёпилгандан кейин тугаса — хато бермайди', () async {
    final loc = _Loc(fail: true);
    final c = EvChargingMapController(repository: _FakeRepo(), locationService: loc);
    await c.init();
    loc.allowed = const LocationCoords(lat: 41.5, lng: 60.4);
    c.dispose();
    expect(await c.refreshLocation(), isFalse);
  });

  test('GPS бор — марказ GPS, хато йўқ, оқим бир марта', () async {
    final repo = _FakeRepo();
    final c = EvChargingMapController(repository: repo, locationService: _Loc());
    await c.init();
    expect(repo.watchCalls, 1);
    expect(c.error, isNull);
    expect(c.centerLat, 41.6);
    expect(c.centerLng, 60.6);
    c.dispose();
  });
}

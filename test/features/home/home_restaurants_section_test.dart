import 'dart:async';

import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/features/home/widgets/home_restaurants_section.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:ava_gurlan/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Firestore'siz: faqat `watchApproved` stream'i beriladi.
class _FakeRepo implements RestaurantsRepository {
  _FakeRepo(this.list);

  final List<Restaurant> list;

  @override
  Stream<List<Restaurant>> watchApproved({int limit = 50}) => Stream.value(list);

  /// Сервер сўрови ўрнига — ўша радиус филтри (D-GEO-4).
  @override
  Stream<List<Restaurant>> watchNearby({
    required double lat,
    required double lng,
    double radiusKm = RestaurantsRepository.nearbyRadiusKm,
    int perCellLimit = 50,
  }) {
    nearbyCalls++;
    return Stream.value(
        RestaurantsRepository.withinRadius(list, lat, lng, radiusKm));
  }

  int nearbyCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Restaurant _r(String id, {double? lat, double? lng, bool open = true}) => Restaurant(
      id: id,
      name: id,
      status: 'approved',
      lat: lat,
      lng: lng,
      prepTimeMin: 20,
      delivery: const RestaurantDelivery(mode: 'ava_courier', pickup: false),
      openingHours: open ? null : const OpeningHours(open: '00:00', close: '00:01'),
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUp(() => ServiceConfigHolder.setForTest(
        defaults: ServiceModuleConfig.allEnabled(['restaurants']),
      ));
  tearDown(ServiceConfigHolder.resetForTest);

  testWidgets('modul ochiq: ro\'yxat masofa bo\'yicha, yopiqlar oxirida; «Barchasi» ishlaydi', (tester) async {
    var all = 0;
    Restaurant? opened;
    await tester.pumpWidget(_host(HomeRestaurantsSection(
      repository: _FakeRepo([
        _r('uzoq', lat: 41.90, lng: 60.39),
        _r('yaqin', lat: 41.85, lng: 60.39),
        _r('yopiq', lat: 41.841, lng: 60.39, open: false),
      ]),
      userLat: 41.84,
      userLng: 60.39,
      onOpenAll: () => all++,
      onOpenRestaurant: (r) => opened = r,
    )));
    await tester.pumpAndSettle();

    expect(find.text('home_section_restaurants'), findsOneWidget);
    final yaqin = tester.getTopLeft(find.text('yaqin'));
    final uzoq = tester.getTopLeft(find.text('uzoq'));
    final yopiq = tester.getTopLeft(find.text('yopiq'));
    expect(yaqin.dy < uzoq.dy, isTrue, reason: 'yaqin — birinchi');
    expect(uzoq.dy < yopiq.dy, isTrue, reason: 'yopiq (eng yaqin bo\'lsa ham) — oxirida');
    expect(find.text('restaurants_closed'), findsOneWidget);

    await tester.tap(find.text('yaqin'));
    await tester.pump();
    expect(opened?.id, 'yaqin');

    await tester.tap(find.text('home_section_see_all'));
    await tester.pump();
    expect(all, 1);
  });

  testWidgets('modul yashirin → bo\'lim umuman chizilmaydi', (tester) async {
    ServiceConfigHolder.setForTest(defaults: ServiceModuleConfig.allEnabled(['bread']));
    await tester.pumpWidget(_host(HomeRestaurantsSection(
      repository: _FakeRepo([_r('a')]),
      onOpenAll: () {},
      onOpenRestaurant: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('home_section_restaurants'), findsNothing);
  });

  testWidgets('«Tez kunda» + sinovchi → ko\'rinadi; sinovchi emas → yo\'q', (tester) async {
    ServiceConfigHolder.setForTest(
      defaults: const ServiceModuleConfig({'restaurants': ModuleStatus.soon}),
      enforce: true,
    );
    await tester.pumpWidget(_host(HomeRestaurantsSection(
      repository: _FakeRepo([_r('a')]),
      accessCheck: () async => true,
      onOpenAll: () {},
      onOpenRestaurant: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);

    await tester.pumpWidget(_host(HomeRestaurantsSection(
      key: const Key('second'),
      repository: _FakeRepo([_r('b')]),
      accessCheck: () async => false,
      onOpenAll: () {},
      onOpenRestaurant: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsNothing);
  });

  testWidgets('bo\'sh ro\'yxat — bo\'lim o\'z o\'rnida, bo\'sh holat matni', (tester) async {
    await tester.pumpWidget(_host(HomeRestaurantsSection(
      repository: _FakeRepo(const []),
      onOpenAll: () {},
      onOpenRestaurant: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('home_section_restaurants'), findsOneWidget);
    expect(find.text('restaurants_empty_nearby'), findsOneWidget);
  });

  // ─── D-GEO-4 (геo 4-босқич) ─────────────────────────────────────────
  testWidgets('GPS бор — профилдан устун; 20 км дан узоғи чиқмайди', (tester) async {
    final repo = _FakeRepo([
      _r('gpsYaqin', lat: 41.551, lng: 60.63), // Урганч атрофи
      _r('profilYaqin', lat: 41.85, lng: 60.39), // Гурлан — GPS'дан ~40 км
    ]);
    await tester.pumpWidget(_host(HomeRestaurantsSection(
      repository: repo,
      userLat: 41.84, // профил — Гурлан
      userLng: 60.39,
      locate: () async => const LocationCoords(lat: 41.55, lng: 60.63),
      onOpenAll: () {},
      onOpenRestaurant: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(repo.nearbyCalls, greaterThan(0));
    expect(find.text('gpsYaqin'), findsOneWidget);
    expect(find.text('profilYaqin'), findsNothing);
  });

  testWidgets('координата йўқ — аввалги умумий рўйхат (ном бўйича)', (tester) async {
    final repo = _FakeRepo([_r('b', lat: 41.0, lng: 69.0), _r('a')]);
    await tester.pumpWidget(_host(HomeRestaurantsSection(
      repository: repo,
      locate: () async => null,
      onOpenAll: () {},
      onOpenRestaurant: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(repo.nearbyCalls, 0);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });

  group('RestaurantsRepository.withinRadius', () {
    test('чегара: 20 км ичи — бор, ташқари — йўқ; координатасиз — йўқ; яқини биринчи', () {
      // 0.1799° кенглик ≈ 20.0 км, 0.1805° ≈ 20.07 км.
      final r = RestaurantsRepository.withinRadius(
        [
          _r('edgeOut', lat: 41.0 + 0.1805, lng: 64.0),
          _r('edgeIn', lat: 41.0 + 0.1795, lng: 64.0),
          _r('near', lat: 41.01, lng: 64.0),
          _r('noCoords'),
        ],
        41.0,
        64.0,
        20,
      );
      expect(r.map((e) => e.id), ['near', 'edgeIn']);
    });
  });
}

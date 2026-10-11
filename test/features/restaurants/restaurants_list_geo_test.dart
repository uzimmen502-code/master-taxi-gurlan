import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurants_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// D-GEO-4 (геo 4-босқич): рўйхат — яқиндагилар; ном бўйича қидирув —
/// бутун республика; яқинда йўқ бўлса «Бутун Ўзбекистон» тугмаси.
class _FakeRepo implements RestaurantsRepository {
  _FakeRepo(this.list);

  final List<Restaurant> list;
  final calls = <String>[];

  @override
  Stream<List<Restaurant>> watchApproved({int limit = 50}) {
    calls.add('approved:$limit');
    return Stream.value(list);
  }

  @override
  Stream<List<Restaurant>> watchNearby({
    required double lat,
    required double lng,
    double radiusKm = RestaurantsRepository.nearbyRadiusKm,
    int perCellLimit = 50,
  }) {
    calls.add('nearby');
    return Stream.value(
        RestaurantsRepository.withinRadius(list, lat, lng, radiusKm));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Restaurant _r(String id, {double? lat, double? lng}) => Restaurant(
      id: id,
      name: id,
      status: 'approved',
      lat: lat,
      lng: lng,
      prepTimeMin: 20,
      delivery: const RestaurantDelivery(mode: 'ava_courier', pickup: true),
    );

void main() {
  // Фойдаланувчи — Гурлан; «Тошкент» ресторани ~700 км.
  Widget host(_FakeRepo repo) => MaterialApp(
        home: RestaurantsListScreen(
          repository: repo,
          userLat: 41.84,
          userLng: 60.39,
          locate: () async => null,
        ),
      );

  testWidgets('яқинда йўқ — бўш ҳолат + «Бутун Ўзбекистон»; босилса ҳаммаси', (tester) async {
    final repo = _FakeRepo([_r('Toshkent', lat: 41.31, lng: 69.28)]);
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    expect(repo.calls.first, 'nearby');
    expect(find.text('Toshkent'), findsNothing);
    expect(find.text('restaurants_empty_nearby'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('restaurants_show_all')));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'approved:100');
    expect(find.text('Toshkent'), findsOneWidget);
  });

  testWidgets('ном бўйича қидирув — бутун республика ҳовузи; оқим ҳар ҳарфда қайта очилмайди', (tester) async {
    final repo = _FakeRepo([
      _r('Toshkent Plov', lat: 41.31, lng: 69.28),
      _r('Gurlan Somsa', lat: 41.845, lng: 60.39),
    ]);
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    expect(find.text('Gurlan Somsa'), findsOneWidget);
    expect(find.text('Toshkent Plov'), findsNothing);

    await tester.enterText(find.byType(TextField), 'pl');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'plov');
    await tester.pumpAndSettle();
    expect(find.text('Toshkent Plov'), findsOneWidget);
    expect(find.text('Gurlan Somsa'), findsNothing);
    expect(
      repo.calls.where(
          (c) => c == 'approved:${RestaurantsListScreen.searchPoolLimit}'),
      hasLength(1),
    );
  });
}

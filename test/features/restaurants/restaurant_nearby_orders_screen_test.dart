import 'package:ava_gurlan/features/restaurants/courier/restaurant_nearby_orders_screen.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Firestore/Functions'siz: faqat kuryer callable'lari va sozlama o'qish.
class _FakeRepo implements RestaurantsRepository {
  _FakeRepo({this.list = const [], this.prefs});

  List<NearbyRestaurantOrder> list;
  CourierBuyoutPrefs? prefs;
  Object? listError;
  Object? claimError;
  int listCalls = 0;
  int? lastRadius;
  double? lastLat;
  final claimed = <String>[];
  ({bool enabled, int limit})? saved;

  @override
  Future<List<NearbyRestaurantOrder>> listNearby({double? lat, double? lng, int? radiusKm}) async {
    listCalls++;
    lastRadius = radiusKm;
    lastLat = lat;
    final e = listError;
    if (e != null) throw e;
    return list;
  }

  @override
  Future<Map<String, dynamic>> claim(String orderId) async {
    claimed.add(orderId);
    final e = claimError;
    if (e != null) throw e;
    return {'ok': true};
  }

  @override
  Future<CourierBuyoutPrefs?> getBuyoutPrefs(String courierUid) async => prefs;

  @override
  Future<void> setBuyoutPrefs({required bool enabled, required int limit}) async {
    saved = (enabled: enabled, limit: limit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

NearbyRestaurantOrder _o(
  String id, {
  String status = 'ready',
  String food = 'prepay',
  int buyout = 0,
  String pay = 'cash',
  int fee = 8000,
  int? toRest = 1200,
  int? toCust = 3400,
}) =>
    NearbyRestaurantOrder(
      id: id,
      restaurantId: 'r',
      restaurantName: 'Osh $id',
      restaurantAddress: 'Markaz',
      restaurantStatus: status,
      deliveryFee: fee,
      deliveryPaymentMethod: pay,
      foodPaymentMethod: food,
      buyoutAmount: buyout,
      courierToRestaurantM: toRest,
      distanceMeters: toCust,
      prepTimeMin: 20,
    );

Future<({double lat, double lng})?> _gps() async => (lat: 41.84, lng: 60.39);

Future<void> _pump(WidgetTester t, _FakeRepo repo, {CourierLocate? locate}) async {
  await t.pumpWidget(MaterialApp(
    home: RestaurantNearbyOrdersScreen(courierUid: '998901234567', repository: repo, locate: locate ?? _gps),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('ro\'yxat: nom, holat, masofa, yetkazish, vykup belgisi; sozlama yuklanadi', (tester) async {
    final repo = _FakeRepo(
      list: [
        _o('a', status: 'ready', food: 'cash_buyout', buyout: 60000, pay: 'cash'),
        _o('b', status: 'accepted', pay: 'wallet'),
      ],
      prefs: const CourierBuyoutPrefs(enabled: true, limit: 100000),
    );
    await _pump(tester, repo);

    expect(repo.listCalls, 1);
    expect(repo.lastRadius, 15);
    expect(repo.lastLat, 41.84);
    expect(find.text('Osh a'), findsOneWidget);
    expect(find.text('Osh b'), findsOneWidget);
    expect(find.text('restaurants_courier_ready_badge'), findsOneWidget);
    expect(find.text('restaurants_courier_preparing'), findsOneWidget);
    expect(find.text('restaurants_courier_buyout_badge'), findsOneWidget, reason: 'faqat naqd buyurtmada');
    expect(find.text('restaurants_courier_fee_cash'), findsOneWidget);
    expect(find.text('restaurants_courier_fee_wallet'), findsOneWidget);
    expect(find.text('restaurants_courier_to_restaurant'), findsNWidgets(2));
    expect(find.text('restaurants_courier_no_gps'), findsNothing);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.widgetWithText(TextField, '100000'), findsOneWidget);
  });

  testWidgets('«Olish» → claim; ekran `true` bilan yopiladi', (tester) async {
    final repo = _FakeRepo(list: [_o('a')]);
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => RestaurantNearbyOrdersScreen(courierUid: 'u', repository: repo, locate: _gps),
            ));
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('restaurants_courier_claim'));
    await tester.pumpAndSettle();

    expect(repo.claimed, ['a']);
    expect(result, isTrue);
    expect(find.text('open'), findsOneWidget, reason: 'kuryer paneliga qaytdi');
  });

  testWidgets('claim xatosi (boshqa kuryer oldi) → xabar, ro\'yxat qayta yuklanadi, ekran ochiq', (tester) async {
    final repo = _FakeRepo(list: [_o('a')])
      ..claimError = const RestaurantsException('failed-precondition', 'COURIER_ASSIGNMENT_CONFLICT', 'conflict');
    await _pump(tester, repo);
    await tester.tap(find.text('restaurants_courier_claim'));
    await tester.pumpAndSettle();

    expect(repo.claimed, ['a']);
    expect(repo.listCalls, 2);
    // Lokalizatsiya yuklanmagan testda kalit matni qaytadi → umumiy xato matni.
    expect(find.text('restaurants_err_generic'), findsOneWidget);
    expect(find.byType(RestaurantNearbyOrdersScreen), findsOneWidget);
  });

  testWidgets('radius chipi → qayta so\'rov; bo\'sh ro\'yxat; GPS yo\'q', (tester) async {
    final repo = _FakeRepo(list: const []);
    await _pump(tester, repo, locate: () async => null);
    expect(find.text('restaurants_courier_empty'), findsOneWidget);
    expect(find.text('restaurants_courier_no_gps'), findsOneWidget);
    expect(repo.lastLat, isNull);

    await tester.tap(find.byType(ChoiceChip).first);
    await tester.pumpAndSettle();
    expect(repo.listCalls, 2);
    expect(repo.lastRadius, RestaurantNearbyOrdersScreen.radiusOptions.first);
  });

  testWidgets('ro\'yxat xatosi → matn + qayta urinish', (tester) async {
    final repo = _FakeRepo()..listError = const RestaurantsException('permission-denied', 'AUTH_REQUIRED', 'x');
    await _pump(tester, repo);
    expect(find.text('restaurants_err_generic'), findsOneWidget);
    repo.listError = null;
    await tester.tap(find.text('restaurants_courier_refresh').last);
    await tester.pumpAndSettle();
    expect(repo.listCalls, 2);
    expect(find.text('restaurants_courier_empty'), findsOneWidget);
  });

  testWidgets('vykup sozlamasi: yoqish + limit → setBuyoutPrefs', (tester) async {
    final repo = _FakeRepo(list: const []);
    await _pump(tester, repo);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.byType(TextField), findsNothing, reason: 'o\'chiq — limit maydoni yo\'q');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '80000');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(repo.saved, (enabled: true, limit: 80000));
    expect(find.text('restaurants_courier_prefs_saved'), findsOneWidget);
    expect(repo.listCalls, 2, reason: 'limit o\'zgardi — ro\'yxat qayta');
  });
}

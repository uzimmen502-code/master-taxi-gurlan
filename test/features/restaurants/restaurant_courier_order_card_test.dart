import 'dart:async';

import 'package:ava_gurlan/features/restaurants/courier/restaurant_courier_logic.dart';
import 'package:ava_gurlan/features/restaurants/courier/restaurant_courier_order_card.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faqat jonli buyurtma oqimi va restoran telefoni.
class _FakeRepo implements RestaurantsRepository {
  final live = StreamController<OrderModel?>.broadcast();

  @override
  Stream<OrderModel?> watchOrder(String orderId) => live.stream;

  @override
  Future<Restaurant?> getRestaurant(String id) async =>
      const Restaurant(id: 'r', name: 'Osh', contactPhone: '+998901234567');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

OrderModel _o({
  String rs = 'accepted',
  String food = 'prepay',
  String pay = 'cash',
  String paymentStatus = 'unpaid',
}) =>
    OrderModel(
      id: 'o1',
      type: 'restaurant',
      total: 69000,
      status: 'accepted',
      items: const [OrderItem(name: 'Osh', count: 2), OrderItem(name: 'Choy', count: 1)],
      userName: 'Mijoz',
      userPhone: '998900000001',
      address: 'Navoiy 1',
      lat: 41.9,
      lng: 60.5,
      restaurantId: 'r',
      restaurantName: 'Gurlan osh',
      restaurantAddress: 'Markaz',
      restaurantLat: 41.8,
      restaurantLng: 60.4,
      restaurantStatus: rs,
      foodPaymentMethod: food,
      deliveryPaymentMethod: pay,
      paymentStatus: paymentStatus,
      itemsTotal: 60000,
      packagingTotal: 1000,
      deliveryFee: 8000,
      prepTimeMin: 25,
    );

class _Calls {
  final pickups = <String>[];
  int arrives = 0;
  final completes = <({bool delivered, String failReason})>[];
  int finalizes = 0;
  Object? pickupError;
  Map<String, dynamic> completeResult = const {
    'outcome': 'delivered', 'deliveryFee': 8000, 'walletPaid': 0, 'cashCollected': 69000, 'deliveryPaymentMethod': 'cash',
  };
}

Future<_Calls> _pump(
  WidgetTester tester,
  OrderModel order, {
  required _FakeRepo repo,
  bool isCurrent = true,
  bool isDone = false,
  bool needsFinalize = false,
}) async {
  final calls = _Calls();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RestaurantCourierOrderCard(
          order: order,
          index: 0,
          isDone: isDone,
          isCurrent: isCurrent,
          needsFinalize: needsFinalize,
          repository: repo,
          onPickup: (code) async {
            calls.pickups.add(code);
            final e = calls.pickupError;
            if (e != null) throw e;
          },
          onArrive: () async => calls.arrives++,
          onComplete: ({required delivered, required failReason}) async {
            calls.completes.add((delivered: delivered, failReason: failReason));
            return CourierCompletionSummary.fromMap(calls.completeResult, order: order);
          },
          onFinalizeRoute: () async => calls.finalizes++,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('accepted: restoran nomi/manzili, «tayyorlanmoqda», olish tugmasi YO\'Q; ready kelganda JONLI paydo bo\'ladi', (tester) async {
    final repo = _FakeRepo();
    await _pump(tester, _o(rs: 'accepted'), repo: repo);

    expect(find.text('Gurlan osh'), findsOneWidget);
    expect(find.text('Markaz'), findsOneWidget);
    expect(find.text('restaurants_courier_preparing'), findsOneWidget);
    expect(find.text('restaurants_courier_call_restaurant'), findsOneWidget);
    expect(find.text('restaurants_courier_pickup_btn'), findsNothing);
    expect(find.text('restaurants_courier_fail_btn'), findsNothing, reason: 'hali qo\'lda emas');

    repo.live.add(_o(rs: 'ready'));
    await tester.pumpAndSettle();
    expect(find.text('restaurants_courier_pickup_btn'), findsOneWidget, reason: 'marshrut hujjati o\'zgarmaydi — karточка o\'zi yangilanadi');
    expect(find.text('restaurants_status_ready'), findsOneWidget);
  });

  testWidgets('ready + naqd: «restoranga to\'lang»; kod dialogi — noto\'g\'ri kod ochiq qoladi, to\'g\'risi yopadi', (tester) async {
    final repo = _FakeRepo();
    final calls = await _pump(tester, _o(rs: 'ready', food: 'cash_buyout'), repo: repo);
    expect(find.text('restaurants_courier_pay_restaurant'), findsOneWidget);
    expect(find.text('restaurants_courier_buyout_badge'), findsOneWidget);

    await tester.tap(find.text('restaurants_courier_pickup_btn'));
    await tester.pumpAndSettle();
    expect(find.text('restaurants_courier_pickup_title'), findsOneWidget);

    calls.pickupError = const RestaurantsException(
      'failed-precondition', 'PICKUP_CODE_MISMATCH', 'mismatch', details: {'attemptsLeft': 3},
    );
    await tester.enterText(find.byType(TextField), '1111');
    // Karточкадаги катта тугма ҳам шу матнда — диалогники охиргиси.
    await tester.tap(find.widgetWithText(FilledButton, 'restaurants_courier_pickup_btn').last);
    await tester.pumpAndSettle();
    expect(calls.pickups, ['1111']);
    expect(find.text('restaurants_courier_pickup_title'), findsOneWidget, reason: 'dialog ochiq');
    expect(find.text('restaurants_courier_pickup_wrong'), findsOneWidget);

    calls.pickupError = null;
    await tester.enterText(find.byType(TextField), '2222');
    await tester.tap(find.widgetWithText(FilledButton, 'restaurants_courier_pickup_btn').last);
    await tester.pumpAndSettle();
    expect(calls.pickups, ['1111', '2222']);
    expect(find.text('restaurants_courier_pickup_title'), findsNothing, reason: 'dialog yopildi');
  });

  testWidgets('picked: mijoz nomi/manzili, «yetib keldim» → onArrive; «yetkazib bo\'lmadi» sabab bilan → onComplete(failed)', (tester) async {
    final repo = _FakeRepo();
    final calls = await _pump(tester, _o(rs: 'picked'), repo: repo);
    expect(find.text('Mijoz'), findsOneWidget);
    expect(find.text('Navoiy 1'), findsOneWidget);
    expect(find.text('restaurants_courier_call_customer'), findsOneWidget);

    await tester.tap(find.text('restaurants_courier_arrive_btn'));
    await tester.pumpAndSettle();
    expect(calls.arrives, 1);

    await tester.tap(find.text('restaurants_courier_fail_btn'));
    await tester.pumpAndSettle();
    expect(find.text('restaurants_courier_fail_title'), findsOneWidget);
    await tester.tap(find.text('restaurants_courier_fail_customer_absent'));
    await tester.pumpAndSettle();
    expect(calls.completes, [(delivered: false, failReason: 'customer_absent')]);
    expect(find.text('restaurants_courier_failed_ok'), findsOneWidget);
    expect(calls.finalizes, 1, reason: 'yopilgach marshrut oldinga');
  });

  testWidgets('arrived + naqd: yig\'im 69 000; «topshirdim» → tasdiq → onComplete(delivered) → natija → finalize', (tester) async {
    final repo = _FakeRepo();
    final calls = await _pump(tester, _o(rs: 'arrived', food: 'cash_buyout', pay: 'cash'), repo: repo);
    expect(find.text('restaurants_courier_collect_title'), findsOneWidget);
    expect(find.text('restaurants_courier_collect_food'), findsOneWidget);
    expect(find.text('restaurants_courier_collect_fee'), findsOneWidget);
    expect(find.text('69 000 currency_sum'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'restaurants_courier_deliver_btn'));
    await tester.pumpAndSettle();
    expect(find.text('restaurants_courier_deliver_confirm'), findsOneWidget);
    expect(calls.completes, isEmpty, reason: 'tasdiqlanmaguncha chaqirilmaydi');

    await tester.tap(find.widgetWithText(FilledButton, 'restaurants_courier_deliver_btn').last);
    await tester.pumpAndSettle();
    expect(calls.completes, [(delivered: true, failReason: 'other')]);
    expect(find.text('restaurants_courier_delivered_ok'), findsOneWidget);
    expect(find.text('restaurants_courier_wallet_fallback'), findsNothing);

    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();
    expect(calls.finalizes, 1);
  });

  testWidgets('arrived + hamyon: yig\'im yo\'q; hamyon yetmasa natijada OGOHLANTIRISH', (tester) async {
    final repo = _FakeRepo();
    final calls = await _pump(tester, _o(rs: 'arrived', pay: 'wallet'), repo: repo);
    expect(find.text('restaurants_courier_collect_none'), findsOneWidget);
    expect(find.text('restaurants_courier_fee_from_wallet'), findsOneWidget);

    calls.completeResult = const {
      'outcome': 'delivered', 'deliveryFee': 8000, 'walletPaid': 0, 'cashCollected': 8000, 'deliveryPaymentMethod': 'cash',
    };
    await tester.tap(find.widgetWithText(FilledButton, 'restaurants_courier_deliver_btn'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'restaurants_courier_deliver_btn').last);
    await tester.pumpAndSettle();
    expect(find.text('restaurants_courier_wallet_fallback'), findsOneWidget);
  });

  testWidgets('yakunlangan: «keyingi buyurtma» → onFinalizeRoute; bekor bo\'lgan — izoh', (tester) async {
    final repo = _FakeRepo();
    final calls = await _pump(tester, _o(rs: 'delivery_failed'), repo: repo, isCurrent: false, isDone: true, needsFinalize: true);
    expect(find.text('restaurants_courier_cancelled_note'), findsOneWidget);
    expect(find.text('restaurants_courier_arrive_btn'), findsNothing);
    await tester.tap(find.text('courier_next_order'));
    await tester.pumpAndSettle();
    expect(calls.finalizes, 1);
  });

  testWidgets('navbatdagi (joriy emas) buyurtma — tugmalarsiz', (tester) async {
    final repo = _FakeRepo();
    await _pump(tester, _o(rs: 'ready'), repo: repo, isCurrent: false);
    expect(find.text('restaurants_courier_pickup_btn'), findsNothing);
    expect(find.text('restaurants_courier_call_restaurant'), findsNothing);
    expect(find.text('Gurlan osh'), findsOneWidget);
  });
}

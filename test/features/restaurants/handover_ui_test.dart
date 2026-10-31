// Буюртмани топшириш (эга, 2026-10-31): курьер карточкаси, код ойнаси, Б курьер
// диалоги, ресторан қайтариш панели ва соф мантиқ. Локализация делегати йўқ —
// `context.tr` калитнинг ўзини қайтаради.
//
//   flutter test test/features/restaurants/handover_ui_test.dart

import 'dart:async';

import 'package:ava_gurlan/features/restaurants/courier/restaurant_courier_logic.dart';
import 'package:ava_gurlan/features/restaurants/courier/restaurant_courier_order_card.dart';
import 'package:ava_gurlan/features/restaurants/courier/restaurant_handover_widgets.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/handover.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements RestaurantsRepository {
  final live = StreamController<OrderModel?>.broadcast();
  final starts = <String>[];
  int cancels = 0;
  HandoverStart next = HandoverStart(code: '482913', expiresAt: DateTime(2026, 10, 31, 18, 15));

  @override
  Stream<OrderModel?> watchOrder(String orderId) => live.stream;

  @override
  Future<HandoverStart> startHandover(String orderId, {required String target, double? lat, double? lng}) async {
    starts.add('$orderId/$target/${lat ?? '-'}');
    return next;
  }

  @override
  Future<void> cancelHandover(String orderId) async => cancels++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

OrderModel _o({String rs = 'picked', String food = 'prepay', String hoStatus = '', String hoTarget = ''}) => OrderModel(
      id: 'o1',
      type: 'restaurant',
      total: 69000,
      status: 'in_delivery',
      items: const [OrderItem(name: 'Osh', count: 1)],
      userName: 'Mijoz',
      address: 'Navoiy 1',
      restaurantId: 'r',
      restaurantName: 'Gurlan osh',
      restaurantAddress: 'Markaz',
      restaurantStatus: rs,
      foodPaymentMethod: food,
      deliveryPaymentMethod: 'cash',
      itemsTotal: 60000,
      deliveryFee: 8000,
      handoverStatus: hoStatus,
      handoverTarget: hoTarget,
    );

Future<void> _pumpCard(WidgetTester tester, _FakeRepo repo, OrderModel o) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RestaurantCourierOrderCard(
          order: o,
          index: 0,
          isDone: false,
          isCurrent: true,
          repository: repo,
          onPickup: (_) async {},
          onArrive: () async {},
          onComplete: ({required delivered, required failReason}) async =>
              CourierCompletionSummary.fromMap(const {'outcome': 'delivered'}, order: o),
          onFinalizeRoute: () async {},
          handoverLocation: () => (lat: 41.85, lng: 60.39),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('soф mantiq', () {
    test('HandoverStart.fromMap: kod, muddat, qo\'yib yuborish', () {
      final a = HandoverStart.fromMap({'ok': true, 'code': '123456', 'expiresAtMs': 1000});
      expect(a.code, '123456');
      expect(a.released, isFalse);
      expect(a.expiresAt, DateTime.fromMillisecondsSinceEpoch(1000));
      final b = HandoverStart.fromMap({'ok': true, 'released': true, 'searchUntilMs': 5});
      expect(b.released, isTrue);
      expect(b.code, '');
      expect(HandoverStart.fromMap({'code': 5}).code, '');
    });

    test('kim topshira oladi: accepted/ready/picked/arrived; «yetkazilmadi» kutilsa — yo\'q; vykup kuryerga — yo\'q', () {
      for (final s in ['accepted', 'ready', 'picked', 'arrived']) {
        expect(courierCanHandover(_o(rs: s)), isTrue, reason: s);
      }
      for (final s in ['placed', 'delivered', 'delivery_failed', 'rejected']) {
        expect(courierCanHandover(_o(rs: s)), isFalse, reason: s);
      }
      expect(handoverIsRelease(_o(rs: 'ready')), isTrue);
      expect(handoverIsRelease(_o(rs: 'picked')), isFalse);
      expect(handoverToCourierAllowed(_o(food: 'cash_buyout')), isFalse);
      expect(handoverToCourierAllowed(_o(rs: 'ready', food: 'cash_buyout')), isTrue);
      expect(isHandoverCode('012345'), isTrue);
      expect(isHandoverCode('12345'), isFalse);
      expect(isHandoverCode('12a456'), isFalse);
    });

    test('OrderModel: kutilayotgan topshirish', () {
      expect(_o(hoStatus: 'pending', hoTarget: 'seller').isReturnToSellerPending, isTrue);
      expect(_o(hoStatus: 'pending', hoTarget: 'courier').isReturnToSellerPending, isFalse);
      expect(_o().isHandoverPending, isFalse);
    });
  });

  group('kuryer kartasi', () {
    testWidgets('picked: «Topshirish» → kuryerga → kod oynasi (kod, muddat) → bekor qilish', (tester) async {
      final repo = _FakeRepo();
      await _pumpCard(tester, repo, _o());
      await tester.tap(find.text('restaurants_handover_btn'));
      await tester.pumpAndSettle();
      expect(find.text('restaurants_handover_title'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('handover-to-courier')));
      await tester.pumpAndSettle();
      expect(repo.starts, ['o1/courier/41.85']);
      expect(find.text('482913'), findsOneWidget);
      expect(find.text('restaurants_handover_code_courier'), findsOneWidget);
      await tester.tap(find.text('restaurants_handover_cancel'));
      await tester.pumpAndSettle();
      expect(repo.cancels, 1);
      expect(find.text('482913'), findsNothing);
    });

    testWidgets('vykup: «boshqa kuryerga» o\'chiq, izoh; restoranga ishlaydi', (tester) async {
      final repo = _FakeRepo();
      await _pumpCard(tester, repo, _o(food: 'cash_buyout'));
      await tester.tap(find.text('restaurants_handover_btn'));
      await tester.pumpAndSettle();
      expect(find.text('restaurants_handover_buyout_note'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('handover-to-courier')));
      await tester.pumpAndSettle();
      expect(repo.starts, isEmpty);
      await tester.tap(find.byKey(const ValueKey('handover-to-seller')));
      await tester.pumpAndSettle();
      expect(repo.starts, ['o1/seller/41.85']);
      expect(find.text('restaurants_handover_code_seller'), findsOneWidget);
    });

    testWidgets('ready (olinmagan): tasdiq → qo\'yib yuborish (kodsiz)', (tester) async {
      final repo = _FakeRepo()..next = const HandoverStart(released: true);
      await _pumpCard(tester, repo, _o(rs: 'ready'));
      await tester.tap(find.text('restaurants_handover_btn'));
      await tester.pumpAndSettle();
      expect(find.text('restaurants_handover_release_q'), findsOneWidget);
      await tester.tap(find.text('restaurants_handover_release_btn'));
      await tester.pumpAndSettle();
      expect(repo.starts, ['o1/seller/-']);
      expect(find.text('restaurants_handover_released'), findsOneWidget);
    });

    testWidgets('kutilayotgan topshirish: izoh va «kodni ko\'rsatish» (o\'sha maqsad bilan)', (tester) async {
      final repo = _FakeRepo();
      await _pumpCard(tester, repo, _o(hoStatus: 'pending', hoTarget: 'seller'));
      expect(find.text('restaurants_handover_pending_seller'), findsOneWidget);
      expect(find.text('restaurants_handover_btn'), findsNothing);
      await tester.tap(find.text('restaurants_handover_show_code'));
      await tester.pumpAndSettle();
      expect(repo.starts, ['o1/seller/41.85']);
      expect(find.text('482913'), findsOneWidget);
    });

    testWidgets('«yetkazilmadi» kutilayotganda «Topshirish» yo\'q', (tester) async {
      final repo = _FakeRepo();
      await _pumpCard(
        tester,
        repo,
        OrderModel(
          id: 'o1', type: 'restaurant', total: 1, status: 'in_delivery', items: const [],
          restaurantStatus: RestaurantOrderStatus.arrived, awaitingConfirmStep: 'delivery_failed',
        ),
      );
      expect(find.text('restaurants_handover_btn'), findsNothing);
    });
  });

  group('B kuryer va restoran', () {
    testWidgets('AcceptHandoverDialog: 6 xonasiz — izoh, serverga ketmaydi; xato — matn; muvaffaqiyat — yopiladi', (tester) async {
      final codes = <String>[];
      Object? err = const RestaurantsException('failed-precondition', 'HANDOVER_CODE_MISMATCH', 'x');
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: ctx,
                    builder: (_) => AcceptHandoverDialog(onSubmit: (c) async {
                      codes.add(c);
                      final e = err;
                      if (e != null) throw e;
                    }),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('handover-accept-code')), '123');
      await tester.tap(find.text('restaurants_handover_accept_btn'));
      await tester.pumpAndSettle();
      expect(codes, isEmpty);
      expect(find.text('restaurants_handover_code_hint'), findsWidgets);
      await tester.enterText(find.byKey(const ValueKey('handover-accept-code')), '123456');
      await tester.tap(find.text('restaurants_handover_accept_btn'));
      await tester.pumpAndSettle();
      expect(codes, ['123456']);
      // Lokalizatsiyasiz `restaurantsErrorText` umumiy kalitga tushadi; ichki kod ko'rinmaydi.
      expect(find.text('restaurants_err_generic'), findsOneWidget);
      expect(find.textContaining('HANDOVER_CODE_MISMATCH'), findsNothing);
      err = null;
      await tester.tap(find.text('restaurants_handover_accept_btn'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('MerchantReturnPanel: noto\'g\'ri kod — qolgan urinish; to\'g\'ri — yuboriladi va tozalanadi', (tester) async {
      final codes = <String>[];
      var fail = true;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MerchantReturnPanel(
            order: _o(hoStatus: 'pending', hoTarget: 'seller'),
            onSubmit: (c) async {
              codes.add(c);
              if (fail) {
                throw const RestaurantsException('failed-precondition', 'HANDOVER_CODE_MISMATCH', 'x', details: {'attemptsLeft': 3});
              }
            },
          ),
        ),
      ));
      final field = find.byKey(const ValueKey('return-code-o1'));
      await tester.enterText(field, '111111');
      await tester.tap(find.text('restaurants_m_return_btn'));
      await tester.pumpAndSettle();
      expect(find.text('restaurants_courier_pickup_wrong'), findsOneWidget);
      fail = false;
      await tester.enterText(field, '222222');
      await tester.tap(find.text('restaurants_m_return_btn'));
      await tester.pumpAndSettle();
      expect(codes, ['111111', '222222']);
      expect(find.text('restaurants_m_return_ok'), findsOneWidget);
    });
  });
}

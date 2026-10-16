import 'package:ava_gurlan/features/courier/controllers/courier_controller.dart';
import 'package:ava_gurlan/features/restaurants/courier/restaurant_courier_logic.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _o({
  String rs = 'accepted',
  String food = 'prepay',
  String pay = 'cash',
  int items = 60000,
  int pack = 1000,
  int fee = 8000,
  String paymentStatus = 'unpaid',
  double? rLat = 41.8,
  double? rLng = 60.4,
  double? lat = 41.9,
  double? lng = 60.5,
}) =>
    OrderModel(
      id: 'o',
      type: 'restaurant',
      total: items + pack + fee,
      status: 'new',
      items: const [],
      restaurantStatus: rs,
      foodPaymentMethod: food,
      deliveryPaymentMethod: pay,
      itemsTotal: items,
      packagingTotal: pack,
      deliveryFee: fee,
      paymentStatus: paymentStatus,
      restaurantLat: rLat,
      restaurantLng: rLng,
      lat: lat,
      lng: lng,
    );

void main() {
  group('courierStageFor — server jadvali bilan bir xil', () {
    test('holat → bosqich', () {
      expect(courierStageFor(_o(rs: 'placed')), CourierRestaurantStage.preparing);
      expect(courierStageFor(_o(rs: 'accepted')), CourierRestaurantStage.preparing);
      expect(courierStageFor(_o(rs: 'ready')), CourierRestaurantStage.pickup);
      expect(courierStageFor(_o(rs: 'picked')), CourierRestaurantStage.toCustomer);
      expect(courierStageFor(_o(rs: 'arrived')), CourierRestaurantStage.handover);
      expect(courierStageFor(_o(rs: 'delivered')), CourierRestaurantStage.done);
      for (final s in ['rejected', 'cancelled', 'delivery_failed']) {
        expect(courierStageFor(_o(rs: s)), CourierRestaurantStage.cancelled, reason: s);
      }
    });
    test('yakuniy — faqat terminal restaurantStatus; oldindan to\'langan picked TUGAMAGAN', () {
      for (final s in ['delivered', 'rejected', 'cancelled', 'delivery_failed']) {
        expect(isRestaurantOrderFinalized(_o(rs: s)), isTrue, reason: s);
        expect(CourierController.isOrderFinalized(_o(rs: s, paymentStatus: 'paid')), isTrue, reason: s);
      }
      final paidPicked = _o(rs: 'picked', paymentStatus: 'paid');
      expect(paidPicked.effectivePayment, 'paid');
      expect(isRestaurantOrderFinalized(paidPicked), isFalse);
      expect(CourierController.isOrderFinalized(paidPicked), isFalse, reason: 'eski `paid` belgisi restoran buyurtmasini yopmasin');
      // Eski (non) buyurtma — eski qoida o'zgarmagan.
      const bread = OrderModel(id: 'b', type: 'bread', total: 10000, status: 'in_delivery', items: [], paymentStatus: 'paid');
      expect(CourierController.isOrderFinalized(bread), isTrue);
      const breadOpen = OrderModel(id: 'b2', type: 'bread', total: 10000, status: 'in_delivery', items: [], fulfillmentStatus: 'arrived');
      expect(CourierController.isOrderFinalized(breadOpen), isFalse);
    });
    test('yetkazib bo\'lmadi — faqat qo\'ldagi buyurtmada', () {
      expect(courierCanFail(_o(rs: 'picked')), isTrue);
      expect(courierCanFail(_o(rs: 'arrived')), isTrue);
      expect(courierCanFail(_o(rs: 'ready')), isFalse);
      expect(courierCanFail(_o(rs: 'accepted')), isFalse);
    });
  });

  group('pul: vykup va mijozdan olinadigan naqd', () {
    test('cash_buyout → taom + qadoq; prepay → 0', () {
      expect(courierBuyoutAmount(_o(food: 'cash_buyout')), 61000);
      expect(courierBuyoutAmount(_o(food: 'prepay')), 0);
      expect(courierBuyoutAmount(_o(food: 'cash_to_restaurant')), 0);
    });
    test('naqd yig\'im: vykup + naqd yetkazish; hamyon yetkazish qo\'shilmaydi', () {
      expect(courierCashToCollect(_o(food: 'cash_buyout', pay: 'cash')), 69000);
      expect(courierCashToCollect(_o(food: 'cash_buyout', pay: 'wallet')), 61000);
      expect(courierCashToCollect(_o(food: 'prepay', pay: 'cash')), 8000);
      expect(courierCashToCollect(_o(food: 'prepay', pay: 'wallet')), 0);
    });
  });

  group('navigatsiya nishoni', () {
    test('olguncha — restoran, keyin — mijoz; koordinata yo\'q → null', () {
      expect(courierNavTarget(_o(rs: 'accepted')), (lat: 41.8, lng: 60.4));
      expect(courierNavTarget(_o(rs: 'ready')), (lat: 41.8, lng: 60.4));
      expect(courierNavTarget(_o(rs: 'picked')), (lat: 41.9, lng: 60.5));
      expect(courierNavTarget(_o(rs: 'arrived')), (lat: 41.9, lng: 60.5));
      expect(courierNavTarget(_o(rs: 'ready', rLat: null, rLng: null)), isNull);
      expect(courierNavTarget(_o(rs: 'picked', lat: null, lng: null)), isNull);
    });
  });

  group('CourierCompletionSummary.fromMap', () {
    test('hamyon yetmadi → naqdga tushdi (fallback) — oldingi holat `wallet`, natija `cash`', () {
      final s = CourierCompletionSummary.fromMap(
        {'ok': true, 'outcome': 'delivered', 'deliveryFee': 8000, 'walletPaid': 0, 'cashCollected': 8000, 'deliveryPaymentMethod': 'cash'},
        order: _o(rs: 'arrived', pay: 'wallet'),
      );
      expect(s.delivered, isTrue);
      expect(s.walletFallback, isTrue);
      expect(s.cashCollected, 8000);
      expect(s.deliveryFee, 8000);
    });
    test('hamyondan to\'landi → fallback emas; naqd 0', () {
      final s = CourierCompletionSummary.fromMap(
        {'outcome': 'delivered', 'deliveryFee': 8000, 'walletPaid': 8000, 'cashCollected': 0, 'deliveryPaymentMethod': 'wallet'},
        order: _o(rs: 'arrived', pay: 'wallet'),
      );
      expect(s.walletFallback, isFalse);
      expect(s.walletPaid, 8000);
      expect(s.cashCollected, 0);
    });
    test('mijoz tasdig\'i: awaitingCustomer true → kutish; maydon yo\'q (eski server) → kutish yo\'q', () {
      final wait = CourierCompletionSummary.fromMap(
        {'ok': true, 'awaitingCustomer': true, 'step': 'received'},
        order: _o(rs: 'arrived', pay: 'wallet'),
      );
      expect(wait.awaitingCustomer, isTrue);
      expect(wait.awaitingStep, 'received');
      expect(wait.delivered, isFalse, reason: 'hali yetkazilmagan');
      expect(wait.walletFallback, isFalse);

      final old = CourierCompletionSummary.fromMap(
        {'outcome': 'delivered', 'deliveryFee': 8000, 'walletPaid': 8000, 'cashCollected': 0, 'deliveryPaymentMethod': 'wallet'},
        order: _o(rs: 'arrived', pay: 'wallet'),
      );
      expect(old.awaitingCustomer, isFalse);
      expect(old.delivered, isTrue);
    });
    test('courierIsAwaitingCustomer: holat o\'zgarsa kutish yo\'qoladi; courierAwaitingFinished faqat kutishdan keyin', () {
      expect(courierIsAwaitingCustomer(_o(rs: 'arrived'), 'arrived'), isTrue);
      expect(courierIsAwaitingCustomer(_o(rs: 'delivered'), 'arrived'), isFalse);
      expect(courierIsAwaitingCustomer(_o(rs: 'arrived'), null), isFalse);
      expect(courierAwaitingFinished(_o(rs: 'delivered'), 'arrived'), isTrue);
      expect(courierAwaitingFinished(_o(rs: 'delivered'), null), isFalse,
          reason: 'kutish bo\'lmagan buyurtmada eski xatti-harakat');
      expect(courierAwaitingFinished(_o(rs: 'arrived'), 'arrived'), isFalse);
    });
    test('naqd buyurtma: fallback yo\'q; failed → delivered=false; deliveryFee bo\'lmasa buyurtmadan', () {
      final cash = CourierCompletionSummary.fromMap(
        {'outcome': 'delivered', 'walletPaid': 0, 'cashCollected': 69000, 'deliveryPaymentMethod': 'cash'},
        order: _o(rs: 'arrived', food: 'cash_buyout', pay: 'cash'),
      );
      expect(cash.walletFallback, isFalse);
      expect(cash.deliveryFee, 8000);
      final failed = CourierCompletionSummary.fromMap(
        {'outcome': 'failed', 'deliveryFee': 8000, 'walletPaid': 0, 'cashCollected': 0, 'deliveryPaymentMethod': 'wallet'},
        order: _o(rs: 'picked', pay: 'wallet'),
      );
      expect(failed.delivered, isFalse);
      expect(failed.walletFallback, isFalse);
    });
  });
}

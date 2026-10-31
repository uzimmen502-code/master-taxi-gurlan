// «Етказилмади» — мижоз тасдиғи билан (эга, 2026-10-31): ресторан қарори панели,
// мижоз карточкаси ва модел майдонлари. Локализация делегати йўқ — `context.tr`
// калитнинг ўзини қайтаради.
//
//   flutter test test/features/restaurants/delivery_failed_ui_test.dart

import 'package:ava_gurlan/features/customer_confirm/widgets/delivery_failed_order_card.dart';
import 'package:ava_gurlan/features/restaurants/courier/restaurant_courier_logic.dart';
import 'package:ava_gurlan/features/restaurants/merchant/merchant_orders_tab.dart';
import 'package:ava_gurlan/models/customer_confirm.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:ava_gurlan/services/customer_confirm_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _o({
  String rs = 'arrived',
  String step = 'delivery_failed',
  String reason = 'customer_absent',
  DateTime? deadline,
  bool escalated = false,
  String type = 'restaurant',
}) =>
    OrderModel(
      id: 'o1',
      type: type,
      total: 60000,
      status: 'in_delivery',
      items: const [],
      restaurantStatus: rs,
      awaitingConfirmStep: step,
      deliveryFailedReason: reason,
      deliveryFailedDeadline: deadline,
      deliveryFailedEscalated: escalated,
    );

class _FakeService implements CustomerConfirmService {
  final calls = <String>[];
  Object? error;

  @override
  Future<CustomerConfirmResult> confirm({
    required String module,
    required String id,
    required String step,
    bool reject = false,
    DateTime? requestedAt,
  }) async {
    calls.add('$module/$id/$step${reject ? '/reject' : ''}');
    final e = error;
    if (e != null) throw e;
    return const CustomerConfirmResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  final now = DateTime(2026, 10, 31, 18, 0);

  group('OrderModel: «yetkazilmadi» holati', () {
    test('kutish faqat restoran + delivery_failed + picked/arrived', () {
      expect(_o().isDeliveryFailedPending, isTrue);
      expect(_o(rs: 'picked').isDeliveryFailedPending, isTrue);
      expect(_o(rs: 'delivery_failed').isDeliveryFailedPending, isFalse);
      expect(_o(rs: 'delivered').isDeliveryFailedPending, isFalse);
      expect(_o(step: 'received').isDeliveryFailedPending, isFalse);
      expect(_o(type: 'bread').isDeliveryFailedPending, isFalse);
    });

    test('qaror ochiq: muddat o\'tgan (chegara: aynan muddat — ochiq) yoki eskalatsiya', () {
      expect(_o(deadline: now.add(const Duration(seconds: 1))).deliveryFailedDecisionOpen(now), isFalse);
      expect(_o(deadline: now).deliveryFailedDecisionOpen(now), isTrue);
      expect(_o(deadline: now.subtract(const Duration(minutes: 1))).deliveryFailedDecisionOpen(now), isTrue);
      expect(_o(escalated: true, deadline: now.add(const Duration(hours: 1))).deliveryFailedDecisionOpen(now), isTrue);
      expect(_o().deliveryFailedDecisionOpen(now), isFalse, reason: 'muddat noma\'lum — kutamiz');
      expect(_o(rs: 'delivery_failed', escalated: true).deliveryFailedDecisionOpen(now), isFalse);
    });

    test('awaitingField: map bo\'lmasa yoki matn bo\'lmasa bo\'sh', () {
      expect(OrderModel.awaitingField({'awaitingCustomerConfirm': {'step': 'delivery_failed'}}, 'step'), 'delivery_failed');
      expect(OrderModel.awaitingField({'awaitingCustomerConfirm': {'step': 5}}, 'step'), '');
      expect(OrderModel.awaitingField({'awaitingCustomerConfirm': 'x'}, 'step'), '');
      expect(OrderModel.awaitingField(const {}, 'step'), '');
    });

    test('kuryer: so\'rovdan keyin «yetkazib bo\'lmadi» yo\'q; yakunlansa «keyingi buyurtma»', () {
      expect(courierCanFail(_o(step: '')), isTrue);
      expect(courierCanFail(_o()), isFalse);
      expect(courierShowNext(needsFinalize: false, isCurrent: true, order: _o(rs: 'delivery_failed', step: '')), isTrue);
      expect(courierShowNext(needsFinalize: false, isCurrent: false, order: _o(rs: 'delivery_failed', step: '')), isFalse);
      expect(courierShowNext(needsFinalize: false, isCurrent: true, order: _o()), isFalse);
    });
  });

  group('MerchantDeliveryFailedPanel', () {
    testWidgets('muddatgacha: sabab va kutish matni, tugma YO\'Q', (tester) async {
      await tester.pumpWidget(_app(MerchantDeliveryFailedPanel(
        order: _o(deadline: now.add(const Duration(minutes: 10))),
        now: now,
        busy: false,
        onDecision: (_) {},
      )));
      expect(find.text('restaurants_m_failed_title'), findsOneWidget);
      expect(find.textContaining('restaurants_courier_fail_customer_absent'), findsOneWidget);
      expect(find.text('restaurants_m_failed_wait_customer'), findsOneWidget);
      expect(find.text('restaurants_m_failed_confirm_btn'), findsNothing);
      expect(find.text('restaurants_m_failed_continue_btn'), findsNothing);
    });

    testWidgets('muddat o\'tgach: ikki tugma — «kuryer yetkazsin» (false) va «yetkazilmadi» (true)', (tester) async {
      final got = <bool>[];
      await tester.pumpWidget(_app(MerchantDeliveryFailedPanel(
        order: _o(deadline: now.subtract(const Duration(minutes: 1))),
        now: now,
        busy: false,
        onDecision: got.add,
      )));
      expect(find.text('restaurants_m_failed_decide_now'), findsOneWidget);
      await tester.tap(find.text('restaurants_m_failed_continue_btn'));
      await tester.tap(find.text('restaurants_m_failed_confirm_btn'));
      expect(got, [false, true]);
    });

    testWidgets('band holatda tugmalar bosilmaydi', (tester) async {
      final got = <bool>[];
      await tester.pumpWidget(_app(MerchantDeliveryFailedPanel(
        order: _o(escalated: true),
        now: now,
        busy: true,
        onDecision: got.add,
      )));
      await tester.tap(find.text('restaurants_m_failed_confirm_btn'));
      expect(got, isEmpty);
    });
  });

  group('DeliveryFailedOrderCard (mijoz)', () {
    testWidgets('«Ha, olmadim» → confirm; «Olmoqchiman» → reject; muvaffaqiyat xabari', (tester) async {
      final svc = _FakeService();
      await tester.pumpWidget(_app(DeliveryFailedOrderCard(order: _o(), service: svc)));
      expect(find.text('customer_confirm_hint_delivery_failed'), findsOneWidget);
      await tester.tap(find.text('customer_confirm_btn_want_it'));
      await tester.pumpAndSettle();
      expect(find.text('customer_confirm_rejected_done'), findsOneWidget);
      await tester.tap(find.text('customer_confirm_btn_not_received'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['restaurant/o1/delivery_failed/reject', 'restaurant/o1/delivery_failed']);
    });

    testWidgets('server xatosi — do\'stona matn, ichki kod ko\'rinmaydi', (tester) async {
      final svc = _FakeService()..error = const CustomerConfirmException('failed-precondition', 'NOT_AWAITING');
      await tester.pumpWidget(_app(DeliveryFailedOrderCard(order: _o(), service: svc)));
      await tester.tap(find.text('customer_confirm_btn_not_received'));
      await tester.pumpAndSettle();
      expect(find.text('customer_confirm_err_not_awaiting'), findsOneWidget);
      expect(find.textContaining('NOT_AWAITING'), findsNothing);
    });

    test('elementi: sabab yo\'q bo\'lsa «other», canReject', () {
      final it = DeliveryFailedOrderCard.itemFor(_o(reason: ''));
      expect(it.failReason, 'other');
      expect(it.canReject, isTrue);
      expect(it.step, CustomerConfirmStep.deliveryFailed);
    });
  });
}

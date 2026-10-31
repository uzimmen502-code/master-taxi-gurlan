// «Етказилмади» — нон/бозор, гилам, сут, йиғиш (эга қарорлари 2026-10-31): моделлар, курьер тугмаси ва
// кутиш блоки, мижоз карточкаси (олиб кетишда «Ҳозир бераман»), сотувчи/админ қарор рўйхати.
// Локализация делегати йўқ — `context.tr` калитнинг ўзини қайтаради.
//
//   flutter test test/features/delivery_failed/delivery_failed_other_ui_test.dart

import 'package:ava_gurlan/features/courier/controllers/courier_controller.dart';
import 'package:ava_gurlan/features/courier/widgets/courier_order_tile.dart';
import 'package:ava_gurlan/features/customer_confirm/widgets/customer_confirm_card.dart';
import 'package:ava_gurlan/features/customer_confirm/widgets/delivery_failed_courier_controls.dart';
import 'package:ava_gurlan/features/customer_confirm/widgets/delivery_failed_decision_list.dart';
import 'package:ava_gurlan/features/customer_confirm/widgets/delivery_failed_order_card.dart';
import 'package:ava_gurlan/models/customer_confirm.dart';
import 'package:ava_gurlan/models/delivery_failed.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:ava_gurlan/services/customer_confirm_service.dart';
import 'package:ava_gurlan/services/delivery_failed_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _bread({
  String fs = 'arrived',
  String status = 'in_delivery',
  String step = 'delivery_failed',
  String module = 'order',
  String payment = 'unpaid',
  String type = 'bread',
}) =>
    OrderModel(
      id: 'b1',
      type: type,
      total: 33000,
      status: status,
      items: const [],
      fulfillmentStatus: fs,
      paymentStatus: payment,
      awaitingConfirmStep: step,
      deliveryFailedModule: module,
      deliveryFailedReason: 'customer_absent',
    );

class _FakeDf implements DeliveryFailedService {
  final calls = <String>[];
  List<DeliveryFailedPendingItem> items = const [];
  Object? error;

  @override
  Future<List<DeliveryFailedPendingItem>> listPending() async {
    calls.add('list');
    final e = error;
    if (e != null) throw e;
    return items;
  }

  @override
  Future<void> resolve({required String module, required String id, required bool failed}) async {
    calls.add('resolve/$module/$id/${failed ? 'failed' : 'continue'}');
  }

  @override
  Future<CourierActionResult> report({required String module, required String id, required String reason}) async {
    calls.add('report/$module/$id/$reason');
    return const CourierActionResult(awaitingCustomer: true, step: 'delivery_failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FakeCc implements CustomerConfirmService {
  final calls = <String>[];

  @override
  Future<CustomerConfirmResult> confirm({
    required String module,
    required String id,
    required String step,
    bool reject = false,
    DateTime? requestedAt,
  }) async {
    calls.add('$module/$id/$step${reject ? '/reject' : ''}');
    return const CustomerConfirmResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

DeliveryFailedPendingItem _item(String module, String id, {bool canDecide = true, DateTime? escalateAt}) =>
    DeliveryFailedPendingItem(
      module: module,
      id: id,
      leg: module == 'order' ? 'delivery' : 'pickup',
      failReason: 'customer_refused',
      canDecide: canDecide,
      escalateAt: escalateAt,
      customerName: 'Mijoz',
      customerPhoneTail: '0301',
      total: module == 'order' ? 33000 : null,
    );

void main() {
  group('Model: DeliveryFailedState / PendingItem / xato kalitlari', () {
    test('fromCallable: belgi yo\'q — kutish yo\'q; bor — sabab, muddat, eskalatsiya', () {
      expect(DeliveryFailedState.fromCallable({'status': 'pickup_in_delivery'}).pending, isFalse);
      expect(DeliveryFailedState.fromCallable({'deliveryFailedPending': 'true'}).pending, isFalse, reason: 'qat\'iy bool');
      final s = DeliveryFailedState.fromCallable({
        'deliveryFailedPending': true,
        'deliveryFailedReason': 'customer_absent',
        'deliveryFailedEscalateAtMs': 1000,
        'deliveryFailedEscalated': true,
      }, leg: 'return');
      expect(s.pending, isTrue);
      expect(s.reason, 'customer_absent');
      expect(s.deadline, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(s.escalated, isTrue);
      expect(s.leg, 'return');
      expect(s.isPickup, isFalse);
    });

    test('fromDoc: faqat SHU modul belgisi (restoran belgisi va boshqa qadam — yo\'q)', () {
      final at = Timestamp.fromMillisecondsSinceEpoch(5000);
      final d = {
        'awaitingCustomerConfirm': {'step': 'delivery_failed', 'module': 'carpet', 'leg': 'pickup', 'failReason': 'other', 'escalateAt': at},
      };
      final s = DeliveryFailedState.fromDoc(d, 'carpet');
      expect(s.pending, isTrue);
      expect(s.isPickup, isTrue);
      expect(s.deadline, at.toDate());
      expect(s.escalated, isFalse);
      expect(DeliveryFailedState.fromDoc(d, 'agro').pending, isFalse);
      expect(DeliveryFailedState.fromDoc({'awaitingCustomerConfirm': {'step': 'delivery_failed'}}, 'carpet').pending, isFalse,
          reason: 'restoran shakli (module yo\'q)');
      expect(DeliveryFailedState.fromDoc({'awaitingCustomerConfirm': {'step': 'handover_pickup', 'module': 'carpet'}}, 'carpet').pending, isFalse);
      expect(DeliveryFailedState.fromDoc(const {}, 'carpet').pending, isFalse);
    });

    test('PendingItem: buzuq element tashlanadi, takror bitta, maydonlar o\'qiladi', () {
      final l = DeliveryFailedPendingItem.listFromResponse({
        'items': [
          {'module': 'order', 'id': 'a', 'canDecide': true, 'total': 33000, 'escalateAtMs': 1000, 'failReason': ''},
          {'module': 'order', 'id': 'a'},
          {'module': '', 'id': 'x'},
          'junk',
          {'module': 'carpet', 'id': 'c', 'leg': 'return'},
        ],
      });
      expect(l.map((e) => e.key), ['order/a', 'carpet/c']);
      expect(l.first.canDecide, isTrue);
      expect(l.first.total, 33000);
      expect(l.first.failReason, 'other');
      expect(l.last.canDecide, isFalse);
      expect(DeliveryFailedPendingItem.listFromResponse(null), isEmpty);
      expect(deliveryFailedModuleKey('carpet', 'return'), 'delivery_failed_module_carpet_return');
      expect(deliveryFailedModuleKey('carpet', 'pickup'), 'delivery_failed_module_carpet_pickup');
    });

    test('xato kalitlari: ichki kod ko\'rsatilmaydi', () {
      expect(deliveryFailedErrorKey('DF_ARRIVE_FIRST'), 'delivery_failed_err_arrive_first');
      expect(deliveryFailedErrorKey('DF_PAYMENT_SUBMITTED'), 'delivery_failed_err_paid');
      expect(deliveryFailedErrorKey('DECISION_NOT_YET'), 'delivery_failed_err_not_yet');
      expect(deliveryFailedErrorKey('DF_NOT_AWAITING_DECISION'), 'delivery_failed_err_state');
      expect(deliveryFailedErrorKey('DF_NOT_ALLOWED'), 'delivery_failed_err_not_allowed');
      expect(deliveryFailedErrorKey('WHATEVER'), 'delivery_failed_err_generic');
      expect(deliveryFailedReasonKey('bogus'), 'restaurants_courier_fail_other');
      expect(deliveryFailedReasonKey('customer_absent'), 'restaurants_courier_fail_customer_absent');
    });
  });

  group('OrderModel (non/bozor)', () {
    test('kutish: faqat non/bozor + module order + in_delivery + picked/arrived', () {
      expect(_bread().isOrderDeliveryFailedPending, isTrue);
      expect(_bread(fs: 'courier_picked').isOrderDeliveryFailedPending, isTrue);
      expect(_bread(module: '').isOrderDeliveryFailedPending, isFalse, reason: 'restoran shakli');
      expect(_bread(type: 'restaurant').isOrderDeliveryFailedPending, isFalse);
      expect(_bread(fs: 'completed').isOrderDeliveryFailedPending, isFalse);
      expect(_bread(step: 'received').isOrderDeliveryFailedPending, isFalse);
    });

    test('kuryer xabar bera oladi: yo\'lda/yetib kelgan, kutish yo\'q, to\'lov yuborilmagan (chegara)', () {
      expect(_bread(step: '').courierCanReportOrderFailed, isTrue);
      expect(_bread(step: '', fs: 'courier_picked').courierCanReportOrderFailed, isTrue);
      expect(_bread().courierCanReportOrderFailed, isFalse, reason: 'allaqachon kutilmoqda');
      expect(_bread(step: '', payment: 'payment_pending_confirm').courierCanReportOrderFailed, isFalse);
      expect(_bread(step: '', fs: 'ready', status: 'ready').courierCanReportOrderFailed, isFalse);
      expect(_bread(step: '', type: 'restaurant').courierCanReportOrderFailed, isFalse);
    });

    test('yakun: delivery_failed → isOrderFinalized (eski snapshot ham «keyingi buyurtma»)', () {
      final f = _bread(step: '', fs: 'delivery_failed', status: 'cancelled');
      expect(f.isOrderDeliveryFailedFinal, isTrue);
      expect(CourierController.isOrderFinalized(f), isTrue);
      expect(CourierController.isOrderFinalized(_bread()), isFalse, reason: 'kutishda — hali yakun emas');
    });
  });

  group('Kuryer tugmasi va kutish bloki', () {
    testWidgets('tugma → sabab varag\'i → onReport(sabab)', (tester) async {
      String? got;
      await tester.pumpWidget(_app(DeliveryFailedCourierControls(
        state: DeliveryFailedState.none,
        canReport: true,
        onReport: (r) async => got = r,
      )));
      expect(find.text('restaurants_courier_fail_btn'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('df-report')));
      await tester.pumpAndSettle();
      expect(find.text('delivery_failed_note_confirm'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('df-reason-customer_refused')));
      await tester.pumpAndSettle();
      expect(got, 'customer_refused');
    });

    testWidgets('olib ketish: «Olib bo\'lmadi» matni; canReport=false — tugma yo\'q', (tester) async {
      await tester.pumpWidget(_app(DeliveryFailedCourierControls(
        state: DeliveryFailedState.none,
        canReport: true,
        pickup: true,
        onReport: (_) async {},
      )));
      expect(find.text('delivery_failed_btn_pickup'), findsOneWidget);
      await tester.pumpWidget(_app(DeliveryFailedCourierControls(
        state: DeliveryFailedState.none,
        canReport: false,
        onReport: (_) async {},
      )));
      expect(find.byKey(const ValueKey('df-report')), findsNothing);
    });

    testWidgets('kutish: muddat bilan — vaqt; eskalatsiya — sotuvchi/admin matni; tugma yo\'q', (tester) async {
      await tester.pumpWidget(_app(DeliveryFailedCourierControls(
        state: DeliveryFailedState(pending: true, reason: 'customer_absent', deadline: DateTime(2026, 10, 31, 18, 5)),
        canReport: true,
        onReport: (_) async {},
      )));
      expect(find.byKey(const ValueKey('df-waiting')), findsOneWidget);
      expect(find.text('delivery_failed_wait_until'), findsOneWidget, reason: 'kalit — {time} o\'rinbosarsiz');
      expect(find.byKey(const ValueKey('df-report')), findsNothing);
      await tester.pumpWidget(_app(DeliveryFailedCourierControls(
        state: const DeliveryFailedState(pending: true, escalated: true),
        canReport: true,
        decider: 'seller',
        onReport: (_) async {},
      )));
      expect(find.text('delivery_failed_wait_seller'), findsOneWidget);
      await tester.pumpWidget(_app(DeliveryFailedCourierControls(
        state: const DeliveryFailedState(pending: true, escalated: true),
        canReport: true,
        onReport: (_) async {},
      )));
      expect(find.text('delivery_failed_wait_admin'), findsOneWidget);
    });

    testWidgets('non buyurtma plitkasi: joriy + yetib kelgan → tugma; kutishda → blok', (tester) async {
      final reported = <String>[];
      Widget tile(OrderModel o) => _app(CourierOrderTile(
            order: o,
            index: 0,
            isDone: false,
            isCurrent: true,
            onPicked: () async {},
            onArrived: () async {},
            onPayment: (_) async => <String, dynamic>{},
            onFinalizeRoute: () async {},
            onReportFailed: (r) async => reported.add(r),
          ));
      await tester.pumpWidget(tile(_bread(step: '')));
      expect(find.byKey(const ValueKey('df-report')), findsOneWidget);
      await tester.pumpWidget(tile(_bread()));
      expect(find.byKey(const ValueKey('df-waiting')), findsOneWidget);
      expect(find.text('delivery_failed_status_pending'), findsOneWidget);
      // Eski chaqiruvchi (onReportFailed yo'q) — tugma ham, blok ham yo'q.
      await tester.pumpWidget(_app(CourierOrderTile(
        order: _bread(step: ''),
        index: 0,
        isDone: false,
        isCurrent: true,
        onPicked: () async {},
        onArrived: () async {},
        onPayment: (_) async => <String, dynamic>{},
        onFinalizeRoute: () async {},
      )));
      expect(find.byKey(const ValueKey('df-report')), findsNothing);
    });
  });

  group('Mijoz kartochkasi', () {
    testWidgets('olib ketish (pickup): «Ha, bermadim» / «Hozir beraman»; rad → reject chaqiruvi', (tester) async {
      final svc = _FakeCc();
      await tester.pumpWidget(_app(DeliveryFailedConfirmCard(
        item: DeliveryFailedConfirmCard.taskItem(module: 'agro', id: 'a1', failReason: 'customer_absent', leg: 'pickup'),
        service: svc,
      )));
      expect(find.text('customer_confirm_btn_not_given'), findsOneWidget);
      expect(find.text('customer_confirm_btn_ready_to_give'), findsOneWidget);
      expect(find.text('customer_confirm_hint_delivery_failed_pickup'), findsOneWidget);
      await tester.tap(find.text('customer_confirm_btn_ready_to_give'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['agro/a1/delivery_failed/reject']);
      expect(find.text('customer_confirm_ready_to_give_done'), findsOneWidget);
    });

    testWidgets('non buyurtmasi: modul order, «Ha, olmadim» → confirm', (tester) async {
      final svc = _FakeCc();
      await tester.pumpWidget(_app(DeliveryFailedOrderCard(order: _bread(), service: svc)));
      expect(find.text('customer_confirm_btn_not_received'), findsOneWidget);
      expect(find.text('customer_confirm_btn_want_it'), findsOneWidget);
      await tester.tap(find.text('customer_confirm_btn_not_received'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['order/b1/delivery_failed']);
      expect(DeliveryFailedOrderCard.itemFor(_bread(type: 'restaurant')).module, 'restaurant', reason: 'restoran o\'zgarmaydi');
    });

    test('modul kaliti: order', () {
      expect(customerConfirmModuleKey('order'), 'customer_confirm_module_order');
      expect(customerConfirmButtonKey('delivery_failed'), 'customer_confirm_btn_not_received');
      expect(customerConfirmButtonKey('delivery_failed', leg: 'pickup'), 'customer_confirm_btn_not_given');
      expect(customerConfirmButtonKey('handover_pickup', leg: 'pickup'), 'customer_confirm_btn_handover');
      final c = CustomerConfirmation.fromMap({
        'module': 'carpet', 'id': 'c1', 'step': 'delivery_failed', 'canReject': true,
        'details': {'failReason': 'other', 'leg': 'return'},
      })!;
      expect(c.leg, 'return');
      expect(c.rejectButtonKey, 'customer_confirm_btn_want_it');
      expect(const CustomerConfirmCard(item: CustomerConfirmation(module: 'x', id: 'y', step: 'z'), busy: false, onConfirm: _noop), isNotNull);
    });
  });

  group('Sotuvchi / admin qaror ro\'yxati', () {
    testWidgets('muddatgacha tugmalar o\'chiq; muddatdan keyin «Yetkazilmadi» → tasdiq dialogi → resolve(failed); «Davom etsin» → continue', (tester) async {
      final svc = _FakeDf()
        ..items = [
          _item('order', 'o1'),
          _item('carpet', 'c1', canDecide: false, escalateAt: DateTime(2030, 1, 1, 10, 0)),
        ];
      await tester.pumpWidget(_app(DeliveryFailedDecisionList(service: svc, now: () => DateTime(2026, 10, 31, 12))));
      await tester.pumpAndSettle();
      expect(find.text('delivery_failed_decide_title'), findsOneWidget);
      expect(find.text('Mijoz · ***0301'), findsNWidgets(2));
      expect(find.text('delivery_failed_decide_wait_until'), findsOneWidget);
      final blocked = tester.widget<FilledButton>(find.byKey(const ValueKey('df-failed-carpet/c1')));
      expect(blocked.onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('df-failed-order/o1')));
      await tester.pumpAndSettle();
      expect(find.text('delivery_failed_decide_failed_body_order'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('df-confirm-failed')));
      await tester.pumpAndSettle();
      expect(svc.calls, contains('resolve/order/o1/failed'));
      await tester.tap(find.byKey(const ValueKey('df-continue-order/o1')));
      await tester.pumpAndSettle();
      expect(svc.calls, contains('resolve/order/o1/continue'));
      expect(svc.calls.where((c) => c == 'list').length, greaterThanOrEqualTo(3), reason: 'har qarordan keyin yangilanadi');
    });

    testWidgets('dialogda «bekor» — chaqiruv YO\'Q', (tester) async {
      final svc = _FakeDf()..items = [_item('order', 'o1')];
      await tester.pumpWidget(_app(DeliveryFailedDecisionList(service: svc)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('df-failed-order/o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(svc.calls.where((c) => c.startsWith('resolve')), isEmpty);
    });

    testWidgets('sotuvchi kassasi (hideWhenEmpty): bo\'sh yoki rad (DF_NOT_ALLOWED) — hech narsa ko\'rinmaydi', (tester) async {
      final svc = _FakeDf();
      await tester.pumpWidget(_app(DeliveryFailedDecisionList(service: svc, hideWhenEmpty: true)));
      await tester.pumpAndSettle();
      expect(find.text('delivery_failed_decide_title'), findsNothing);
      final denied = _FakeDf()..error = const DeliveryFailedException('permission-denied', 'DF_NOT_ALLOWED');
      await tester.pumpWidget(_app(DeliveryFailedDecisionList(key: const ValueKey('seller-denied'), service: denied, hideWhenEmpty: true)));
      await tester.pumpAndSettle();
      expect(find.text('delivery_failed_err_not_allowed'), findsNothing);
      await tester.pumpWidget(_app(DeliveryFailedDecisionList(key: const ValueKey('admin'), service: denied)));
      await tester.pumpAndSettle();
      expect(find.text('delivery_failed_err_not_allowed'), findsOneWidget, reason: 'admin ekranida xato ko\'rinadi');
    });
  });
}

void _noop() {}

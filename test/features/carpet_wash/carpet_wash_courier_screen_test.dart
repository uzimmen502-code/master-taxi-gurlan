import 'package:ava_gurlan/features/carpet_wash/screens/carpet_wash_courier_screen.dart';
import 'package:ava_gurlan/models/carpet_wash_order.dart';
import 'package:ava_gurlan/services/carpet_wash_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Гилам курьер экрани вазифаларни `courierListCarpetTasks` callable'дан
/// олади: `carpet_wash_orders` қоидаси capability курьерга тўғридан-тўғри
/// рўйхат бермайди (functions/test/carpet_agro_courier_rules.test.js).
/// Аввалги StreamBuilder рад жавобини «вазифа йўқ» деб кўрсатарди.
///
/// Локализация делегати атайлаб йўқ — `context.tr` калитнинг ўзини
/// қайтаради (test/features/demand_offer/service_ui_adapter_test.dart).
const _courier = '998901110001';
const _customer = '998905550005';

class _FakeCarpetService implements CarpetWashService {
  _FakeCarpetService(this.responses);

  /// `list` → навбатдаги жавоблар (рўйхат ёки хато); охиргиси такрорланади.
  final Map<String, List<Object>> responses;
  final Map<String, int> listCalls = {};
  final List<String> calls = [];
  Object? actionError;

  @override
  Future<List<CarpetWashOrder>> listCourierTasks(String list) async {
    final n = listCalls[list] ?? 0;
    listCalls[list] = n + 1;
    final rs = responses[list] ?? const [<CarpetWashOrder>[]];
    final r = rs[n < rs.length ? n : rs.length - 1];
    if (r is List<CarpetWashOrder>) return r;
    throw r;
  }

  Future<void> _record(String call) async {
    calls.add(call);
    final e = actionError;
    if (e != null) throw e;
  }

  @override
  Future<void> courierClaimPickup({
    required String courierPhone,
    required String orderId,
  }) =>
      _record('claimPickup:$courierPhone:$orderId');

  @override
  Future<void> courierClaimReturn({
    required String courierPhone,
    required String orderId,
  }) =>
      _record('claimReturn:$courierPhone:$orderId');

  @override
  Future<void> courierMarkArrived({
    required String courierPhone,
    required String orderId,
    required String leg,
  }) =>
      _record('arrived:$courierPhone:$orderId:$leg');

  @override
  Future<void> courierMarkPickedUp({
    required String courierPhone,
    required String orderId,
  }) =>
      _record('pickedUp:$courierPhone:$orderId');

  @override
  Future<void> courierMarkDelivered({
    required String courierPhone,
    required String orderId,
  }) =>
      _record('delivered:$courierPhone:$orderId');

  @override
  Future<String> placeOrder({
    required int carpetCount,
    required String pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String note = '',
    String? idempotencyKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> adminSetStatus({
    required String adminPhone,
    required String orderId,
    required String status,
    int? finalPrice,
  }) =>
      throw UnimplementedError();
}

/// Олиш рўйхати элементи — сервер шакли (мижоз майдонлари йўқ).
CarpetWashOrder _preview(String id, int count) =>
    CarpetWashService.courierTaskFromMap(
      {'id': id, 'carpetCount': count, 'createdAtMs': 1000},
      fallbackStatus: CarpetWashOrder.statusPickupReady,
    );

/// «Фаол» элементи — вазифа олингандан кейинги сервер шакли.
CarpetWashOrder _active(
  String id, {
  String status = CarpetWashOrder.statusPickupInDelivery,
  int? pickupArrivedAtMs,
  int? returnArrivedAtMs,
}) =>
    CarpetWashService.courierTaskFromMap({
      'id': id,
      'status': status,
      'carpetCount': 3,
      'pickupAddress': 'Navoiy ko\'chasi 7',
      'customerName': 'Mijoz Ismi',
      'customerPhone': _customer,
      'pickupArrivedAtMs': pickupArrivedAtMs,
      'returnArrivedAtMs': returnArrivedAtMs,
      'createdAtMs': 1000,
    });

Future<void> _pump(WidgetTester tester, _FakeCarpetService service) async {
  SharedPreferences.setMockInitialValues({'user_phone': _courier});
  await tester.pumpWidget(MaterialApp(
    home: CarpetWashCourierScreen(service: service),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String key) async {
  await tester.tap(find.text(key));
  await tester.pumpAndSettle();
}

void main() {
  test('courierTaskFromMap: olish ro\'yxati — mijoz maydonlari bo\'sh', () {
    final o = _preview('p1', 4);
    expect(o.id, 'p1');
    expect(o.carpetCount, 4);
    expect(o.status, CarpetWashOrder.statusPickupReady);
    expect(o.createdAt, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(o.customerPhone, isEmpty);
    expect(o.customerName, isEmpty);
    expect(o.pickupAddress, isEmpty);
    expect(o.note, isEmpty);
  });

  test('courierTaskFromMap: «Faol» — ish maydonlari va belgilar', () {
    final o = _active(
      'a1',
      status: CarpetWashOrder.statusReturnInDelivery,
      returnArrivedAtMs: 2500,
    );
    expect(o.status, CarpetWashOrder.statusReturnInDelivery);
    expect(o.customerPhone, _customer);
    expect(o.pickupAddress, 'Navoiy ko\'chasi 7');
    expect(o.pickupArrivedAt, isNull);
    expect(o.returnArrivedAt, DateTime.fromMillisecondsSinceEpoch(2500));
  });

  testWidgets('olish ro\'yxati: faqat gilam soni — telefon, ism, manzil, qo\'ng\'iroq YO\'Q',
      (tester) async {
    final service = _FakeCarpetService({
      CarpetWashService.courierListPickup: [
        [_preview('p1', 3)],
      ],
    });
    await _pump(tester, service);

    expect(service.listCalls[CarpetWashService.courierListPickup], 1);
    expect(find.text('3 carpet_count_suffix'), findsOneWidget);
    expect(find.text('courier_task_details_after_claim'), findsOneWidget);
    expect(find.text('carpet_claim_pickup'), findsOneWidget);
    expect(find.byIcon(Icons.call), findsNothing);
    expect(find.textContaining(_customer), findsNothing);
  });

  testWidgets('olish: claim serverga ketadi, ro\'yxat yangilanadi, «Faol»da manzil va telefon',
      (tester) async {
    final service = _FakeCarpetService({
      CarpetWashService.courierListPickup: [
        [_preview('p1', 3)],
        <CarpetWashOrder>[],
      ],
      CarpetWashService.courierListActive: [
        [_active('p1')],
      ],
    });
    await _pump(tester, service);

    await tester.tap(find.text('carpet_claim_pickup'));
    await tester.pumpAndSettle();
    expect(service.calls, ['claimPickup:$_courier:p1']);
    expect(service.listCalls[CarpetWashService.courierListPickup], 2);
    expect(find.text('carpet_no_pickup_tasks'), findsOneWidget);

    await _openTab(tester, 'carpet_active_tab');
    expect(find.text('carpet_pickup_in_progress'), findsOneWidget);
    expect(find.text('Navoiy ko\'chasi 7'), findsOneWidget);
    expect(find.text('Mijoz Ismi · $_customer'), findsOneWidget);
    expect(find.byIcon(Icons.call), findsOneWidget);
    expect(find.text('courier_arrived_btn'), findsOneWidget);
  });

  testWidgets('qaytarish: claim return callable\'ini chaqiradi', (tester) async {
    final service = _FakeCarpetService({
      CarpetWashService.courierListReturn: [
        [_preview('r1', 2)],
        <CarpetWashOrder>[],
      ],
    });
    await _pump(tester, service);
    await _openTab(tester, 'carpet_return_tab');

    expect(find.text('2 carpet_count_suffix'), findsOneWidget);
    expect(find.byIcon(Icons.call), findsNothing);
    await tester.tap(find.text('carpet_claim_return'));
    await tester.pumpAndSettle();
    expect(service.calls, ['claimReturn:$_courier:r1']);
    expect(find.text('carpet_no_return_tasks'), findsOneWidget);
  });

  testWidgets('«Faol»: yetib keldim → olib ketildi; qaytarishda → yetkazildi',
      (tester) async {
    final service = _FakeCarpetService({
      CarpetWashService.courierListActive: [
        [_active('a1')],
        [_active('a1', pickupArrivedAtMs: 2000)],
        [
          _active(
            'b1',
            status: CarpetWashOrder.statusReturnInDelivery,
            returnArrivedAtMs: 3000,
          ),
        ],
      ],
    });
    await _pump(tester, service);
    await _openTab(tester, 'carpet_active_tab');

    await tester.tap(find.text('courier_arrived_btn'));
    await tester.pumpAndSettle();
    expect(service.calls, ['arrived:$_courier:a1:pickup']);

    await tester.tap(find.text('carpet_mark_picked_up'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'pickedUp:$_courier:a1');

    expect(find.text('carpet_return_in_progress'), findsOneWidget);
    await tester.tap(find.text('carpet_mark_delivered'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'delivered:$_courier:b1');
  });

  testWidgets('rad etilgan claim: xabar ko\'rsatiladi va ro\'yxat baribir yangilanadi',
      (tester) async {
    final service = _FakeCarpetService({
      CarpetWashService.courierListPickup: [
        [_preview('p1', 3)],
        <CarpetWashOrder>[],
      ],
    })
      ..actionError = Exception('already claimed');
    await _pump(tester, service);

    await tester.tap(find.text('carpet_claim_pickup'));
    await tester.pumpAndSettle();
    expect(find.text('Exception: already claimed'), findsOneWidget);
    expect(service.listCalls[CarpetWashService.courierListPickup], 2);
    expect(find.text('carpet_no_pickup_tasks'), findsOneWidget);
  });

  testWidgets('xato «vazifa yo\'q» deb yashirilmaydi, pull-to-refresh qayta oladi',
      (tester) async {
    final service = _FakeCarpetService({
      CarpetWashService.courierListPickup: [
        Exception('permission-denied'),
        [_preview('p1', 3)],
      ],
    });
    await _pump(tester, service);

    expect(find.textContaining('courier_error_generic'), findsOneWidget);
    expect(find.text('carpet_no_pickup_tasks'), findsNothing);

    await tester.fling(
        find.textContaining('courier_error_generic'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(service.listCalls[CarpetWashService.courierListPickup], 2);
    expect(find.text('3 carpet_count_suffix'), findsOneWidget);
  });
}

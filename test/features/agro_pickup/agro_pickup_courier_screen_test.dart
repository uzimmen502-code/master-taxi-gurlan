import 'package:ava_gurlan/features/agro_pickup/screens/agro_pickup_courier_screen.dart';
import 'package:ava_gurlan/models/agro_pickup_order.dart';
import 'package:ava_gurlan/models/customer_confirm.dart';
import 'package:ava_gurlan/services/agro_pickup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сут қабул курьер экрани вазифаларни `courierListAgroTasks` callable'дан
/// олади: `agro_pickup_orders` қоидаси capability курьерга тўғридан-тўғри
/// рўйхат бермайди (functions/test/carpet_agro_courier_rules.test.js), «Фаол»
/// таб эса аввал ҲАММА курьерларнинг `pickup_in_delivery` вазифаларини
/// оқим қиларди — энди сервер фақат шу курьерникини беради
/// (functions/test/carpet_agro_courier_tasks_cf.test.js).
///
/// Локализация делегати атайлаб йўқ — `context.tr` калитнинг ўзини қайтаради.
const _courier = '998901110001';
const _customer = '998905550005';

class _FakeAgroService implements AgroPickupService {
  _FakeAgroService(this.responses);

  /// `list` → навбатдаги жавоблар (рўйхат ёки хато); охиргиси такрорланади.
  final Map<String, List<Object>> responses;
  final Map<String, int> listCalls = {};
  final List<String> calls = [];

  @override
  Future<List<AgroPickupOrder>> listCourierTasks(String list) async {
    final n = listCalls[list] ?? 0;
    listCalls[list] = n + 1;
    final rs = responses[list] ?? const [<AgroPickupOrder>[]];
    final r = rs[n < rs.length ? n : rs.length - 1];
    if (r is List<AgroPickupOrder>) return r;
    throw r;
  }

  @override
  Future<void> courierClaimPickup({
    required String courierPhone,
    required String orderId,
  }) async =>
      calls.add('claim:$courierPhone:$orderId');

  @override
  Future<void> courierMarkArrived({
    required String courierPhone,
    required String orderId,
  }) async =>
      calls.add('arrived:$courierPhone:$orderId');

  /// courierMarkPickedUp жавоби: waitingCustomer синови учун алмаштирилади.
  CourierActionResult pickedUpResult = CourierActionResult.completed;

  @override
  Future<CourierActionResult> courierMarkPickedUp({
    required String courierPhone,
    required String orderId,
  }) async {
    calls.add('pickedUp:$courierPhone:$orderId');
    return pickedUpResult;
  }

  @override
  Future<String> placeMilkOrder({
    required double literCount,
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
    String? reason,
  }) =>
      throw UnimplementedError();
}

/// Олиш рўйхати элементи — сервер шакли (мижоз майдонлари йўқ).
AgroPickupOrder _preview(String id, num liters, {String productType = 'milk'}) =>
    AgroPickupService.courierTaskFromMap(
      {
        'id': id,
        'productType': productType,
        'literCount': liters,
        'createdAtMs': 1000,
      },
      fallbackStatus: AgroPickupOrder.statusAccepted,
    );

/// «Фаол» элементи — вазифа олингандан кейинги сервер шакли.
AgroPickupOrder _active(String id, {int? arrivedAtMs}) =>
    AgroPickupService.courierTaskFromMap({
      'id': id,
      'status': AgroPickupOrder.statusPickupInDelivery,
      'productType': 'milk',
      'literCount': 20,
      'pickupAddress': 'Navoiy ko\'chasi 7',
      'customerName': 'Mijoz Ismi',
      'customerPhone': _customer,
      'note': 'ertalab',
      'arrivedAtMs': arrivedAtMs,
      'createdAtMs': 1000,
    });

Future<void> _pump(WidgetTester tester, _FakeAgroService service) async {
  SharedPreferences.setMockInitialValues({'user_phone': _courier});
  await tester.pumpWidget(MaterialApp(
    home: AgroPickupCourierScreen(service: service),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('courierTaskFromMap: olish ro\'yxati — mijoz maydonlari bo\'sh, mahsulotsiz eski hujjat = sut',
      () {
    final o = _preview('m1', 35.5);
    expect(o.status, AgroPickupOrder.statusAccepted);
    expect(o.literCount, 35.5);
    expect(o.customerPhone, isEmpty);
    expect(o.customerName, isEmpty);
    expect(o.pickupAddress, isEmpty);
    expect(o.note, isEmpty);
    expect(_preview('m2', 1, productType: '').productType,
        AgroPickupOrder.productMilk);
  });

  test('courierTaskFromMap: «Faol» — ish maydonlari va «yetib keldim» belgisi', () {
    final o = _active('a1', arrivedAtMs: 2000);
    expect(o.status, AgroPickupOrder.statusPickupInDelivery);
    expect(o.customerPhone, _customer);
    expect(o.note, 'ertalab');
    expect(o.arrivedAt, DateTime.fromMillisecondsSinceEpoch(2000));
  });

  testWidgets('olish ro\'yxati: faqat litr — telefon, ism, manzil, izoh, qo\'ng\'iroq YO\'Q',
      (tester) async {
    final service = _FakeAgroService({
      AgroPickupService.courierListPickup: [
        [_preview('m1', 20), _preview('x1', 5, productType: 'eggs')],
      ],
    });
    await _pump(tester, service);

    expect(service.listCalls[AgroPickupService.courierListPickup], 1);
    expect(find.text('20 milk_liter_label'), findsOneWidget);
    expect(find.text('5 milk_liter_label'), findsNothing, reason: 'faqat sut');
    expect(find.text('courier_task_details_after_claim'), findsOneWidget);
    expect(find.byIcon(Icons.call), findsNothing);
    expect(find.textContaining(_customer), findsNothing);
  });

  testWidgets('claim → ro\'yxat yangilanadi; «Faol»da manzil, telefon, izoh; yetib keldim → olib ketildi',
      (tester) async {
    final service = _FakeAgroService({
      AgroPickupService.courierListPickup: [
        [_preview('m1', 20)],
        <AgroPickupOrder>[],
      ],
      AgroPickupService.courierListActive: [
        [_active('m1')],
        [_active('m1', arrivedAtMs: 2000)],
      ],
    });
    await _pump(tester, service);

    await tester.tap(find.text('agro_courier_claim'));
    await tester.pumpAndSettle();
    expect(service.calls, ['claim:$_courier:m1']);
    expect(find.text('agro_courier_no_tasks'), findsOneWidget);

    await tester.tap(find.text('carpet_active_tab'));
    await tester.pumpAndSettle();
    expect(find.text('agro_courier_pickup_in_progress'), findsOneWidget);
    expect(find.text('Navoiy ko\'chasi 7'), findsOneWidget);
    expect(find.text('Mijoz Ismi · $_customer'), findsOneWidget);
    expect(find.text('ertalab'), findsOneWidget);
    expect(find.byIcon(Icons.call), findsOneWidget);

    await tester.tap(find.text('courier_arrived_btn'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'arrived:$_courier:m1');

    await tester.tap(find.text('agro_courier_mark_picked_up'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'pickedUp:$_courier:m1');
  });

  testWidgets('xato «vazifa yo\'q» deb yashirilmaydi, pull-to-refresh qayta oladi',
      (tester) async {
    final service = _FakeAgroService({
      AgroPickupService.courierListPickup: [
        Exception('permission-denied'),
        [_preview('m1', 20)],
      ],
    });
    await _pump(tester, service);

    expect(find.textContaining('courier_error_generic'), findsOneWidget);
    expect(find.text('agro_courier_no_tasks'), findsNothing);

    await tester.fling(
        find.textContaining('courier_error_generic'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(service.listCalls[AgroPickupService.courierListPickup], 2);
    expect(find.text('20 milk_liter_label'), findsOneWidget);
  });

  // ── Mijoz tasdig'i (D2/D7) ────────────────────────────────────────────

  testWidgets('awaitingCustomer: kutish holati, tugma o\'chadi, qayta bosib bo\'lmaydi',
      (tester) async {
    final service = _FakeAgroService({
      AgroPickupService.courierListActive: [
        [_active('m1', arrivedAtMs: 2000)],
      ],
    })
      ..pickedUpResult =
          const CourierActionResult(awaitingCustomer: true, step: 'handover_pickup');
    await _pump(tester, service);
    await tester.tap(find.text('carpet_active_tab'));
    await tester.pumpAndSettle();

    // Hali kutish yo'q: oddiy tugma.
    expect(find.text('customer_confirm_waiting_hint'), findsNothing);
    await tester.tap(find.text('agro_courier_mark_picked_up'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'pickedUp:$_courier:m1');

    // Kutish: ogohlantirish bloki + tugma o'rnida «kutilmoqda» (o'chirilgan).
    expect(find.text('customer_confirm_waiting_hint'), findsOneWidget);
    expect(find.text('customer_confirm_waiting'), findsNWidgets(2)); // blok + tugma
    expect(find.text('agro_courier_mark_picked_up'), findsNothing);
    final callsBefore = service.calls.length;
    await tester.tap(find.text('customer_confirm_waiting').last);
    await tester.pumpAndSettle();
    expect(service.calls.length, callsBefore, reason: 'qayta chaqirilmaydi');

    // Muvaffaqiyat ham, xato ham emas: xato matni yo'q.
    expect(find.textContaining('courier_error_generic'), findsNothing);

    // Dispose'da avto-yangilash taymeri to'xtashi kerak (test oxirida kutilayotgan taymer yo'q).
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('kutish davomida ro\'yxat o\'zi yangilanadi; mijoz tasdiqlagach (vazifa ketdi) kutish yo\'qoladi',
      (tester) async {
    final service = _FakeAgroService({
      AgroPickupService.courierListActive: [
        [_active('m1', arrivedAtMs: 2000)], // birinchi yuklash
        [_active('m1', arrivedAtMs: 2000)], // amaldan keyingi yangilash
        <AgroPickupOrder>[], // avto-yangilash: vazifa ketdi
      ],
    })
      ..pickedUpResult = const CourierActionResult(awaitingCustomer: true);
    await _pump(tester, service);
    await tester.tap(find.text('carpet_active_tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('agro_courier_mark_picked_up'));
    await tester.pumpAndSettle();
    expect(find.text('customer_confirm_waiting_hint'), findsOneWidget);
    expect(service.listCalls[AgroPickupService.courierListActive], 2);

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(service.listCalls[AgroPickupService.courierListActive], 3);
    expect(find.text('customer_confirm_waiting_hint'), findsNothing);
    expect(find.text('carpet_no_active_tasks'), findsOneWidget);

    // Kutish tugadi — taymer to'xtagan: yana 9 s o'tsa ham yangi so'rov yo'q.
    await tester.pump(const Duration(seconds: 9));
    expect(service.listCalls[AgroPickupService.courierListActive], 3);
  });

  testWidgets('eski server (awaitingCustomer yo\'q): avvalgidek — kutish bloki ko\'rinmaydi',
      (tester) async {
    final service = _FakeAgroService({
      AgroPickupService.courierListActive: [
        [_active('m1', arrivedAtMs: 2000)],
        [_active('m1', arrivedAtMs: 2000)],
      ],
    }); // pickedUpResult = completed
    await _pump(tester, service);
    await tester.tap(find.text('carpet_active_tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('agro_courier_mark_picked_up'));
    await tester.pumpAndSettle();
    expect(find.text('customer_confirm_waiting'), findsNothing);
    expect(find.text('agro_courier_mark_picked_up'), findsOneWidget);
  });
}

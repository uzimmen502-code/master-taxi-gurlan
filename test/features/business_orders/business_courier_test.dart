import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_orders/courier/business_courier_banner.dart';
import 'package:ava_gurlan/features/business_orders/courier/business_courier_order_card.dart';
import 'package:ava_gurlan/features/business_orders/courier/business_nearby_orders_screen.dart';
import 'package:ava_gurlan/features/business_orders/data/business_orders_repository.dart';
import 'package:ava_gurlan/features/business_orders/domain/business_order.dart';
import 'package:ava_gurlan/features/courier/controllers/courier_controller.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_business_orders_repository.dart';

const _snap = OrderModel(id: 'o1', type: 'business', total: 20000, status: 'accepted', items: [], businessStatus: 'accepted');

BusinessOrder _o(String status, {Map<String, dynamic> extra = const {}}) => BusinessOrder.fromMap('o1', {
      'type': 'business',
      'businessStatus': status,
      'businessName': 'Дўкон',
      'businessLat': 41.5,
      'businessLng': 60.3,
      'sellerUid': '998901111111',
      'userPhone': '998902222222',
      'userName': 'Али',
      'address': 'Мустақиллик 5',
      'lat': 41.6,
      'lng': 60.4,
      'itemsTotal': 12000,
      'deliveryFee': 8000,
      'total': 20000,
      'deliveryPaymentMethod': 'cash',
      'courierId': '998903333333',
      ...extra,
    });

class _Log {
  final calls = <String>[];
}

Future<(FakeBusinessOrdersRepository, _Log)> _pump(WidgetTester tester, BusinessOrder o, {bool isCurrent = true}) async {
  tester.view.physicalSize = const Size(420 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeBusinessOrdersRepository();
  final log = _Log();
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    theme: AppTheme.light,
    home: Scaffold(
      body: ListView(children: [
        BusinessCourierOrderCard(
          order: _snap,
          index: 0,
          isDone: false,
          isCurrent: isCurrent,
          repository: repo,
          onPickup: (code) async {
            log.calls.add('pickup:$code');
            final e = repo.nextActionError;
            if (e != null) {
              repo.nextActionError = null;
              throw e;
            }
          },
          onArrive: () async => log.calls.add('arrive'),
          onComplete: () async {
            log.calls.add('complete');
            return repo.completeResult;
          },
          onReportFailed: (r) async => log.calls.add('failed:$r'),
          onFinalizeRoute: () async => log.calls.add('next'),
        ),
      ]),
    ),
  ));
  await tester.pump();
  repo.orderCtrl('o1').add(o);
  await tester.pumpAndSettle();
  return (repo, log);
}

void main() {
  test('курьер контроллери: бизнес буюртмаси фақат якуний businessStatus да тугаган', () {
    OrderModel m(String bs, {String ps = ''}) =>
        OrderModel(id: 'x', type: 'business', total: 1, status: 'in_delivery', items: const [], businessStatus: bs, paymentStatus: ps);
    expect(CourierController.isOrderFinalized(m('picked', ps: 'paid')), isFalse, reason: 'paymentStatus маъносиз');
    expect(CourierController.isOrderFinalized(m('arrived')), isFalse);
    for (final s in ['delivered', 'rejected', 'cancelled', 'delivery_failed']) {
      expect(CourierController.isOrderFinalized(m(s)), isTrue, reason: s);
    }
  });

  testWidgets('accepted: тайёрланмоқда, олиш тугмаси йўқ', (tester) async {
    await _pump(tester, _o('accepted'));
    expect(find.text('biz_order_courier_preparing'), findsOneWidget);
    expect(find.byKey(const ValueKey('biz_courier_pickup_o1')), findsNothing);
  });

  testWidgets('ready: код киритиш; нотўғри код — қолган уриниш, диалог очиқ; тўғриси — onPickup', (tester) async {
    final (repo, log) = await _pump(tester, _o('ready'));
    expect(find.text('biz_order_courier_pay_seller'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('biz_courier_pickup_o1')));
    await tester.pumpAndSettle();
    repo.nextActionError =
        const BusinessOrderException('failed-precondition', 'PICKUP_CODE_MISMATCH', details: {'attemptsLeft': 3});
    await tester.enterText(find.byKey(const ValueKey('biz_courier_code_field')), '1234');
    await tester.tap(find.byKey(const ValueKey('biz_courier_code_submit')));
    await tester.pumpAndSettle();
    expect(find.text('biz_order_err_pickup_code_mismatch'), findsOneWidget);
    expect(find.byKey(const ValueKey('biz_courier_code_field')), findsOneWidget, reason: 'диалог очиқ');
    await tester.enterText(find.byKey(const ValueKey('biz_courier_code_field')), '4821');
    await tester.tap(find.byKey(const ValueKey('biz_courier_code_submit')));
    await tester.pumpAndSettle();
    expect(log.calls, ['pickup:1234', 'pickup:4821']);
    expect(find.byKey(const ValueKey('biz_courier_code_field')), findsNothing);
  });

  testWidgets('picked: «Етиб келдим» ва «Етказиб бўлмади» (умумий виджет, сабаб билан)', (tester) async {
    final (_, log) = await _pump(tester, _o('picked'));
    await tester.tap(find.byKey(const ValueKey('biz_courier_arrive_o1')));
    await tester.pumpAndSettle();
    expect(log.calls, ['arrive']);
    await tester.tap(find.byKey(const ValueKey('df-report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('df-reason-customer_absent')));
    await tester.pumpAndSettle();
    expect(log.calls, ['arrive', 'failed:customer_absent']);
  });

  testWidgets('«етказилмади» кутилмоқда — тугма йўқ, кутиш блоки', (tester) async {
    await _pump(tester, _o('arrived', extra: {
      'awaitingCustomerConfirm': {'step': 'delivery_failed', 'module': 'business', 'failReason': 'customer_absent'},
    }));
    expect(find.byKey(const ValueKey('df-waiting')), findsOneWidget);
    expect(find.byKey(const ValueKey('df-report')), findsNothing);
  });

  testWidgets('arrived: нақд жами (маҳсулот + нақд етказиш); «Топширдим» → мижоз тасдиғи кутилади', (tester) async {
    final (repo, log) = await _pump(tester, _o('arrived'));
    expect(find.byKey(const ValueKey('biz_courier_collect')), findsOneWidget);
    repo.completeResult = const BusinessCompleteResult(awaitingCustomer: true);
    await tester.tap(find.byKey(const ValueKey('biz_courier_deliver_o1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz_courier_deliver_confirm')));
    await tester.pumpAndSettle();
    expect(log.calls, ['complete']);
    expect(find.text('customer_confirm_waiting'), findsWidgets, reason: 'кутиш блоки ва ўчиқ тугма');
    expect(
      tester.widget<FilledButton>(find.byKey(const ValueKey('biz_courier_deliver_o1'))).onPressed,
      isNull,
    );
    expect(log.calls.contains('next'), isFalse, reason: 'кутишда маршрут сурилмайди');

    // Мижоз «Олдим» босди → delivered → «Кейинги буюртма».
    repo.orderCtrl('o1').add(_o('delivered'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz_courier_next_o1')));
    await tester.pumpAndSettle();
    expect(log.calls, ['complete', 'next']);
  });

  testWidgets('arrived: дарҳол етказилди → натижа ва кейинги буюртма', (tester) async {
    final (_, log) = await _pump(tester, _o('arrived'));
    await tester.tap(find.byKey(const ValueKey('biz_courier_deliver_o1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz_courier_deliver_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('biz_order_courier_delivered_ok'), findsOneWidget);
    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();
    expect(log.calls, ['complete', 'next']);
  });

  testWidgets('сотувчи рад этди — бекор изоҳи ва «Кейинги буюртма»', (tester) async {
    await _pump(tester, _o('rejected'));
    expect(find.text('biz_order_courier_cancelled_note'), findsOneWidget);
    expect(find.byKey(const ValueKey('biz_courier_next_o1')), findsOneWidget);
  });

  group('курьер кириши', () {
    Future<void> banner(WidgetTester tester, BusinessOrdersAccess a) async {
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.light,
        home: Scaffold(body: BusinessCourierBanner(onClaimed: () {}, accessCheck: () async => a)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('баннер: ёпиқ/синов — йўқ; пилот/оммавий — бор', (tester) async {
      await banner(tester, const BusinessOrdersAccess(allowed: false, stage: 'off', reason: 'MODULE_OFF'));
      expect(find.byKey(const ValueKey('biz_courier_banner')), findsNothing);
      await banner(tester, const BusinessOrdersAccess(allowed: false, stage: 'internal', reason: 'MODULE_INTERNAL_ONLY'));
      expect(find.byKey(const ValueKey('biz_courier_banner')), findsNothing);
      await banner(tester, const BusinessOrdersAccess(allowed: false, stage: 'pilot', reason: 'MODULE_NOT_IN_PILOT'));
      expect(find.byKey(const ValueKey('biz_courier_banner')), findsOneWidget);
      await banner(tester, const BusinessOrdersAccess(allowed: true, stage: 'public'));
      expect(find.byKey(const ValueKey('biz_courier_banner')), findsOneWidget);
    });

    testWidgets('яқиндагилар: «Олиш» → courierClaimBusinessOrder; выкуп лимитидан катта — ўчиқ', (tester) async {
      tester.view.physicalSize = const Size(420 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = FakeBusinessOrdersRepository()
        ..nearby = const NearbyBusinessOrders([
          NearbyBusinessOrder(id: 'n1', businessName: 'A', status: 'ready', buyoutAmount: 10000, buyoutAllowed: true, deliveryFee: 8000),
          NearbyBusinessOrder(id: 'n2', businessName: 'B', status: 'accepted', buyoutAmount: 900000, buyoutAllowed: false),
        ], buyoutLimit: 100000);
      final popped = <bool?>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => popped.add(await Navigator.of(ctx).push<bool>(MaterialPageRoute(
                builder: (_) => BusinessNearbyOrdersScreen(repository: repo, locate: () async => (lat: 41.5, lng: 60.3)),
              ))),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('nearby:15'));
      expect(find.text('biz_order_courier_buyout_over'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('biz_nearby_claim_n2'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('biz_nearby_claim_n1')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('claim:n1'));
      expect(popped, [true]);
    });

    testWidgets('бошқа курьер олган — дўстона матн, рўйхат янгиланади', (tester) async {
      tester.view.physicalSize = const Size(420 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = FakeBusinessOrdersRepository()
        ..nearby = const NearbyBusinessOrders([
          NearbyBusinessOrder(id: 'n1', businessName: 'A', status: 'ready', buyoutAllowed: true),
        ])
        ..nextActionError = const BusinessOrderException('failed-precondition', 'COURIER_ASSIGNMENT_CONFLICT');
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: BusinessNearbyOrdersScreen(repository: repo, locate: () async => null),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('biz_nearby_claim_n1')));
      await tester.pumpAndSettle();
      expect(find.text('biz_order_err_courier_assignment_conflict'), findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('nearby')), hasLength(2));
    });
  });
}

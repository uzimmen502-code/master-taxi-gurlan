import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_orders/data/business_orders_repository.dart';
import 'package:ava_gurlan/features/business_orders/domain/business_order.dart';
import 'package:ava_gurlan/features/business_orders/screens/business_order_screen.dart';
import 'package:ava_gurlan/features/business_orders/widgets/business_order_hub_tile.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_business_orders_repository.dart';

BusinessOrder _o(String status, {String rejectReason = '', Map<String, dynamic> extra = const {}}) =>
    BusinessOrder.fromMap('o1', {
      'type': 'business',
      'businessStatus': status,
      'businessName': 'Дўкон',
      'items': [
        {'itemId': 'a', 'title': 'Ун', 'unitPrice': 5000, 'priceUnit': 'kg', 'qty': 2, 'lineTotal': 10000},
      ],
      'itemsTotal': 10000,
      'deliveryFee': 8000,
      'total': 18000,
      'deliveryPaymentMethod': 'cash',
      'rejectReason': rejectReason,
      ...extra,
    });

Future<FakeBusinessOrdersRepository> _pump(WidgetTester tester, BusinessOrder o, {List<String>? log}) async {
  tester.view.physicalSize = const Size(420 * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeBusinessOrdersRepository();
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    theme: AppTheme.light,
    home: BusinessOrderScreen(orderId: 'o1', repository: repo, openConfirm: (_) async => log?.add('confirm')),
  ));
  await tester.pump();
  repo.orderCtrl('o1').add(o);
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('placed: вақт чизиғи, эшик олдида нақд, бекор қилиш → customerCancelBusinessOrder', (tester) async {
    final repo = await _pump(tester, _o('placed'));
    expect(find.byKey(const ValueKey('biz_order_timeline')), findsOneWidget);
    expect(find.byKey(const ValueKey('biz_order_cash_at_door')), findsOneWidget);
    expect(find.text('biz_order_goods_cash_explain'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('biz_order_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz_order_cancel_yes')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('cancel:o1'));
    expect(find.text('biz_order_cancel_ok'), findsOneWidget);
  });

  testWidgets('бекор рад этилса — дўстона матн (CANCEL_NOT_ALLOWED)', (tester) async {
    final repo = await _pump(tester, _o('placed'));
    repo.nextActionError = const BusinessOrderException('failed-precondition', 'CANCEL_NOT_ALLOWED');
    await tester.tap(find.byKey(const ValueKey('biz_order_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz_order_cancel_yes')));
    await tester.pumpAndSettle();
    expect(find.text('biz_order_err_cancel_not_allowed'), findsOneWidget);
  });

  testWidgets('accepted: бекор тугмаси йўқ', (tester) async {
    await _pump(tester, _o('accepted'));
    expect(find.byKey(const ValueKey('biz_order_cancel')), findsNothing);
  });

  testWidgets('рад этилган (вақт тугаган) — якуний қизил блок', (tester) async {
    await _pump(tester, _o('rejected', rejectReason: 'timeout'));
    expect(find.byKey(const ValueKey('biz_order_timeline_final')), findsOneWidget);
    expect(find.text('biz_order_rejected_timeout'), findsOneWidget);
  });

  testWidgets('«Олдим» кутилмоқда — мижоз тасдиғи экрани очилади', (tester) async {
    final log = <String>[];
    await _pump(tester, _o('arrived', extra: {
      'awaitingCustomerConfirm': {'step': 'received', 'module': 'business'},
    }), log: log);
    await tester.tap(find.byKey(const ValueKey('biz_order_open_confirm')));
    await tester.pumpAndSettle();
    expect(log, ['confirm']);
  });

  testWidgets('ҳаб карточкаси: дўкон номи, ҳолат, бекор (фақат placed)', (tester) async {
    var cancelled = 0;
    const placed = OrderModel(
      id: 'o1', type: 'business', total: 18000, status: 'new', items: [], businessStatus: 'placed', businessName: 'Дўкон');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: BusinessOrderHubTile(order: placed, onCancel: placed.canCustomerCancel ? () => cancelled++ : null),
      ),
    ));
    expect(find.text('Дўкон'), findsOneWidget);
    expect(find.text('biz_order_status_placed'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('biz_hub_cancel_o1')));
    expect(cancelled, 1);
  });
}

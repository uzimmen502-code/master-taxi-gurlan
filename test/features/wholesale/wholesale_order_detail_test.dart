// 4-босқич: буюртма тафсилоти — ҳар ҳолат ва ролда фақат рухсат этилган
// амал кўринади. Эга қарори (2026-10-31): сотувчида ҚАБУЛ/РАД ЙЎҚ; унинг
// ягона амали — карта буюртмасида «Пул тушди».
import 'package:ava_gurlan/features/wholesale/models/wholesale_order.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_orders_repository.dart';
import 'package:ava_gurlan/features/wholesale/screens/wholesale_order_detail_screen.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_order_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wholesale_orders_fakes.dart';

const _buyer = '998900000001';
const _seller = '998901111111';

WholesaleOrder _order({
  String status = WholesaleOrderStatus.placed,
  String method = WholesalePaymentMethod.wallet,
  Map<String, dynamic>? card,
  Object? returnDebt,
}) =>
    WholesaleOrder.fromMap('o1', {
      'buyerId': _buyer,
      'sellerId': _seller,
      'productId': 'prod1',
      'productTitle': 'Гуруч',
      'packLabel': '25 кг',
      'qty': 2,
      'unitPrice': 320000,
      'goodsTotal': 640000,
      'deliveryFee': 45000,
      'total': 685000,
      'status': status,
      'paymentMethod': method,
      if (card != null) 'cardPayment': card,
      if (status != WholesaleOrderStatus.placed) 'shipment': {'shipmentId': 's1', 'trackingNumber': 'AVA-1'},
      if (returnDebt != null) 'returnDebt': returnDebt,
    });

class _H {
  final demand = FakeFunctions('demand');
  late final repo = WholesaleOrdersRepository(
    firestore: FakeDb(),
    demandFunctions: demand,
    walletFunctions: FakeFunctions('wallet'),
  );
  final uploads = <String>[];
}

Future<_H> _pump(WidgetTester tester, WholesaleOrder o, String viewer, {_H? h}) async {
  final hh = h ?? _H();
  tester.view.physicalSize = const Size(400 * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WholesaleOrderDetailView(
        order: o,
        viewerId: viewer,
        repository: hh.repo,
        uploadReceipt: (buyerId) async {
          hh.uploads.add(buyerId);
          return 'wholesale_receipts/$buyerId/r.jpg';
        },
        resolveReceiptUrl: (_) async => throw StateError('no network in test'),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return hh;
}

const _code = ValueKey('wholesale-delivery-code');
const _cancel = ValueKey('wholesale-order-cancel');
const _money = ValueKey('wholesale-money-received');
const _cardInfo = ValueKey('wholesale-card-info');
const _upload = ValueKey('wholesale-receipt-upload');

/// Сотувчига қабул/рад умуман кўрсатилмаслиги — ҳар қандай ҳолатда.
void _expectNoAcceptReject() {
  for (final t in ['accept', 'reject', 'qabul', 'rad', 'Қабул қилиш', 'Рад этиш']) {
    expect(find.textContaining(RegExp('^$t\$', caseSensitive: false)), findsNothing);
  }
  expect(find.byKey(const ValueKey('wholesale-order-accept')), findsNothing);
  expect(find.byKey(const ValueKey('wholesale-order-reject')), findsNothing);
}

void main() {
  group('харидор (ҳамён буюртмаси)', () {
    testWidgets('placed: бекор қилиш бор, код йўқ', (tester) async {
      await _pump(tester, _order(), _buyer);
      expect(find.byKey(_cancel), findsOneWidget);
      expect(find.byKey(_code), findsNothing);
      expect(find.byKey(_money), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-order-timeline')), findsOneWidget);
    });

    testWidgets('in_delivery: код тугмаси + изоҳ; бекор йўқ; кузатув рақами', (tester) async {
      final h = _H();
      h.demand.handlers['getWholesaleDeliveryCode'] =
          (_) => {'deliveryCode': '482913', 'trackingNumber': 'AVA-1', 'shipmentId': 's1'};
      await _pump(tester, _order(status: WholesaleOrderStatus.inDelivery), _buyer, h: h);
      expect(find.byKey(_code), findsOneWidget);
      expect(find.text('wholesale_order_delivery_code_hint'), findsOneWidget);
      expect(find.byKey(_cancel), findsNothing);
      expect(find.text('wholesale_order_tracking'), findsOneWidget);

      await tester.tap(find.byKey(_code));
      await tester.pumpAndSettle();
      expect(h.demand.calls.single.$1, 'getWholesaleDeliveryCode');
      expect(h.demand.calls.single.$2, {'orderId': 'o1'});
      expect(find.byKey(const ValueKey('wholesale-delivery-code-value')), findsOneWidget);
      expect(find.text('482913'), findsOneWidget);
    });

    testWidgets('бекор: тасдиқдан кейин callable, сервер рад этса — матн (ички код эмас)', (tester) async {
      final h = _H();
      h.demand.handlers['cancelWholesaleOrder'] = (_) => throw fnError('failed-precondition', 'invalid_transition');
      await _pump(tester, _order(), _buyer, h: h);
      await tester.tap(find.byKey(_cancel));
      await tester.pumpAndSettle();
      expect(find.textContaining('wholesale_order_cancel_refund_note'), findsOneWidget,
          reason: 'ҳамён буюртмасида — пул қайтиши айтилади');
      await tester.tap(find.byKey(const ValueKey('wholesale-confirm-yes')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.single.$1, 'cancelWholesaleOrder');
      expect(find.text('wholesale_order_err_invalid_transition'), findsOneWidget);
      expect(find.text('invalid_transition'), findsNothing);
    });

    for (final s in [
      WholesaleOrderStatus.delivered,
      WholesaleOrderStatus.cancelled,
      WholesaleOrderStatus.refused,
      WholesaleOrderStatus.returning,
      WholesaleOrderStatus.returned,
      WholesaleOrderStatus.paymentDispute,
    ]) {
      testWidgets('$s: код ҳам, бекор ҳам йўқ', (tester) async {
        await _pump(tester, _order(status: s), _buyer);
        expect(find.byKey(_code), findsNothing);
        expect(find.byKey(_cancel), findsNothing);
        expect(find.byKey(_money), findsNothing);
      });
    }

    testWidgets('payment_dispute: «Низо — админ кўриб чиқмоқда» баннери', (tester) async {
      await _pump(tester, _order(status: WholesaleOrderStatus.paymentDispute, method: 'card_on_delivery'), _buyer);
      expect(find.byKey(const ValueKey('wholesale-dispute-banner')), findsOneWidget);
    });
  });

  group('харидор (карта буюртмаси, 3b)', () {
    testWidgets('in_delivery, тўлов тасдиқланмаган: код ЙЎҚ, карта маълумоти + чек юклаш бор', (tester) async {
      final h = _H();
      h.demand.handlers['submitWholesaleCardReceipt'] = (_) => {'ok': true};
      await _pump(
        tester,
        _order(status: WholesaleOrderStatus.inDelivery, method: 'card_on_delivery', card: {'status': 'awaiting'}),
        _buyer,
        h: h,
      );
      expect(find.byKey(_code), findsNothing);
      expect(find.text('wholesale_order_err_card_payment_unconfirmed'), findsOneWidget);
      expect(find.byKey(_cardInfo), findsOneWidget);
      expect(find.byKey(_upload), findsOneWidget);

      await tester.tap(find.byKey(_upload));
      await tester.pumpAndSettle();
      expect(h.uploads, [_buyer]);
      expect(h.demand.calls.single.$1, 'submitWholesaleCardReceipt');
      expect(h.demand.calls.single.$2, {'orderId': 'o1', 'receiptPath': 'wholesale_receipts/$_buyer/r.jpg'});
    });

    testWidgets('чек юборилган: «Сотувчи тасдиқлашини кутяпмиз», қайта юклаш йўқ', (tester) async {
      await _pump(
        tester,
        _order(
          status: WholesaleOrderStatus.inDelivery,
          method: 'card_on_delivery',
          card: {'status': 'receipt_submitted', 'receiptPath': 'wholesale_receipts/x/r.jpg'},
        ),
        _buyer,
      );
      expect(find.byKey(const ValueKey('wholesale-wait-seller')), findsOneWidget);
      expect(find.byKey(_upload), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-receipt')), findsNothing, reason: 'чек расми — сотувчига');
    });

    testWidgets('карта маълумоти: сотувчи картаси ва сумма', (tester) async {
      final h = _H();
      h.demand.handlers['getWholesaleCardPaymentInfo'] =
          (_) => {'amount': 640000, 'cardNumber': '8600123456789012', 'holderName': 'ALI V', 'sellerName': 'Ali'};
      await _pump(
        tester,
        _order(method: 'card_on_delivery', card: {'status': 'awaiting'}),
        _buyer,
        h: h,
      );
      await tester.tap(find.byKey(_cardInfo));
      await tester.pumpAndSettle();
      expect(find.text('8600 1234 5678 9012'), findsOneWidget);
    });

    testWidgets('тўлов тасдиқланган + in_delivery: код тугмаси чиқади', (tester) async {
      await _pump(
        tester,
        _order(status: WholesaleOrderStatus.inDelivery, method: 'card_on_delivery', card: {'status': 'confirmed'}),
        _buyer,
      );
      expect(find.byKey(_code), findsOneWidget);
      expect(find.byKey(_cardInfo), findsNothing);
      expect(find.byKey(_upload), findsNothing);
    });
  });

  group('сотувчи — қабул/рад ЙЎҚ', () {
    for (final s in WholesaleOrderStatus.known) {
      testWidgets('ҳамён буюртмаси, $s: ҳеч қандай амал тугмаси йўқ', (tester) async {
        await _pump(tester, _order(status: s), _seller);
        _expectNoAcceptReject();
        expect(find.byKey(_code), findsNothing, reason: 'етказиш коди фақат харидорга');
        expect(find.byKey(_cancel), findsNothing, reason: 'сотувчи бекор қилмайди');
        expect(find.byKey(_money), findsNothing, reason: '«Пул тушди» фақат карта буюртмасида');
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
      });
    }

    testWidgets('карта, awaiting: «Пул тушди» бор → тасдиқ → callable', (tester) async {
      final h = _H();
      h.demand.handlers['confirmWholesaleCardPayment'] = (_) => {'ok': true};
      await _pump(
        tester,
        _order(status: WholesaleOrderStatus.inDelivery, method: 'card_on_delivery', card: {'status': 'awaiting'}),
        _seller,
        h: h,
      );
      _expectNoAcceptReject();
      expect(find.byKey(_money), findsOneWidget);
      expect(find.byKey(_code), findsNothing);
      expect(find.byKey(_cardInfo), findsNothing);
      await tester.tap(find.byKey(_money));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-confirm-yes')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.single.$1, 'confirmWholesaleCardPayment');
      expect(h.demand.calls.single.$2, {'orderId': 'o1'});
    });

    testWidgets('карта, receipt_submitted: чек бўлими + 30 дақиқа огоҳлантириши + «Пул тушди»', (tester) async {
      await _pump(
        tester,
        _order(
          status: WholesaleOrderStatus.inDelivery,
          method: 'card_on_delivery',
          card: {'status': 'receipt_submitted', 'receiptPath': 'wholesale_receipts/x/r.jpg'},
        ),
        _seller,
      );
      expect(find.byKey(const ValueKey('wholesale-receipt')), findsOneWidget);
      expect(find.text('wholesale_order_receipt_load_failed'), findsOneWidget);
      expect(find.text('wholesale_order_receipt_window'), findsOneWidget);
      expect(find.byKey(_money), findsOneWidget);
    });

    testWidgets('карта, confirmed / dispute: «Пул тушди» йўқ', (tester) async {
      await _pump(
        tester,
        _order(status: WholesaleOrderStatus.inDelivery, method: 'card_on_delivery', card: {'status': 'confirmed'}),
        _seller,
      );
      expect(find.byKey(_money), findsNothing);
      await _pump(
        tester,
        _order(
            status: WholesaleOrderStatus.paymentDispute, method: 'card_on_delivery', card: {'status': 'receipt_submitted'}),
        _seller,
      );
      expect(find.byKey(_money), findsNothing);
    });

    testWidgets('қайтариш қарзи — огоҳлантириш', (tester) async {
      await _pump(
        tester,
        _order(status: WholesaleOrderStatus.returned, method: 'card_on_delivery', returnDebt: 30000),
        _seller,
      );
      expect(find.byKey(const ValueKey('wholesale-return-debt')), findsOneWidget);
    });
  });

  testWidgets('бегона (на харидор, на сотувчи) — ҳеч қандай амал йўқ', (tester) async {
    await _pump(
      tester,
      _order(status: WholesaleOrderStatus.inDelivery, method: 'card_on_delivery', card: {'status': 'awaiting'}),
      '998909999999',
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  group('ҳолат қадамлари (соф)', () {
    List<(String, WholesaleStepState)> s(String st) =>
        wholesaleTimelineSteps(st).map((x) => (x.status, x.state)).toList();

    test('асосий йўл', () {
      expect(s('placed'), [
        ('placed', WholesaleStepState.current),
        ('in_delivery', WholesaleStepState.upcoming),
        ('delivered', WholesaleStepState.upcoming),
      ]);
      expect(s('delivered').every((x) => x.$2 == WholesaleStepState.done), isTrue);
    });

    test('якуний тармоқлар', () {
      expect(s('cancelled').last, ('cancelled', WholesaleStepState.failed));
      expect(s('returning').map((x) => x.$1), ['placed', 'in_delivery', 'refused', 'returning', 'returned']);
      expect(s('returned').last, ('returned', WholesaleStepState.done));
      expect(s('payment_dispute').last, ('payment_dispute', WholesaleStepState.failed));
      expect(s('weird'), [('weird', WholesaleStepState.current)]);
    });
  });
}

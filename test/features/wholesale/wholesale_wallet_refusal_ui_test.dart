// Улгуржи ҲАМЁН буюртмаси «Етказилмади» (эга, 2026-11-01: «тавсияларга розиман»): модел (walletRefusal,
// returnDebt.payer), харидор/сотувчи ойналари (пул оқибати), ҳамён қайтими изоҳи, харидор қарзи,
// курьер ойнасида «бошқа» йўқ + огоҳлантириш, хато матни. Пул — серверда; бу ерда фақат кўрсатиш.
import 'package:ava_gurlan/features/demand_offer/domain/demand_match.dart';
import 'package:ava_gurlan/features/logistics/data/logistics_repository.dart';
import 'package:ava_gurlan/features/logistics/domain/logistics_models.dart';
import 'package:ava_gurlan/features/logistics/services/logistics_photo_storage.dart';
import 'package:ava_gurlan/features/logistics/ui/leg_actions.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_order.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_orders_repository.dart';
import 'package:ava_gurlan/features/wholesale/screens/wholesale_order_detail_screen.dart';
import 'package:ava_gurlan/features/wholesale/utils/wholesale_order_errors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wholesale_orders_fakes.dart';

const _buyer = '998900000001';
const _seller = '998901111111';
final _due = DateTime(2026, 11, 1, 12, 15);

Map<String, dynamic> _df(String reason) => {
      'seq': 1,
      'open': true,
      'stage': 'awaiting_buyer',
      'reasonCode': reason,
      'escalateAt': Timestamp.fromDate(_due),
      'escalatedAt': null,
      'resolution': null,
    };

WholesaleOrder _order({
  String status = WholesaleOrderStatus.inDelivery,
  String method = WholesalePaymentMethod.wallet,
  Map<String, dynamic>? df,
  Map<String, dynamic>? walletRefusal,
  Map<String, dynamic>? returnDebt,
  String returnStatus = '',
}) =>
    WholesaleOrder.fromMap('o1', {
      'buyerId': _buyer,
      'sellerId': _seller,
      'productTitle': 'Гуруч',
      'qty': 10,
      'unitPrice': 14000,
      'goodsTotal': 140000,
      'deliveryFee': 60000,
      'total': 200000,
      'status': status,
      'paymentMethod': method,
      if (method == WholesalePaymentMethod.cardOnDelivery) 'cardPayment': {'status': 'awaiting'},
      'shipment': {'shipmentId': 's1', 'trackingNumber': 'AVA-1'},
      if (df != null) 'deliveryFailed': df,
      if (walletRefusal != null) 'walletRefusal': walletRefusal,
      if (returnDebt != null) 'returnDebt': returnDebt,
      if (returnStatus.isNotEmpty) 'returnStatus': returnStatus,
    });

class _H {
  final demand = FakeFunctions('demand');
  late final repo = WholesaleOrdersRepository(firestore: FakeDb(), demandFunctions: demand, walletFunctions: FakeFunctions('wallet'));
}

Future<_H> _detail(WidgetTester tester, WholesaleOrder o, String viewer, {DateTime? now}) async {
  final h = _H();
  tester.view.physicalSize = const Size(400 * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: WholesaleOrderDetailView(
              order: o, viewerId: viewer, repository: h.repo, now: () => now ?? DateTime(2026, 11, 1, 12, 5)))));
  await tester.pumpAndSettle();
  return h;
}

class _FakeLogistics extends Fake implements LogisticsRepository {
  _FakeLogistics(this.shipment);
  final Map<String, dynamic> shipment;

  @override
  Stream<Shipment?> watchShipment(String shipmentId) => Stream.value(Shipment.fromMap(shipmentId, shipment));
}

class _FakePhotos extends Fake implements LogisticsPhotoStorage {}

Future<FakeFunctions> _courier(WidgetTester tester, Map<String, dynamic> state) async {
  final demand = FakeFunctions('demand');
  demand.handlers['getWholesaleDeliveryFailedState'] = (_) => state;
  tester.view.physicalSize = const Size(400 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: LogisticsLegActions(
        match: DemandMatch.fromMap('l1_998903333333', {
          'demandId': 'l1',
          'providerId': '998903333333',
          'module': 'logistics',
          'mode': 'quote',
          'status': 'in_progress',
          'projection': {
            'attributes': {'shipmentId': 's1', 'trackingNumber': 'AVA-1', 'legIndex': 0, 'legCount': 1},
          },
        }),
        providerId: '998903333333',
        repository: _FakeLogistics(const {'source': 'wholesale', 'wholesaleOrderId': 'o1'}),
        photos: _FakePhotos(),
        wholesaleRepository: WholesaleOrdersRepository(firestore: FakeDb(), demandFunctions: demand, walletFunctions: FakeFunctions('wallet')),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return demand;
}

const _state = {'ok': true, 'orderId': 'o1', 'status': 'in_delivery', 'pending': false, 'stage': null, 'resolution': null};

void main() {
  group('модел', () {
    test('walletRefusal / returnDebt.payer ўқилади; эски ҳужжат — бўш (0)', () {
      final o = _order(
        status: WholesaleOrderStatus.refused,
        walletRefusal: {'fault': 'buyer', 'goodsRefunded': 140000, 'returnFeeCharged': 40000},
        returnDebt: {'amount': 1, 'payer': 'buyer'},
      );
      expect([o.walletRefusalFault, o.walletRefundGoods, o.walletReturnFeeCharged, o.returnDebtPayer, o.returnDebt], ['buyer', 140000, 40000, 'buyer', 1]);
      final old = _order();
      expect([old.walletRefusalFault, old.walletRefundGoods, old.returnDebtPayer], ['', 0, '']);
    });

    test('ҳамён қайтими изоҳи: харидор сабаби / курьер сабаби; сотувчига, картага, суммасиз — йўқ', () {
      final b = _order(status: WholesaleOrderStatus.refused, walletRefusal: {'fault': 'buyer', 'goodsRefunded': 140000, 'returnFeeCharged': 40000});
      expect(b.walletRefundNoticeKey(_buyer), 'wholesale_order_wallet_refund');
      expect(b.walletRefundNoticeKey(_seller), isNull);
      final c = _order(status: WholesaleOrderStatus.refused, walletRefusal: {'fault': 'courier', 'goodsRefunded': 140000});
      expect(c.walletRefundNoticeKey(_buyer), 'wholesale_order_wallet_refund_courier');
      expect(_order(status: WholesaleOrderStatus.refused, walletRefusal: {'fault': 'buyer'}).walletRefundNoticeKey(_buyer), isNull,
          reason: 'пул ҳали ҳисобланмаган');
      expect(_order(method: WholesalePaymentMethod.cardOnDelivery, walletRefusal: {'fault': 'buyer', 'goodsRefunded': 1}).walletRefundNoticeKey(_buyer), isNull);
    });

    test('қарз: харидор қарзи — харидорга (сотувчига эмас); карта (payer йўқ) — сотувчига, аввалгидек', () {
      final w = _order(status: WholesaleOrderStatus.refused, returnDebt: {'amount': 1, 'payer': 'buyer'});
      expect(WholesaleOrderActions.of(w, _buyer).showBuyerReturnDebt, isTrue);
      expect(WholesaleOrderActions.of(w, _seller).showReturnDebt, isFalse);
      final k = _order(status: WholesaleOrderStatus.refused, returnDebt: {'amount': 5, 'payer': 'courier'});
      expect([WholesaleOrderActions.of(k, _buyer).showBuyerReturnDebt, WholesaleOrderActions.of(k, _seller).showReturnDebt], [false, false]);
      final card = _order(status: WholesaleOrderStatus.refused, method: WholesalePaymentMethod.cardOnDelivery, returnDebt: {'amount': 40000});
      expect([WholesaleOrderActions.of(card, _seller).showReturnDebt, WholesaleOrderActions.of(card, _buyer).showBuyerReturnDebt], [true, false]);
    });

    test('қайтиш ҳолати матни: ҳамён awaiting_payment — тўловчига қараб; карта — аввалгидек', () {
      expect(_order(returnStatus: 'awaiting_payment', walletRefusal: {'fault': 'courier'}).returnStatusKey(), 'wholesale_return_status_awaiting_payment_courier');
      expect(_order(returnStatus: 'awaiting_payment', returnDebt: {'amount': 1, 'payer': 'buyer'}).returnStatusKey(), 'wholesale_return_status_awaiting_payment_buyer');
      expect(_order(returnStatus: 'awaiting_payment', method: WholesalePaymentMethod.cardOnDelivery).returnStatusKey(), 'wholesale_return_status_awaiting_payment');
      expect(_order(returnStatus: 'in_transit').returnStatusKey(), 'wholesale_return_status_in_transit');
    });

    test('курьер ҳолати: allowedReasons (ҳамён — 3), эски сервер — 4; хато матни reason_not_allowed_wallet / reason_required', () {
      final w = WholesaleDeliveryFailedReport.fromMap({
        'paymentMethod': 'wallet',
        'allowedReasons': ['customer_absent', 'customer_refused', 'courier_problem'],
      });
      expect([w.isWalletOrder, w.reasons], [true, ['customer_absent', 'customer_refused', 'courier_problem']]);
      expect(WholesaleDeliveryFailedReport.fromMap(const {}).reasons, wholesaleDeliveryFailedReasons);
      expect(WholesaleDeliveryFailedReport.fromMap({'allowedReasons': ['bogus']}).reasons, wholesaleDeliveryFailedReasons, reason: 'номаълум — ҳаммаси');
      String k(String r) => wholesaleOrderErrorKey(WholesaleOrderException('invalid-argument', r));
      expect(k('reason_not_allowed_wallet'), 'wholesale_courier_failed_err_reason');
      expect(k('reason_required'), 'wholesale_courier_failed_err_reason');
    });
  });

  group('харидор / сотувчи', () {
    testWidgets('ҳамён, харидор сабаби: карта матни ҳамён варианти; тасдиқ ойнаси — «қайтариш ҳақи ушланади»', (tester) async {
      final h = await _detail(tester, _order(df: _df('customer_absent')), _buyer);
      h.demand.handlers['respondWholesaleDeliveryFailed'] = (_) => {'ok': true, 'status': 'refused'};
      expect(find.text('wholesale_df_buyer_body_wallet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wholesale-df-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('wholesale_df_buyer_confirm_dialog_wallet_buyer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wholesale-confirm-yes')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.single.$2, {'orderId': 'o1', 'decision': 'confirm'});
    });

    testWidgets('ҳамён, курьер сабаби: ойна — «қайтариш ҳақини курьер тўлайди»', (tester) async {
      await _detail(tester, _order(df: _df('courier_problem')), _buyer);
      await tester.tap(find.byKey(const ValueKey('wholesale-df-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('wholesale_df_buyer_confirm_dialog_wallet_courier'), findsOneWidget);
    });

    testWidgets('карта буюртмаси — аввалги матнлар (ўзгармаган)', (tester) async {
      await _detail(tester, _order(method: WholesalePaymentMethod.cardOnDelivery, df: _df('customer_absent')), _buyer);
      expect(find.text('wholesale_df_buyer_body'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wholesale-df-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('wholesale_df_buyer_confirm_dialog'), findsOneWidget);
    });

    testWidgets('сотувчи, ҳамён: «Етказилмади» ойнаси — «қайтариш ҳақини сиз тўламайсиз»', (tester) async {
      await _detail(tester, _order(df: _df('customer_refused')), _seller, now: _due);
      await tester.tap(find.byKey(const ValueKey('wholesale-df-failed')));
      await tester.pumpAndSettle();
      expect(find.text('wholesale_df_seller_failed_dialog_wallet'), findsOneWidget);
    });

    testWidgets('рад этилгач: харидорга ҳамён қайтими изоҳи; қарз — тўлдириш тугмаси билан; сотувчида қарз огоҳлантириши йўқ', (tester) async {
      final o = _order(
        status: WholesaleOrderStatus.refused,
        walletRefusal: {'fault': 'buyer', 'goodsRefunded': 140000, 'returnFeeCharged': 140000},
        returnDebt: {'amount': 1, 'payer': 'buyer'},
        returnStatus: 'awaiting_payment',
      );
      await _detail(tester, o, _buyer);
      expect(find.byKey(const ValueKey('wholesale-wallet-refund-notice')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-buyer-return-debt')), findsOneWidget);
      expect(find.text('wholesale_return_status_awaiting_payment_buyer'), findsOneWidget);
      await _detail(tester, o, _seller);
      expect(find.byKey(const ValueKey('wholesale-wallet-refund-notice')), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-return-debt')), findsNothing);
    });
  });

  group('курьер', () {
    testWidgets('ҳамён буюртмаси: ойнада «бошқа» йўқ, огоҳлантириш бор; сабаб → callable', (tester) async {
      final demand = await _courier(tester, {
        ..._state,
        'paymentMethod': 'wallet',
        'allowedReasons': ['customer_absent', 'customer_refused', 'courier_problem'],
      });
      demand.handlers['markWholesaleBuyerRefused'] = (_) => {'ok': true, 'status': 'in_delivery', 'awaitingBuyer': true, 'stage': 'awaiting_buyer'};
      expect(find.text('wholesale_courier_failed_hint_all'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wholesale-failed-reason-other')), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-failed-reason-courier_problem')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-failed-wallet-note')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wholesale-failed-reason-courier_problem')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused-yes')));
      await tester.pumpAndSettle();
      expect(demand.calls.where((c) => c.$1 == 'markWholesaleBuyerRefused').single.$2, {'orderId': 'o1', 'reasonCode': 'courier_problem'});
    });

    testWidgets('карта / эски сервер (allowedReasons йўқ): 4 сабаб, огоҳлантириш йўқ', (tester) async {
      await _courier(tester, _state);
      await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wholesale-failed-reason-other')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-failed-wallet-note')), findsNothing);
    });
  });
}

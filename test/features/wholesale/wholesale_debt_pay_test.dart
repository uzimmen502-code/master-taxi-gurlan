// Харидор қарзини AVA ҳамёнидан тўлаш (эга, 2026-11-15, A вариант): қарз банерида «Тўлаш ({amount})» →
// тасдиқ ойнаси → `payWholesaleBuyerDebt` (default codebase, `_wallet`), етмаса — етишмаётган сумма билан
// «Ҳамённи тўлдириш», муваффақият — snack; хато калитлари; checkout'да «қаерда тўлаш» изоҳи.
// Пул — серверда. Тестда `tr` калитнинг ўзини қайтаради.
import 'package:ava_gurlan/features/wholesale/models/wholesale_order.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_orders_repository.dart';
import 'package:ava_gurlan/features/wholesale/screens/wholesale_order_detail_screen.dart';
import 'package:ava_gurlan/features/wholesale/utils/wholesale_order_errors.dart';
import 'package:ava_gurlan/features/wholesale/widgets/ship_from_fields.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_checkout_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wholesale_orders_fakes.dart';

const _buyer = '998900000001';
const _seller = '998901111111';

class _Harness {
  final demand = FakeFunctions('demand');
  final wallet = FakeFunctions('wallet');
  late final repo = WholesaleOrdersRepository(firestore: FakeDb(), demandFunctions: demand, walletFunctions: wallet);
}

WholesaleOrder _order(Map<String, dynamic> debt, {String? dpm = 'cash', Map<String, dynamic>? extra}) =>
    WholesaleOrder.fromMap('o1', {
      'buyerId': _buyer,
      'sellerId': _seller,
      'productTitle': 'Гуруч',
      'qty': 10,
      'unitPrice': 14000,
      'goodsTotal': 140000,
      'deliveryFee': 60000,
      'total': 200000,
      'status': WholesaleOrderStatus.returning,
      'paymentMethod': WholesalePaymentMethod.wallet,
      'sellerDecision': 'accepted',
      'shipment': {'shipmentId': 's1', 'trackingNumber': 'AVA-1'},
      if (dpm != null) 'deliveryPaymentMethod': dpm,
      'returnDebt': debt,
      ...?extra,
    });

const _cashDebt = {'payer': 'buyer', 'kind': 'cash_refusal', 'amount': 85000, 'status': 'open'};

Future<_Harness> _detail(WidgetTester tester, WholesaleOrder o, String viewer) async {
  final h = _Harness();
  tester.view.physicalSize = const Size(400 * 2, 2000 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: WholesaleOrderDetailView(
              order: o, viewerId: viewer, repository: h.repo, now: () => DateTime(2026, 11, 15, 12)))));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final f = find.byKey(key);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('қарз банери → «Тўлаш»', () {
    testWidgets('нақд рад қарзи: тугма; тасдиқ → payWholesaleBuyerDebt {orderId} (_wallet), snack', (tester) async {
      final h = await _detail(tester, _order(_cashDebt), _buyer);
      expect(find.byKey(const ValueKey('wholesale-buyer-cash-debt')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-debt-pay')), findsOneWidget);
      expect(find.text('wholesale_debt_pay_btn'), findsOneWidget);
      h.wallet.handlers['payWholesaleBuyerDebt'] =
          (_) => {'ok': true, 'paid': true, 'idempotent': false, 'kind': 'cash_refusal', 'amount': 85000};
      await _tap(tester, const ValueKey('wholesale-debt-pay'));
      // Тасдиқ ойнаси: сарлавҳа ва матн; «Йўқ» — сўров йўқ.
      expect(find.text('wholesale_debt_pay_title'), findsOneWidget);
      expect(find.text('wholesale_debt_pay_confirm'), findsOneWidget);
      await tester.tap(find.text('consent_no'));
      await tester.pumpAndSettle();
      expect(h.wallet.calls, isEmpty);
      expect(h.demand.calls, isEmpty);
      await _tap(tester, const ValueKey('wholesale-debt-pay'));
      await _tap(tester, const ValueKey('wholesale-confirm-yes'));
      expect(h.wallet.calls.single.$1, 'payWholesaleBuyerDebt');
      expect(h.wallet.calls.single.$2, {'orderId': 'o1'}, reason: 'сумма сервердан — илова юбормайди');
      expect(h.demand.calls, isEmpty, reason: 'default codebase (us-central1)');
      expect(find.text('wholesale_debt_paid'), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-debt-pay-insufficient')), findsNothing);
    });

    testWidgets('ҳамён етмади: insufficient_balance {amount, balance} → етишмаётган сумма + «Ҳамённи тўлдириш»',
        (tester) async {
      final h = await _detail(tester, _order(_cashDebt), _buyer);
      h.wallet.handlers['payWholesaleBuyerDebt'] =
          (_) => throw fnError('failed-precondition', 'insufficient_balance', {'amount': 85000, 'balance': 30000});
      await _tap(tester, const ValueKey('wholesale-debt-pay'));
      await _tap(tester, const ValueKey('wholesale-confirm-yes'));
      expect(find.byKey(const ValueKey('wholesale-debt-pay-insufficient')), findsOneWidget);
      expect(find.text('wholesale_debt_pay_insufficient'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('wholesale-debt-pay-insufficient')),
              matching: find.byKey(const ValueKey('wallet-inline-error-topup'))),
          findsOneWidget);
      expect(find.text('wholesale_debt_paid'), findsNothing);
      expect(find.text('wholesale_order_err_insufficient_balance'), findsNothing, reason: 'умумий хато эмас — тўлдириш CTA');
      // Қайта уриниш (тўлдиргач) — CTA йўқолади.
      h.wallet.handlers['payWholesaleBuyerDebt'] = (_) => {'ok': true, 'paid': true, 'idempotent': false};
      await _tap(tester, const ValueKey('wholesale-debt-pay'));
      await _tap(tester, const ValueKey('wholesale-confirm-yes'));
      expect(find.byKey(const ValueKey('wholesale-debt-pay-insufficient')), findsNothing);
      expect(h.wallet.calls.length, 2);
    });

    testWidgets('бошқа хато (debt_not_ready) — матн калити, snack йўқ', (tester) async {
      final h = await _detail(tester, _order(_cashDebt), _buyer);
      h.wallet.handlers['payWholesaleBuyerDebt'] = (_) => throw fnError('failed-precondition', 'debt_not_ready');
      await _tap(tester, const ValueKey('wholesale-debt-pay'));
      await _tap(tester, const ValueKey('wholesale-confirm-yes'));
      expect(find.text('wholesale_debt_err_not_ready'), findsOneWidget);
      expect(find.text('wholesale_debt_paid'), findsNothing);
    });

    testWidgets('ҳамён радидаги қайтариш ҳақи қарзи: эски тўлдириш тугмаси + «Тўлаш»', (tester) async {
      final h = await _detail(
          tester,
          _order({'payer': 'buyer', 'amount': 1}, dpm: null, extra: {
            'status': WholesaleOrderStatus.refused,
            'walletRefusal': {'fault': 'buyer'},
          }),
          _buyer);
      expect(find.byKey(const ValueKey('wholesale-buyer-return-debt')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-debt-pay')), findsOneWidget);
      h.wallet.handlers['payWholesaleBuyerDebt'] = (_) => {'ok': true, 'paid': true, 'kind': 'return_fee', 'amount': 1};
      await _tap(tester, const ValueKey('wholesale-debt-pay'));
      await _tap(tester, const ValueKey('wholesale-confirm-yes'));
      expect(h.wallet.calls.single.$2, {'orderId': 'o1'});
      expect(find.text('wholesale_debt_paid'), findsOneWidget);
    });

    testWidgets('сотувчи ва қарзсиз харидор — тугма йўқ', (tester) async {
      await _detail(tester, _order(_cashDebt), _seller);
      expect(find.byKey(const ValueKey('wholesale-debt-pay')), findsNothing);
      await _detail(tester, _order(const {}), _buyer);
      expect(find.byKey(const ValueKey('wholesale-debt-pay')), findsNothing);
      // Курьер қарзи (payer courier) — харидор тўламайди.
      await _detail(tester, _order({'payer': 'courier', 'amount': 5}, dpm: null), _buyer);
      expect(find.byKey(const ValueKey('wholesale-debt-pay')), findsNothing);
    });
  });

  group('хато калитлари', () {
    test('қарз тўлови сабаблари', () {
      String k(String reason, [Map<String, dynamic> d = const {}]) =>
          wholesaleOrderErrorKey(WholesaleOrderException('failed-precondition', reason, details: d));
      expect(k('debt_not_open'), 'wholesale_debt_err_none');
      expect(k('debt_not_ready'), 'wholesale_debt_err_not_ready');
      expect(k('debt_changed'), 'wholesale_order_err_retry');
      expect(k('debt_payment_unavailable'), 'wholesale_debt_err_unavailable');
      for (final r in [
        'debt_kind_mismatch',
        'debt_shipment_mismatch',
        'debt_state_mismatch',
        'debt_components_mismatch',
        'debt_ava_cover_mismatch',
        'cash_split_mismatch',
        'collector_wallet_missing',
        'fee_config_invalid',
      ]) {
        expect(k(r), 'wholesale_debt_err_unavailable', reason: r);
      }
      expect(k('insufficient_balance', {'amount': 1, 'balance': 0}), 'wholesale_order_err_insufficient_balance');
      expect(k('not_order_party'), 'wholesale_order_err_not_party');
    });

    test('repository: payBuyerDebt → _wallet, payload фақат orderId; хато details сақланади', () async {
      final h = _Harness();
      h.wallet.handlers['payWholesaleBuyerDebt'] =
          (_) => throw fnError('failed-precondition', 'insufficient_balance', {'amount': 85000, 'balance': 10});
      try {
        await h.repo.payBuyerDebt('o7');
        fail('кутилган хато');
      } on WholesaleOrderException catch (e) {
        expect([e.reason, e.detailInt('amount'), e.detailInt('balance')], ['insufficient_balance', 85000, 10]);
      }
      expect(h.wallet.calls.single.$2, {'orderId': 'o7'});
      expect(h.demand.calls, isEmpty);
    });
  });

  group('checkout', () {
    testWidgets('buyer_debt: «аввал қарзни тўланг» + қаерда тўлаш изоҳи', (tester) async {
      final h = _Harness();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => {
            ...quoteReply(quoteId: 'q-debt'),
            'deliveryMethod': 'ava_courier',
            'deliveryMethods': {'ava_courier': true, 'self': false},
            'deliveryPaymentMethods': {'wallet': true, 'cash': false},
            'cashUnavailableReason': 'buyer_debt',
            'deliveryPaymentMethod': 'wallet',
          };
      tester.view.physicalSize = const Size(400 * 2, 2000 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final product = sampleProduct();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WholesaleCheckoutSheet(
            product: product,
            pack: product.packById('p2'),
            qty: 2,
            repository: h.repo,
            geoRepository: FakeGeo(),
            balance: Stream.value(10000000),
            initialDestination:
                const ShipFromDraft(regionId: 'xorazm', districtId: 'gurlan', address: 'Мустақиллик кўчаси 5'),
            onTopUp: (_, __) {},
            debounce: Duration.zero,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('wholesale_cash_unavailable_buyer_debt'), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-cash-debt-pay-hint')), findsOneWidget);
      expect(find.text('wholesale_cash_unavailable_buyer_debt_hint'), findsOneWidget);
    });
  });
}

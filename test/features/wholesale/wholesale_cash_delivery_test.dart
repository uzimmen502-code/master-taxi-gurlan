// S57 нақд етказиш (эга, 2026-11-14; сервер жонли, флаг `cashDeliveryEnabled` ҳозир ЎЧИҚ):
// checkout танлови ФАҚАТ квота айтса, қарз сабаби, квота payload'и, тўлов режаси; харидор саҳифаси
// (курьерга нақд, рад огоҳлантириши, қарз банери, `courier_chain_expired`); сотувчи матнлари;
// курьер — LEG карточкасидаги сумма, «етказилмади»да тўлади/тўламади → `cashPaid`, «курьер муаммоси» йўқ;
// хато матнлари. Пул — серверда; бу ерда фақат кўрсатиш. Тестда `tr` калитнинг ўзини қайтаради.
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:ava_gurlan/features/demand_offer/domain/demand_match.dart';
import 'package:ava_gurlan/features/logistics/data/logistics_repository.dart';
import 'package:ava_gurlan/features/logistics/domain/logistics_models.dart';
import 'package:ava_gurlan/features/logistics/services/logistics_photo_storage.dart';
import 'package:ava_gurlan/features/logistics/ui/leg_actions.dart';
import 'package:ava_gurlan/features/logistics/ui/logistics_text.dart';
import 'package:ava_gurlan/features/logistics/ui/logistics_ui_adapter.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_order.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_quote.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_orders_repository.dart';
import 'package:ava_gurlan/features/wholesale/screens/wholesale_order_detail_screen.dart';
import 'package:ava_gurlan/features/wholesale/utils/wholesale_order_errors.dart';
import 'package:ava_gurlan/features/wholesale/widgets/ship_from_fields.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_checkout_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wholesale_orders_fakes.dart';

const _buyer = '998900000001';
const _seller = '998901111111';
const _courierId = '998903333333';
const _dest = ShipFromDraft(regionId: 'xorazm', districtId: 'gurlan', address: 'Мустақиллик кўчаси 5');

/// Сервер квотаси (S57 шакли): нақд сўралса `deliveryPaymentMethod: cash`, `cashToCourier`, `payPlan`.
Map<String, dynamic> _cashQuote(
  Map<String, dynamic> p, {
  bool cashOk = true,
  String? reason,
  Map<String, dynamic>? paymentMethods,
}) {
  final method = '${p['paymentMethod'] ?? 'wallet'}';
  final cash = p['deliveryPaymentMethod'] == 'cash';
  const goods = 640000;
  const fee = 45000;
  final walletNow = method == 'wallet' ? goods + (cash ? 0 : fee) : (cash ? 0 : fee);
  return {
    ...quoteReply(quoteId: 'q-$method-${cash ? 'cash' : 'wallet'}', paymentMethods: paymentMethods),
    'deliveryMethod': 'ava_courier',
    'deliveryMethods': {'ava_courier': true, 'self': false},
    'deliveryPaymentMethods': {'wallet': true, 'cash': cashOk},
    'cashUnavailableReason': cashOk ? null : (reason ?? 'cash_disabled'),
    'deliveryPaymentMethod': cash ? 'cash' : 'wallet',
    if (cash) 'cashToCourier': fee,
    'payPlan': {
      'walletNow': walletNow,
      'atDoorToSellerCard': method == 'card_on_delivery' ? goods : 0,
      'bankTransfer': method == 'bank_transfer' ? goods : 0,
      if (cash) 'cashToCourier': fee,
    },
    if (method != 'wallet') 'walletHold': cash ? 0 : fee,
  };
}

class _Harness {
  final demand = FakeFunctions('demand');
  final wallet = FakeFunctions('wallet');
  late final repo = WholesaleOrdersRepository(firestore: FakeDb(), demandFunctions: demand, walletFunctions: wallet);
}

Future<void> _openCheckout(WidgetTester tester, _Harness h, {int balance = 10000000}) async {
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
        balance: Stream.value(balance),
        initialDestination: _dest,
        onTopUp: (_, __) {},
        debounce: Duration.zero,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final f = find.byKey(key);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

WholesaleOrder _order({
  String status = WholesaleOrderStatus.inDelivery,
  String method = WholesalePaymentMethod.wallet,
  String? dpm = 'cash',
  Map<String, dynamic>? extra,
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
      'sellerDecision': 'accepted',
      if (method == WholesalePaymentMethod.cardOnDelivery) 'cardPayment': {'status': 'awaiting'},
      if (method == WholesalePaymentMethod.cardOnDelivery) 'deliveryPaidBy': 'buyer',
      'shipment': {'shipmentId': 's1', 'trackingNumber': 'AVA-1'},
      if (dpm != null) 'deliveryPaymentMethod': dpm,
      ...?extra,
    });

Future<_Harness> _detail(WidgetTester tester, WholesaleOrder o, String viewer, {DateTime? now}) async {
  final h = _Harness();
  tester.view.physicalSize = const Size(400 * 2, 2000 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: WholesaleOrderDetailView(
              order: o, viewerId: viewer, repository: h.repo, now: () => now ?? DateTime(2026, 11, 14, 12, 5)))));
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

DemandMatch _match({String status = 'in_progress', Map<String, dynamic> attrs = const {}}) =>
    DemandMatch.fromMap('l1_$_courierId', {
      'demandId': 'l1',
      'providerId': _courierId,
      'module': 'logistics',
      'mode': 'quote',
      'status': status,
      'projection': {
        'attributes': {'shipmentId': 's1', 'trackingNumber': 'AVA-1', 'legIndex': 0, 'legCount': 1, ...attrs},
      },
    });

Future<FakeFunctions> _courier(WidgetTester tester, Map<String, dynamic> state, {Map<String, dynamic> attrs = const {}}) async {
  final demand = FakeFunctions('demand');
  demand.handlers['getWholesaleDeliveryFailedState'] = (_) => state;
  tester.view.physicalSize = const Size(400 * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: LogisticsLegActions(
        match: _match(attrs: attrs),
        providerId: _courierId,
        repository: _FakeLogistics(const {'source': 'wholesale', 'wholesaleOrderId': 'o1'}),
        photos: _FakePhotos(),
        wholesaleRepository:
            WholesaleOrdersRepository(firestore: FakeDb(), demandFunctions: demand, walletFunctions: FakeFunctions('wallet')),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return demand;
}

const _cashState = {
  'ok': true,
  'orderId': 'o1',
  'status': 'in_delivery',
  'pending': false,
  'stage': null,
  'resolution': null,
  'paymentMethod': 'wallet',
  'allowedReasons': ['customer_absent', 'customer_refused'],
  'deliveryPaymentMethod': 'cash',
  'cashToCollect': 60000,
  'cashDue': {'deliveryFee': 60000, 'returnFee': 40000, 'total': 100000},
};

void main() {
  group('модел', () {
    test('квота: нақд мумкин / қарз сабаби / эски сервер (калит йўқ) — нақд йўқ', () {
      final q = WholesaleQuote.fromMap(_cashQuote({'paymentMethod': 'wallet', 'deliveryPaymentMethod': 'cash'}));
      expect([q.cashDeliveryAvailable, q.isCashDelivery, q.cashToCourier, q.payPlan!.cashToCourier, q.payPlan!.walletNow],
          [true, true, 45000, 45000, 640000]);
      final d = WholesaleQuote.fromMap(_cashQuote({'paymentMethod': 'wallet'}, cashOk: false, reason: 'buyer_debt'));
      expect([d.cashDeliveryAvailable, d.cashUnavailableReason, d.isCashDelivery, d.cashToCourier], [false, 'buyer_debt', false, 0]);
      final old = WholesaleQuote.fromMap(quoteReply());
      expect([old.cashDeliveryAvailable, old.isCashDelivery, old.payPlan], [false, false, null]);
    });

    test('буюртма: нақд майдонлари; эски ҳужжат — ҳамён, 0; ўз етказишида нақд йўқ', () {
      final o = _order(extra: {
        'cashDelivery': {'status': 'opened', 'amount': 61000},
        'returnDebt': {'payer': 'buyer', 'kind': 'cash_refusal', 'amount': 100000, 'status': 'open'},
        'cashRefusal': {'paid': false, 'total': 100000},
      });
      expect([o.isCashDelivery, o.cashToCourierAmount, o.hasBuyerCashDebt, o.cashRefusalPaid, o.returnDebtStatus],
          [true, 61000, true, false, 'open']);
      expect(_order(extra: const {}).cashToCourierAmount, 60000, reason: 'cashDelivery йўқ — етказиш ҳақи');
      final old = _order(dpm: null);
      expect([old.isCashDelivery, old.cashToCourierAmount, old.hasBuyerCashDebt], [false, 0, false]);
      expect(_order(extra: {'deliveryMethod': 'self'}).isCashDelivery, isFalse);
      // Банк + нақд: ҳамёндан ҳеч нарса ушланмаган (bank `walletHeldDeliveryOnly` эмас).
      expect(_order(method: WholesalePaymentMethod.bankTransfer).walletHeldDeliveryOnly, isFalse);
      expect(_order(method: WholesalePaymentMethod.bankTransfer, dpm: 'wallet').walletHeldDeliveryOnly, isTrue);
    });

    test('амаллар: нақд қарз алоҳида банер (ҳамён қарзи эмас); рад огоҳлантириши фақат етказилгунча', () {
      final debt = _order(status: WholesaleOrderStatus.refused, extra: {
        'returnDebt': {'payer': 'buyer', 'kind': 'cash_refusal', 'amount': 100000, 'status': 'open'},
      });
      final a = WholesaleOrderActions.of(debt, _buyer);
      expect([a.showBuyerCashDebt, a.showBuyerReturnDebt, a.showCashToCourier], [true, false, false]);
      expect(WholesaleOrderActions.of(debt, _seller).showBuyerCashDebt, isFalse);
      // Ҳамён қарзи (kind йўқ) — аввалгидек.
      final w = _order(status: WholesaleOrderStatus.refused, dpm: null, extra: {
        'returnDebt': {'payer': 'buyer', 'amount': 1},
      });
      expect([WholesaleOrderActions.of(w, _buyer).showBuyerReturnDebt, WholesaleOrderActions.of(w, _buyer).showBuyerCashDebt],
          [true, false]);
      expect(WholesaleOrderActions.of(_order(), _buyer).showCashToCourier, isTrue);
      expect(WholesaleOrderActions.of(_order(status: WholesaleOrderStatus.placed), _buyer).showCashToCourier, isTrue);
      expect(WholesaleOrderActions.of(_order(status: WholesaleOrderStatus.delivered), _buyer).showCashToCourier, isFalse);
      expect(WholesaleOrderActions.of(_order(), _seller).showCashToCourier, isFalse);
      expect(WholesaleOrderActions.of(_order(dpm: null), _buyer).showCashToCourier, isFalse);
    });

    test('курьер ҳолати: нақд — фақат харидор сабаблари, ҳамён огоҳлантириши эмас; суммалар сервердан', () {
      final r = WholesaleDeliveryFailedReport.fromMap(_cashState);
      expect([r.isCashOrder, r.isWalletOrder, r.reasons, r.cashToCollect, r.cashDueTotal, r.cashDueReturnFee],
          [true, false, ['customer_absent', 'customer_refused'], 60000, 100000, 40000]);
      // Сервер рўйхати бўлмаса ҳам нақдда «курьер муаммоси» / «бошқа» йўқ.
      final noList = WholesaleDeliveryFailedReport.fromMap({'deliveryPaymentMethod': 'cash'});
      expect(noList.reasons, ['customer_absent', 'customer_refused']);
      final wallet = WholesaleDeliveryFailedReport.fromMap({
        'paymentMethod': 'wallet',
        'allowedReasons': ['customer_absent', 'customer_refused', 'courier_problem'],
      });
      expect([wallet.isCashOrder, wallet.isWalletOrder, wallet.reasons.contains('courier_problem')], [false, true, true]);
    });

    test('LEG проекцияси: cashToCollect фақат нақд + мусбат; эскроу — 0', () {
      final c = LegProjection.fromAttributes({'deliveryPaymentMethod': 'cash', 'cashToCollect': 60000, 'legIndex': 1, 'legCount': 2});
      expect([c.isCash, c.collectsCash, c.cashToCollect], [true, true, 60000]);
      final mid = LegProjection.fromAttributes({'deliveryPaymentMethod': 'cash', 'cashToCollect': 0, 'legCount': 2});
      expect([mid.isCash, mid.collectsCash], [true, false]);
      final escrow = LegProjection.fromAttributes({'legCount': 1});
      expect([escrow.isCash, escrow.collectsCash, escrow.cashToCollect], [false, false, 0]);
    });

    test('хато матнлари: нақд сабаблари, такрорсиз', () {
      String k(String r, [Map<String, dynamic> d = const {}]) =>
          wholesaleOrderErrorKey(WholesaleOrderException('failed-precondition', r, details: d));
      expect(k('cash_delivery_unavailable', {'cashUnavailableReason': 'buyer_debt'}), 'wholesale_cash_unavailable_buyer_debt');
      expect(k('cash_delivery_unavailable', {'cashUnavailableReason': 'cash_disabled'}), 'wholesale_cash_unavailable');
      expect(k('cash_delivery_unavailable'), 'wholesale_cash_unavailable');
      expect(k('cash_paid_required'), 'wholesale_courier_cash_err_paid_required');
      expect(k('cash_paid_absent'), 'wholesale_courier_cash_err_paid_absent');
      expect(k('reason_not_allowed_cash'), 'wholesale_courier_failed_err_reason');
      expect(wholesaleCashUnavailableKey('self_delivery'), 'wholesale_cash_unavailable');
      String lk(String r) => logisticsErrorKey(LogisticsException('failed-precondition', r, 'x'))!;
      expect(lk('cash_confirmation_required'), 'logistics_cash_err_confirm');
      expect(lk('cash_state_invalid'), 'logistics_cash_err_state');
      expect(lk('cash_collector_mismatch'), 'logistics_cash_err_collector');
    });

    test('confirmDelivery: cashCollected фақат нақдда юборилади', () async {
      final fns = FakeFunctions('demand');
      fns.handlers['confirmDelivery'] = (_) => {'ok': true};
      final repo = LogisticsRepository(firestore: FakeDb(), demandFunctions: fns, escrowFunctions: FakeFunctions('escrow'));
      await repo.confirmDelivery(legId: 'l1', deliveryCode: '123456', photoUrls: const ['u'], cashCollected: true);
      await repo.confirmDelivery(legId: 'l1', deliveryCode: '123456', photoUrls: const ['u']);
      expect(fns.calls[0].$2['cashCollected'], isTrue);
      expect(fns.calls[1].$2.containsKey('cashCollected'), isFalse);
    });
  });

  group('checkout', () {
    testWidgets('флаг ўчиқ (cash_disabled): танлов ҳам, сабаб ҳам йўқ; payload аввалгидек', (tester) async {
      final h = _Harness();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => _cashQuote(p, cashOk: false);
      await _openCheckout(tester, h);
      expect(find.byKey(const ValueKey('wholesale-delivery-pay-cash')), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-cash-unavailable')), findsNothing);
      expect(h.demand.calls.single.$2.containsKey('deliveryPaymentMethod'), isFalse);
    });

    testWidgets('қарз (buyer_debt): танлов йўқ, «аввал қарзни тўланг» бор', (tester) async {
      final h = _Harness();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => _cashQuote(p, cashOk: false, reason: 'buyer_debt');
      await _openCheckout(tester, h);
      expect(find.byKey(const ValueKey('wholesale-delivery-pay-cash')), findsNothing);
      expect(find.text('wholesale_cash_unavailable_buyer_debt'), findsOneWidget);
    });

    testWidgets('нақд мумкин: танланса квота cash билан; «курьерга нақд» қатори, рад огоҳлантириши; ҳамёндан фақат товар',
        (tester) async {
      final h = _Harness();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => _cashQuote(p);
      h.wallet.handlers['placeWholesaleOrder'] =
          (_) => {'ok': true, 'orderId': 'o9', 'status': 'placed', 'total': 685000, 'idempotent': false};
      await _openCheckout(tester, h, balance: 650000);
      expect(find.byKey(const ValueKey('wholesale-delivery-pay-wallet')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-cash-to-courier')), findsNothing);
      await _tap(tester, const ValueKey('wholesale-delivery-pay-cash'));
      expect(h.demand.calls.last.$2['deliveryPaymentMethod'], 'cash');
      expect(h.demand.calls.last.$2['paymentMethod'], 'wallet');
      expect(find.byKey(const ValueKey('wholesale-cash-to-courier')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-cash-wallet-now')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-cash-refusal-note')), findsOneWidget);
      // Баланс 650 000 ≥ товар 640 000 (етказиш курьерга) — ҳамён огоҳлантириши «етмайди» эмас.
      expect(find.text(formatMoney(640000)), findsWidgets);
      await _tap(tester, const ValueKey('wholesale-checkout-confirm'));
      expect(h.wallet.calls.single.$2['quoteId'], 'q-wallet-cash');
    });

    testWidgets('банк + нақд: квота bank_transfer + cash, ҳамёндан ҳеч нарса (огоҳлантириш йўқ), изоҳ — нақд матни',
        (tester) async {
      final h = _Harness();
      h.demand.handlers['quoteWholesaleOrder'] =
          (p) => _cashQuote(p, paymentMethods: {'wallet': true, 'card_on_delivery': false, 'bank_transfer': true});
      await _openCheckout(tester, h, balance: 0);
      await _tap(tester, const ValueKey('wholesale-pay-bank'));
      expect(h.demand.calls.last.$2['deliveryPaymentMethod'], 'wallet', reason: 'банк — аввалгидек ҳамён');
      await _tap(tester, const ValueKey('wholesale-delivery-pay-cash'));
      final last = h.demand.calls.last.$2;
      expect([last['paymentMethod'], last['deliveryPaymentMethod']], ['bank_transfer', 'cash']);
      expect(find.text('wholesale_pay_bank_note_cash'), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-bank-hold')), findsNothing);
      expect(find.byKey(const ValueKey('wallet-balance-info')), findsNothing);
    });

    testWidgets('сервер нақдни рад этди (cash_delivery_unavailable, buyer_debt) — ҳамёнга қайтади, сабаб кўринади',
        (tester) async {
      final h = _Harness();
      var debt = false;
      h.demand.handlers['quoteWholesaleOrder'] = (p) {
        if (p['deliveryPaymentMethod'] == 'cash' && debt) {
          throw fnError('failed-precondition', 'cash_delivery_unavailable', {'cashUnavailableReason': 'buyer_debt'});
        }
        return debt ? _cashQuote(p, cashOk: false, reason: 'buyer_debt') : _cashQuote(p);
      };
      await _openCheckout(tester, h);
      debt = true;
      await _tap(tester, const ValueKey('wholesale-delivery-pay-cash'));
      final calls = h.demand.calls.map((c) => c.$2['deliveryPaymentMethod']).toList();
      expect(calls, [null, 'cash', null]);
      expect(find.byKey(const ValueKey('wholesale-delivery-pay-cash')), findsNothing);
      expect(find.text('wholesale_cash_unavailable_buyer_debt'), findsOneWidget);
    });
  });

  group('харидор / сотувчи саҳифаси', () {
    testWidgets('харидор, йўлда: курьерга нақд сумма, рад огоҳлантириши, тўлов матни', (tester) async {
      await _detail(tester, _order(extra: {'cashDelivery': {'amount': 60000}}), _buyer);
      expect(find.byKey(const ValueKey('wholesale-cash-to-courier-notice')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-cash-refusal-notice')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-order-cash-to-courier')), findsOneWidget);
      expect(find.text('wholesale_order_payment_wallet_cash'), findsOneWidget);
    });

    testWidgets('ҳамён буюртмаси (нақд эмас) — нақд элементлари йўқ', (tester) async {
      await _detail(tester, _order(dpm: null), _buyer);
      expect(find.byKey(const ValueKey('wholesale-cash-to-courier-notice')), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-order-cash-to-courier')), findsNothing);
      expect(find.text('wholesale_order_payment_wallet'), findsOneWidget);
    });

    testWidgets('сотувчи: тўлов матни (банк + нақд), курьерга нақд қатори; харидор огоҳлантириши йўқ', (tester) async {
      await _detail(tester, _order(method: WholesalePaymentMethod.bankTransfer), _seller);
      expect(find.text('wholesale_order_payment_bank_cash'), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-order-cash-to-courier')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-cash-to-courier-notice')), findsNothing);
    });

    testWidgets('нақд рад қарзи: банер (тўлдириш тугмасисиз), ҳамён қарзи банери йўқ', (tester) async {
      await _detail(
          tester,
          _order(status: WholesaleOrderStatus.refused, extra: {
            'returnDebt': {'payer': 'buyer', 'kind': 'cash_refusal', 'amount': 100000, 'status': 'open'},
            'cashRefusal': {'paid': false, 'total': 100000},
          }),
          _buyer);
      expect(find.byKey(const ValueKey('wholesale-buyer-cash-debt')), findsOneWidget);
      expect(find.text('wholesale_order_cash_debt_buyer'), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-buyer-return-debt')), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-cash-refusal-paid')), findsNothing);
    });

    testWidgets('нақд рад, тўланди: изоҳ бор', (tester) async {
      await _detail(
          tester, _order(status: WholesaleOrderStatus.refused, extra: {'cashRefusal': {'paid': true, 'total': 100000}}), _buyer);
      expect(find.byKey(const ValueKey('wholesale-cash-refusal-paid')), findsOneWidget);
    });

    testWidgets('бекор: courier_chain_expired — ҳамён (тўлиқ қайтариш) / банк + нақд (ушланмаган)', (tester) async {
      await _detail(tester, _order(status: WholesaleOrderStatus.cancelled, extra: {'cancelReason': 'courier_chain_expired'}), _buyer);
      expect(find.text('wholesale_order_cancel_courier_chain_expired'), findsOneWidget);
      await _detail(
          tester,
          _order(
              status: WholesaleOrderStatus.cancelled,
              method: WholesalePaymentMethod.bankTransfer,
              extra: {'cancelReason': 'courier_chain_expired'}),
          _buyer);
      expect(find.text('wholesale_order_cancel_courier_chain_expired_nohold'), findsOneWidget);
    });

    testWidgets('«етказилмади», харидор: нақд матни, курьер белгиси, тасдиқ ойнаси — тўламади (қарз)', (tester) async {
      final df = {
        'seq': 1,
        'open': true,
        'stage': 'awaiting_buyer',
        'reasonCode': 'customer_refused',
        'escalateAt': Timestamp.fromDate(DateTime(2026, 11, 14, 12, 20)),
        'cash': {'paid': false, 'deliveryFee': 60000, 'returnFee': 40000, 'total': 100000},
      };
      await _detail(tester, _order(extra: {'deliveryFailed': df}), _buyer);
      expect(find.text('wholesale_df_buyer_body_cash'), findsOneWidget);
      expect(find.text('wholesale_df_cash_unpaid_line'), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-cash-to-courier-notice')), findsNothing, reason: 'сўров очиқ');
      await _tap(tester, const ValueKey('wholesale-df-confirm'));
      expect(find.text('wholesale_df_buyer_confirm_dialog_cash_unpaid'), findsOneWidget);
    });

    testWidgets('сотувчи қабул ойнаси: нақд матни', (tester) async {
      final h = await _detail(
          tester,
          _order(status: WholesaleOrderStatus.placed, extra: {
            'sellerDecision': 'pending',
            'acceptDeadlineAt': Timestamp.fromDate(DateTime(2026, 11, 16)),
          }),
          _seller);
      h.demand.handlers['acceptWholesaleOrder'] = (_) => {'ok': true};
      await _tap(tester, const ValueKey('wholesale-order-accept'));
      expect(find.text('wholesale_order_accept_confirm_cash'), findsOneWidget);
    });
  });

  group('курьер', () {
    testWidgets('LEG карточкаси: нақд оладиган LEG — сумма; ўрта LEG ва эскроу — йўқ', (tester) async {
      Future<void> card(Map<String, dynamic> attrs) => tester.pumpWidget(MaterialApp(
          home: Scaffold(body: LegMatchCard(match: _match(status: 'new', attrs: attrs)))));
      await card({'deliveryPaymentMethod': 'cash', 'cashToCollect': 60000});
      expect(find.byKey(const ValueKey('leg-cash-to-collect')), findsOneWidget);
      expect(find.text('60 000 sum'), findsOneWidget);
      await card({'deliveryPaymentMethod': 'cash', 'cashToCollect': 0, 'legCount': 2});
      expect(find.byKey(const ValueKey('leg-cash-to-collect')), findsNothing);
      await card(const {});
      expect(find.byKey(const ValueKey('leg-cash-to-collect')), findsNothing);
    });

    testWidgets('олишдан олдин ойнада ҳам сумма', (tester) async {
      tester.view.physicalSize = const Size(400 * 2, 1600 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: LogisticsLegActions(
        match: _match(status: 'new', attrs: {'deliveryPaymentMethod': 'cash', 'cashToCollect': 60000}),
        providerId: _courierId,
        repository: _FakeLogistics(const {}),
        photos: _FakePhotos(),
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('logistics_leg_take'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.byKey(const ValueKey('leg-cash-to-collect'))),
          findsOneWidget);
    });

    testWidgets('етказиш қадами: сумма + далил варағида «нақд олдим» белгиси (белгисиз тасдиқ ёпиқ)', (tester) async {
      await _courier(tester, _cashState, attrs: {'deliveryPaymentMethod': 'cash', 'cashToCollect': 60000});
      expect(find.byKey(const ValueKey('leg-cash-to-collect')), findsOneWidget);
      await tester.tap(find.text('logistics_delivered_btn'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('proof-cash-collected')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('proof-submit'))).onPressed, isNull);
    });

    testWidgets('эскроу LEG: далил варағида нақд белгиси йўқ', (tester) async {
      await _courier(tester, const {'ok': true, 'orderId': 'o1', 'status': 'in_delivery', 'pending': false});
      expect(find.byKey(const ValueKey('leg-cash-to-collect')), findsNothing);
      await tester.tap(find.text('logistics_delivered_btn'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('proof-cash-collected')), findsNothing);
    });

    testWidgets('«етказилмади» нақд: «курьер муаммоси» йўқ, суммалар, «Харидор тўлади» → cashPaid true', (tester) async {
      final demand = await _courier(tester, _cashState);
      demand.handlers['markWholesaleBuyerRefused'] =
          (_) => {'ok': true, 'status': 'in_delivery', 'awaitingBuyer': true, 'stage': 'awaiting_buyer'};
      await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wholesale-failed-reason-courier_problem')), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-failed-reason-other')), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-failed-wallet-note')), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-failed-cash')), findsOneWidget);
      expect(find.textContaining('100 000'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wholesale-failed-reason-customer_refused')));
      await tester.pumpAndSettle();
      // Тўлов натижаси танланмагунча тасдиқ ёпиқ.
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('wholesale-courier-refused-yes'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('wholesale-failed-cash-paid')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused-yes')));
      await tester.pumpAndSettle();
      expect(demand.calls.where((c) => c.$1 == 'markWholesaleBuyerRefused').single.$2,
          {'orderId': 'o1', 'reasonCode': 'customer_refused', 'cashPaid': true});
    });

    testWidgets('«етказилмади» нақд, харидор йўқ: «тўлади» ёпиқ, автоматик «тўламади» → cashPaid false', (tester) async {
      final demand = await _courier(tester, _cashState);
      demand.handlers['markWholesaleBuyerRefused'] =
          (_) => {'ok': true, 'status': 'in_delivery', 'awaitingBuyer': true, 'stage': 'awaiting_buyer'};
      await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-failed-reason-customer_absent')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('wholesale-failed-cash-paid'))).onSelected, isNull);
      expect(find.byKey(const ValueKey('wholesale-failed-cash-unpaid-note')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused-yes')));
      await tester.pumpAndSettle();
      expect(demand.calls.where((c) => c.$1 == 'markWholesaleBuyerRefused').single.$2,
          {'orderId': 'o1', 'reasonCode': 'customer_absent', 'cashPaid': false});
    });

    testWidgets('нақд бўлмаган буюртма: cashPaid юборилмайди, нақд бўлими йўқ', (tester) async {
      final demand = await _courier(tester, const {
        'ok': true,
        'orderId': 'o1',
        'status': 'in_delivery',
        'pending': false,
        'paymentMethod': 'wallet',
        'allowedReasons': ['customer_absent', 'customer_refused', 'courier_problem'],
      });
      demand.handlers['markWholesaleBuyerRefused'] =
          (_) => {'ok': true, 'status': 'in_delivery', 'awaitingBuyer': true, 'stage': 'awaiting_buyer'};
      await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wholesale-failed-cash')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('wholesale-failed-reason-customer_absent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused-yes')));
      await tester.pumpAndSettle();
      expect(demand.calls.where((c) => c.$1 == 'markWholesaleBuyerRefused').single.$2,
          {'orderId': 'o1', 'reasonCode': 'customer_absent'});
    });
  });
}

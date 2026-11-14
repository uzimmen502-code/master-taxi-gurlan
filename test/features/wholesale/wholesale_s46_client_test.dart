// S6 (карта: етказиш ҳақини харидор ҳамёндан тўлайди) ва S4 (сотувчининг ўз
// етказиши) клиенти — сервер 2026-11-14 дан жонли. Тестда `tr` калитнинг ўзини
// қайтаради. Пул фақат сервердан — бу ерда фақат кўрсатиш ва тугмалар текширилади.
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_order.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_quote.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_seller.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_orders_repository.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_sellers_repository.dart';
import 'package:ava_gurlan/features/wholesale/screens/wholesale_order_detail_screen.dart';
import 'package:ava_gurlan/features/wholesale/utils/wholesale_order_errors.dart';
import 'package:ava_gurlan/features/wholesale/widgets/ship_from_fields.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_checkout_sheet.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_order_entries.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_order_status.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wholesale_orders_fakes.dart';

const _buyer = '998900000001';
const _seller = '998901111111';

WholesaleOrder _order({
  String status = WholesaleOrderStatus.placed,
  String method = WholesalePaymentMethod.wallet,
  String? deliveryMethod,
  String? deliveryPaidBy,
  Map<String, dynamic>? self,
  Map<String, dynamic>? card,
  Map<String, dynamic>? bank,
  String sellerDecision = 'accepted',
  String? refundStatus,
  int deliveryFee = 45000,
  Map<String, dynamic>? walletRefusal,
}) =>
    WholesaleOrder.fromMap('o1', {
      'buyerId': _buyer,
      'sellerId': _seller,
      'productId': 'prod1',
      'productTitle': 'Гуруч',
      'qty': 2,
      'unitPrice': 320000,
      'goodsTotal': 640000,
      'deliveryFee': deliveryFee,
      'total': 640000 + deliveryFee,
      'status': status,
      'paymentMethod': method,
      'sellerDecision': sellerDecision,
      'acceptedAt': DateTime(2026, 11, 14),
      if (deliveryMethod != null) 'deliveryMethod': deliveryMethod,
      if (deliveryPaidBy != null) 'deliveryPaidBy': deliveryPaidBy,
      if (self != null) 'selfDelivery': self,
      if (card != null) 'cardPayment': card,
      if (bank != null) 'bankPayment': bank,
      if (refundStatus != null) 'refundStatus': refundStatus,
      if (walletRefusal != null) 'walletRefusal': walletRefusal,
    });

WholesaleOrder _selfOrder({
  String status = WholesaleOrderStatus.placed,
  String method = WholesalePaymentMethod.wallet,
  String selfStatus = WholesaleSelfStatus.pending,
  String dropoff = 'buyer_address',
  Map<String, dynamic>? card,
  Map<String, dynamic>? bank,
  String? refundStatus,
}) =>
    _order(
      status: status,
      method: method,
      deliveryMethod: 'self',
      deliveryFee: 0,
      self: {'status': selfStatus, 'coverage': 'district', 'dropoff': dropoff},
      card: card,
      bank: bank,
      refundStatus: refundStatus,
    );

class _H {
  final demand = FakeFunctions('demand');
  final wallet = FakeFunctions('wallet');
  late final repo = WholesaleOrdersRepository(firestore: FakeDb(), demandFunctions: demand, walletFunctions: wallet);
}

Future<_H> _pumpOrder(WidgetTester tester, WholesaleOrder o, String viewer, {_H? h}) async {
  final hh = h ?? _H();
  tester.view.physicalSize = const Size(400 * 2, 2200 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: WholesaleOrderDetailView(order: o, viewerId: viewer, repository: hh.repo)),
  ));
  await tester.pumpAndSettle();
  return hh;
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final f = find.byKey(key);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

const _start = ValueKey('wholesale-self-start');
const _complete = ValueKey('wholesale-self-complete');
const _refused = ValueKey('wholesale-self-refused');
const _return = ValueKey('wholesale-self-return');
const _code = ValueKey('wholesale-delivery-code');

void main() {
  // ═════════════════════════════ S6 КАРТА ═════════════════════════════
  group('S6 карта: янги (deliveryPaidBy buyer) ва эски', () {
    test('модел: эшик олдидаги сумма — янгида фақат товар, эскида товар + етказиш', () {
      final n = _order(method: WholesalePaymentMethod.cardOnDelivery, deliveryPaidBy: 'buyer');
      final l = _order(method: WholesalePaymentMethod.cardOnDelivery);
      expect([n.isNewCard, n.isLegacyCard, n.cardAtDoorAmount], [true, false, 640000]);
      expect([l.isNewCard, l.isLegacyCard, l.cardAtDoorAmount], [false, true, 685000]);
      // Ҳамён буюртмасида `deliveryPaidBy` бўлса ҳам — карта эмас.
      expect(_order(deliveryPaidBy: 'buyer').isNewCard, isFalse);
      expect(n.walletHeldDeliveryOnly, isTrue);
      expect(l.walletHeldDeliveryOnly, isFalse);
    });

    testWidgets('янги карта: «ҳамёндан тўланди» қатори, эшик олдида товар суммаси, тўлов матни', (tester) async {
      await _pumpOrder(
          tester,
          _order(
              status: WholesaleOrderStatus.inDelivery,
              method: WholesalePaymentMethod.cardOnDelivery,
              deliveryPaidBy: 'buyer',
              card: {'status': 'awaiting'}),
          _seller);
      expect(find.text('wholesale_order_card_paid_wallet'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('wholesale-order-card-at-door')), matching: find.text(formatMoney(640000))),
          findsOneWidget);
      expect(find.text('wholesale_order_payment_card_new'), findsOneWidget);
      await _tap(tester, const ValueKey('wholesale-money-received'));
      expect(find.text('wholesale_order_money_received_confirm'), findsOneWidget);
    });

    testWidgets('эски карта: ҳамён қатори йўқ, эшик олдида жами (товар + етказиш) — аввалгидек', (tester) async {
      await _pumpOrder(
          tester,
          _order(
              status: WholesaleOrderStatus.inDelivery,
              method: WholesalePaymentMethod.cardOnDelivery,
              card: {'status': 'awaiting'}),
          _seller);
      expect(find.text('wholesale_order_card_paid_wallet'), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('wholesale-order-card-at-door')), matching: find.text(formatMoney(685000))),
          findsOneWidget);
      expect(find.text('wholesale_order_payment_card'), findsOneWidget);
    });

    testWidgets('янги карта «етказилмади»: харидорга банк матнлари (товар пули тилга олинмайди), сотувчига newcard',
        (tester) async {
      final o = WholesaleOrder.fromMap('o1', {
        'buyerId': _buyer,
        'sellerId': _seller,
        'goodsTotal': 640000,
        'deliveryFee': 45000,
        'total': 685000,
        'status': 'in_delivery',
        'paymentMethod': 'card_on_delivery',
        'deliveryPaidBy': 'buyer',
        'cardPayment': {'status': 'awaiting'},
        'deliveryFailed': {'open': true, 'reasonCode': 'customer_absent', 'escalatedAt': DateTime(2026)},
      });
      await _pumpOrder(tester, o, _buyer);
      expect(find.text('wholesale_df_buyer_body_bank'), findsOneWidget);
      await _pumpOrder(tester, o, _seller);
      await _tap(tester, const ValueKey('wholesale-df-failed'));
      expect(find.text('wholesale_df_seller_failed_dialog_newcard'), findsOneWidget);
    });

    test('янги карта рад, харидор айби: қайтариш ҳақи изоҳи; курьер айби ёки эски карта — йўқ', () {
      WholesaleOrder r(String? paidBy, String fault, int fee) => _order(
          status: WholesaleOrderStatus.refused,
          method: WholesalePaymentMethod.cardOnDelivery,
          deliveryPaidBy: paidBy,
          walletRefusal: {'fault': fault, 'returnFeeCharged': fee});
      expect(r('buyer', 'buyer', 30000).cardReturnFeeNoticeKey(_buyer), 'wholesale_order_card_return_fee_charged');
      expect(r('buyer', 'buyer', 30000).cardReturnFeeNoticeKey(_seller), isNull);
      expect(r('buyer', 'courier', 0).cardReturnFeeNoticeKey(_buyer), isNull);
      expect(r(null, 'buyer', 30000).cardReturnFeeNoticeKey(_buyer), isNull);
    });

    test('курьер ҳолати: янги карта (сабаблар рўйхатида «бошқа» йўқ) — ҳамён огоҳлантириши', () {
      expect(
          WholesaleDeliveryFailedReport.fromMap({
            'paymentMethod': 'card_on_delivery',
            'allowedReasons': ['customer_absent', 'customer_refused', 'courier_problem'],
          }).isWalletOrder,
          isTrue);
      expect(
          WholesaleDeliveryFailedReport.fromMap({
            'paymentMethod': 'card_on_delivery',
            'allowedReasons': ['customer_absent', 'customer_refused', 'courier_problem', 'other'],
          }).isWalletOrder,
          isFalse);
    });

    testWidgets('бекор (сотувчи рад этди): янги карта — банк матни; ўз етказиши карта — nohold; эски — аввалгидек',
        (tester) async {
      WholesaleOrder c({String? paidBy, String? dm}) => WholesaleOrder.fromMap('o1', {
            'buyerId': _buyer,
            'sellerId': _seller,
            'goodsTotal': 640000,
            'deliveryFee': dm == 'self' ? 0 : 45000,
            'total': dm == 'self' ? 640000 : 685000,
            'status': 'cancelled',
            'paymentMethod': 'card_on_delivery',
            'cancelReason': 'seller_rejected',
            if (paidBy != null) 'deliveryPaidBy': paidBy,
            if (dm != null) 'deliveryMethod': dm,
          });
      await _pumpOrder(tester, c(paidBy: 'buyer'), _buyer);
      expect(find.text('wholesale_order_cancel_seller_rejected_bank'), findsOneWidget);
      await _pumpOrder(tester, c(dm: 'self'), _buyer);
      expect(find.text('wholesale_order_cancel_seller_rejected_nohold'), findsOneWidget);
      await _pumpOrder(tester, c(), _buyer);
      expect(find.text('wholesale_order_cancel_seller_rejected'), findsOneWidget);
    });
  });

  // ═════════════════════════════ КВОТА МОДЕЛИ ═════════════════════════
  group('квота: payPlan ва deliveryMethods', () {
    test('янги сервер: payPlan, self мумкин, dropoff', () {
      final q = WholesaleQuote.fromMap({
        ...quoteReply(),
        'payPlan': {'walletNow': 45000, 'atDoorToSellerCard': 640000, 'bankTransfer': 0},
        'deliveryMethods': {'ava_courier': true, 'self': true},
        'selfUnavailableReason': null,
        'selfDelivery': {'coverage': 'region', 'dropoff': 'buyer_address'},
        'deliveryMethod': 'self',
      });
      expect(q.payPlan!.walletNow, 45000);
      expect(q.payPlan!.atDoorToSellerCard, 640000);
      expect([q.isSelf, q.selfAvailable, q.courierAvailable], [true, true, true]);
      expect([q.selfCoverage, q.selfDropoff], ['region', 'buyer_address']);
      expect(q.walletNowAmount, 45000);
    });

    test('эски сервер: deliveryMethods йўқ — фақат курьер, payPlan null', () {
      final q = WholesaleQuote.fromMap(quoteReply());
      expect([q.isSelf, q.selfAvailable, q.courierAvailable, q.payPlan], [false, false, true, null]);
      expect(q.walletNowAmount, isNull);
    });

    test('хато калити: self_delivery_unavailable — out_of_coverage алоҳида, қолгани умумий', () {
      expect(
          wholesaleOrderErrorKey(const WholesaleOrderException('failed-precondition', 'self_delivery_unavailable',
              details: {'selfUnavailableReason': 'out_of_coverage'})),
          'wholesale_self_unavailable_out_of_coverage');
      expect(
          wholesaleOrderErrorKey(const WholesaleOrderException('failed-precondition', 'self_delivery_unavailable',
              details: {'selfUnavailableReason': 'self_disabled'})),
          'wholesale_self_unavailable');
      expect(wholesaleOrderErrorKey(const WholesaleOrderException('invalid-argument', 'delivery_code_invalid')),
          'wholesale_self_err_code_invalid');
      expect(wholesaleOrderErrorKey(const WholesaleOrderException('resource-exhausted', 'code_locked')),
          'wholesale_self_err_code_locked');
      expect(wholesaleOrderErrorKey(const WholesaleOrderException('failed-precondition', 'refund_pending')),
          'wholesale_self_return_wait');
    });
  });

  // ═════════════════════════════ CHECKOUT ═════════════════════════════
  group('checkout: ўз етказиши ва S6 карта', () {
    const dest = ShipFromDraft(regionId: 'xorazm', districtId: 'gurlan', address: 'Мустақиллик кўчаси 5');

    Future<_H> open(WidgetTester tester, _H h, {int balance = 10000000}) async {
      tester.view.physicalSize = const Size(400 * 2, 2200 * 2);
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
            initialDestination: dest,
            onTopUp: (_, __) {},
            debounce: Duration.zero,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return h;
    }

    Map<String, dynamic> reply(Map<String, dynamic> p, {bool selfOk = true, String? selfReason}) {
      final self = p['deliveryMethod'] == 'self';
      final pm = (p['paymentMethod'] ?? 'wallet') as String;
      final fee = self ? 0 : 45000;
      return {
        ...quoteReply(
          quoteId: 'q-$pm-${self ? 'self' : 'courier'}',
          delivery: fee,
          paymentMethods: {'wallet': true, 'card_on_delivery': true, 'bank_transfer': true},
        ),
        'deliveryMethod': self ? 'self' : 'ava_courier',
        'deliveryMethods': {'ava_courier': true, 'self': selfOk},
        'selfUnavailableReason': selfOk ? null : (selfReason ?? 'self_disabled'),
        if (selfOk) 'selfDelivery': {'coverage': 'district', 'dropoff': 'district_center'},
        'payPlan': pm == 'card_on_delivery'
            ? {'walletNow': fee, 'atDoorToSellerCard': 640000, 'bankTransfer': 0}
            : (pm == 'bank_transfer'
                ? {'walletNow': fee, 'atDoorToSellerCard': 0, 'bankTransfer': 640000}
                : {'walletNow': 640000 + fee, 'atDoorToSellerCard': 0, 'bankTransfer': 0}),
        if (pm != 'wallet' && !(pm == 'bank_transfer' && self)) 'walletHold': fee,
      };
    }

    testWidgets('self мумкин эмас — танлов ЙЎҚ; қамровдан ташқари бўлса изоҳ', (tester) async {
      final h = _H();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => reply(p, selfOk: false, selfReason: 'out_of_coverage');
      await open(tester, h);
      expect(find.byKey(const ValueKey('wholesale-delivery-self')), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-self-out-of-coverage')), findsOneWidget);
      expect(h.demand.calls.single.$2.containsKey('deliveryMethod'), isFalse, reason: 'курьер — майдон юборилмайди');
    });

    testWidgets('self_disabled — на танлов, на изоҳ', (tester) async {
      final h = _H();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => reply(p, selfOk: false);
      await open(tester, h);
      expect(find.byKey(const ValueKey('wholesale-delivery-self')), findsNothing);
      expect(find.byKey(const ValueKey('wholesale-self-out-of-coverage')), findsNothing);
    });

    testWidgets('self мумкин — танланса квота deliveryMethod self; етказиш «нархга киради», dropoff изоҳи',
        (tester) async {
      final h = _H();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => reply(p);
      h.wallet.handlers['placeWholesaleOrder'] =
          (_) => {'ok': true, 'orderId': 'o7', 'status': 'placed', 'total': 640000, 'idempotent': false};
      await open(tester, h);
      expect(find.byKey(const ValueKey('wholesale-delivery-self')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-self-dropoff-note')), findsNothing);
      await _tap(tester, const ValueKey('wholesale-delivery-self'));
      expect(h.demand.calls.last.$2['deliveryMethod'], 'self');
      expect(find.text('wholesale_self_fee_included'), findsOneWidget);
      expect(find.text('wholesale_checkout_self_dropoff_district_center'), findsOneWidget);
      expect(find.text('wholesale_checkout_self_note'), findsOneWidget);
      await _tap(tester, const ValueKey('wholesale-checkout-confirm'));
      expect(h.wallet.calls.single.$2['quoteId'], 'q-wallet-self');
    });

    testWidgets('self + банк: deliveryPaymentMethod ЮБОРИЛМАЙДИ, ҳамёндан ушланма қатори йўқ', (tester) async {
      final h = _H();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => reply(p);
      await open(tester, h, balance: 0);
      await _tap(tester, const ValueKey('wholesale-delivery-self'));
      await _tap(tester, const ValueKey('wholesale-pay-bank'));
      final p = h.demand.calls.last.$2;
      expect([p['paymentMethod'], p['deliveryMethod'], p.containsKey('deliveryPaymentMethod')],
          ['bank_transfer', 'self', false]);
      expect(find.text('wholesale_pay_bank_note_self'), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-bank-hold')), findsNothing);
      expect(find.byKey(const ValueKey('wallet-balance-short')), findsNothing, reason: 'ушланадиган сумма 0');
      expect(find.text('wholesale_checkout_self_note_bank'), findsOneWidget);
    });

    testWidgets('сервер self_delivery_unavailable — курьерга қайтади ва қайта сўрайди', (tester) async {
      final h = _H();
      h.demand.handlers['quoteWholesaleOrder'] = (p) {
        if (p['deliveryMethod'] == 'self') {
          throw fnError('failed-precondition', 'self_delivery_unavailable', {'selfUnavailableReason': 'out_of_coverage'});
        }
        return reply(p);
      };
      await open(tester, h);
      await _tap(tester, const ValueKey('wholesale-delivery-self'));
      expect(h.demand.calls.map((c) => c.$2['deliveryMethod']).toList(), [null, 'self', null]);
      expect(find.byKey(const ValueKey('wholesale-quote')), findsOneWidget);
      expect(find.text(formatMoney(45000)), findsOneWidget, reason: 'курьер етказиш нархи қайтди');
    });

    testWidgets('S6 карта: ҳозир ҳамёндан етказиш ҳақи, эшик олдида фақат товар; ҳамён етмаса огоҳлантириш',
        (tester) async {
      final h = _H();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => reply(p, selfOk: false);
      await open(tester, h, balance: 10000);
      await _tap(tester, const ValueKey('wholesale-pay-card'));
      expect(find.byKey(const ValueKey('wholesale-card-wallet-now')), findsOneWidget);
      expect(find.text('wholesale_quote_card_at_door'), findsOneWidget);
      expect(find.text('wholesale_pay_card_note'), findsOneWidget);
      // Баланс 10 000 < етказиш ҳақи 45 000 — огоҳлантириш (жами 685 000 эмас, етказиш ҳақи бўйича).
      expect(find.byKey(const ValueKey('wallet-balance-short')), findsOneWidget);
    });

    testWidgets('S6 карта: баланс етказиш ҳақига етади (чегара 45 000 = 45 000) — огоҳлантириш йўқ', (tester) async {
      final h = _H();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => reply(p, selfOk: false);
      await open(tester, h, balance: 45000);
      await _tap(tester, const ValueKey('wholesale-pay-card'));
      expect(find.byKey(const ValueKey('wallet-balance-short')), findsNothing);
    });

    testWidgets('self + карта: ҳамёндан 0 — ҳамён қатори ва огоҳлантириш йўқ, эшик олдида товар', (tester) async {
      final h = _H();
      h.demand.handlers['quoteWholesaleOrder'] = (p) => reply(p);
      await open(tester, h, balance: 0);
      await _tap(tester, const ValueKey('wholesale-delivery-self'));
      await _tap(tester, const ValueKey('wholesale-pay-card'));
      expect(h.demand.calls.last.$2['deliveryMethod'], 'self');
      expect(find.byKey(const ValueKey('wholesale-card-wallet-now')), findsNothing);
      expect(find.text('wholesale_pay_card_note_self'), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-balance-short')), findsNothing);
    });
  });

  // ═════════════════════════════ S4 БУЮРТМА ═══════════════════════════
  group('S4 ўз етказиши: сотувчи тугмалари ҳолатга қараб', () {
    test('модел: майдон йўқ — курьер; self ўқилади', () {
      expect(_order().isSelf, isFalse);
      final o = _selfOrder(selfStatus: WholesaleSelfStatus.inDelivery);
      expect([o.isSelf, o.selfStatus, o.selfDropoff], [true, 'in_delivery', 'buyer_address']);
    });

    test('ҳаракатлар матрицаси', () {
      WholesaleOrderActions a(WholesaleOrder o, [String v = _seller]) => WholesaleOrderActions.of(o, v);
      // placed + қабул қилинган → «Йўлга чиқдим»; харидорга «кутинг».
      expect(a(_selfOrder()).canStartSelf, isTrue);
      expect(a(_selfOrder(), _buyer).selfAwaitingStart, isTrue);
      expect(a(_selfOrder(), _buyer).canStartSelf, isFalse);
      // Қабул қилинмаган — йўқ.
      expect(
          WholesaleOrderActions.of(
                  _order(deliveryMethod: 'self', sellerDecision: 'pending', self: {'status': 'pending'}), _seller)
              .canStartSelf,
          isFalse);
      // Банк: «Пул тушди»гача йўқ, кейин бор.
      expect(a(_selfOrder(method: WholesalePaymentMethod.bankTransfer, bank: {'status': 'awaiting'})).canStartSelf,
          isFalse);
      expect(a(_selfOrder(method: WholesalePaymentMethod.bankTransfer, bank: {'status': 'confirmed'})).canStartSelf,
          isTrue);
      // Курьер буюртмасида — ҳеч қачон.
      expect(a(_order()).canStartSelf, isFalse);
      // Йўлда: ҳамён — якунлаш ва рад.
      final onWay = _selfOrder(status: WholesaleOrderStatus.inDelivery, selfStatus: WholesaleSelfStatus.inDelivery);
      expect([a(onWay).canCompleteSelf, a(onWay).canRefuseSelf, a(onWay).canStartSelf], [true, true, false]);
      // Карта, «Пул тушди» йўқ: якунлаш йўқ (изоҳ), рад бор.
      final cardOpen = _selfOrder(
          status: WholesaleOrderStatus.inDelivery,
          selfStatus: WholesaleSelfStatus.inDelivery,
          method: WholesalePaymentMethod.cardOnDelivery,
          card: {'status': 'awaiting'});
      expect([a(cardOpen).canCompleteSelf, a(cardOpen).selfCompleteAfterCard, a(cardOpen).canRefuseSelf],
          [false, true, true]);
      // Карта тасдиқланган: якунлаш бор, рад йўқ.
      final cardOk = _selfOrder(
          status: WholesaleOrderStatus.inDelivery,
          selfStatus: WholesaleSelfStatus.inDelivery,
          method: WholesalePaymentMethod.cardOnDelivery,
          card: {'status': 'confirmed'});
      expect([a(cardOk).canCompleteSelf, a(cardOk).canRefuseSelf], [true, false]);
      // Код тасдиқланган (completed) — тугмалар йўқ, «ҳисоб-китоб».
      final done = _selfOrder(status: WholesaleOrderStatus.inDelivery, selfStatus: WholesaleSelfStatus.completed);
      expect([a(done).canCompleteSelf, a(done).canRefuseSelf, a(done).selfCompletedWaiting], [false, false, true]);
      // Рад: ҳисоб-китоб тугамаган — кутиш; тугаган — «Товар қайтиб келди».
      final refPending = _selfOrder(status: WholesaleOrderStatus.refused, refundStatus: 'pending');
      expect([a(refPending).canCompleteSelfReturn, a(refPending).selfReturnWaitRefund], [false, true]);
      final refDone = _selfOrder(status: WholesaleOrderStatus.refused, refundStatus: 'done');
      expect([a(refDone).canCompleteSelfReturn, a(refDone, _buyer).canCompleteSelfReturn], [true, false]);
      // Харидор коди: фақат сотувчи йўлга чиққач.
      expect(a(_selfOrder(status: WholesaleOrderStatus.inDelivery, selfStatus: 'pending'), _buyer).showDeliveryCode,
          isFalse);
      expect(a(onWay, _buyer).showDeliveryCode, isTrue);
      expect(a(cardOpen, _buyer).showDeliveryCode, isFalse);
    });

    testWidgets('«Йўлга чиқдим» → тасдиқ → startWholesaleSelfDelivery', (tester) async {
      final h = _H();
      h.demand.handlers['startWholesaleSelfDelivery'] = (_) => {'ok': true, 'status': 'in_delivery'};
      await _pumpOrder(tester, _selfOrder(), _seller, h: h);
      expect(find.text('wholesale_self_seller_start_hint'), findsOneWidget);
      expect(find.byKey(_complete), findsNothing);
      await _tap(tester, _start);
      await tester.tap(find.byKey(const ValueKey('wholesale-confirm-yes')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.single.$1, 'startWholesaleSelfDelivery');
      expect(h.demand.calls.single.$2, {'orderId': 'o1'});
    });

    testWidgets('код киритиш: 5 рақам — хато, чақирув йўқ; 6 рақам — completeWholesaleSelfDelivery', (tester) async {
      final h = _H();
      h.demand.handlers['completeWholesaleSelfDelivery'] = (_) => {'ok': true, 'selfDeliveryStatus': 'completed'};
      await _pumpOrder(
          tester,
          _selfOrder(status: WholesaleOrderStatus.inDelivery, selfStatus: WholesaleSelfStatus.inDelivery),
          _seller,
          h: h);
      expect(find.byKey(_start), findsNothing);
      await _tap(tester, _complete);
      await tester.enterText(find.byKey(const ValueKey('wholesale-self-code')), '12345');
      await tester.tap(find.byKey(const ValueKey('wholesale-self-code-submit')));
      await tester.pumpAndSettle();
      expect(find.text('wholesale_self_code_err'), findsOneWidget);
      expect(h.demand.calls, isEmpty);
      // 7-рақам киритилмайди (чеклов 6) — ортиқчаси кесилади.
      await tester.enterText(find.byKey(const ValueKey('wholesale-self-code')), '1234567');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('wholesale-self-code'))).controller!.text, '123456');
      await tester.tap(find.byKey(const ValueKey('wholesale-self-code-submit')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.single.$1, 'completeWholesaleSelfDelivery');
      expect(h.demand.calls.single.$2, {'orderId': 'o1', 'code': '123456'});
    });

    testWidgets('нотўғри код (сервер delivery_code_invalid) — тушунарли матн', (tester) async {
      final h = _H();
      h.demand.handlers['completeWholesaleSelfDelivery'] =
          (_) => throw fnError('invalid-argument', 'delivery_code_invalid', {'attemptsLeft': 3});
      await _pumpOrder(
          tester,
          _selfOrder(status: WholesaleOrderStatus.inDelivery, selfStatus: WholesaleSelfStatus.inDelivery),
          _seller,
          h: h);
      await _tap(tester, _complete);
      await tester.enterText(find.byKey(const ValueKey('wholesale-self-code')), '000000');
      await tester.tap(find.byKey(const ValueKey('wholesale-self-code-submit')));
      await tester.pumpAndSettle();
      expect(find.text('wholesale_self_err_code_invalid'), findsOneWidget);
      expect(find.text('delivery_code_invalid'), findsNothing);
    });

    test('isValidCode чегаралари', () {
      expect(WholesaleSelfCodeDialog.isValidCode('123456'), isTrue);
      expect(WholesaleSelfCodeDialog.isValidCode(' 123456 '), isTrue);
      expect(WholesaleSelfCodeDialog.isValidCode('12345'), isFalse);
      expect(WholesaleSelfCodeDialog.isValidCode('1234567'), isFalse);
      expect(WholesaleSelfCodeDialog.isValidCode('12a456'), isFalse);
      expect(WholesaleSelfCodeDialog.isValidCode(''), isFalse);
    });

    testWidgets('«Харидор воз кечди»: сабаб 2 белги — хато; 3+ — markWholesaleSelfDeliveryRefused', (tester) async {
      final h = _H();
      h.demand.handlers['markWholesaleSelfDeliveryRefused'] = (_) => {'ok': true, 'status': 'refused'};
      await _pumpOrder(
          tester,
          _selfOrder(status: WholesaleOrderStatus.inDelivery, selfStatus: WholesaleSelfStatus.inDelivery),
          _seller,
          h: h);
      await _tap(tester, _refused);
      expect(find.text('wholesale_self_refused_title'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('wholesale-reject-reason')), 'аб');
      await tester.tap(find.byKey(const ValueKey('wholesale-reject-submit')));
      await tester.pumpAndSettle();
      expect(h.demand.calls, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('wholesale-reject-reason')), '  уйда йўқ  ');
      await tester.tap(find.byKey(const ValueKey('wholesale-reject-submit')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.single.$1, 'markWholesaleSelfDeliveryRefused');
      expect(h.demand.calls.single.$2, {'orderId': 'o1', 'reason': 'уйда йўқ'});
    });

    testWidgets('карта йўлда, «Пул тушди» йўқ: якунлаш тугмаси йўқ, изоҳ бор, «Пул тушди» бор', (tester) async {
      await _pumpOrder(
          tester,
          _selfOrder(
              status: WholesaleOrderStatus.inDelivery,
              selfStatus: WholesaleSelfStatus.inDelivery,
              method: WholesalePaymentMethod.cardOnDelivery,
              card: {'status': 'awaiting'}),
          _seller);
      expect(find.byKey(_complete), findsNothing);
      expect(find.byKey(_refused), findsOneWidget);
      expect(find.text('wholesale_self_complete_after_card'), findsOneWidget);
      await _tap(tester, const ValueKey('wholesale-money-received'));
      expect(find.text('wholesale_order_money_received_confirm_self'), findsOneWidget);
    });

    testWidgets('рад, ҳисоб-китоб тугаган: «Товар қайтиб келди» → completeWholesaleSelfReturn', (tester) async {
      final h = _H();
      h.demand.handlers['completeWholesaleSelfReturn'] = (_) => {'ok': true, 'status': 'returned'};
      await _pumpOrder(tester, _selfOrder(status: WholesaleOrderStatus.refused, refundStatus: 'done'), _seller, h: h);
      expect(find.text('wholesale_self_return_pending'), findsOneWidget, reason: 'қайтиш жўнатмаси матни эмас');
      expect(find.text('wholesale_return_status_pending_shipment'), findsNothing);
      await _tap(tester, _return);
      await tester.tap(find.byKey(const ValueKey('wholesale-confirm-yes')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.single.$1, 'completeWholesaleSelfReturn');
    });

    testWidgets('рад, ҳисоб-китоб тугамаган: тугма йўқ, «бироздан кейин»', (tester) async {
      await _pumpOrder(tester, _selfOrder(status: WholesaleOrderStatus.refused, refundStatus: 'pending'), _seller);
      expect(find.byKey(_return), findsNothing);
      expect(find.text('wholesale_self_return_wait'), findsOneWidget);
    });

    testWidgets('харидор: йўлда — код тугмаси ва «сотувчига айтинг» изоҳи; dropoff ва «нархга киради»', (tester) async {
      final h = _H();
      h.demand.handlers['getWholesaleDeliveryCode'] =
          (_) => {'orderId': 'o1', 'shipmentId': null, 'trackingNumber': '', 'deliveryMethod': 'self', 'deliveryCode': '482913'};
      await _pumpOrder(
          tester,
          _selfOrder(status: WholesaleOrderStatus.inDelivery, selfStatus: WholesaleSelfStatus.inDelivery),
          _buyer,
          h: h);
      expect(find.text('wholesale_order_delivery_code_hint_self'), findsOneWidget);
      expect(find.text('wholesale_order_delivery_code_hint'), findsNothing);
      expect(find.text('wholesale_order_self_dropoff_buyer_address'), findsOneWidget);
      expect(find.text('wholesale_self_fee_included'), findsOneWidget);
      expect(find.text('wholesale_order_status_in_delivery_self'), findsWidgets);
      expect(find.byKey(_start), findsNothing);
      expect(find.byKey(_complete), findsNothing);
      await _tap(tester, _code);
      expect(find.text('482913'), findsOneWidget);
      expect(find.text('wholesale_order_delivery_code_hint_self'), findsWidgets);
    });

    testWidgets('харидор: сотувчи ҳали йўлга чиқмаган — код йўқ, «кутинг» изоҳи', (tester) async {
      await _pumpOrder(tester, _selfOrder(), _buyer);
      expect(find.byKey(_code), findsNothing);
      expect(find.text('wholesale_self_buyer_wait_start'), findsOneWidget);
    });

    testWidgets('харидор: рад этилди (ҳамён) — товар суммаси қайтади изоҳи', (tester) async {
      await _pumpOrder(tester, _selfOrder(status: WholesaleOrderStatus.refused, refundStatus: 'done'), _buyer);
      expect(find.text('wholesale_self_refused_buyer_wallet'), findsOneWidget);
    });

    testWidgets('сотувчи қабул қилиш ойнаси: ўз етказиши матни (курьер эмас)', (tester) async {
      final h = _H();
      await _pumpOrder(
          tester,
          WholesaleOrder.fromMap('o1', {
            'buyerId': _buyer,
            'sellerId': _seller,
            'goodsTotal': 640000,
            'deliveryFee': 0,
            'total': 640000,
            'status': 'placed',
            'paymentMethod': 'wallet',
            'deliveryMethod': 'self',
            'selfDelivery': {'status': 'pending'},
            'sellerDecision': 'pending',
            'acceptDeadlineAt': DateTime.now().add(const Duration(days: 1)),
          }),
          _seller,
          h: h);
      await _tap(tester, const ValueKey('wholesale-order-accept'));
      expect(find.text('wholesale_order_accept_confirm_self'), findsOneWidget);
    });

    test('вақт чизиғи: ўз етказиши қайтарилди — «қайтарилмоқда» қадами йўқ; курьерда бор', () {
      final self = wholesaleTimelineSteps('returned', self: true).map((s) => s.status).toList();
      expect(self, ['placed', 'in_delivery', 'refused', 'returned']);
      final courier = wholesaleTimelineSteps('returned').map((s) => s.status).toList();
      expect(courier, contains('returning'));
      expect(WholesaleOrderStatusChip.labelKey('in_delivery', self: true), 'wholesale_order_status_in_delivery_self');
      expect(WholesaleOrderStatusChip.labelKey('in_delivery'), 'wholesale_order_status_in_delivery');
    });
  });

  // ═════════════════════════════ СОТУВЧИ СОЗЛАМАСИ ════════════════════
  group('«Ўзим етказаман» созламаси', () {
    test('модел: учала калит; бузуқ/йўқ — ўчиқ', () {
      final s = WholesaleSelfDeliverySettings.fromMap({'enabled': true, 'coverage': 'region', 'dropoff': 'buyer_address'});
      expect(s.toFirestore(), {'enabled': true, 'coverage': 'region', 'dropoff': 'buyer_address'});
      expect(WholesaleSelfDeliverySettings.fromMap(null).enabled, isFalse);
      expect(WholesaleSelfDeliverySettings.fromMap({'enabled': true, 'coverage': 'city', 'dropoff': 'buyer_address'}).enabled,
          isFalse, reason: 'номаълум қамров — ўчиқ (сервер ҳам)');
      expect(WholesaleSelfDeliverySettings.fromMap('x').toFirestore(),
          {'enabled': false, 'coverage': 'district', 'dropoff': 'district_center'});
    });

    test('репозиторий патчи: ФАҚАТ selfDelivery (3 калит) + updatedAt (Rules)', () {
      final p = WholesaleSellersRepository.selfDeliveryPatch(
          const WholesaleSelfDeliverySettings(enabled: true, coverage: 'nation', dropoff: 'district_center'));
      expect(p.keys.toSet(), {'selfDelivery', 'updatedAt'});
      expect(p['selfDelivery'], {'enabled': true, 'coverage': 'nation', 'dropoff': 'district_center'});
      expect(p['updatedAt'], isA<FieldValue>());
    });

    Future<List<WholesaleSelfDeliverySettings>> pumpSheet(WidgetTester tester, WholesaleSelfDeliverySettings initial,
        {bool fail = false}) async {
      final saved = <WholesaleSelfDeliverySettings>[];
      tester.view.physicalSize = const Size(400 * 2, 1800 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WholesaleSelfDeliverySheet(
            initial: initial,
            save: (s) async {
              if (fail) throw StateError('permission-denied');
              saved.add(s);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return saved;
    }

    testWidgets('ёқиш → Вилоятим + Харидор манзилигача → сақлаш: тўлиқ шакл', (tester) async {
      final saved = await pumpSheet(tester, WholesaleSelfDeliverySettings.off);
      expect(find.text('wholesale_self_price_note'), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-self-coverage-region')), findsNothing, reason: 'ўчиқда танлов йўқ');
      await tester.tap(find.byKey(const ValueKey('wholesale-self-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-self-coverage-region')));
      await tester.tap(find.byKey(const ValueKey('wholesale-self-dropoff-buyer_address')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-self-save')));
      await tester.pumpAndSettle();
      expect(saved.single.toFirestore(), {'enabled': true, 'coverage': 'region', 'dropoff': 'buyer_address'});
    });

    testWidgets('ўчириш ҳам учала калит билан сақланади (Rules hasAll)', (tester) async {
      final saved = await pumpSheet(
          tester, const WholesaleSelfDeliverySettings(enabled: true, coverage: 'nation', dropoff: 'buyer_address'));
      await tester.tap(find.byKey(const ValueKey('wholesale-self-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wholesale-self-save')));
      await tester.pumpAndSettle();
      expect(saved.single.toFirestore(), {'enabled': false, 'coverage': 'nation', 'dropoff': 'buyer_address'});
    });

    testWidgets('сақлаш хатоси — умумий матн, варақ очиқ', (tester) async {
      await pumpSheet(tester, WholesaleSelfDeliverySettings.off, fail: true);
      await tester.tap(find.byKey(const ValueKey('wholesale-self-save')));
      await tester.pumpAndSettle();
      expect(find.text('wholesale_action_failed'), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-self-save')), findsOneWidget);
    });
  });
}

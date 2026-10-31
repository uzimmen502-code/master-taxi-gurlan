// 4-босқич: репозиторий ↔ callable харитаси, модел парсери, дарвоза ва
// хато матни калитлари (Firebase'сиз, қатъий сохталар).
import 'package:ava_gurlan/features/wholesale/models/wholesale_order.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_quote.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_orders_repository.dart';
import 'package:ava_gurlan/features/wholesale/services/wholesale_storage_service.dart' show ReceiptTooLargeException;
import 'package:ava_gurlan/features/wholesale/utils/wholesale_order_errors.dart';
import 'package:ava_gurlan/services/push_navigation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wholesale_orders_fakes.dart';

void main() {
  late FakeFunctions demand;
  late FakeFunctions wallet;
  late WholesaleOrdersRepository repo;

  setUp(() {
    demand = FakeFunctions('demand');
    wallet = FakeFunctions('wallet');
    repo = WholesaleOrdersRepository(firestore: FakeDb(), demandFunctions: demand, walletFunctions: wallet);
  });

  group('callable харитаси', () {
    test('quote → europe-west1 (demand), манзил ва тўлов усули юборилади', () async {
      demand.handlers['quoteWholesaleOrder'] = (_) => quoteReply(
            paymentMethods: {'wallet': true, 'card_on_delivery': false},
            cardReason: 'seller_debt',
          );
      final q = await repo.quote(
        productId: 'prod1',
        packId: 'p2',
        qty: 2,
        destination: const WholesaleDestination(
          regionId: 'xorazm',
          districtId: 'gurlan',
          addressText: '  Мустақиллик 5  ',
          lat: 41.8,
          lng: 60.4,
        ),
        paymentMethod: WholesalePaymentMethod.wallet,
      );
      final (name, payload) = demand.calls.single;
      expect(name, 'quoteWholesaleOrder');
      expect(wallet.calls, isEmpty);
      expect(payload['productId'], 'prod1');
      expect(payload['packId'], 'p2');
      expect(payload['qty'], 2);
      expect(payload['paymentMethod'], 'wallet');
      expect(payload['destination'], {
        'regionId': 'xorazm',
        'districtId': 'gurlan',
        'addressText': 'Мустақиллик 5',
        'lat': 41.8,
        'lng': 60.4,
      });
      expect(q.quoteId, 'q1');
      expect(q.total, 685000);
      expect(q.paymentMethodsKnown, isTrue);
      expect(q.cardOnDeliveryAvailable, isFalse);
      expect(q.cardUnavailableReason, 'seller_debt');
      expect(q.isExpired(DateTime.now()), isFalse);
    });

    test('координатасиз манзил — lat/lng юборилмайди', () {
      const d = WholesaleDestination(regionId: 'r', districtId: 'd', addressText: 'abc', lat: 41.0);
      expect(d.toInput().containsKey('lat'), isFalse);
      expect(d.toInput().containsKey('lng'), isFalse);
    });

    test('place → us-central1 (wallet), quoteId + clientRequestId', () async {
      wallet.handlers['placeWholesaleOrder'] =
          (_) => {'ok': true, 'orderId': 'o1', 'status': 'placed', 'total': 685000, 'idempotent': false};
      final r = await repo.place(quoteId: 'q1', clientRequestId: 'wo-abcdef123456');
      expect(wallet.calls.single.$1, 'placeWholesaleOrder');
      expect(wallet.calls.single.$2, {'quoteId': 'q1', 'clientRequestId': 'wo-abcdef123456'});
      expect(demand.calls, isEmpty);
      expect(r.orderId, 'o1');
      expect(r.idempotent, isFalse);
    });

    test('cancel / deliveryCode / 3b карта callable\'лари — europe-west1', () async {
      demand.handlers['cancelWholesaleOrder'] = (_) => {'ok': true};
      demand.handlers['getWholesaleDeliveryCode'] =
          (_) => {'deliveryCode': '482913', 'trackingNumber': 'AVA-1', 'shipmentId': 's1'};
      demand.handlers['getWholesaleCardPaymentInfo'] =
          (_) => {'amount': 640000, 'cardNumber': '8600123456789012', 'holderName': 'ALI V', 'sellerName': 'Ali'};
      demand.handlers['confirmWholesaleCardPayment'] = (_) => {'ok': true};
      demand.handlers['submitWholesaleCardReceipt'] = (_) => {'ok': true};
      demand.handlers['setWholesaleSellerCard'] = (_) => {'ok': true};

      await repo.cancel('o1');
      final code = await repo.deliveryCode('o1');
      final card = await repo.cardPaymentInfo('o1');
      await repo.confirmCardPayment('o1');
      await repo.submitCardReceipt(orderId: 'o1', receiptPath: 'wholesale_receipts/998900000001/o1/a.jpg');
      await repo.setSellerCard(cardNumber: '8600 1234 5678 9012', holderName: ' ALI V ');

      expect(demand.calls.map((c) => c.$1), [
        'cancelWholesaleOrder',
        'getWholesaleDeliveryCode',
        'getWholesaleCardPaymentInfo',
        'confirmWholesaleCardPayment',
        'submitWholesaleCardReceipt',
        'setWholesaleSellerCard',
      ]);
      expect(wallet.calls, isEmpty);
      expect(code.deliveryCode, '482913');
      expect(card.cardNumberGrouped, '8600 1234 5678 9012');
      expect(demand.calls[4].$2, {'orderId': 'o1', 'receiptPath': 'wholesale_receipts/998900000001/o1/a.jpg'});
      expect(demand.calls[5].$2, {'cardNumber': '8600123456789012', 'holderName': 'ALI V'});
    });

    test('сервер хатоси → WholesaleOrderException(reason, details)', () async {
      wallet.handlers['placeWholesaleOrder'] =
          (_) => throw fnError('failed-precondition', 'insufficient_balance', {'required': 685000, 'balance': 100000});
      final e = await repo
          .place(quoteId: 'q1', clientRequestId: 'wo-abcdef123456')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(e, isA<WholesaleOrderException>());
      final we = e! as WholesaleOrderException;
      expect(we.reason, 'insufficient_balance');
      expect(we.detailInt('required'), 685000);
      expect(we.detailInt('balance'), 100000);
    });

    test('details.reason йўқ — reason = code', () async {
      demand.handlers['cancelWholesaleOrder'] =
          (_) => throw FirebaseFunctionsException(message: 'x', code: 'unavailable');
      final e = await repo.cancel('o1').then<Object?>((_) => null, onError: (Object e) => e);
      expect((e! as WholesaleOrderException).reason, 'unavailable');
    });
  });

  group('3b жонли контракт', () {
    test('setSellerCard → last4; курьер callable\'лари europe-west1', () async {
      demand.handlers['setWholesaleSellerCard'] = (_) => {'ok': true, 'last4': '9012', 'unchanged': false};
      demand.handlers['markWholesaleBuyerRefused'] = (_) => {'ok': true, 'status': 'refused'};
      demand.handlers['getWholesaleReturnHandoverCode'] =
          (_) => {'orderId': 'o1', 'shipmentId': 'rs1', 'trackingNumber': 'AVA-R1', 'handoverCode': '731905'};
      expect(await repo.setSellerCard(cardNumber: '8600123456789012', holderName: 'ALI'), '9012');
      await repo.markBuyerRefused(orderId: 'o1', reason: '  тўламади ');
      await repo.markBuyerRefused(orderId: 'o2');
      final code = await repo.returnHandoverCode('o1');
      expect(demand.calls[1].$2, {'orderId': 'o1', 'reason': 'тўламади'});
      expect(demand.calls[2].$2, {'orderId': 'o2'}, reason: 'бўш сабаб юборилмайди');
      expect(demand.calls[3].$1, 'getWholesaleReturnHandoverCode');
      expect(code.handoverCode, '731905');
      expect(code.trackingNumber, 'AVA-R1');
      expect(wallet.calls, isEmpty);
    });

    test('details билан аниқлашадиган сабаблар', () {
      WholesaleOrderException e(String reason, Map<String, dynamic> d) =>
          WholesaleOrderException('failed-precondition', reason, details: d);
      expect(wholesaleOrderErrorKey(e('card_unavailable', {'cardUnavailableReason': 'buyer_limited'})),
          'wholesale_pay_card_unavailable_buyer_limited');
      expect(wholesaleOrderErrorKey(e('card_unavailable', {'cardUnavailableReason': 'seller_no_card'})),
          'wholesale_pay_card_unavailable_seller_no_card');
      expect(wholesaleOrderErrorKey(e('card_unavailable', {})), 'wholesale_pay_card_unavailable');
      expect(wholesaleOrderErrorKey(e('card_number_invalid', {'check': 'luhn'})), 'wholesale_order_err_card_luhn');
      expect(wholesaleOrderErrorKey(e('card_number_invalid', {'check': 'format'})), 'wholesale_seller_card_err_number');
    });

    test('янги сабаблар — ҳаммаси матнга (умумий эмас)', () {
      for (final r in [
        'receipt_not_found',
        'receipt_not_image',
        'receipt_path_invalid',
        'receipt_already_submitted',
        'card_payment_confirmed',
        'payment_disputed',
        'payment_method_invalid',
        'seller_balance_insufficient',
        'not_card_order',
        'order_not_in_delivery',
        'holder_name_invalid',
        'not_wholesale_seller',
        'seller_not_approved',
        'not_last_leg_courier',
        'parcel_not_in_hand',
        'card_encryption_unavailable',
        'card_decryption_unavailable',
        'card_concurrent_update',
      ]) {
        final k = wholesaleOrderErrorKey(WholesaleOrderException('failed-precondition', r));
        expect(k, isNot('wholesale_order_err_generic'), reason: r);
        expect(k, isNot('err_conflict'), reason: r);
      }
    });

    test('чек ҳажми ошса — алоҳида матн', () {
      expect(wholesaleOrderErrorKey(const ReceiptTooLargeException()), 'wholesale_order_err_receipt_too_large');
    });

    test('order: returnStatus / returnShipment / returnDebt{amount,at,attempts}; disputed — карта ёпиқ', () {
      final o = WholesaleOrder.fromMap('o1', {
        'buyerId': '998900000001',
        'status': 'returning',
        'paymentMethod': 'card_on_delivery',
        'returnStatus': 'awaiting_payment',
        'returnShipment': {'shipmentId': 'rs1', 'trackingNumber': 'AVA-R1'},
        'returnDebt': {'amount': 45000, 'at': 1, 'attempts': 2},
      });
      expect(o.returnStatus, 'awaiting_payment');
      expect(o.returnTrackingNumber, 'AVA-R1');
      expect(o.returnDebt, 45000);
      expect(WholesaleReturnStatus.l10nKey(o.returnStatus), 'wholesale_return_status_awaiting_payment');
      expect(WholesaleReturnStatus.l10nKey('x'), isNull);
      final d = WholesaleOrder.fromMap('o2', {
        'status': 'in_delivery',
        'paymentMethod': 'card_on_delivery',
        'cardPayment': {'status': 'disputed'},
      });
      expect(d.cardPaymentOpen, isFalse);
    });

    test('push: wholesale_order → orderId; бошқа тур ёки нотўғри ID — null', () {
      expect(
        PushNavigation.wholesaleOrderIdFromPush(
            {'type': 'wholesale_order', 'event': 'card_receipt', 'orderId': 'AbC123_-x', 'screen': 'wholesale_order'}),
        'AbC123_-x',
      );
      expect(PushNavigation.wholesaleOrderIdFromPush({'screen': 'wholesale_order', 'orderId': 'o1'}), 'o1');
      expect(PushNavigation.wholesaleOrderIdFromPush({'type': 'wholesale_order', 'orderId': ''}), isNull);
      expect(PushNavigation.wholesaleOrderIdFromPush({'type': 'wholesale_order', 'orderId': '../x'}), isNull);
      expect(PushNavigation.wholesaleOrderIdFromPush({'type': 'order', 'orderId': 'o1'}), isNull);
    });
  });
  test('clientRequestId: сервер шакли ^[A-Za-z0-9_-]{8,80}\$ ва ҳар сафар янги', () {
    final a = repo.newRequestId();
    final b = repo.newRequestId();
    final rx = RegExp(r'^[A-Za-z0-9_-]{8,80}$');
    expect(rx.hasMatch(a), isTrue, reason: a);
    expect(a, isNot(b));
  });

  group('WholesaleOrder.fromMap', () {
    test('тўлиқ ҳужжат', () {
      final o = WholesaleOrder.fromMap('o1', {
        'buyerId': '998900000001',
        'sellerId': '998901111111',
        'productTitle': 'Гуруч',
        'packLabel': '25 кг',
        'qty': 2,
        'unitPrice': 320000,
        'goodsTotal': 640000,
        'deliveryFee': 45000,
        'total': 685000,
        'status': 'in_delivery',
        'paymentMethod': 'card_on_delivery',
        'cardPayment': {'status': 'receipt_submitted', 'receiptPath': 'wholesale_receipts/x/a.jpg'},
        'shipment': {'shipmentId': 's1', 'trackingNumber': 'AVA-1'},
        'destination': {'addressText': 'Гурлан, Мустақиллик 5'},
        'returnDebt': {'amount': 30000},
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      });
      expect(o.isCardOrder, isTrue);
      expect(o.cardConfirmed, isFalse);
      expect(o.cardPaymentOpen, isTrue);
      expect(o.trackingNumber, 'AVA-1');
      expect(o.receiptPath, 'wholesale_receipts/x/a.jpg');
      expect(o.returnDebt, 30000);
      expect(o.createdAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(o.isBuyer('+998 90 000 00 01'), isTrue, reason: 'телефон канон шаклга келтирилади');
      expect(o.isSeller('998901111111'), isTrue);
    });

    test('эски (2-босқич) ҳужжат: paymentMethod йўқ → ҳамён; shipment null', () {
      final o = WholesaleOrder.fromMap('o2', {'buyerId': '998900000001', 'status': 'placed', 'shipment': null});
      expect(o.paymentMethod, WholesalePaymentMethod.wallet);
      expect(o.isCardOrder, isFalse);
      expect(o.trackingNumber, '');
      expect(o.returnDebt, 0);
      expect(o.isSeller(''), isFalse, reason: 'бўш ID ҳеч кимга тенг эмас');
    });

    test('ҳолат матни калити: маълум + номаълум', () {
      for (final s in WholesaleOrderStatus.known) {
        expect(WholesaleOrderStatus.l10nKey(s), 'wholesale_order_status_$s');
      }
      expect(WholesaleOrderStatus.l10nKey('weird'), 'wholesale_order_status_unknown');
    });
  });

  group('WholesaleQuote.fromMap', () {
    test('эски сервер (paymentMethods йўқ) — карта маълум эмас', () {
      final q = WholesaleQuote.fromMap(quoteReply());
      expect(q.paymentMethodsKnown, isFalse);
      expect(q.cardOnDeliveryAvailable, isFalse);
    });

    test('муддати ўтган квота', () {
      final q = WholesaleQuote.fromMap({...quoteReply(), 'expiresAtMs': 1000});
      expect(q.isExpired(DateTime.now()), isTrue);
    });
  });

  group('дарвоза (кириш нуқтаси)', () {
    test('ҳужжат йўқ / enabled false — ёпиқ', () {
      expect(WholesaleOrdersGate.fromMap(null).allows('998900000001'), isFalse);
      expect(
        WholesaleOrdersGate.fromMap({'enabled': false, 'stage': 'public'}).allows('998900000001'),
        isFalse,
      );
    });

    test('public — ҳамма; off — ҳеч ким', () {
      expect(WholesaleOrdersGate.fromMap({'enabled': true, 'stage': 'public'}).allows('998900000009'), isTrue);
      expect(
        WholesaleOrdersGate.fromMap({
          'enabled': true,
          'stage': 'off',
          'testerIds': ['998900000001'],
        }).allows('998900000001'),
        isFalse,
      );
    });

    test('internal / pilot / номаълум — фақат синовчи (канон телефон)', () {
      for (final stage in ['internal', 'pilot', 'weird', null]) {
        final g = WholesaleOrdersGate.fromMap({
          'enabled': true,
          'stage': stage,
          'testerIds': ['+998 90 000 00 01'],
        });
        expect(g.allows('998900000001'), isTrue, reason: '$stage');
        expect(g.allows('998900000002'), isFalse, reason: '$stage');
        expect(g.allows(''), isFalse, reason: '$stage');
      }
    });
  });

  group('хато → матн калити (ички код кўрсатилмайди)', () {
    WholesaleOrderException e(String reason, [String code = 'failed-precondition']) =>
        WholesaleOrderException(code, reason);

    test('маълум сабаблар', () {
      expect(wholesaleOrderErrorKey(e('insufficient_balance')), 'wholesale_order_err_insufficient_balance');
      expect(wholesaleOrderErrorKey(e('zone_not_found')), 'wholesale_order_err_delivery_price');
      expect(wholesaleOrderErrorKey(e('tariff_extra_price_missing')), 'wholesale_order_err_delivery_price');
      expect(wholesaleOrderErrorKey(e('quote_used')), 'wholesale_order_err_quote_expired');
      expect(wholesaleOrderErrorKey(e('module_internal_only', 'unavailable')), 'wholesale_order_err_unavailable');
      expect(wholesaleOrderErrorKey(e('card_payment_unconfirmed')),
          'wholesale_order_err_card_payment_unconfirmed');
    });

    test('номаълум сабаб — код харитаси ёки умумий матн', () {
      expect(wholesaleOrderErrorKey(e('unavailable', 'unavailable')), 'err_network');
      expect(wholesaleOrderErrorKey(e('something_new')), 'wholesale_order_err_generic');
      expect(wholesaleOrderErrorKey(StateError('x')), 'wholesale_order_err_generic');
    });

    test('дарвоза ёпиқлиги аниқланади', () {
      expect(isWholesaleOrdersClosed(e('module_disabled', 'unavailable')), isTrue);
      expect(isWholesaleOrdersClosed(e('insufficient_stock')), isFalse);
    });

    test('карта ёпиқлиги сабаби', () {
      expect(wholesaleCardUnavailableKey('seller_debt'), 'wholesale_pay_card_unavailable_seller_debt');
      expect(wholesaleCardUnavailableKey('no_card'), 'wholesale_pay_card_unavailable');
    });
  });
}

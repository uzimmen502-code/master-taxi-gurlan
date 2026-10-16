// AVA LOGISTICS — модел ёрдамчилари (форматлаш, ҳолат мантиқи, бўш ҳужжат).
//
//   flutter test test/features/logistics/logistics_models_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/logistics/domain/logistics_models.dart';

void main() {
  group('форматлаш', () {
    test('пул — бутун сўм, минг ажратгичи', () {
      expect(logisticsMoney(0), '0');
      expect(logisticsMoney(999), '999');
      expect(logisticsMoney(10000), '10 000');
      expect(logisticsMoney(1234567), '1 234 567');
    });

    test('вазн — грамм/кг', () {
      expect(logisticsWeightLabel(800), '800 г');
      expect(logisticsWeightLabel(1000), '1 кг');
      expect(logisticsWeightLabel(1200), '1,2 кг');
      expect(logisticsWeightLabel(30000), '30 кг');
    });
  });

  group('ҳолатлар', () {
    test('номаълум сатр — null (илова йиқилмайди)', () {
      expect(ShipmentStatus.tryParse('kelajak'), isNull);
      expect(PaymentStatus.tryParse(''), isNull);
      expect(CustodianKind.tryParse(null), isNull);
    });

    test('бекор қилиш фақат custody бошлангунча', () {
      expect(ShipmentStatus.awaitingPayment.isCancellable, isTrue);
      expect(ShipmentStatus.ready.isCancellable, isTrue);
      expect(ShipmentStatus.inTransit.isCancellable, isFalse);
      expect(ShipmentStatus.delivered.isCancellable, isFalse);
    });

    test('matn kalitlari — wire сатридан', () {
      expect(ShipmentStatus.inTransit.l10nKey, 'logistics_status_in_transit');
      expect(PaymentStatus.escrowFunded.l10nKey, 'logistics_payment_escrow_funded');
      expect(ConditionFlags.l10nKey('wet'), 'logistics_condition_wet');
    });
  });

  group('бўш/нотўлиқ ҳужжат', () {
    test('Shipment бўш map билан йиқилмайди', () {
      final s = Shipment.fromMap('x', <String, dynamic>{});
      expect(s.id, 'x');
      expect(s.status, ShipmentStatus.awaitingPayment);
      expect(s.paymentStatus, PaymentStatus.pending);
      expect(s.needsPayment, isTrue);
      expect(s.legIds, isEmpty);
      expect(s.parcel.isValid, isFalse);
      expect(s.origin, isNull);
    });

    test('LogisticsOrder ва CustodyEvent бўш map билан', () {
      final o = LogisticsOrder.fromMap('o', <String, dynamic>{});
      expect(o.status, '');
      expect(o.shipmentIds, isEmpty);
      final e = CustodyEvent.fromMap('e', <String, dynamic>{});
      expect(e.isDelivery, isFalse);
      expect(e.l10nKey, 'logistics_event_handed_over');
    });

    test('ParcelSpec — фақат мусбат бутун сонлар, қиймат МАЖБУРИЙ (D1)', () {
      const ok = ParcelSpec(
          actualWeightG: 800, lengthCm: 20, widthCm: 15, heightCm: 10, declaredValue: 35000);
      expect(ok.isValid, isTrue);
      expect(ok.localErrorReason, isNull);
      expect(ok.toInput()['declaredValue'], 35000);
      const bad = ParcelSpec(
          actualWeightG: 0, lengthCm: 20, widthCm: 15, heightCm: 10, declaredValue: 35000);
      expect(bad.isValid, isFalse);
      expect(bad.localErrorReason, 'parcel_invalid');
    });

    test('ParcelSpec — declaredValue чегара: 0 ва манфий рад, 1 қабул', () {
      ParcelSpec withValue(int v) => ParcelSpec(
          actualWeightG: 800, lengthCm: 20, widthCm: 15, heightCm: 10, declaredValue: v);
      expect(withValue(0).isValid, isFalse);
      expect(withValue(0).localErrorReason, 'declared_value_required');
      expect(withValue(-5000).isValid, isFalse);
      expect(withValue(-5000).localErrorReason, 'declared_value_required');
      expect(withValue(1).isValid, isTrue);
      // ўлчам хато бўлса — аввал ўлчам хатоси (қиймат ҳам бўш бўлса ҳам)
      const both = ParcelSpec(actualWeightG: 0, lengthCm: 20, widthCm: 15, heightCm: 10);
      expect(both.localErrorReason, 'parcel_invalid');
    });

    test('йўқолган посилка тўлов ҳолатлари (D1) — wire ва номаълум сатр', () {
      expect(PaymentStatus.tryParse('loss_pending'), PaymentStatus.lossPending);
      expect(PaymentStatus.tryParse('loss_settled'), PaymentStatus.lossSettled);
      expect(PaymentStatus.lossPending.l10nKey, 'logistics_payment_loss_pending');
      expect(PaymentStatus.lossSettled.wire, 'loss_settled');
      // келажакдаги номаълум ҳолат — йиқилмайди, ҳужжат pending'га тушади
      final s = Shipment.fromMap('x', <String, dynamic>{'paymentStatus': 'kelajak'});
      expect(s.paymentStatus, PaymentStatus.pending);
    });

    test('LogisticsPoint — координата фақат жуфт бўлса юборилади', () {
      const p = LogisticsPoint(regionId: 'xorazm', districtId: 'gurlan', lat: 41.8);
      final input = p.toInput();
      expect(input.containsKey('lat'), isFalse);
      expect(input['districtId'], 'gurlan');
      expect(const LogisticsPoint(regionId: '').isSet, isFalse);
    });
  });
}

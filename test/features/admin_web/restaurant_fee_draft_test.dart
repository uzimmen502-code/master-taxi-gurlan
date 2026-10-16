// Kafe-restoran: AVA haqi (foiz) va tun koeffitsienti — forma mantiqi.
//
//   flutter test test/features/admin_web/restaurant_fee_draft_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/admin_web/utils/restaurant_fee_draft.dart';

void main() {
  group('RestaurantFeeCurrent.fromDoc', () {
    test('hujjat yo\'q — standart (avaFeeBps null), maydonlar bo\'sh', () {
      final c = RestaurantFeeCurrent.fromDoc(null);
      expect(c.avaFeeBps, isNull);
      expect(c.feePercentText, '');
      expect(c.nightCoefText, '');
      expect(c.version, 0);
    });
    test('qiymatlar', () {
      final c = RestaurantFeeCurrent.fromDoc({'avaFeeBps': 250, 'nightCoef': 1.5, 'version': 4});
      expect(c.feePercentText, '2.5');
      expect(c.nightCoefText, '1.5');
      expect(c.version, 4);
      expect(RestaurantFeeCurrent.fromDoc({'avaFeeBps': 200, 'nightCoef': 2}).nightCoefText, '2');
    });
  });

  group('planRestaurantFeeChange', () {
    const absent = RestaurantFeeCurrent();
    const set250 = RestaurantFeeCurrent(avaFeeBps: 250, nightCoef: 1.5, version: 2);

    test('foiz -> bps', () {
      final p = planRestaurantFeeChange(current: absent, feeText: '3', nightText: '');
      expect(p.errors, isEmpty);
      expect(p.payload, {'avaFeeBps': 300});
      expect(planRestaurantFeeChange(current: absent, feeText: '2,5', nightText: '').payload, {'avaFeeBps': 250});
      expect(planRestaurantFeeChange(current: absent, feeText: '0', nightText: '').payload, {'avaFeeBps': 0});
      expect(planRestaurantFeeChange(current: absent, feeText: '100', nightText: '').payload, {'avaFeeBps': 10000});
    });

    test('o\'zgarish yo\'q — payload bo\'sh (hech narsa yuborilmaydi)', () {
      final p = planRestaurantFeeChange(current: set250, feeText: '2.5', nightText: '1.5');
      expect(p.hasChange, isFalse);
      expect(p.errors, isEmpty);
      // standartda va maydon bo'sh
      expect(planRestaurantFeeChange(current: absent, feeText: '', nightText: '').hasChange, isFalse);
    });

    test('standartga qaytarish: bo\'sh yoki "standart" -> avaFeeBps: null (faqat qiymat bor bo\'lsa)', () {
      for (final t in ['', '  ', 'standart', 'Стандарт']) {
        final p = planRestaurantFeeChange(current: set250, feeText: t, nightText: '1.5');
        expect(p.payload!.containsKey('avaFeeBps'), isTrue, reason: t);
        expect(p.payload!['avaFeeBps'], isNull, reason: t);
      }
    });

    test('tun koeffitsienti: chegara 1 va 3 qabul, 0.99 va 3.01 rad', () {
      expect(planRestaurantFeeChange(current: set250, feeText: '2.5', nightText: '1').payload, {'nightCoef': 1.0});
      expect(planRestaurantFeeChange(current: set250, feeText: '2.5', nightText: '3').payload, {'nightCoef': 3.0});
      for (final t in ['0.99', '3.01', 'x', '-1']) {
        final p = planRestaurantFeeChange(current: set250, feeText: '2.5', nightText: t);
        expect(p.errors, isNotEmpty, reason: t);
        expect(p.payload, isNull, reason: t);
      }
    });

    test('foiz chegaralari: manfiy, > 100, harf — xato', () {
      for (final t in ['-1', '100.01', '101', 'abc']) {
        final p = planRestaurantFeeChange(current: absent, feeText: t, nightText: '');
        expect(p.errors, isNotEmpty, reason: t);
        expect(p.hasChange, isFalse, reason: t);
      }
    });

    test('ikkalasi birga', () {
      final p = planRestaurantFeeChange(current: absent, feeText: '1,5', nightText: '2');
      expect(p.payload, {'avaFeeBps': 150, 'nightCoef': 2.0});
    });
  });
}

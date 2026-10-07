// AVA LOGISTICS — тариф нархини фоизга ўзгартириш (admin «битта тугма»).
//
//   flutter test test/features/logistics/tariff_adjust_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/logistics/domain/tariff_adjust.dart';

void main() {
  group('adjustPrice — бутун сўм, ярим юқорига, қадамга яхлитлаш', () {
    test('−10 % · қадам 1000: 29 000 → 26 000, 36 000 → 32 000 (32 400)', () {
      expect(adjustPrice(29000, percentBps: -1000, step: 1000), 26000);
      expect(adjustPrice(36000, percentBps: -1000, step: 1000), 32000);
      expect(adjustPrice(43000, percentBps: -1000, step: 1000), 39000);
    });

    test('+5 % · қадам 100: 88 000 → 92 400; қадамсиз аниқ', () {
      expect(adjustPrice(88000, percentBps: 500, step: 100), 92400);
      expect(adjustPrice(88000, percentBps: 500), 92400);
      expect(adjustPrice(12345, percentBps: 500), 12962); // 12962.25 → 12962
    });

    test('0 % — ўзгармайди; extraPerKg 0 — 0 қолади', () {
      expect(adjustPrice(187000, percentBps: 0, step: 1000), 187000);
      expect(adjustPrice(0, percentBps: -1000, step: 1000), 0);
    });

    test('ярим юқорига: 1 005 × (−0,5 %) = 999,975 → 1 000', () {
      expect(adjustPrice(1005, percentBps: -50), 1000);
    });

    test('−100 % дан паст — манфий бўлмайди; поғона нархи камида қадам', () {
      expect(adjustPrice(50000, percentBps: -12000), 0);
      expect(adjustBracketPrice(50000, percentBps: -12000, step: 1000), 1000);
      expect(adjustBracketPrice(300, percentBps: -9000, step: 1000), 1000);
      expect(adjustBracketPrice(300, percentBps: -9000), 30);
    });
  });

  group('фоиз матни ↔ bps', () {
    test('парс', () {
      expect(percentTextToBps('-10'), -1000);
      expect(percentTextToBps('+7.25'), 725);
      expect(percentTextToBps('12,5'), 1250);
      expect(percentTextToBps(' 0 '), 0);
      expect(percentTextToBps('abc'), isNull);
      expect(percentTextToBps(''), isNull);
    });

    test('кўрсатиш', () {
      expect(bpsToPercentText(2000), '20');
      expect(bpsToPercentText(1250), '12.5');
      expect(bpsToPercentText(725), '7.25');
      expect(bpsToPercentText(0), '0');
    });
  });

  group('adjustTariffPrices — эга жадвали, −10 %, қадам 1000', () {
    final prices = <String, dynamic>{
      'ZONE_0': {'brackets': [29000, 36000, 43000, 59000, 88000], 'extraPerKg': 0},
      'ZONE_5': {'brackets': [46000, 69000, 92000, 143000, 240000], 'extraPerKg': 0},
    };

    test('ҳар катак алоҳида, эски map ўзгармайди', () {
      final out = adjustTariffPrices(prices, percentBps: -1000, step: 1000);
      expect(out['ZONE_0']!['brackets'], [26000, 32000, 39000, 53000, 79000]);
      expect(out['ZONE_5']!['brackets'], [41000, 62000, 83000, 129000, 216000]);
      expect(out['ZONE_0']!['extraPerKg'], 0);
      expect((prices['ZONE_0'] as Map)['brackets'], [29000, 36000, 43000, 59000, 88000]);
    });

    test('сатр кўринишидаги сонлар ҳам ўқилади (Firestore/JSON)', () {
      final out = adjustTariffPrices({
        'ZONE_1': {'brackets': ['34000', 52000.0], 'extraPerKg': '0'},
      }, percentBps: 0);
      expect(out['ZONE_1']!['brackets'], [34000, 52000]);
    });

    test('extraPerKg null («ҳали берилмаган») — null қолади, 0 га айланмайди', () {
      final out = adjustTariffPrices({
        'ZONE_0': {'brackets': [29000], 'extraPerKg': null},
        'ZONE_1': {'brackets': [34000], 'extraPerKg': 3000},
      }, percentBps: -1000, step: 100);
      expect(out['ZONE_0']!['extraPerKg'], isNull);
      expect(out['ZONE_1']!['extraPerKg'], 2700);
    });
  });
}

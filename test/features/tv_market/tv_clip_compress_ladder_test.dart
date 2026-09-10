import 'package:ava_gurlan/features/tv_market/services/tv_clip_compress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveLadderOutcome', () {
    test('birinchi urinish maqsad ichida — shu tanlanadi, oversized=false',
        () {
      final outcome = resolveLadderOutcome([80], targetBytes: 100);
      expect(outcome.chosenIndex, 0);
      expect(outcome.oversized, isFalse);
    });

    test(
        'birinchi urinish muvaffaqiyatsiz (null), ikkinchisi maqsad ichida '
        '— ikkinchisi tanlanadi, oversized=false', () {
      final outcome = resolveLadderOutcome([null, 90], targetBytes: 100);
      expect(outcome.chosenIndex, 1);
      expect(outcome.oversized, isFalse);
    });

    test(
        'birinchi urinish maqsaddan katta, ikkinchisi maqsad ichida — '
        'birinchisi "eng yaxshi" bo\'lsa ham ikkinchisi tanlanadi '
        '(birinchi maqsad ichiga tushgani zutlik bilan qaytariladi)', () {
      final outcome = resolveLadderOutcome([300, 80], targetBytes: 100);
      expect(outcome.chosenIndex, 1);
      expect(outcome.oversized, isFalse);
    });

    test(
        'barcha urinishlar muvaffaqiyatli, lekin barchasi maqsaddan katta '
        '— eng kichigi tanlanadi, oversized=true', () {
      final outcome =
          resolveLadderOutcome([300, 200, 150], targetBytes: 100);
      expect(outcome.chosenIndex, 2);
      expect(outcome.oversized, isTrue);
    });

    test(
        'oraliqda null bo\'lsa ham eng kichik muvaffaqiyatli urinish '
        'topiladi — oversized=true', () {
      final outcome = resolveLadderOutcome([300, null, 150], targetBytes: 100);
      expect(outcome.chosenIndex, 2);
      expect(outcome.oversized, isTrue);
    });

    test('barcha urinishlar muvaffaqiyatsiz (null) — chosenIndex=null, '
        'oversized=true (xom faylni HECH QACHON qaytarmaslik uchun)', () {
      final outcome = resolveLadderOutcome([null, null, null],
          targetBytes: 100);
      expect(outcome.chosenIndex, isNull);
      expect(outcome.oversized, isTrue);
    });

    test('bo\'sh ro\'yxat (hech qanday urinish qilinmagan) — chosenIndex=null, '
        'oversized=true', () {
      final outcome = resolveLadderOutcome(<int?>[], targetBytes: 100);
      expect(outcome.chosenIndex, isNull);
      expect(outcome.oversized, isTrue);
    });

    test('0 yoki manfiy hajm — null bilan bir xil, muvaffaqiyatsiz deb '
        'hisoblanadi', () {
      final outcome = resolveLadderOutcome([0, 50], targetBytes: 100);
      expect(outcome.chosenIndex, 1);
      expect(outcome.oversized, isFalse);
    });
  });
}

import 'package:ava_gurlan/features/admin_web/screens/china_inquiries_admin_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Хитой таклифи нархи — `double`сиз бутун минор бирликка (CLAUDE.md 8-банд).
void main() {
  group('parsePriceMinor', () {
    test('бутун ва каср', () {
      expect(parsePriceMinor('38'), 3800);
      expect(parsePriceMinor('38.5'), 3850);
      expect(parsePriceMinor('38.50'), 3850);
      expect(parsePriceMinor('0.01'), 1);
      expect(parsePriceMinor(' 12,34 '), 1234, reason: 'вергул ҳам қабул');
    });

    test('float хатоси бўлмайди (0.1+0.2 каби ҳолатлар)', () {
      expect(parsePriceMinor('0.29'), 29);
      expect(parsePriceMinor('1.15'), 115);
      expect(parsePriceMinor('19.99'), 1999);
    });

    test('нотўғри қийматлар → null', () {
      for (final s in ['', ' ', '0', '0.00', '-5', '1.234', 'abc', '1.', '.5', '1e3', '12345678901']) {
        expect(parsePriceMinor(s), isNull, reason: '"$s"');
      }
    });
  });

  test('formatPriceMinor — қайтиш йўли', () {
    expect(formatPriceMinor(3850), '38.50');
    expect(formatPriceMinor(1), '0.01');
    expect(formatPriceMinor(3800), '38.00');
    expect(formatPriceMinor(parsePriceMinor('19.99')!), '19.99');
  });
}

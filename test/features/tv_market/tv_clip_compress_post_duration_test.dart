import 'package:ava_gurlan/features/tv_market/services/tv_clip_compress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('exceedsMaxPostCompressDuration', () {
    test('199s — ruxsat (false), 200s dan kichik', () {
      expect(exceedsMaxPostCompressDuration(199), isFalse);
    });

    test('200s — ruxsat (false), chegara qiymatning o\'zi "oshmagan"', () {
      expect(exceedsMaxPostCompressDuration(200), isFalse);
    });

    test('201s — rad etiladi (true), 200s dan oshgan', () {
      expect(exceedsMaxPostCompressDuration(201), isTrue);
    });

    test('null (metadata o\'qib bo\'lmadi) — xavfsiz tomonga: false '
        '(bloklanmaydi)', () {
      expect(exceedsMaxPostCompressDuration(null), isFalse);
    });

    test('0 yoki manfiy (noto\'g\'ri o\'qilgan qiymat) — false', () {
      expect(exceedsMaxPostCompressDuration(0), isFalse);
      expect(exceedsMaxPostCompressDuration(-5), isFalse);
    });

    test('juda katta qiymat (masalan 600s) — true', () {
      expect(exceedsMaxPostCompressDuration(600), isTrue);
    });
  });
}

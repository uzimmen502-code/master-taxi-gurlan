import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tvOwnerGivenName', () {
    test('@nick бўш', () {
      expect(tvOwnerGivenName('@ali'), isEmpty);
      expect(tvOwnerGivenName('@nick'), isEmpty);
    });

    test('UI fallback бўш', () {
      expect(tvOwnerGivenName('Фойдаланувчи'), isEmpty);
      expect(tvOwnerGivenName('foydalanuvchi'), isEmpty);
      expect(tvOwnerGivenName('Пользователь'), isEmpty);
    });

    test('телефон бўш', () {
      expect(tvOwnerGivenName('998901234567'), isEmpty);
    });

    test('профил исми', () {
      expect(tvOwnerGivenName('Алишер Каримов'), 'Алишер');
      expect(tvOwnerGivenName('Madina'), 'Madina');
    });
  });
}

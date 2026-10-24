import 'package:ava_gurlan/features/ads/utils/seller_name.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эълондаги сотувчи номи: дўкон номи → профил исми → email → умумий.
const _fb = 'FALLBACK';

void main() {
  test('дўкон номи бор — у кўринади (профил исмидан устун)', () {
    expect(
      resolveSellerName(shopName: 'Barakat kiyim', authName: 'Aziz', email: 'a@b.c', fallback: _fb),
      'Barakat kiyim',
    );
  });

  test('дўкон номи бўш — профил исми (аввалги хатти-ҳаракат)', () {
    expect(resolveSellerName(shopName: '', authName: 'Aziz', fallback: _fb), 'Aziz');
    expect(resolveSellerName(authName: 'Aziz', fallback: _fb), 'Aziz');
  });

  test('ёлғон номлар (телефон, @nick, «Фойдаланувчи») дўкон номи ҳисобланмайди', () {
    for (final fake in ['998901234567', '+998 90 123 45 67', '@aziz', 'Фойдаланувчи', 'user', '   ']) {
      expect(
        resolveSellerName(shopName: fake, authName: 'Aziz', fallback: _fb),
        'Aziz',
        reason: fake,
      );
    }
  });

  test('профил исми бўш — email, у ҳам бўлмаса умумий ном', () {
    expect(resolveSellerName(authName: '  ', email: 'a@b.c', fallback: _fb), 'a@b.c');
    expect(resolveSellerName(authName: null, email: null, fallback: _fb), _fb);
    expect(resolveSellerName(fallback: _fb), _fb);
  });

  test('бўшлиқлар тозаланади', () {
    expect(resolveSellerName(shopName: '  Barakat   kiyim ', fallback: _fb), 'Barakat kiyim');
  });

  test('чегара: 80 белгигача қолади, ундан узун қисқартирилади', () {
    final exactly = 'a' * kSellerNameMaxLength;
    expect(resolveSellerName(shopName: exactly, fallback: _fb), exactly);
    expect(
      resolveSellerName(shopName: 'a' * (kSellerNameMaxLength + 20), fallback: _fb).length,
      kSellerNameMaxLength,
    );
  });
}

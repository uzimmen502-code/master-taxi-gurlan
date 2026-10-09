import 'package:ava_gurlan/features/ads/widgets/platform_market_card.dart';
import 'package:ava_gurlan/models/platform_product.dart';
import 'package:ava_gurlan/models/price_tier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эски товар (2026-10-07 гача) — поғоналар нархдан ҳисобланади.
final _legacy = DateTime.utc(2026, 8, 1);

/// Янги товар — поғона ҳисобланмайди.
final _fresh = DateTime.utc(2026, 10, 8);

PlatformProduct _p({
  int price = 10000,
  List<PriceTier> tiers = const [],
  DateTime? createdAt,
}) =>
    PlatformProduct(
      id: 'p',
      name: 'Ун',
      price: price,
      priceTiers: tiers,
      createdAt: createdAt ?? _legacy,
    );

void main() {
  group('platformShelfPrice — бош саҳифа Улгуржи бўлими (2026-10-07)', () {
    test('эски товар: ўрта поғона нархи + «10–50 дона»', () {
      final r = platformShelfPrice(_p());
      expect(r.price, '10 000 сўм');
      expect(r.note, '10–49 дона');
    });

    test('админ қўйган поғоналар: биринчи поғона + «N+ дона»', () {
      final r = platformShelfPrice(_p(
        createdAt: _fresh,
        tiers: const [
          PriceTier(minQty: 5, price: 12000),
          PriceTier(minQty: 50, price: 9000),
        ],
      ));
      expect(r.price, '12 000 сўм');
      expect(r.note, '5+ дона');
    });

    test('янги товар, поғонасиз: ягона нарх, изоҳ йўқ', () {
      final r = platformShelfPrice(_p(createdAt: _fresh, price: 7000));
      expect(r.price, '7 000 сўм');
      expect(r.note, '');
    });

    test('нарх Улгуржи лентасидаги карточка билан бир хил манбадан', () {
      // Тор карточка учун қисқа шакл, лекин РАҚАМ ўша: ўрта поғона.
      final p = _p();
      expect(platformWholesalePriceLine(p), contains('10 000 сўм'));
      expect(platformShelfPrice(p).price, '10 000 сўм');
    });
  });
}

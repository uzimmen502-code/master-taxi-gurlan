import 'package:ava_gurlan/features/ads/widgets/platform_market_card.dart';
import 'package:ava_gurlan/models/platform_product.dart';
import 'package:ava_gurlan/models/price_tier.dart';
import 'package:flutter_test/flutter_test.dart';

/// AVA дўкони нархи ЯГОНА (эга 2026-11-28): ҳисобланган поғоналар
/// (1–9 +5 %, 50+ −5 %) олиб ташланди, базадаги `priceTiers` эътиборсиз.
/// Сервер: `functions/platform_pricing.js` `platformUnitPrice` (ҳар доим
/// `price`), тест `functions/test/platform_pricing_server_cf.test.js`.
void main() {
  group('эски товар (2026-10-07 гача, поғонасиз) — энди ҳисобланмайди', () {
    final legacy = PlatformProduct(
      id: 'a',
      name: 'a',
      price: 10000,
      createdAt: DateTime.utc(2026, 8, 1),
    );

    test('ҳар қандай миқдорда ягона нарх (аввал 1 дона = 10 500 эди)', () {
      expect(legacy.priceForQty(1), 10000);
      expect(legacy.priceForQty(9), 10000);
      expect(legacy.priceForQty(10), 10000);
      expect(legacy.priceForQty(50), 10000);
      expect(legacy.priceForQty(500), 10000);
      expect(legacy.displayPrice, 10000);
    });

    test('санаси йўқ товар ҳам ягона нарх', () {
      const p = PlatformProduct(id: 'n', name: 'n', price: 10000);
      expect(p.priceForQty(1), 10000);
      expect(p.displayPrice, 10000);
    });
  });

  test('базада priceTiers бўлса ҳам эътиборсиз (сервер каби)', () {
    const p = PlatformProduct(
      id: 'b',
      name: 'b',
      price: 10000,
      priceTiers: [
        PriceTier(minQty: 1, price: 12000),
        PriceTier(minQty: 5, price: 8000),
      ],
    );
    expect(p.priceForQty(1), 10000);
    expect(p.priceForQty(5), 10000);
    expect(p.displayPrice, 10000);
  });

  test('нархсиз товар — 0, йиқилмайди', () {
    const p = PlatformProduct(id: 'z', name: 'z', price: 0);
    expect(p.priceForQty(3), 0);
    expect(p.displayPrice, 0);
  });

  group('карточка қаторлари — ягона нарх', () {
    final p = PlatformProduct(
      id: 'c',
      name: 'c',
      price: 10000,
      createdAt: DateTime.utc(2026, 8, 1),
    );

    test('асосий қатор: «10 000 сўм / дона», «дан» ва оралиқ йўқ', () {
      expect(platformWholesalePriceLine(p), '10 000 сўм / дона');
    });

    test('иккинчи қатор: МОҚ = minQty', () {
      expect(platformWholesaleSubLine(p), 'МОҚ 1 дона');
      const q = PlatformProduct(id: 'q', name: 'q', price: 5000, minQty: 3);
      expect(platformWholesaleSubLine(q), 'МОҚ 3 дона');
    });
  });

  test('илова юборадиган версия ўзгармади (сервер эътиборсиз қолдиради)', () {
    expect(kPlatformPricingVersion, 2);
  });
}

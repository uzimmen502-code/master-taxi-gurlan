import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/ads/widgets/platform_market_card.dart';
import 'package:ava_gurlan/models/platform_product.dart';
import 'package:ava_gurlan/models/price_tier.dart';
import 'package:flutter_test/flutter_test.dart';

/// AVA дўкони нарх поғоналари (эга қарори, 2026-10-06):
/// базадаги нарх = 10–50 дона, 1–9 +5%, 50+ −5%, юқорига бутун сўмгача.
///
/// Fixture: `functions/test/fixtures/platform_price_vectors.json` — сервер
/// (`functions/platform_pricing.js`) ҳам айнан шу векторларни текширади.
/// Илова карточкада кўрсатган нарх сервер ечадиган нархдан фарқ қилмасин.
void main() {
  final file = File('functions/test/fixtures/platform_price_vectors.json');

  test('fixture топилди (тест репо илдизидан ишлайди)', () {
    expect(file.existsSync(), isTrue, reason: file.absolute.path);
  });

  group('сервер билан паритет (pricingVersion 2)', () {
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final vectors = (data['vectors'] as List).cast<Map<String, dynamic>>();
    for (final v in vectors) {
      test('price=${v['price']} tiers=${v['tiers']} qty=${v['qty']} → ${v['v2']}',
          () {
        final created = v['createdAt'] as String?;
        final p = PlatformProduct(
          id: 'x',
          name: 'x',
          price: v['price'] as int,
          priceTiers: parsePriceTiers(v['tiers']),
          createdAt: created == null ? null : DateTime.parse(created),
        );
        expect(p.priceForQty(v['qty'] as int), v['v2']);
      });
    }
  });

  group('ҳисобланган поғоналар', () {
    const p = PlatformProduct(id: 'a', name: 'a', price: 10000);

    test('эга мисоли: 10 000 → 10 500 / 10 000 / 9 500', () {
      expect(
        p.effectiveTiers.map((t) => (t.minQty, t.price)).toList(),
        [(1, 10500), (10, 10000), (50, 9500)],
      );
      expect(p.hasDerivedTiers, isTrue);
    });

    test('Улгуржи карточкаси: «10–50 дона: 10 000 сўм» + «1–9 дона: 10 500 сўм»',
        () {
      expect(platformWholesalePriceLine(p), '10–50 дона: 10 000 сўм');
      expect(platformWholesaleSubLine(p), '1–9 дона: 10 500 сўм');
    });

    test('чакана нарх = 1 дона учун ҲАҚИҚАТДА тўланадиган нарх', () {
      // Карточкада 10 000, саватда 10 500 чиқиб қолмасин.
      expect(p.displayPrice, 10500);
      expect(p.displayPrice, p.priceForQty(p.minQty));
    });

    test('тафсилотдаги оралиқ ёрлиқлари', () {
      expect([0, 1, 2].map(p.tierRangeLabel).toList(), ['1–9', '10–50', '50+']);
    });
  });

  group('админ поғонаси бор товар — ҳисобланмайди', () {
    const p = PlatformProduct(
      id: 'b',
      name: 'b',
      price: 10000,
      priceTiers: [PriceTier(minQty: 5, price: 8000)],
    );

    test('ўша поғоналар ишлатилади', () {
      expect(p.hasDerivedTiers, isFalse);
      expect(p.priceForQty(1), 8000);
      expect(platformWholesaleSubLine(p), 'МОҚ 5 дона');
      expect(p.tierRangeLabel(0), '5+');
    });
  });

  group('ЯНГИ товар (2026-10-07 дан) — поғонани қўшувчи ўзи қўяди', () {
    final fresh = PlatformProduct(
      id: 'n',
      name: 'n',
      price: 10000,
      createdAt: DateTime.utc(2026, 10, 7, 9),
    );

    test('ҳисобланмайди: ягона нарх, «10–50» ёрлиғи йўқ', () {
      expect(fresh.isLegacyPricing, isFalse);
      expect(fresh.effectiveTiers, isEmpty);
      expect(fresh.priceForQty(1), 10000);
      expect(fresh.priceForQty(60), 10000);
      expect(fresh.displayPrice, 10000);
      expect(platformWholesalePriceLine(fresh), '10 000 сўм / дона');
    });

    test('чегара: 18:59:59Z — эски, 19:00:00Z — янги', () {
      final before = PlatformProduct(
          id: 'b', name: 'b', price: 10000,
          createdAt: DateTime.utc(2026, 10, 6, 18, 59, 59));
      final at = PlatformProduct(
          id: 'a', name: 'a', price: 10000,
          createdAt: DateTime.utc(2026, 10, 6, 19));
      expect(before.priceForQty(1), 10500);
      expect(at.priceForQty(1), 10000);
    });
  });

  test('нархсиз товар — поғона йўқ, йиқилмайди', () {
    const p = PlatformProduct(id: 'z', name: 'z', price: 0);
    expect(p.effectiveTiers, isEmpty);
    expect(p.priceForQty(3), 0);
    expect(p.hasDerivedTiers, isFalse);
  });

  test('версия сервер билан бир хил', () {
    expect(kPlatformPricingVersion, 2);
  });
}

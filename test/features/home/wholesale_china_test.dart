import 'package:ava_gurlan/features/home/widgets/home_wholesale_section.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WholesaleProduct _p({
  String market = WholesaleProduct.marketWholesale,
  String currency = '',
  int? deliveryDays,
  List<WholesalePriceTier> tiers = const [
    WholesalePriceTier(minQty: 10, price: 9000),
  ],
}) =>
    WholesaleProduct(
      id: 'p1',
      sellerId: '998901234567',
      sellerCompanyName: 'AVA Savdo',
      title: 'Choynak',
      titleLower: 'choynak',
      description: 'd',
      priceTiers: tiers,
      market: market,
      currency: currency,
      deliveryDays: deliveryDays,
    );

Future<T> _withContext<T>(WidgetTester t, T Function(BuildContext c) fn) async {
  late T out;
  await t.pumpWidget(MaterialApp(
    home: Builder(builder: (c) {
      out = fn(c);
      return const SizedBox.shrink();
    }),
  ));
  return out;
}

void main() {
  group('WholesaleProduct — bozor turi', () {
    test('default — ulgurji', () {
      expect(_p().market, WholesaleProduct.marketWholesale);
      expect(_p().isChina, isFalse);
    });

    test('xitoy bozori', () {
      expect(_p(market: WholesaleProduct.marketChina).isChina, isTrue);
    });

    test('moq va basePrice eng past pog‘onadan', () {
      final p = _p(tiers: const [
        WholesalePriceTier(minQty: 5, price: 12000),
        WholesalePriceTier(minQty: 50, price: 9000),
      ]);
      expect(p.moq, 5);
      expect(p.basePrice, 12000);
    });

    test('pog‘ona yo‘q — moq 1, narx 0', () {
      final p = _p(tiers: const []);
      expect(p.moq, 1);
      expect(p.basePrice, 0);
    });
  });

  group('priceCurrency', () {
    testWidgets('valyuta bo‘sh — so‘m', (t) async {
      final s = await _withContext(t, (c) => priceCurrency(c, _p()));
      expect(s, 'сўм');
    });

    testWidgets('xitoy bozorida o‘z valyutasi', (t) async {
      final s = await _withContext(
        t,
        (c) => priceCurrency(
          c,
          _p(market: WholesaleProduct.marketChina, currency: '\$'),
        ),
      );
      expect(s, '\$');
    });
  });

  group('formatDelivery', () {
    testWidgets('muddat bor', (t) async {
      final s = await _withContext(
        t,
        (c) => formatDelivery(c, _p(deliveryDays: 14)),
      );
      expect(s, '14 home_delivery_days');
    });

    testWidgets('muddat yo‘q yoki nol — bo‘sh', (t) async {
      expect(await _withContext(t, (c) => formatDelivery(c, _p())), '');
      expect(
        await _withContext(t, (c) => formatDelivery(c, _p(deliveryDays: 0))),
        '',
      );
    });
  });

  group('formatTierNote — narx pog‘onasi', () {
    testWidgets('eng past pog‘ona ko‘rsatiladi', (t) async {
      final s = await _withContext(t, (c) => formatTierNote(c, _p()));
      expect(s, '10+ дона');
    });

    testWidgets('pog‘ona yo‘q — bo‘sh', (t) async {
      final s = await _withContext(
        t,
        (c) => formatTierNote(c, _p(tiers: const [])),
      );
      expect(s, '');
    });
  });
}

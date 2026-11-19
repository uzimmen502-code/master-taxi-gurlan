import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ava_gurlan/features/ads/widgets/market_grid.dart';
import 'package:ava_gurlan/features/admin_web/screens/promo_moderation_screen.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/utils/wholesale_price_only.dart';

WholesaleProduct _p({
  String title = 'Un',
  List<PriceTier> tiers = const [PriceTier(minQty: 1, price: 10000)],
  List<WholesalePack> packs = const [],
  int? moq,
}) =>
    WholesaleProduct(
      id: 'w1',
      sellerId: '998900000000',
      sellerCompanyName: 'G',
      title: title,
      titleLower: title.toLowerCase(),
      description: 'Oliy nav',
      priceTiers: tiers,
      unit: 'qop',
      imageUrls: const ['a'],
      status: 'active',
      views: 0,
      videoClipIds: const [],
      searchTokens: const [],
      packs: packs,
      minOrderQty: moq,
    );

void main() {
  testWidgets('MarketCardText with oldPrice: red discounted price + struck base, one line', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox(width: 180, child: MarketCardText(title: 'Un', price: '9 000 сўм', oldPrice: '10 000'))),
    ));
    expect(find.byKey(const ValueKey('discount_price_line')), findsOneWidget);
    final red = tester.widget<Text>(find.text('9 000 сўм'));
    expect(red.style!.color, DiscountPriceLine.red);
    final old = tester.widget<Text>(find.byKey(const ValueKey('discount_old_price')));
    expect(old.style!.decoration, TextDecoration.lineThrough);
    expect(old.data, '10 000');
  });

  testWidgets('MarketCardText without oldPrice: plain price (no struck text)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MarketCardText(title: 'Un', price: '10 000 сўм'))));
    expect(find.byKey(const ValueKey('discount_price_line')), findsNothing);
    expect(find.text('10 000 сўм'), findsOneWidget);
  });

  group('wholesaleOnlyPriceChanged', () {
    test('price tiers only → true', () {
      expect(wholesaleOnlyPriceChanged(_p(), _p(tiers: const [PriceTier(minQty: 1, price: 9000)])), isTrue);
    });
    test('title changed → false', () {
      expect(wholesaleOnlyPriceChanged(_p(), _p(title: 'Shakar')), isFalse);
    });
    test('MOQ changed → false', () {
      expect(wholesaleOnlyPriceChanged(_p(), _p(moq: 5)), isFalse);
    });
    test('pack price only → true; pack label → false', () {
      const a = WholesalePack(id: 'p1', label: '1 kg', priceTiers: [PriceTier(minQty: 1, price: 100)]);
      const b = WholesalePack(id: 'p1', label: '1 kg', priceTiers: [PriceTier(minQty: 1, price: 90)]);
      const c = WholesalePack(id: 'p1', label: '2 kg', priceTiers: [PriceTier(minQty: 1, price: 100)]);
      expect(wholesaleOnlyPriceChanged(_p(packs: const [a]), _p(packs: const [b])), isTrue);
      expect(wholesaleOnlyPriceChanged(_p(packs: const [a]), _p(packs: const [c])), isFalse);
    });
  });

  test('AvaPromoRow parses platform and AVA wholesale docs', () {
    final pl = AvaPromoRow.fromRaw('platform_products', 'x', {
      'name': 'Un',
      'price': 9000,
      'promo': {'kind': 'discount', 'percent': 10, 'basePrice': 10000, 'until': Timestamp.fromDate(DateTime(2026, 12, 1))},
    });
    expect(pl.hasDiscount, isTrue);
    expect(pl.basePrice, 10000);
    final ws = AvaPromoRow.fromRaw('wholesale_products', 'pp_1', {
      'title': 'Yog\'',
      'priceTiers': [
        {'minQty': 1, 'price': 5000},
      ],
      'promo': {'kind': 'promo'},
    });
    expect(ws.price, 5000);
    expect(ws.hasDiscount, isFalse);
  });
}

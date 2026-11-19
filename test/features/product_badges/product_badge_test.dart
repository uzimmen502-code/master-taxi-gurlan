import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ava_gurlan/features/product_badges/product_badge.dart';
import 'package:ava_gurlan/features/product_badges/product_promo_sheet.dart';
import 'package:ava_gurlan/models/platform_product.dart';

void main() {
  final now = DateTime(2026, 11, 19, 12);
  final later = now.add(const Duration(days: 3));
  final past = now.subtract(const Duration(minutes: 1));

  group('resolveProductBadge — priority / expiry', () {
    test('discount wins over everything', () {
      final b = resolveProductBadge(
        ProductBadgeData(promoKind: 'discount', percent: 20, basePrice: 100, until: later, stockLeft: 2, firstActiveAt: now),
        now,
      );
      expect(b!.kind, ProductBadgeKind.discount);
      expect(b.percent, 20);
    });
    test('promo beats last units and new', () {
      final b = resolveProductBadge(ProductBadgeData(promoKind: 'promo', until: later, stockLeft: 1, firstActiveAt: now), now);
      expect(b!.kind, ProductBadgeKind.promo);
    });
    test('expired discount hidden → falls to last units', () {
      final b = resolveProductBadge(ProductBadgeData(promoKind: 'discount', percent: 20, until: past, stockLeft: 4), now);
      expect(b!.kind, ProductBadgeKind.lastUnits);
    });
    test('until exactly now → hidden', () {
      expect(resolveProductBadge(ProductBadgeData(promoKind: 'promo', until: now), now), isNull);
    });
    test('last units: 1..4 yes, 0 and 5 no', () {
      expect(resolveProductBadge(const ProductBadgeData(stockLeft: 4), now)!.kind, ProductBadgeKind.lastUnits);
      expect(resolveProductBadge(const ProductBadgeData(stockLeft: 1), now)!.kind, ProductBadgeKind.lastUnits);
      expect(resolveProductBadge(const ProductBadgeData(stockLeft: 5), now), isNull);
      expect(resolveProductBadge(const ProductBadgeData(stockLeft: 0), now), isNull);
    });
    test('new: < 7 days yes; 7 days no; future no', () {
      expect(resolveProductBadge(ProductBadgeData(firstActiveAt: now.subtract(const Duration(days: 6, hours: 23))), now)!.kind,
          ProductBadgeKind.fresh);
      expect(resolveProductBadge(ProductBadgeData(firstActiveAt: now.subtract(const Duration(days: 7))), now), isNull);
      expect(resolveProductBadge(ProductBadgeData(firstActiveAt: now.add(const Duration(days: 1))), now), isNull);
    });
    test('legacy doc (no server fields) → no badge', () {
      expect(resolveProductBadge(ProductBadgeData.fromMap(const {'title': 'x', 'price': 5}), now), isNull);
    });
  });

  test('fromMap reads server fields only (client promoRequest never shows a badge)', () {
    final d = ProductBadgeData.fromMap({
      'promoRequest': {'kind': 'discount', 'percent': 30, 'until': Timestamp.fromDate(later)},
      'promoState': {'status': 'pending', 'percent': 30},
    });
    expect(resolveProductBadge(d, now), isNull);
    expect(d.hasRequest, isTrue);
    expect(d.stateStatus, 'pending');
    final ok = ProductBadgeData.fromMap({
      'promo': {'kind': 'discount', 'percent': 30, 'basePrice': 200, 'price': 140, 'until': Timestamp.fromDate(later)},
      'stockLeft': 3,
    });
    expect(resolveProductBadge(ok, now)!.percent, 30);
    expect(ok.activeDiscount(now), isTrue);
    expect(ok.strikePrice(now), isNotNull);
    expect(d.requestPercent, 30);
    expect(ProductBadgeData.fromMap({'promo': {'kind': 'discount', 'percent': 30, 'basePrice': 200, 'until': Timestamp.fromDate(past)}}).strikePrice(now), isNull);
  });

  test('platform adapter: unlimited stock → no last units; createdAt → new', () {
    final p = PlatformProduct(id: 'a', name: 'n', description: '', price: 1, imageUrl: '', unit: 'дона', totalStock: 0, createdAt: now);
    expect(resolveProductBadge(ProductBadgeData.forPlatform(p), now)!.kind, ProductBadgeKind.fresh);
    final q = PlatformProduct(id: 'b', name: 'n', description: '', price: 1, imageUrl: '', unit: 'дона', totalStock: 10, soldToday: 7);
    expect(resolveProductBadge(ProductBadgeData.forPlatform(q), now)!.kind, ProductBadgeKind.lastUnits);
  });

  group('seller form helpers', () {
    test('discounted price floor parity with server', () {
      expect(promoDiscountedPrice(10000, 10), 9000);
      expect(promoDiscountedPrice(999, 10), 899);
      expect(promoDiscountedPrice(1, 90), 1);
    });
    test('client errors', () {
      expect(promoClientError(kind: 'discount', price: 0, percent: 5), 'promo_reason_PRICE_REQUIRED');
      expect(promoClientError(kind: 'discount', price: 100, percent: 0), 'promo_reason_PERCENT_INVALID');
      expect(promoClientError(kind: 'discount', price: 100, percent: 51), 'promo_reason_PERCENT_INVALID');
      expect(promoClientError(kind: 'discount', price: 100, percent: 90), 'promo_reason_PERCENT_INVALID');
      expect(promoClientError(kind: 'discount', price: 100, percent: 50), isNull); // max (эга 2026-11-20)
      expect(promoClientError(kind: 'discount', price: 1, percent: 10), 'promo_reason_DISCOUNT_TOO_SMALL');
      expect(promoClientError(kind: 'discount', price: 10000, percent: 10), isNull);
      expect(promoClientError(kind: 'promo', price: null, percent: null), isNull);
    });    test('until capped to 30 days minus 5 min', () {
      final u = promoUntilFor(now.add(const Duration(days: 40)), now);
      expect(u, now.add(const Duration(days: 30)).subtract(const Duration(minutes: 5)));
      expect(promoUntilFor(now, now), DateTime(2026, 11, 19, 23, 59));
    });
    test('wholesale price = smallest minQty tier', () {
      expect(promoPriceOf('wholesale_products', {
        'priceTiers': [
          {'minQty': 10, 'price': 9000},
          {'minQty': 1, 'price': 10000},
        ],
      }), 10000);
      expect(promoPriceOf('tv_shop_items', {'price': 5}), 5);
    });
  });

  testWidgets('overlay: exactly one badge, discount text, nothing when none', (tester) async {
    Widget host(ProductBadgeData d) => MaterialApp(
          home: SizedBox(width: 200, height: 200, child: Stack(children: [ProductBadgeOverlay(data: d, now: now)])),
        );
    await tester.pumpWidget(host(ProductBadgeData(promoKind: 'discount', percent: 15, until: later, stockLeft: 1, firstActiveAt: now)));
    expect(find.byKey(const ValueKey('product_badge_discount')), findsOneWidget);
    expect(find.text('−15%'), findsOneWidget);
    expect(find.byKey(const ValueKey('product_badge_lastUnits')), findsNothing);
    expect(find.byKey(const ValueKey('product_badge_fresh')), findsNothing);

    await tester.pumpWidget(host(ProductBadgeData(promoKind: 'discount', percent: 15, until: past)));
    expect(find.byType(Positioned), findsNothing);
  });

  testWidgets('old price struck through only for active discount', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProductOldPriceText(
        data: ProductBadgeData(promoKind: 'discount', percent: 20, basePrice: 100000, until: later),
        format: (p) => '$p',
        now: now,
      ),
    ));
    final t = tester.widget<Text>(find.byKey(const ValueKey('product_old_price')));
    expect(t.style!.decoration, TextDecoration.lineThrough);
    await tester.pumpWidget(MaterialApp(
      home: ProductOldPriceText(data: ProductBadgeData(promoKind: 'promo', until: later), format: (p) => '$p', now: now),
    ));
    expect(find.byKey(const ValueKey('product_old_price')), findsNothing);
  });
}

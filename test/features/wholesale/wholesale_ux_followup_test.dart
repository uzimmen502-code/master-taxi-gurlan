import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_products_repository.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_empty_market.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_field_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WholesaleProduct _p(String id, String title,
        {String company = 'Firma', String desc = '', int price = 1000}) =>
    WholesaleProduct(
      id: id,
      sellerId: 's',
      sellerCompanyName: company,
      title: title,
      titleLower: title.toLowerCase(),
      description: desc,
      priceTiers: [WholesalePriceTier(minQty: 1, price: price)],
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('filterBySearch - qidiruv Firestore so\'rovisiz (UI/UX audit 2026-10-24)', () {
    final items = [
      _p('1', 'Pomidor', company: 'Gurlan Agro', price: 14000),
      _p('2', 'Olma', desc: 'qizil olma'),
      _p('3', 'Shakar', company: 'Urganch Savdo'),
    ];

    test('bo\'sh so\'rov - ro\'yxat o\'zgarmaydi (xuddi o\'sha obyekt)', () {
      expect(identical(WholesaleProductsRepository.filterBySearch(items, '  '), items), isTrue);
    });

    test('nom, tavsif va sotuvchi nomi bo\'yicha topadi', () {
      expect(WholesaleProductsRepository.filterBySearch(items, 'pomidor').map((e) => e.id), ['1']);
      expect(WholesaleProductsRepository.filterBySearch(items, 'qizil').map((e) => e.id), ['2']);
      expect(WholesaleProductsRepository.filterBySearch(items, 'urganch').map((e) => e.id), ['3']);
    });

    test('kirill-lotin: lotin yozilsa kirill nom topiladi (CatalogSearch)', () {
      final cyr = [_p('c', 'Помидор')];
      expect(WholesaleProductsRepository.filterBySearch(cyr, 'pomidor').map((e) => e.id), ['c']);
    });

    test('topilmasa bo\'sh, limit ishlaydi', () {
      expect(WholesaleProductsRepository.filterBySearch(items, 'zzzz'), isEmpty);
      final many = [for (var i = 0; i < 10; i++) _p('$i', 'Mahsulot $i')];
      expect(WholesaleProductsRepository.filterBySearch(many, 'mahsulot', limit: 3), hasLength(3));
    });
  });

  group('WholesaleEmptyMarket', () {
    testWidgets('qidiruv bor - "tozalash" tugmasi chiqadi, 48 dp va ishlaydi', (tester) async {
      var cleared = 0;
      await tester.pumpWidget(_host(WholesaleEmptyMarket(
        hasQuery: true,
        narrowedArea: false,
        onClearSearch: () => cleared++,
      )));
      final btn = find.byType(OutlinedButton);
      expect(btn, findsOneWidget);
      expect(tester.getSize(btn).height, greaterThanOrEqualTo(48));
      await tester.tap(btn);
      expect(cleared, 1);
      expect(find.text('wholesale_empty_try_area'), findsNothing);
    });

    testWidgets('qidiruv yo\'q, hudud toraytirilgan - hudud taklifi, tugma yo\'q', (tester) async {
      await tester.pumpWidget(_host(WholesaleEmptyMarket(
        hasQuery: false,
        narrowedArea: true,
        onClearSearch: () {},
      )));
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('wholesale_empty_try_area'), findsOneWidget);
    });
  });

  testWidgets('WholesaleFieldError - matn va ikonka (rang yolg\'iz belgi emas)', (tester) async {
    await tester.pumpWidget(_host(const WholesaleFieldError(textKey: 'wholesale_err_tier_required')));
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('wholesale_err_tier_required'), findsOneWidget);
  });
}

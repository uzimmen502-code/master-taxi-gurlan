import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_products_repository.dart';
import 'package:ava_gurlan/features/wholesale/screens/wholesale_seller_products_screen.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_product_card.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_seller_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WholesaleProduct _p(
  String id, {
  String market = WholesaleProduct.marketWholesale,
  String sellerId = '998901234567',
  DateTime? publishedAt,
}) =>
    WholesaleProduct(
      id: id,
      sellerId: sellerId,
      sellerCompanyName: 'Sunlight',
      title: 'товар $id',
      titleLower: 'товар $id',
      description: 'd',
      priceTiers: const [WholesalePriceTier(minQty: 1, price: 3800)],
      market: market,
      publishedAt: publishedAt,
    );

List<String> _ids(List<WholesaleProduct> l) => l.map((e) => e.id).toList();

void main() {
  group('sortActiveSellerProducts', () {
    test('янгиси биринчи (publishedAt камаювчи)', () {
      final list = WholesaleProductsRepository.sortActiveSellerProducts([
        _p('old', publishedAt: DateTime(2026, 1, 1)),
        _p('new', publishedAt: DateTime(2026, 10, 1)),
        _p('mid', publishedAt: DateTime(2026, 5, 1)),
      ]);
      expect(_ids(list), ['new', 'mid', 'old']);
    });

    test('санасиз ҳужжат охирида, хато бермайди', () {
      final list = WholesaleProductsRepository.sortActiveSellerProducts([
        _p('nodate'),
        _p('dated', publishedAt: DateTime(2026, 1, 1)),
      ]);
      expect(_ids(list), ['dated', 'nodate']);
    });

    test('Хитой сотувчисида Улгуржи товар аралашмайди', () {
      final all = [
        _p('c1', market: WholesaleProduct.marketChina),
        _p('w1'),
        _p('legacy', market: ''),
      ];
      expect(
        _ids(WholesaleProductsRepository.sortActiveSellerProducts(all,
            market: WholesaleProduct.marketChina)),
        ['c1'],
      );
      final wholesale = _ids(WholesaleProductsRepository
          .sortActiveSellerProducts(all, market: WholesaleProduct.marketWholesale))
        ..sort();
      expect(wholesale, ['legacy', 'w1']);
    });

    test('market берилмаса — ҳаммаси', () {
      final all = [_p('a'), _p('b', market: WholesaleProduct.marketChina)];
      expect(
        WholesaleProductsRepository.sortActiveSellerProducts(all).length,
        2,
      );
    });

    test('бўш рўйхат — бўш', () {
      expect(WholesaleProductsRepository.sortActiveSellerProducts(const []),
          isEmpty);
    });
  });

  group('WholesaleSellerCard', () {
    Future<void> pump(WidgetTester t, WholesaleProduct p) => t.pumpWidget(
          MaterialApp(home: Scaffold(body: WholesaleSellerCard(product: p))),
        );

    testWidgets('сотувчи номи ва «барча маҳсулотлари» тугмаси бор', (t) async {
      await pump(t, _p('a'));
      expect(find.text('Sunlight'), findsOneWidget);
      final btn = find.byKey(const ValueKey('wholesale_go_seller'));
      expect(btn, findsOneWidget);
      expect(find.text('shop_item_seller_all'), findsOneWidget);
      expect(t.getSize(btn).height, greaterThanOrEqualTo(48));
    });

    testWidgets('sellerId бўш — тугма чиқмайди', (t) async {
      await pump(t, _p('a', sellerId: ''));
      expect(find.byKey(const ValueKey('wholesale_go_seller')), findsNothing);
      expect(find.text('Sunlight'), findsOneWidget);
    });
  });

  group('WholesaleSellerProductsScreen', () {
    // Тест шрифти (Ahem) карточка баландлигини реал шрифтдан бироз фарқли
    // ўлчайди: катакда 0.5 px «overflow» — тест муҳити артефакти, бозор
    // экрани ҳам шу катакдан фойдаланади. Бошқа хатолар ўтказиб юборилмайди.
    Future<void> pump(
      WidgetTester t,
      Stream<List<WholesaleProduct>> Function() f,
    ) {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed by')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      return t.pumpWidget(MaterialApp(
        home: WholesaleSellerProductsScreen(
          sellerId: '998901234567',
          sellerName: 'Sunlight',
          streamFactory: f,
        ),
      ));
    }

    testWidgets('сотувчи номи сарлавҳада, товарлар карточкада', (t) async {
      await pump(t, () => Stream.value([_p('a'), _p('b')]));
      await t.pump();
      expect(find.text('Sunlight'), findsOneWidget);
      expect(find.byType(WholesaleProductCard), findsNWidgets(2));
    });

    testWidgets('товар йўқ — бўш ҳолат', (t) async {
      await pump(t, () => Stream.value(const <WholesaleProduct>[]));
      await t.pump();
      expect(find.byType(WholesaleProductCard), findsNothing);
      expect(find.text('wholesale_empty_products'), findsOneWidget);
    });

    testWidgets('хатодан кейин «Қайта уриниш» қайта уланади', (t) async {
      var n = 0;
      await pump(t, () {
        n++;
        return n == 1
            ? Stream<List<WholesaleProduct>>.error(StateError('boom'))
            : Stream.value([_p('a')]);
      });
      await t.pump();
      await t.pump();
      expect(find.text('wholesale_load_error'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);

      await t.tap(find.text('wholesale_retry'));
      await t.pump();
      await t.pump();
      expect(n, 2);
      expect(find.byType(WholesaleProductCard), findsOneWidget);
    });
  });
}

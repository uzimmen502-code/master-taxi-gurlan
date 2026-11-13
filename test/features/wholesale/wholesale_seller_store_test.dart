// Улгуржи «сотувчи магазини» (эга, 2026-11-13, 1–2-босқич).
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_seller.dart';
import 'package:ava_gurlan/features/wholesale/screens/wholesale_seller_products_screen.dart';
import 'package:ava_gurlan/features/wholesale/utils/wholesale_store.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_product_card.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_sellers_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WholesaleProduct _p(
  String id, {
  String seller = '998901110001',
  String market = WholesaleProduct.marketWholesale,
  String status = WholesaleProduct.statusActive,
  int price = 1000,
  int views = 0,
  DateTime? publishedAt,
  String title = '',
}) =>
    WholesaleProduct(
      id: id,
      sellerId: seller,
      sellerCompanyName: 'S-$seller',
      title: title.isEmpty ? 'товар $id' : title,
      titleLower: (title.isEmpty ? 'товар $id' : title).toLowerCase(),
      description: 'd',
      priceTiers: [WholesalePriceTier(minQty: 1, price: price)],
      market: market,
      status: status,
      views: views,
      publishedAt: publishedAt,
    );

WholesaleSeller _s(String phone, String name, {String status = WholesaleSeller.statusApproved}) =>
    WholesaleSeller(
      phone: phone,
      companyName: name,
      approvalStatus: status,
      sellerType: WholesaleSeller.typeManufacturer,
      createdAt: DateTime(2026, 10, 5),
    );

List<String> _ids(Iterable<WholesaleProduct> l) => l.map((e) => e.id).toList();

void main() {
  group('sortStoreProducts', () {
    final items = [
      _p('a', price: 300, views: 5, publishedAt: DateTime(2026, 10, 1)),
      _p('b', price: 100, views: 50, publishedAt: DateTime(2026, 9, 1)),
      _p('c', price: 200, views: 0, publishedAt: DateTime(2026, 11, 1)),
    ];
    test('янги / арзон / оммабоп', () {
      expect(_ids(sortStoreProducts(items, WholesaleStoreSort.newest)), ['c', 'a', 'b']);
      expect(_ids(sortStoreProducts(items, WholesaleStoreSort.cheapest)), ['b', 'c', 'a']);
      expect(_ids(sortStoreProducts(items, WholesaleStoreSort.popular)), ['b', 'a', 'c']);
    });
  });

  group('buildStoreSummaries («Сотувчилар» таби)', () {
    test('фақат тасдиқланган + камида 1 фаол маҳсулот; кўпи биринчи; бошқа бозор санамайди', () {
      final products = [
        _p('1', seller: '998900000001'),
        _p('2', seller: '998900000002'),
        _p('3', seller: '998900000002'),
        _p('4', seller: '998900000003'), // тасдиқланмаган
        _p('5', seller: '998900000004', status: WholesaleProduct.statusInactive), // фаол эмас
        _p('6', seller: '998900000005', market: WholesaleProduct.marketChina), // Хитой
        _p('7', seller: '998900000006'), // ҳужжати йўқ
      ];
      final sellers = {
        '998900000001': _s('998900000001', 'Бета'),
        '998900000002': _s('998900000002', 'Альфа'),
        '998900000003': _s('998900000003', 'Кутувчи', status: WholesaleSeller.statusPending),
        '998900000004': _s('998900000004', 'Фаолмас'),
        '998900000005': _s('998900000005', 'Хитойчи'),
      };
      final out = buildStoreSummaries(products, sellers, market: WholesaleProduct.marketWholesale);
      expect(out.map((e) => '${e.seller.companyName}:${e.productCount}'), ['Альфа:2', 'Бета:1']);
    });

    test('қидирув: ном ёки шаҳар (кирилл↔лотин)', () {
      final list = [
        WholesaleStoreSummary(seller: _s('1', 'Ун-Савдо'), productCount: 3),
        WholesaleStoreSummary(seller: _s('2', 'Мой Маркет'), productCount: 1),
      ];
      String place(WholesaleSeller s) => s.phone == '2' ? 'Урганч' : 'Тошкент';
      expect(filterStores(list, 'savdo', place).map((e) => e.seller.phone), ['1']);
      expect(filterStores(list, 'урганч', place).map((e) => e.seller.phone), ['2']);
      expect(filterStores(list, '  ', place).length, 2);
    });
  });

  test('storeInitials ва storeSinceLabel', () {
    expect(storeInitials('Ун-Савдо'), 'УС');
    expect(storeInitials('AVA'), 'AV');
    expect(storeInitials(''), '?');
    expect(storeSinceLabel(DateTime(2026, 3, 9)), '03.2026');
    expect(storeSinceLabel(null), '');
  });

  group('WholesaleSellerProductsScreen (магазин)', () {
    Future<void> pump(WidgetTester t, List<WholesaleProduct> items, {WholesaleSeller? seller}) {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed by')) return; // Ahem шрифти артефакти
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      return t.pumpWidget(MaterialApp(
        home: WholesaleSellerProductsScreen(
          sellerId: '998901110001',
          sellerName: 'Ун-Савдо',
          streamFactory: () => Stream.value(items),
          sellerLoader: () async => seller,
        ),
      ));
    }

    testWidgets('тепа: ном, ✓, сон; қўнғироқ тугмаси', (t) async {
      await pump(t, [_p('a'), _p('b')], seller: _s('998901110001', 'Ун-Савдо'));
      await t.pump();
      await t.pump();
      expect(find.byKey(const ValueKey('wholesale-store-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-store-verified')), findsOneWidget);
      expect(find.byKey(const ValueKey('wholesale-store-call')), findsOneWidget);
      final trust = t.widget<Text>(find.byKey(const ValueKey('wholesale-store-trust'))).data!;
      expect(trust, contains('wholesale_store_products_count'));
      expect(find.byType(WholesaleProductCard), findsNWidgets(2));
    });

    testWidgets('тасдиқланмаган/ўқилмаган сотувчи — ✓ йўқ, маҳсулотлар барибир кўринади', (t) async {
      await pump(t, [_p('a')], seller: null);
      await t.pump();
      await t.pump();
      expect(find.byKey(const ValueKey('wholesale-store-verified')), findsNothing);
      expect(find.byType(WholesaleProductCard), findsOneWidget);
    });

    testWidgets('магазин ичида қидириш ва тартиблаш', (t) async {
      await pump(t, [
        _p('a', title: 'Ун олий нав', price: 300),
        _p('b', title: 'Гуруч лазер', price: 100),
      ], seller: _s('998901110001', 'Ун-Савдо'));
      await t.pump();
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('wholesale-store-search')), 'гуруч');
      await t.pump();
      expect(find.byType(WholesaleProductCard), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('wholesale-store-search')), 'йўқмаҳсулот');
      await t.pump();
      expect(find.text('wholesale_store_search_none'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('wholesale-store-search')), '');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('wholesale-store-sort-cheapest')));
      await t.pump();
      final first = t.widget<WholesaleProductCard>(find.byType(WholesaleProductCard).first);
      expect(first.product.id, 'b');
    });
  });

  group('WholesaleSellersList', () {
    testWidgets('рўйхат ва босиш; ҳужжатлар бир марта сўралади', (t) async {
      final opened = <String>[];
      var calls = 0;
      final products = [_p('1', seller: '998900000001'), _p('2', seller: '998900000002')];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WholesaleSellersList(
            products: products,
            market: WholesaleProduct.marketWholesale,
            query: '',
            onOpen: (s) => opened.add(s.phone),
            loader: (ids) async {
              calls++;
              return {
                '998900000001': _s('998900000001', 'Бета'),
                '998900000002': _s('998900000002', 'Альфа', status: WholesaleSeller.statusRejected),
              };
            },
          ),
        ),
      ));
      await t.pump();
      await t.pump();
      expect(find.text('Бета'), findsOneWidget);
      expect(find.text('Альфа'), findsNothing, reason: 'тасдиқланмаган кўринмайди');
      await t.tap(find.byKey(const ValueKey('wholesale-seller-row-998900000001')));
      expect(opened, ['998900000001']);
      expect(calls, 1);
    });

    testWidgets('карточкадаги сотувчи номи алоҳида босилади', (t) async {
      var seller = 0, card = 0;
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed by')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 300,
              child: WholesaleProductCard(
                product: _p('x'),
                onTap: () => card++,
                onSellerTap: () => seller++,
              ),
            ),
          ),
        ),
      ));
      expect(find.text('S-998901110001 ›'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('wholesale-card-seller-x')));
      await t.tapAt(t.getCenter(find.byType(WholesaleProductCard)) - const Offset(0, 80));
      expect([seller, card], [1, 1]);
    });
  });
}

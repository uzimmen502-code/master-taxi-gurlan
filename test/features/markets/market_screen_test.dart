// «Бозорлар» 6-босқич: умумий бозор экрани (сохта манба), карточка, детал майдонлари, openMarket дарвозаси.
import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/ring_query.dart';
import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/markets/data/market_listings_source.dart';
import 'package:ava_gurlan/features/markets/open_market.dart';
import 'package:ava_gurlan/features/markets/screens/market_screen.dart';
import 'package:ava_gurlan/features/markets/widgets/market_attrs_section.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_item_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'taxonomy_fixture.dart';

TvShopItem _it(String id, String market,
        {String category = '', int price = 100000, bool? imported, Map<String, Object?> attrs = const {},
        PriceUnit unit = PriceUnit.fixed}) =>
    TvShopItem(
      id: id,
      ownerPhone: '998901111111',
      ownerName: 'Сотувчи',
      title: 'Эълон $id',
      price: price,
      photoUrl: '',
      kind: 'product',
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      market: market,
      category: category,
      attrs: attrs,
      imported: imported,
      priceUnit: unit,
    );

/// Сохта манба: ҳужжатларни филтр ва туман бўйича беради; сўров параметрларини ёзиб боради.
class _FakeSource implements MarketListingSource {
  _FakeSource(this.items);
  final List<TvShopItem> items;
  final List<MarketFilter> fetched = [];

  bool _match(TvShopItem i, MarketFilter f) =>
      i.market == f.market &&
      (f.category.isEmpty || i.category == f.category) &&
      (!f.importedOnly || i.imported == true);

  @override
  RingFetcher<TvShopItem> fetcher(MarketFilter filter) {
    fetched.add(filter);
    return (districtIds, startAfter, limit) async {
      final all = [for (final i in items) if (districtIds.contains(i.districtId) && _match(i, filter)) i];
      final start = startAfter is int ? startAfter : 0;
      final page = all.skip(start).take(limit).toList();
      return RingFetchResult(page, start + page.length);
    };
  }

  @override
  Future<List<String>> districtsOf(String regionId) async => regionId == 'xorazm' ? ['gurlan'] : const [];
}

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1100 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: w));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    GeoContext.resetForTest();
    ServiceConfigHolder.resetForTest();
  });

  final meatItems = [
    _it('b1', 'meat', category: 'beef', price: 85000, unit: PriceUnit.kg, attrs: {'slaughter_date': '2026-11-14'}),
    _it('b2', 'meat', category: 'beef', price: 120000, unit: PriceUnit.kg, imported: true),
    _it('f1', 'meat', category: 'fish', price: 40000, unit: PriceUnit.kg, imported: true),
    _it('x1', 'farm', category: 'fruits'),
  ];

  testWidgets('Гўшт: номи, «+», Барчаси/бўлим/Импорт чиплари, бўлим филтри; сон ЙЎҚ (2026-11-16)', (tester) async {
    final src = _FakeSource(meatItems);
    await _pump(tester, MarketScreen(marketId: 'meat', source: src, loadTaxonomy: () async => kTaxonomyV1));
    expect(find.text('Гўшт бозори'), findsOneWidget);
    expect(find.byKey(const ValueKey('market-add-ad')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_cat_all')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_imported_chip')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_f1')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_x1')), findsNothing);
    // «N та эълон» ва унинг count() сўрови олиб ташланди (эга, 2026-11-16).
    expect(find.text('market_count'), findsNothing);
    expect(find.byKey(const ValueKey('market_count')), findsNothing);
    // Ягона қидирув майдони тепада.
    expect(find.byKey(const ValueKey('market_search')), findsOneWidget);
    // Нарх бирлиги билан: «85 000 сўм / кг» (тестда «price_unit_short_kg»).
    expect(find.textContaining('price_unit_short_kg'), findsWidgets);
    expect(find.byKey(const ValueKey('market_card_attrs_b1')), findsOneWidget);
    expect(find.text('Сўйилган санаси: 14.11.2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_fav_slot_b1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('market_cat_fish')));
    await tester.pumpAndSettle();
    expect(src.fetched.last, const MarketFilter(market: 'meat', category: 'fish'));
    expect(find.byKey(const ValueKey('market_card_b1')), findsNothing);
    expect(find.byKey(const ValueKey('market_card_f1')), findsOneWidget);
  });

  testWidgets('Гўшт: «Импорт» барча турлар бўйича imported == true', (tester) async {
    final src = _FakeSource(meatItems);
    await _pump(tester, MarketScreen(marketId: 'meat', source: src, loadTaxonomy: () async => kTaxonomyV1));
    await tester.tap(find.byKey(const ValueKey('market_imported_chip')));
    await tester.pumpAndSettle();
    expect(src.fetched.last, const MarketFilter(market: 'meat', importedOnly: true));
    expect(find.byKey(const ValueKey('market_card_b1')), findsNothing);
    expect(find.byKey(const ValueKey('market_card_b2')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_f1')), findsOneWidget);
  });

  testWidgets('нарх филтри — клиентда (сервер сўрови ўзгармайди)', (tester) async {
    final src = _FakeSource(meatItems);
    await _pump(tester, MarketScreen(marketId: 'meat', source: src, loadTaxonomy: () async => kTaxonomyV1));
    final fetches = src.fetched.length;
    await tester.tap(find.byKey(const ValueKey('market_price_chip')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('market_price_min')), '50000');
    await tester.enterText(find.byKey(const ValueKey('market_price_max')), '100000');
    await tester.tap(find.byKey(const ValueKey('market_price_apply')));
    await tester.pumpAndSettle();
    expect(src.fetched.length, fetches);
    expect(find.byKey(const ValueKey('market_card_b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_b2')), findsNothing);
    expect(find.byKey(const ValueKey('market_card_f1')), findsNothing);
  });

  testWidgets('қидирув: бозор ичида клиентда (сарлавҳа/тавсиф/сотувчи), сервер сўрови ўзгармайди; тозалаш', (tester) async {
    final src = _FakeSource([
      _it('b1', 'meat', category: 'beef'),
      _TitledItem.of('q1', 'meat', 'Қўй гўшти янги'),
    ]);
    await _pump(tester, MarketScreen(marketId: 'meat', source: src, loadTaxonomy: () async => kTaxonomyV1));
    final fetches = src.fetched.length;
    await tester.enterText(find.byKey(const ValueKey('market_search')), 'қўй');
    await tester.pumpAndSettle();
    expect(src.fetched.length, fetches);
    expect(find.byKey(const ValueKey('market_card_q1')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_b1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('market_search_clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('market_card_b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_q1')), findsOneWidget);
  });

  test('marketItemMatchesQuery: бўш — ҳаммаси; сарлавҳа/тавсиф/сотувчи', () {
    final i = _TitledItem.of('z', 'farm', 'Олма', description: 'Наманган олмаси');
    expect(marketItemMatchesQuery(i, ''), isTrue);
    expect(marketItemMatchesQuery(i, 'олма'), isTrue);
    expect(marketItemMatchesQuery(i, 'наманган'), isTrue);
    expect(marketItemMatchesQuery(i, 'сотувчи'), isTrue);
    expect(marketItemMatchesQuery(i, 'мошина'), isFalse);
  });

  testWidgets('ихчам тепа: AppBar 44, қаторлар оралиғи 1 px', (tester) async {
    await _pump(tester, MarketScreen(marketId: 'meat', source: _FakeSource(meatItems), loadTaxonomy: () async => kTaxonomyV1));
    expect(tester.getSize(find.byType(AppBar)).height, lessThanOrEqualTo(44 + 0.1));
    final search = tester.getRect(find.byKey(const ValueKey('market_search')));
    final chips = tester.getRect(find.byKey(const ValueKey('market_categories')));
    expect(chips.top - search.bottom, closeTo(1, 0.6));
  });

  testWidgets('Мошина: 4 таб («Барчаси»сиз), биринчиси танланган; «+» жорий бўлим билан', (tester) async {
    final src = _FakeSource([
      _it('c1', 'auto', category: 'cars', attrs: {'brand': 'Chevrolet', 'year': 2020}),
      _it('p1', 'auto', category: 'parts'),
    ]);
    final added = <String>[];
    await _pump(
        tester,
        MarketScreen(
          marketId: 'auto',
          source: src,
          loadTaxonomy: () async => kTaxonomyV1,
          openAdd: (_, m, c) async => added.add('$m/$c'),
          // «Эҳтиёт қисмлар» тепасидаги AVA блоки (9-босқич) — Firebase'сиз ўринбосар.
          partsHeader: (_) => const SizedBox(key: ValueKey('parts_header_stub'), height: 40),
        ));
    expect(find.byKey(const ValueKey('market_tabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_cat_all')), findsNothing);
    expect(find.byKey(const ValueKey('market_card_c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_p1')), findsNothing);
    expect(find.text('Марка: Chevrolet · Йили: 2020'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('market_tab_parts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('market_card_p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('parts_header_stub')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('market-add-ad')));
    await tester.pumpAndSettle();
    expect(added, ['auto/parts']);
  });

  testWidgets('Мол: бўлим чиплари йўқ; бўш ҳолат', (tester) async {
    await _pump(tester,
        MarketScreen(marketId: 'livestock', source: _FakeSource(const []), loadTaxonomy: () async => kTaxonomyV1));
    expect(find.byKey(const ValueKey('market_categories')), findsNothing);
    expect(find.byKey(const ValueKey('market_tabs')), findsNothing);
    expect(find.byKey(const ValueKey('market_empty')), findsOneWidget);
  });

  testWidgets('таксономия хатоси — LoadErrorView', (tester) async {
    await _pump(tester,
        MarketScreen(marketId: 'meat', source: _FakeSource(const []), loadTaxonomy: () async => throw StateError('x')));
    expect(find.text('err_retry'), findsOneWidget);
  });

  testWidgets('openMarket: модул ёпиқ — экран очилмайди; очиқ — очилади', (tester) async {
    final pushed = <Widget>[];
    await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (c) => Column(children: [
              TextButton(
                onPressed: () => openMarket(c, 'meat',
                    loadTaxonomy: () async => kTaxonomyV1, canOpen: (_) => false, push: (s) async => pushed.add(s)),
                child: const Text('closed'),
              ),
              TextButton(
                onPressed: () => openMarket(c, 'meat',
                    loadTaxonomy: () async => kTaxonomyV1,
                    canOpen: (m) => m == 'meat_market',
                    push: (s) async => pushed.add(s)),
                child: const Text('open'),
              ),
            ]),
          ),
        ));
    await tester.tap(find.text('closed'));
    await tester.pumpAndSettle();
    expect(pushed, isEmpty);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(pushed.single, isA<MarketScreen>());
  });

  group('детал: бозор майдонлари', () {
    testWidgets('таксономия номлари билан; bool → «yes»; Импорт белгиси', (tester) async {
      await _pump(
          tester,
          const Scaffold(
            body: MarketAttrsSection(
              market: 'livestock',
              category: 'all',
              attrs: {'sex': 'female', 'pregnant': true, 'unknown': 1},
            ),
          ).withTaxonomy());
      expect(find.text('Мол бозори'), findsOneWidget);
      expect(find.text('Жинси'), findsOneWidget);
      expect(find.text('Урғочи'), findsOneWidget);
      expect(find.text('yes'), findsOneWidget);
      expect(find.text('unknown'), findsNothing);
    });

    testWidgets('TvShopItemDetailScreen: market бор — бўлим; йўқ — бўлим йўқ', (tester) async {
      final item = _it('b2', 'meat', category: 'beef', imported: true, attrs: {'slaughter_date': '2026-11-14'});
      await _pump(
          tester,
          TvShopItemDetailScreen(
            item: item,
            loadLatest: (_) async => item,
            loadTaxonomy: () async => kTaxonomyV1,
          ));
      expect(find.byKey(const ValueKey('market_attrs')), findsOneWidget);
      expect(find.text('Гўшт бозори · Мол'), findsOneWidget);
      expect(find.byKey(const ValueKey('market_attrs_imported')), findsOneWidget);
      expect(find.text('14.11.2026'), findsOneWidget);

      final plain = _it('a1', '');
      await _pump(tester, TvShopItemDetailScreen(key: const ValueKey('plain'), item: plain, loadLatest: (_) async => plain));
      expect(find.byKey(const ValueKey('market_attrs')), findsNothing);
    });
  });
}

extension on Scaffold {
  /// [MarketAttrsSection] тест таксономияси билан.
  Widget withTaxonomy() {
    final s = body! as MarketAttrsSection;
    return Scaffold(
      body: MarketAttrsSection(
        market: s.market,
        category: s.category,
        attrs: s.attrs,
        imported: s.imported,
        loadTaxonomy: () async => kTaxonomyV1,
      ),
    );
  }
}

/// Сарлавҳа/тавсифи берилган эълон (қидирув тестлари учун).
class _TitledItem {
  static TvShopItem of(String id, String market, String title, {String description = ''}) => TvShopItem(
        id: id,
        ownerPhone: '998901111111',
        ownerName: 'Сотувчи',
        title: title,
        description: description,
        price: 100000,
        photoUrl: '',
        kind: 'product',
        districtId: 'gurlan',
        districtLabel: 'Гурлан',
        market: market,
      );
}

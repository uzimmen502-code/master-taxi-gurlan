// «Бозорлар» 7+8+9-босқич (эга, 2026-11-15): Уй-жой/Улгуржи/Хитой ҳалқа манбалари, «Барча ҳудудларда»
// бирлаштириш, Аралашдаги Уй-жой манбаи ва белгилар, Мошина бозори «Эҳтиёт қисмлар» таркиби, «Менинг машинам»
// кириши.
import 'dart:io';

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/module_geo_policy.dart';
import 'package:ava_gurlan/core/geo/ring_query.dart';
import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/markets/data/market_listings_source.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:ava_gurlan/features/markets/open_market.dart';
import 'package:ava_gurlan/features/markets/screens/market_screen.dart';
import 'package:ava_gurlan/features/markets/widgets/auto_parts_header.dart';
import 'package:ava_gurlan/features/markets/widgets/market_form_fields.dart';
import 'package:ava_gurlan/features/realty/data/realty_ring_source.dart';
import 'package:ava_gurlan/features/realty/widgets/realty_grid_card.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_shop_item_grid_card.dart';
import 'package:ava_gurlan/features/wholesale/data/wholesale_ring_source.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/models/platform_product.dart';
import 'package:ava_gurlan/models/realty_listing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'taxonomy_fixture.dart';

RealtyListing _r(String id, {String district = 'gurlan', String region = 'xorazm', RealtyDeal deal = RealtyDeal.sale,
        DateTime? expiresAt, String price = '500 000 000 сўм'}) =>
    RealtyListing(
      id: id,
      ownerKey: 'k',
      ownerName: 'Эга',
      deal: deal,
      tier: RealtyTier.plain,
      title: 'Уй $id',
      text: '',
      priceText: price,
      areaLat: 41,
      areaLng: 60,
      status: 'active',
      districtId: district,
      regionId: region,
      expiresAt: expiresAt,
    );

/// Сохта Уй-жой манбаи: туман бўйича беради, сўров филтрларини ёзиб боради.
class _FakeRealty implements RealtyListingSource {
  _FakeRealty(this.items);
  final List<RealtyListing> items;
  final List<RealtyRingFilter> fetched = [];

  @override
  RingFetcher<RealtyListing> fetcher(RealtyRingFilter filter) {
    fetched.add(filter);
    return (districtIds, startAfter, limit) async {
      final all = [for (final i in items) if (districtIds.contains(i.districtId)) i];
      final start = startAfter is int ? startAfter : 0;
      final page = all.skip(start).take(limit).toList();
      return RingFetchResult(page, start + page.length);
    };
  }

  @override
  Future<List<String>> districtsOf(String regionId) async => switch (regionId) {
        'xorazm' => ['gurlan', 'hazorasp'],
        'toshkent_shahri' => ['chilonzor'],
        _ => const <String>[],
      };
}

WholesaleProduct _w(String id) => WholesaleProduct.fromMap(id, {
      'sellerId': '998901111111',
      'title': 'Маҳсулот $id',
      'status': 'active',
      'basePrice': 1000,
      'districtId': 'gurlan',
    });

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1100 * 2, 1800 * 2);
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

  group('7 — Уй-жой ҳалқа манбаи', () {
    test('таб → `tier` тенглиги; харита (tier йўқ) — фақат туман + status', () {
      expect(const RealtyRingFilter(tier: RealtyTier.plain).equals, {'tier': 'plain'});
      expect(const RealtyRingFilter(tier: RealtyTier.urgent, deal: RealtyDeal.rent).equals, {'tier': 'urgent'},
          reason: 'Сотиш/Ижара клиентда — янги индекс керак эмас');
      expect(const RealtyRingFilter().equals, isEmpty);
    });

    test('клиент филтри: битим тури ва муддати ўтганлар', () {
      final now = DateTime(2026, 11, 15);
      const rent = RealtyRingFilter(tier: RealtyTier.plain, deal: RealtyDeal.rent);
      expect(rent.shows(_r('a', deal: RealtyDeal.rent), now: now), isTrue);
      expect(rent.shows(_r('b'), now: now), isFalse);
      expect(const RealtyRingFilter().shows(_r('c', expiresAt: DateTime(2026, 11, 1)), now: now), isFalse);
      expect(const RealtyRingFilter().shows(_r('d', expiresAt: DateTime(2026, 12, 1)), now: now), isTrue);
    });

    test('харита: ҳалқа тартиби (туман → вилоят → бошқа вилоят), камера — энг яқин ҳалқа', () async {
      final src = _FakeRealty([
        _r('far', district: 'chilonzor', region: 'toshkent_shahri'),
        _r('near2', district: 'hazorasp'),
        _r('near1'),
        _r('rentX', deal: RealtyDeal.rent),
      ]);
      const scope = GeoScope(
        level: GeoLevel.nation,
        area: GeoArea(regionId: 'xorazm', districtId: 'gurlan'),
      );
      final items = await loadRealtyRings(src, scope, deal: RealtyDeal.sale);
      expect(items.map((e) => e.item.id), ['near1', 'near2', 'far']);
      expect(items.map((e) => e.ring).toList(), [0, 1, isNot(lessThan(2))]);
      expect(nearestRingIds(items), {'near1'});
      expect(src.fetched.every((f) => f.tier == null && f.deal == RealtyDeal.sale), isTrue);
    });

    test('аниқ туман танланса — фақат шу туман (битта ҳалқа)', () async {
      final src = _FakeRealty([_r('g'), _r('h', district: 'hazorasp')]);
      const scope = GeoScope(level: GeoLevel.district, area: GeoArea(regionId: 'xorazm', districtId: 'hazorasp'));
      final items = await loadRealtyRings(src, scope);
      expect(items.map((e) => e.item.id), ['h']);
    });

    test('экран: қизил «+», «N та эълон» ЙЎҚ, ҳалқа ленталари; эски GeoWiderHint/stream оқими йўқ', () {
      final src = File('lib/features/realty/screens/realty_screen.dart').readAsStringSync();
      expect(src.contains("ValueKey('realty-add-ad')"), isTrue);
      expect(src.contains("ValueKey('realty_count')"), isFalse, reason: '«N та эълон» олиб ташланди (2026-11-16)');
      expect(src.contains('.count('), isFalse);
      expect(src.contains('ringPlanFor(widget.scope)'), isTrue);
      expect(src.contains('watchScoped('), isFalse);
      expect(src.contains("GeoContext.clearSessionScope('realty')"), isTrue);
      final map = File('lib/features/realty/screens/realty_map_screen.dart').readAsStringSync();
      expect(map.contains('loadRealtyRings('), isTrue);
      expect(map.contains('focusIds: _focusIds'), isTrue);
    });

    test('бош саҳифа Уй-жой бўлими — аввалгидек фаол туман', () {
      final src = File('lib/features/home/widgets/home_realty_section.dart').readAsStringSync();
      expect(src.contains('GeoScope(level: GeoLevel.district, area: GeoContext.active)'), isTrue);
    });
  });

  group('7 — Улгуржи/Хитой ҳалқа манбаи', () {
    test('Хитой: `market` серверда; Улгуржи — клиентда (эски ҳужжатларда майдон йўқ); тартиб publishedAt', () {
      expect(const WholesaleRingFilter(market: WholesaleProduct.marketChina).equals, {'market': 'china'});
      expect(const WholesaleRingFilter(market: WholesaleProduct.marketWholesale).equals, isEmpty);
      expect(WholesaleRingFilter.orderField, 'publishedAt');
    });

    test('«Барча ҳудудларда» — бошида, такрор йўқ', () {
      final merged = mergeAllAreas([_w('ava1'), _w('ava2')], [_w('x'), _w('ava1'), _w('y')]);
      expect(merged.map((p) => p.id), ['ava1', 'ava2', 'x', 'y']);
      expect(mergeAllAreas(const [], [_w('x')]).map((p) => p.id), ['x']);
    });

    test('пейжер: адаптер клиентда филтрласа ҳам (rawCount) бўлак давом этади', () async {
      var calls = 0;
      final pager = RingPager<int>(
        plan: const [RingStepSpec(ring: 0, regionId: 'r', onlyDistrictId: 'd')],
        fetch: (ids, after, limit) async {
          calls++;
          final start = after is int ? after : 0;
          if (start >= 4) return const RingFetchResult<int>([], null);
          // 2 та хом ҳужжатдан биттаси филтрда қолади.
          return RingFetchResult<int>([start], start + 2, rawCount: 2);
        },
      );
      final page = await pager.next(2);
      expect(page.map((e) => e.item), [0, 2]);
      expect(calls, 2);
    });

    test('экран: GeoTierBar + ҳалқалар + «Барча ҳудудларда» + қизил «+» (сотувчи оқими шу бозор билан)', () {
      final src = File('lib/features/wholesale/screens/wholesale_market_screen.dart').readAsStringSync();
      expect(src.contains('GeoTierBar('), isTrue);
      expect(src.contains('ringPlanFor(_scope)'), isTrue);
      expect(src.contains('mergeAllAreas('), isTrue);
      expect(src.contains("ValueKey('wholesale-add-ad')"), isTrue);
      expect(src.contains('openWholesaleSeller(context, phone: widget.userPhone, market: widget.market)'), isTrue);
      expect(src.contains("_isChina ? 'china_market' : 'wholesale_market'"), isTrue);
    });
  });

  group('8 — Аралаш: Уй-жой манбаи ва белгилар', () {
    test('нарх битим тури билан', () {
      String tr(String k) => {'realty_deal_sale': 'Сотиш', 'realty_deal_rent': 'Ижара'}[k] ?? k;
      expect(realtyPriceWithDeal(tr, _r('a')), '500 000 000 сўм · сотиш');
      expect(realtyPriceWithDeal(tr, _r('b', deal: RealtyDeal.rent, price: '3 000 000')), '3 000 000 · ижара');
      expect(realtyPriceWithDeal(tr, _r('c', price: ' ')), 'сотиш');
    });

    test('бозор белгиси: market_short_* калити; бозорсиз/номаълум — бўш', () {
      String tr(String k) => {'market_short_auto': 'Мошина', 'market_short_meat': 'Гўшт'}[k] ?? k;
      expect(marketShortBadge(tr, 'auto'), 'Мошина');
      expect(marketShortBadge(tr, 'meat'), 'Гўшт');
      expect(marketShortBadge(tr, ''), '');
      expect(marketShortBadge(tr, 'unknown'), '');
    });

    testWidgets('Уй-жой карточкаси: «Уй-жой» белгиси, нисбий жой, нарх+битим', (tester) async {
      var tapped = 0;
      await _pump(
        tester,
        Scaffold(
          body: SizedBox(
            width: 180,
            height: 260,
            child: RealtyGridCard(listing: _r('z'), locationLabel: 'Гурлан', onTap: () => tapped++),
          ),
        ),
      );
      expect(find.text('aralash_badge_realty'), findsOneWidget); // тестда tr = калит
      expect(find.byKey(const ValueKey('market_location_pill')), findsOneWidget);
      expect(find.text('Гурлан'), findsOneWidget);
      expect(find.textContaining('500 000 000 сўм'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aralash_realty_z')));
      expect(tapped, 1);
    });

    testWidgets('дўкон/бозор маҳсулоти: бозор белгиси ва нисбий жой', (tester) async {
      const item = TvShopItem(
        id: 's1',
        ownerPhone: '998901111111',
        ownerName: 'С',
        title: 'Шина',
        price: 100000,
        photoUrl: '',
        kind: 'product',
        districtId: 'gurlan',
        districtLabel: 'Гурлан',
        market: 'auto',
      );
      await _pump(
        tester,
        Scaffold(
          body: SizedBox(
            width: 180,
            height: 260,
            child: TvShopItemGridCard(item: item, cornerBadge: 'Мошина', locationLabel: 'Гурлан', onTap: () {}),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('market_corner_badge')), findsOneWidget);
      expect(find.text('Мошина'), findsOneWidget);
      expect(find.byKey(const ValueKey('market_location_pill')), findsOneWidget);
    });

    test('Аралаш экрани ва бош саҳифа бўлими: Уй-жой манбаи, тафсилот Уй-жой бозори устида', () {
      final src = File('lib/features/ads/screens/cheap_products_screen.dart').readAsStringSync();
      expect(src.contains('RealtyRepository().watchScoped(scope, limit: _realtyLimit)'), isTrue);
      expect(src.contains('market: const RealtyScreen()'), isTrue);
      expect(src.contains('openDetailOverOtherMarket('), isTrue);
      expect(src.contains('realtyLocationLabel(r, user, lang)'), isTrue);
      expect(src.contains('marketShortBadge(context.tr, item.market)'), isTrue);
      final home = File('lib/features/home/widgets/home_market_section.dart').readAsStringSync();
      expect(home.contains('_realtyTile('), isTrue);
      expect(home.contains("context.tr('aralash_badge_realty')"), isTrue);
      final hs = File('lib/features/home/home_screen.dart').readAsStringSync();
      expect(hs.contains('onOpenRealty: _openAralashRealty'), isTrue);
      expect(hs.contains('_pushOverMarket(const RealtyScreen()'), isTrue);
    });
  });

  group('9 — Мошина бозори «Эҳтиёт қисмлар»', () {
    test('AVA блоки фақат auto/parts табида', () {
      expect(showsAutoPartsHeader('auto', 'parts'), isTrue);
      expect(showsAutoPartsHeader('auto', 'cars'), isFalse);
      expect(showsAutoPartsHeader('meat', 'parts'), isFalse);
    });

    test('AVA тасмаси: шина/мой/аккумулятор, фаол ва нархли (суғурта йўқ)', () {
      PlatformProduct p(String id, String cat, {int price = 1000, bool active = true}) =>
          PlatformProduct(id: id, name: id, price: price, active: active, incentiveCategory: cat);
      final out = autoPartsAvaProducts([
        p('t', 'tire'),
        p('o', 'oil'),
        p('b', 'battery'),
        p('i', 'insurance'),
        p('n', ''),
        p('z', 'oil', price: 0),
        p('off', 'tire', active: false),
      ]);
      expect(out.map((e) => e.id), ['t', 'o', 'b']);
    });

    testWidgets('initialCategory = parts: таб танланган, тепада AVA блоки, остида эълонлар', (tester) async {
      final src = _FakeMarketSource([
        _tv('c1', 'cars'),
        _tv('p1', 'parts'),
      ]);
      await _pump(
        tester,
        MarketScreen(
          marketId: 'auto',
          source: src,
          loadTaxonomy: () async => kTaxonomyV1,
          initialCategory: kAutoPartsCategory,
          partsHeader: (_) => const SizedBox(key: ValueKey('parts_header_stub'), height: 40),
        ),
      );
      expect(find.byKey(const ValueKey('parts_header_stub')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_card_p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('market_card_c1')), findsNothing);
      // Бошқа таб — AVA блоки йўқ.
      await tester.tap(find.byKey(const ValueKey('market_tab_cars')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('parts_header_stub')), findsNothing);
      expect(find.byKey(const ValueKey('market_card_c1')), findsOneWidget);
    });

    testWidgets('номаълум initialCategory — сукут (биринчи таб)', (tester) async {
      await _pump(
        tester,
        MarketScreen(
          marketId: 'auto',
          source: _FakeMarketSource([_tv('c1', 'cars')]),
          loadTaxonomy: () async => kTaxonomyV1,
          initialCategory: 'nope',
          partsHeader: (_) => const SizedBox(key: ValueKey('parts_header_stub')),
        ),
      );
      expect(find.byKey(const ValueKey('market_card_c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('parts_header_stub')), findsNothing);
    });

    testWidgets('openMarket бўлимни узатади', (tester) async {
      Widget? pushed;
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openMarket(
              context,
              'auto',
              initialCategory: kAutoPartsCategory,
              loadTaxonomy: () async => kTaxonomyV1,
              canOpen: (_) => true,
              push: (s) async => pushed = s,
            ),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect((pushed as MarketScreen).initialCategory, 'parts');
      expect((pushed as MarketScreen).marketId, 'auto');
    });

    test('«Менинг машинам»: «Мошина бозори → Эҳтиёт қисмлар» кириши; бонус/машина бўлимлари жойида', () {
      final src = File('lib/features/incentives/screens/auto_hub_screen.dart').readAsStringSync();
      expect(src.contains("ValueKey('auto_hub_parts_market')"), isTrue);
      expect(src.contains("openMarket(context, 'auto', initialCategory: kAutoPartsCategory)"), isTrue);
      expect(src.contains('_partsMarketEntry(context)'), isTrue);
      for (final kept in ['_carCard(context)', '_bonusCard(context)', '_serviceCard(context)', '_chips(context)']) {
        expect(src.contains(kept), isTrue, reason: kept);
      }
    });
  });
}

TvShopItem _tv(String id, String category) => TvShopItem(
      id: id,
      ownerPhone: '998901111111',
      ownerName: 'С',
      title: 'Эълон $id',
      price: 1000,
      photoUrl: '',
      kind: 'product',
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      market: 'auto',
      category: category,
    );

class _FakeMarketSource implements MarketListingSource {
  _FakeMarketSource(this.items);
  final List<TvShopItem> items;

  @override
  RingFetcher<TvShopItem> fetcher(MarketFilter filter) => (districtIds, startAfter, limit) async {
        final all = [
          for (final i in items)
            if (districtIds.contains(i.districtId) && (filter.category.isEmpty || i.category == filter.category)) i
        ];
        final start = startAfter is int ? startAfter : 0;
        final page = all.skip(start).take(limit).toList();
        return RingFetchResult(page, start + page.length);
      };

  @override
  Future<List<String>> districtsOf(String regionId) async => regionId == 'xorazm' ? ['gurlan'] : const [];
}

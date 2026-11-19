// Эга 2026-11-19 (тезлик): бозор экрани уй кешидан (HomeShopFeed) дарҳол чизилади, сервер натижаси келгач
// алмаштирилади; биринчи саҳифа кичик ва биринчи бўш бўлмаган ҳалқадан кейиноқ; карточка расми декод кенглиги.
import 'dart:async';

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/ring_query.dart';
import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/home_strip_mix.dart';
import 'package:ava_gurlan/features/markets/data/market_listings_source.dart';
import 'package:ava_gurlan/features/markets/data/market_search.dart';
import 'package:ava_gurlan/features/markets/screens/market_screen.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_shop_photo_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'taxonomy_fixture.dart';

TvShopItem _it(String id, String market,
        {String category = '',
        String district = 'gurlan',
        String region = 'xorazm',
        int ageMin = 0,
        String status = 'active',
        bool? imported}) =>
    TvShopItem(
      id: id,
      ownerPhone: '998901111111',
      ownerName: 'Сотувчи',
      title: 'Эълон $id',
      price: 1000,
      photoUrl: '',
      kind: 'product',
      districtId: district,
      regionId: region,
      districtLabel: '',
      market: market,
      category: category,
      imported: imported,
      status: status,
      createdAt: DateTime(2026, 11, 19, 12).subtract(Duration(minutes: ageMin)),
    );

/// Сохта манба: сўров [gate] тугагунча кутади.
class _GatedSource implements MarketListingSource {
  _GatedSource(this.items);
  final List<TvShopItem> items;
  final gate = Completer<void>();
  final List<int> limits = [];

  @override
  RingFetcher<TvShopItem> fetcher(MarketFilter filter) => (districtIds, startAfter, limit) async {
        limits.add(limit);
        await gate.future;
        final all = [
          for (final i in items)
            if (districtIds.contains(i.districtId) && i.market == filter.market) i
        ];
        final start = startAfter is int ? startAfter : 0;
        final page = all.skip(start).take(limit).toList();
        return RingFetchResult(page, start + page.length);
      };

  @override
  Future<List<String>> districtsOf(String regionId) async =>
      regionId == 'xorazm' ? ['gurlan', 'xiva'] : const [];

  @override
  Future<MarketSearchPage> search(MarketSearchRequest request, {Object? startAfter}) async => MarketSearchPage.empty;
}

void main() {
  setUp(() {
    GeoContext.resetForTest();
    ServiceConfigHolder.resetForTest();
    GeoContext.homeOverride = () => const GeoArea(regionId: 'xorazm', districtId: 'gurlan');
    HomeShopFeed.debugReset();
  });
  tearDown(HomeShopFeed.debugReset);

  group('marketSeedItems (тоза)', () {
    final plan = buildRingPlan(userDistrictId: 'gurlan', userRegionId: 'xorazm');
    test('шу бозор, фаол, ҳалқа бўйича, ҳалқа ичида янгиси олдин, такрорсиз', () {
      final out = marketSeedItems([
        _it('far', 'meat', district: 'nukus', region: 'qoraqalpogiston'),
        _it('reg', 'meat', district: 'xiva', ageMin: 1),
        _it('old', 'meat', ageMin: 30),
        _it('new', 'meat', ageMin: 2),
        _it('new', 'meat', ageMin: 2),
        _it('farm', 'farm'),
        _it('blocked', 'meat', status: 'blocked'),
        _it('nodistrict', 'meat', district: ''),
      ], filter: const MarketFilter(market: 'meat'), plan: plan);
      expect(out.map((r) => r.item.id), ['new', 'old', 'reg', 'far']);
      expect(out.map((r) => r.ring), [0, 0, 1, 2]);
    });
    test('бўлим ва «Импорт» филтри', () {
      final items = [
        _it('b', 'meat', category: 'beef'),
        _it('f', 'meat', category: 'fish', imported: true),
      ];
      expect(marketSeedItems(items, filter: const MarketFilter(market: 'meat', category: 'beef'), plan: plan)
          .map((r) => r.item.id), ['b']);
      expect(marketSeedItems(items, filter: const MarketFilter(market: 'meat', importedOnly: true), plan: plan)
          .map((r) => r.item.id), ['f']);
    });
  });

  group('HomeShopFeed.cachedItems', () {
    test('йўқ → null; янги → рўйхат; 10 дақиқадан эски → null (чегара)', () {
      expect(HomeShopFeed.cachedItems(), isNull);
      final at = DateTime(2026, 11, 19, 12);
      HomeShopFeed.debugSetCached([_it('a', 'meat')], at: at);
      expect(HomeShopFeed.cachedItems(now: at.add(const Duration(minutes: 10)))!.single.id, 'a');
      expect(HomeShopFeed.cachedItems(now: at.add(const Duration(minutes: 10, seconds: 1))), isNull);
    });
    test('recent() муваффақиятли натижани кешга ёзади', () async {
      HomeShopFeed.debugLoader = () async => [_it('z', 'farm')];
      addTearDown(() => HomeShopFeed.debugLoader = null);
      await HomeShopFeed.recent();
      await Future<void>.delayed(Duration.zero);
      expect(HomeShopFeed.cachedItems()!.single.id, 'z');
    });
  });

  testWidgets('кешдан дарҳол: сервер кутаётганда кеш карточкалари; сервер тугагач — фақат сервер, такрорсиз',
      (tester) async {
    tester.view.physicalSize = const Size(1100 * 2, 1600 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final src = _GatedSource([_it('s1', 'meat'), _it('both', 'meat', ageMin: 5)]);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: MarketScreen(
        marketId: 'meat',
        source: src,
        loadTaxonomy: () async => kTaxonomyV1,
        cachedItems: () => [_it('both', 'meat', ageMin: 5), _it('stale', 'meat', ageMin: 9), _it('x', 'farm')],
      ),
    ));
    await tester.pump();
    await tester.pump();
    // Сервер ҳали жавоб бермаган — кеш карточкалари кўринади (бошқа бозор — йўқ).
    expect(find.byKey(const ValueKey('market_card_both')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_stale')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_x')), findsNothing);
    expect(src.limits.first, MarketScreen.firstPageSize, reason: 'биринчи саҳифа кичик');

    src.gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('market_card_s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_card_both')), findsOneWidget, reason: 'такрорсиз');
    expect(find.byKey(const ValueKey('market_card_stale')), findsNothing,
        reason: 'сервер ҳалқани тугатди — кешдаги эски ёзув олиб ташланди');
  });

  test('cardDecodeWidth: кенглик × DPR, чегаралар, номаълум ўлчам → 900', () {
    expect(cardDecodeWidth(112, 2.75), 308);
    expect(cardDecodeWidth(10, 1), 64);
    expect(cardDecodeWidth(2000, 3), 900);
    expect(cardDecodeWidth(double.infinity, 2), 900);
    expect(cardDecodeWidth(0, 2), 900);
  });
}

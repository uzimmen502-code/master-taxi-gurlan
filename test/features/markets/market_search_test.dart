// «Бозорлар» сервер қидируви (2026-11-16): токен танлаш, сўров параметрлари, бирлаштириш, хато/индекс фоллбэк,
// debounce ва минимал узунлик.
import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/ring_query.dart';
import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/markets/data/market_listings_source.dart';
import 'package:ava_gurlan/features/markets/data/market_search.dart';
import 'package:ava_gurlan/features/markets/screens/market_screen.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'taxonomy_fixture.dart';

TvShopItem _it(String id, String title,
        {String market = 'meat', String category = 'beef', String status = 'active', DateTime? at}) =>
    TvShopItem(
      id: id,
      ownerPhone: '998901111111',
      ownerName: 'Сотувчи',
      title: title,
      price: 100000,
      photoUrl: '',
      kind: 'product',
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      market: market,
      category: category,
      status: status,
      createdAt: at,
    );

FirebaseException _fx(String code) => FirebaseException(plugin: 'cloud_firestore', code: code);

class _Src implements MarketListingSource {
  _Src(this.local, {this.server = const [], this.error});
  final List<TvShopItem> local;
  final List<TvShopItem> server;
  Object? error;
  final List<MarketSearchRequest> requests = [];

  @override
  RingFetcher<TvShopItem> fetcher(MarketFilter filter) => (districtIds, startAfter, limit) async {
        final all = [
          for (final i in local)
            if (districtIds.contains(i.districtId) && i.market == filter.market) i
        ];
        final start = startAfter is int ? startAfter : 0;
        final page = all.skip(start).take(limit).toList();
        return RingFetchResult(page, start + page.length);
      };

  @override
  Future<List<String>> districtsOf(String regionId) async => regionId == 'xorazm' ? ['gurlan'] : const [];

  @override
  Future<MarketSearchPage> search(MarketSearchRequest request, {Object? startAfter}) async {
    requests.add(request);
    final e = error;
    if (e != null) throw e;
    return MarketSearchPage(server, null, hasMore: false);
  }
}

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1100 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: w));
  await tester.pumpAndSettle();
}

Finder _card(String id) => find.byKey(ValueKey('market_card_$id'));

void main() {
  group('marketServerSearchToken', () {
    test('бўш/1 белги — null (фақат клиент)', () {
      expect(marketServerSearchToken(''), isNull);
      expect(marketServerSearchToken('  '), isNull);
      expect(marketServerSearchToken('г'), isNull);
    });
    test('биринчи сўз, лотин шакли (иккала ёзув учун)', () {
      expect(marketServerSearchToken('Гўшт мол'), "go'sht");
      expect(marketServerSearchToken("go'sht mol"), "go'sht");
      expect(marketServerSearchToken('Telefon Samsung'), 'telefon');
      expect(marketServerSearchToken('oʻrik'), "o'rik"); // белги бирлаштирилади
    });
    test('2 белги — бутун сўз токени; 15 дан узун — қирқилади (сервер бош лимити)', () {
      expect(marketServerSearchToken('tv'), 'tv');
      expect(marketServerSearchToken('abcdefghijklmnopqrst'), 'abcdefghijklmno');
      expect(marketServerSearchToken('abcdefghijklmnopqrst')!.length, kMarketSearchTokenMaxLen);
    });
    test("`'` билан тугайдиган номзод ўтказилади (сервер ёзмайди)", () {
      expect(marketServerSearchToken("qo'"), 'қў');
    });
  });

  group('MarketSearchRequest', () {
    test('бозор: status + market, лимит 40, createdAt desc', () {
      final r = MarketSearchRequest.forQuery('Гўшт', market: 'meat')!;
      expect(r.equals, {'status': 'active', 'market': 'meat'});
      expect(r.token, "go'sht");
      expect(r.limit, 40);
      expect(MarketSearchRequest.arrayField, 'searchTokens');
      expect(MarketSearchRequest.orderField, 'createdAt');
      expect(MarketSearchRequest.orderDescending, isTrue);
    });
    test('Аралаш: бозор филтрисиз', () {
      final r = MarketSearchRequest.forQuery('telefon')!;
      expect(r.equals, {'status': 'active'});
      expect(r.market, isNull);
    });
    test('қисқа сўров — сўров йўқ', () => expect(MarketSearchRequest.forQuery('a', market: 'meat'), isNull));
  });

  group('marketServerItemMatches (қолган сўзлар)', () {
    final item = _it('t', 'Telefon Samsung A52');
    test('сўз боши, иккала ёзув', () {
      expect(marketServerItemMatches(item, 'telef'), isTrue);
      expect(marketServerItemMatches(item, 'телеф самс'), isTrue);
      expect(marketServerItemMatches(_it('g', 'Гўшт мол'), "go'sht"), isTrue);
    });
    test('барча сўзлар шарт; ўрта қисм — мос эмас', () {
      expect(marketServerItemMatches(item, 'telefon iphone'), isFalse);
      expect(marketServerItemMatches(item, 'efon'), isFalse);
    });
    test('бўш сўров — true', () => expect(marketServerItemMatches(item, '  '), isTrue));
  });

  group('mergeMarketSearch', () {
    test('id бўйича такрорсиз, энг янгиси олдин, санасиз — охирида', () {
      final a = _it('a', 'A', at: DateTime(2026, 11, 1));
      final b = _it('b', 'B', at: DateTime(2026, 11, 10));
      final c = _it('c', 'C');
      final bDup = _it('b', 'B (server)', at: DateTime(2026, 11, 10));
      final out = mergeMarketSearch([a, c, b], [bDup, _it('d', 'D', at: DateTime(2026, 11, 5))]);
      expect(out.map((i) => i.id), ['b', 'd', 'a', 'c']);
      expect(out.first.title, 'B'); // клиент нусхаси устун
    });
    test('бўш', () => expect(mergeMarketSearch(const [], const []), isEmpty));
  });

  group('searchAllMarkets (Аралаш)', () {
    test('асосий сўров: фаол эълонлар', () async {
      MarketSearchRequest? got;
      final out = await searchAllMarkets(
        'Telefon yangi',
        primary: (r) async {
          got = r;
          return MarketSearchPage([_it('x', 't'), _it('y', 't', status: 'pending')], null, hasMore: false);
        },
        legacy: (t, l) async => fail('legacy чақирилмаслиги керак'),
      );
      expect(got, const MarketSearchRequest(token: 'telefon'));
      expect(out.map((i) => i.id), ['x']);
    });
    test('индекс хатоси — аввалги оддий сўровга қайтади', () async {
      String? token;
      int? limit;
      final out = await searchAllMarkets(
        'telefon',
        primary: (r) async => throw _fx('failed-precondition'),
        legacy: (t, l) async {
          token = t;
          limit = l;
          return [_it('z', 't')];
        },
      );
      expect(token, 'telefon');
      expect(limit, 40);
      expect(out.map((i) => i.id), ['z']);
    });
    test('бошқа хато — юқорига', () {
      expect(
        searchAllMarkets('telefon',
            primary: (r) async => throw _fx('unavailable'), legacy: (t, l) async => const []),
        throwsA(isA<FirebaseException>()),
      );
    });
    test('қисқа сўров — сервер чақирилмайди', () async {
      final out = await searchAllMarkets('t',
          primary: (r) async => fail('чақирилмасин'), legacy: (t, l) async => fail('чақирилмасин'));
      expect(out, isEmpty);
    });
    test('хато коди', () {
      expect(marketSearchErrorCode(_fx('failed-precondition')), 'MARKET_SEARCH_INDEX_MISSING');
      expect(marketSearchErrorCode(StateError('x')), 'MARKET_SEARCH_FAILED');
    });
  });

  group('MarketScreen қидируви', () {
    setUp(() {
      GeoContext.resetForTest();
      ServiceConfigHolder.resetForTest();
    });

    final local = [
      _it('l1', 'Гўшт мол', at: DateTime(2026, 11, 1)),
      _it('l2', 'Қўй', at: DateTime(2026, 11, 2)),
    ];
    final server = [
      _it('s1', 'Мол гўшти янги', at: DateTime(2026, 11, 12)),
      _it('l1', 'Гўшт мол', at: DateTime(2026, 11, 1)), // такрор
      _it('s2', 'Гўшт балиқ', category: 'fish', at: DateTime(2026, 11, 11)),
      _it('s3', 'Гўшт бошқа бозор', market: 'farm', at: DateTime(2026, 11, 13)),
      _it('s4', 'Мол', at: DateTime(2026, 11, 14)), // қолган сўз мос эмас
    ];

    testWidgets('debounce 350 мс, 1 белги — сервер йўқ; бирлаштириш, такрорсиз, филтрлар клиентда', (tester) async {
      final src = _Src(local, server: server);
      await _pump(tester, MarketScreen(marketId: 'meat', source: src, loadTaxonomy: () async => kTaxonomyV1));
      final field = find.descendant(of: find.byKey(const ValueKey('market_search')), matching: find.byType(TextField));
      final input = field.evaluate().isEmpty ? find.byKey(const ValueKey('market_search')) : field;

      await tester.enterText(input, 'г');
      await tester.pump(const Duration(milliseconds: 400));
      expect(src.requests, isEmpty);

      await tester.enterText(input, 'гўшт');
      await tester.pump(const Duration(milliseconds: 200));
      expect(src.requests, isEmpty, reason: 'debounce');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(src.requests, [const MarketSearchRequest(token: "go'sht", market: 'meat')]);
      expect(_card('s1'), findsOneWidget);
      expect(_card('l1'), findsOneWidget);
      expect(_card('l2'), findsNothing);
      expect(_card('s2'), findsOneWidget); // «Барчаси»
      expect(_card('s3'), findsNothing); // бошқа бозор
      expect(_card('s4'), findsNothing);
      // Энг янгиси олдин.
      expect(tester.getTopLeft(_card('s1')).dy, lessThan(tester.getTopLeft(_card('l1')).dy));

      // Бўлим — клиентда (сервер натижасига ҳам).
      await tester.tap(find.byKey(const ValueKey('market_cat_fish')));
      await tester.pumpAndSettle();
      expect(_card('s2'), findsOneWidget);
      expect(_card('s1'), findsNothing);

      // Тозалаш — сервер натижалари йўқолади.
      await tester.enterText(input, '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('market_cat_all')));
      await tester.pumpAndSettle();
      expect(_card('s1'), findsNothing);
      expect(_card('l2'), findsOneWidget);
    });

    testWidgets('индекс хатоси — жим, фақат клиент, кейинги сўровлар серверга бормайди', (tester) async {
      final src = _Src(local, server: server, error: _fx('failed-precondition'));
      await _pump(tester, MarketScreen(marketId: 'meat', source: src, loadTaxonomy: () async => kTaxonomyV1));
      final input = find.descendant(of: find.byKey(const ValueKey('market_search')), matching: find.byType(TextField));
      final f = input.evaluate().isEmpty ? find.byKey(const ValueKey('market_search')) : input;
      await tester.enterText(f, 'гўшт');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(src.requests, hasLength(1));
      expect(find.text('search_error_internet'), findsNothing);
      expect(_card('l1'), findsOneWidget);
      expect(_card('s1'), findsNothing);
      await tester.enterText(f, 'мол');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(src.requests, hasLength(1));
      expect(_card('l1'), findsOneWidget);
    });

    testWidgets('бошқа хато — умумий хабар, клиент натижалари қолади', (tester) async {
      final src = _Src(local, server: server, error: _fx('unavailable'));
      await _pump(tester, MarketScreen(marketId: 'meat', source: src, loadTaxonomy: () async => kTaxonomyV1));
      final input = find.descendant(of: find.byKey(const ValueKey('market_search')), matching: find.byType(TextField));
      final f = input.evaluate().isEmpty ? find.byKey(const ValueKey('market_search')) : input;
      await tester.enterText(f, 'гўшт');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('search_error_internet'), findsOneWidget);
      expect(_card('l1'), findsOneWidget);
    });
  });
}

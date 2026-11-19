// Уй тасмалари аралашмаси (эга 2026-11-16/17): Аралаш — tv_shop_items яқиндан узоққа + бозор белгиси;
// «Яқиндаги эълонлар» — showInNearbyAds / fallback, деҳқон (дўкон эмас), ишлатилган хусусий электроника, уй-жой;
// янги уй ошпазлари (7 кун, бир марталик); «Уй таоми» белгиси.
import 'dart:io';

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/module_geo_policy.dart';
import 'package:ava_gurlan/features/home/home_strip_mix.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:ava_gurlan/features/markets/widgets/market_form_fields.dart' show marketShortBadge;
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/models/realty_listing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

TvShopItem item(
  String id, {
  String market = '',
  String category = '',
  String businessId = '',
  Map<String, Object?> attrs = const {},
  String district = '',
  String region = '',
  int ageMin = 0,
  String status = 'active',
}) =>
    TvShopItem.fromMap(id, {
      'title': 'T $id',
      'status': status,
      if (market.isNotEmpty) 'market': market,
      if (category.isNotEmpty) 'category': category,
      if (businessId.isNotEmpty) 'businessId': businessId,
      if (attrs.isNotEmpty) 'attrs': attrs,
      'districtId': district,
      'regionId': region,
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 16, 12).subtract(Duration(minutes: ageMin))),
    });

RealtyListing realty(String id, {String district = '', String region = '', String status = 'active'}) =>
    RealtyListing.fromMap(id, {
      'title': 'R $id',
      'status': status,
      'districtId': district,
      'regionId': region,
    });

const userD = 'gurlan';
const userR = 'xorazm';
const nation = GeoScope(level: GeoLevel.nation, area: GeoArea(regionId: userR, districtId: userD));

MarketTaxonomy tax(Map<String, dynamic> markets) => MarketTaxonomy.fromMap({'version': 4, 'markets': markets});

Map<String, dynamic> m(String moduleId, List<Map<String, dynamic>> cats) => {
      'moduleId': moduleId,
      'order': 1,
      'names': {'uz_Cyrl': 'x', 'uz_Latn': 'x', 'ru': 'x'},
      'categories': cats,
    };

void main() {
  group('nearbyAdsCategories', () {
    test('v4: showInNearbyAds true бўлимлар; false/йўқ — чиқмайди', () {
      final t = tax({
        'livestock': m('livestock_market', [
          {'id': 'all', 'showInNearbyAds': true}
        ]),
        'auto': m('auto_market', [
          {'id': 'cars', 'showInNearbyAds': true},
          {'id': 'parts', 'showInNearbyAds': false},
          {'id': 'moto'},
        ]),
      });
      expect(nearbyAdsCategories(t), {'livestock.all', 'auto.cars'});
    });
    test('калит умуман йўқ (v3) ёки таксономия йўқ → fallback', () {
      final t = tax({
        'auto': m('auto_market', [
          {'id': 'cars'}
        ])
      });
      expect(nearbyAdsCategories(t), kNearbyAdsFallbackCategories);
      expect(nearbyAdsCategories(null), {'livestock.all', 'auto.cars', 'auto.moto', 'auto.tech'});
    });
    test('MarketCategory.fromMap: bool эмас → null', () {
      final t = tax({
        'auto': m('auto_market', [
          {'id': 'cars', 'showInNearbyAds': 'yes'}
        ])
      });
      expect(t.market('auto')!.categories.single.showInNearbyAds, isNull);
    });
  });

  group('showsInNearbyAds', () {
    final cats = kNearbyAdsFallbackCategories;
    test('мол/мошина бўлими — ҳа; эҳтиёт қисм / гўшт — йўқ; нофаол — йўқ', () {
      expect(showsInNearbyAds(item('a', market: 'livestock', category: 'all'), cats), isTrue);
      expect(showsInNearbyAds(item('b', market: 'auto', category: 'tech'), cats), isTrue);
      // Бизнес объекти (хусусий эмас) — 11-19 дан хусусий эҳтиёт қисм чиқади, шунинг учун businessId билан.
      expect(showsInNearbyAds(item('c', market: 'auto', category: 'parts', businessId: 'B1'), cats), isFalse);
      expect(showsInNearbyAds(item('d', market: 'meat', category: 'beef'), cats), isFalse);
      expect(showsInNearbyAds(item('e', market: 'livestock', category: 'all', status: 'blocked'), cats), isFalse);
    });
    test('электроника/маиший: хусусий — ҳа (used ҳам, new ҳам — эга 2026-11-19); бизнес — йўқ', () {
      expect(showsInNearbyAds(item('a', market: 'electronics', attrs: {'condition': 'used'}), cats), isTrue);
      expect(showsInNearbyAds(item('b', market: 'appliances', attrs: {'condition': 'used'}), cats), isTrue);
      expect(showsInNearbyAds(item('c', market: 'electronics', businessId: 'B1', attrs: {'condition': 'used'}), cats),
          isFalse);
      expect(showsInNearbyAds(item('c2', market: 'electronics', businessId: 'B1', attrs: {'condition': 'new'}), cats),
          isFalse);
      // Аввал (11-16) хусусий new/шартсиз — йўқ эди; 11-19 дан хусусий сотувчи ҳар қандай бозорда — ҳа.
      expect(showsInNearbyAds(item('d', market: 'electronics', attrs: {'condition': 'new'}), cats), isTrue);
      expect(showsInNearbyAds(item('e', market: 'electronics'), cats), isTrue);
    });
    test('хусусий сотувчи (эга 2026-11-19): ҳар бозор ва Аралаш — ҳа; гўшт — йўқ; бизнес белгиланмаган бозорда — йўқ',
        () {
      // positive
      expect(showsInNearbyAds(item('p1'), cats), isTrue, reason: 'Аралаш (market бўш), хусусий');
      expect(showsInNearbyAds(item('p2', market: 'clothes', category: 'women'), cats), isTrue);
      expect(showsInNearbyAds(item('p3', market: 'auto', category: 'parts'), cats), isTrue,
          reason: 'хусусий эҳтиёт қисм ҳам');
      expect(isNearbyPrivateItem(item('p4', businessId: '   ')), isTrue, reason: 'бўшлиқ businessId — хусусий');
      // negative
      expect(showsInNearbyAds(item('n1', market: 'meat', category: 'beef'), cats), isFalse, reason: 'гўшт хусусий');
      expect(showsInNearbyAds(item('n1b', market: ' meat '), cats), isFalse, reason: 'гўшт (бўшлиқ билан)');
      expect(showsInNearbyAds(item('n2', market: 'clothes', category: 'women', businessId: 'B1'), cats), isFalse);
      expect(showsInNearbyAds(item('n3', businessId: 'B1'), cats), isFalse, reason: 'Аралаш, бизнес');
      expect(showsInNearbyAds(item('n4', status: 'blocked'), cats), isFalse, reason: 'нофаол хусусий');
      expect(showsInNearbyAds(item('n5', status: 'pending'), cats), isFalse);
      // boundary: бизнес, лекин белгиланган бўлим — аввалгидек ҳа (мавжуд қоида сақланди)
      expect(showsInNearbyAds(item('b1', market: 'livestock', category: 'all', businessId: 'B1'), cats), isTrue);
      expect(showsInNearbyAds(item('b2', market: 'meat', category: 'beef', businessId: 'B1'), cats), isFalse);
    });
    test('қатор матни: сарлавҳа · нарх · туман; бўшлари ташланади', () {
      expect(nearbyShopRowText(title: ' Сигир ', price: '7 000 000 сўм', district: 'Гурлан'),
          'Сигир · 7 000 000 сўм · Гурлан');
      expect(nearbyShopRowText(title: 'Сигир', price: '', district: 'Гурлан'), 'Сигир · Гурлан');
      expect(nearbyShopRowText(title: 'Сигир', price: ' ', district: ''), 'Сигир');
    });
    test('деҳқон: хусусий — ҳа; қишлоқ хўжалиги объекти — ҳа; дўкон (retail) — йўқ; аниқланмаган — йўқ', () {
      final bc = <String, String?>{'farmB': 'agriculture', 'shopB': 'retail', 'goneB': null};
      expect(showsInNearbyAds(item('a', market: 'farm', category: 'fruits'), cats, businessCategories: bc), isTrue);
      expect(showsInNearbyAds(item('b', market: 'farm', businessId: 'farmB'), cats, businessCategories: bc), isTrue);
      expect(showsInNearbyAds(item('c', market: 'farm', businessId: 'shopB'), cats, businessCategories: bc), isFalse);
      expect(showsInNearbyAds(item('d', market: 'farm', businessId: 'goneB'), cats, businessCategories: bc), isFalse);
      expect(showsInNearbyAds(item('e', market: 'farm', businessId: 'unknownB'), cats, businessCategories: bc),
          isFalse);
    });
    test('farmBusinessIds — фақат фаол деҳқон маҳсулоти объектлари, такрорсиз', () {
      final ids = farmBusinessIds([
        item('a', market: 'farm', businessId: 'B1'),
        item('b', market: 'farm', businessId: 'B1'),
        item('c', market: 'farm'),
        item('d', market: 'auto', businessId: 'B2'),
        item('e', market: 'farm', businessId: 'B3', status: 'blocked'),
      ]);
      expect(ids, {'B1'});
    });
  });

  group('HomeBusinessCategoryCache', () {
    setUp(HomeBusinessCategoryCache.debugReset);
    test('фақат янги id ўқилади; топилмагани null сақланади; хато — кешланмайди', () async {
      final calls = <List<String>>[];
      Future<Map<String, String>> loader(List<String> ids) async {
        calls.add(ids);
        return {'A': 'agriculture'};
      }

      final r1 = await HomeBusinessCategoryCache.resolve({'A', 'B'}, loader);
      expect(r1, {'A': 'agriculture', 'B': null});
      final r2 = await HomeBusinessCategoryCache.resolve({'A', 'B'}, loader);
      expect(r2, r1);
      expect(calls.length, 1);
      final r3 = await HomeBusinessCategoryCache.resolve({'C'}, (_) async => throw StateError('offline'));
      expect(r3, isEmpty);
      await HomeBusinessCategoryCache.resolve({'C'}, loader);
      expect(calls.last, ['C']);
    });
  });

  group('nearestFirst / scope', () {
    test('туман → вилоят → бошқа; бир ҳалқада янгиси олдин', () {
      final list = aralashShopItems([
        item('far', region: 'toshkent', district: 'chilonzor'),
        item('reg_old', region: userR, district: 'urganch', ageMin: 30),
        item('mine', region: userR, district: userD, ageMin: 60),
        item('reg_new', region: userR, district: 'xiva', ageMin: 5),
        item('mine', region: userR, district: userD), // такрор id
      ], scope: nation, userDistrictId: userD, userRegionId: userR, limit: 10);
      expect(list.map((i) => i.id), ['mine', 'reg_new', 'reg_old', 'far']);
    });
    test('limit ва нофаол чиқмайди', () {
      final list = aralashShopItems([
        for (var i = 0; i < 15; i++) item('i$i', ageMin: i),
        item('x', status: 'blocked'),
      ], scope: nation, userDistrictId: userD, userRegionId: userR, limit: 10);
      expect(list.length, 10);
      expect(list.any((i) => i.id == 'x'), isFalse);
    });
    test('inHomeStripScope: туман / вилоят / Республика', () {
      const d = GeoScope(level: GeoLevel.district, area: GeoArea(regionId: userR, districtId: userD));
      const r = GeoScope(level: GeoLevel.region, area: GeoArea(regionId: userR, districtId: userD));
      expect(inHomeStripScope(districtId: userD, regionId: userR, scope: d), isTrue);
      expect(inHomeStripScope(districtId: '', regionId: '', scope: d), isTrue);
      expect(inHomeStripScope(districtId: 'xiva', regionId: userR, scope: d), isFalse);
      expect(inHomeStripScope(districtId: 'xiva', regionId: userR, scope: r), isTrue);
      expect(inHomeStripScope(districtId: 'chilonzor', regionId: 'toshkent', scope: r), isFalse);
      expect(inHomeStripScope(districtId: 'xiva', regionId: '', scope: r), isFalse);
      expect(inHomeStripScope(districtId: 'chilonzor', regionId: 'toshkent', scope: nation), isTrue);
    });
  });

  group('buildNearbyAdExtras', () {
    test('маҳсулот + уй-жой, такрорсиз, белги калити, яқиндан, limit', () {
      final extras = buildNearbyAdExtras(
        shop: [
          item('cow', market: 'livestock', category: 'all', region: userR, district: userD),
          item('cow', market: 'livestock', category: 'all', region: userR, district: userD),
          item('meat', market: 'meat', category: 'beef', region: userR, district: userD),
          item('tv', market: 'electronics', attrs: {'condition': 'used'}, region: 'toshkent', district: 'chilonzor'),
          item('apple', market: 'farm', businessId: 'shopB', region: userR, district: userD),
        ],
        realty: [realty('h1', region: userR, district: 'xiva'), realty('h2', status: 'sold')],
        categories: kNearbyAdsFallbackCategories,
        businessCategories: const {'shopB': 'retail'},
        scope: nation,
        userDistrictId: userD,
        userRegionId: userR,
        limit: 10,
      );
      expect(extras.map((e) => e.id), ['shop_cow', 'realty_h1', 'shop_tv']);
      expect(extras.map((e) => e.badgeKey),
          ['market_short_livestock', 'aralash_badge_realty', 'market_short_electronics']);
      final limited = buildNearbyAdExtras(
        shop: [for (var i = 0; i < 20; i++) item('c$i', market: 'auto', category: 'cars')],
        realty: const [],
        categories: kNearbyAdsFallbackCategories,
        scope: nation,
        userDistrictId: userD,
        userRegionId: userR,
        limit: 10,
      );
      expect(limited.length, 10);
    });
    test('бозор белгиси: market_short_* ; бозорсиз (ўз дўкони) — белгисиз', () {
      String tr(String k) => {'market_short_farm': 'Деҳқон', 'market_short_livestock': 'Мол'}[k] ?? k;
      expect(marketShortBadge(tr, 'farm'), 'Деҳқон');
      expect(marketShortBadge(tr, ''), '');
    });
  });

  group('newHomeCooks', () {
    final now = DateTime(2026, 11, 16, 12);
    Restaurant r(String id, {String legal = 'individual', String status = 'approved', int? daysAgo, bool demo = false}) =>
        Restaurant.fromMap(id, {
          'name': ' Ош $id ',
          'legalType': legal,
          'status': status,
          if (demo) 'isDemo': true,
          if (daysAgo != null) 'createdAt': Timestamp.fromDate(now.subtract(Duration(days: daysAgo))),
        });
    test('7 кун ичидаги тасдиқланган уй ошпазлари, янгиси олдин; кафе/эски/намуна/кўрилган — йўқ', () {
      final out = newHomeCooks([
        r('a', daysAgo: 3),
        r('b', daysAgo: 1),
        r('cafe', legal: 'llc', daysAgo: 1),
        r('old', daysAgo: 8),
        r('demo', daysAgo: 1, demo: true),
        r('pending', status: 'applied', daysAgo: 1),
        r('nodate'),
        r('seen', daysAgo: 2),
      ], now, dismissed: {'seen'});
      expect(out.map((x) => x.id), ['b', 'a']);
    });
    test('чегара: роппа-роса 7 кун — ҳа', () {
      expect(newHomeCooks([r('edge', daysAgo: 7)], now).length, 1);
    });
    test('сарлавҳа шаблони', () {
      expect(newHomeCookTitle('Янги: {name} уй таомлари', r('x', daysAgo: 1)), 'Янги: Ош x уй таомлари');
    });
  });

  group('3 тил ва манба шартномаси', () {
    test('янги калитлар 3 тилда', () {
      for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        final t = File('assets/lang/$lang.json').readAsStringSync();
        expect(t.contains('"home_badge_home_food"'), isTrue, reason: lang);
        expect(t.contains('"home_ads_new_home_cook"'), isTrue, reason: lang);
        expect(t.contains('{name}'), isTrue, reason: lang);
      }
    });
    test('ресторанлар тасмасида «Уй таоми», эълонлар тасмасида қўшимчалар уланган', () {
      final rest = File('lib/features/home/widgets/home_restaurants_section.dart').readAsStringSync();
      expect(rest.contains("if (r.isHomeCook) Flexible(child: HomeRowBadge(context.tr('home_badge_home_food')))"), isTrue);
      final home = File('lib/features/home/home_screen.dart').readAsStringSync();
      expect('onOpenShopItem: _openHomeShopItem'.allMatches(home).length, 2);
      final ads = File('lib/features/home/widgets/home_ads_section.dart').readAsStringSync();
      expect(ads.contains("bool get _withExtras => widget.adType == 'ad'"), isTrue);
      // Маҳсулот қатори: сарлавҳа · нарх (+бирлик) · туман (эга 2026-11-19).
      expect(ads.contains('nearbyShopRowText('), isTrue);
      expect(ads.contains('priceLabel(context.tr)'), isTrue);
      expect(ads.contains('GeoNames.district(entry.shop!.districtId'), isTrue);
    });
  });
}

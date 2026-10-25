import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/data/business_repository.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/tv_market/domain/shop_directions.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_public_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга қарори 2026-10-25: «битта онлайн дўкон, унинг таркибида турли йўналишдаги дўконлар; харидор маҳсулот,
/// видео ёки харита орқали ЎША ягона дўконга, айнан тегишли йўналишга ўтади».
const _owner = '998901111111';
const _alien = '998909999999';

Business _biz(String id, String name, {String owner = _owner, String status = 'active', int day = 1}) => Business(
      id: id,
      ownerId: owner,
      name: name,
      category: BusinessCategory.retail,
      phone: '998905550000',
      lat: 41.3,
      lng: 69.2,
      address: 'Гурлан, Навоий 5',
      openingHours: '09:00-20:00',
      status: status,
      createdAt: DateTime(2026, 10, day),
    );

TvShopItem _item(String id, String title,
        {String biz = '', String owner = _owner, String status = 'active', String kind = 'product', String desc = ''}) =>
    TvShopItem(
      id: id,
      ownerPhone: owner,
      ownerName: 'x',
      title: title,
      price: 1000,
      photoUrl: '',
      kind: kind,
      districtId: 'd',
      districtLabel: '',
      description: desc,
      status: status,
      businessId: biz,
    );

void main() {
  group('ShopDirections.build', () {
    test('ўз дўкони биринчи, кейин йўналишлар (энг эскиси олдин); блокланган ва бегона эганики йўқ', () {
      final d = ShopDirections.build(ownerPhone: _owner, shopName: 'Сидабилла', businesses: [
        _biz('b2', 'Техника', day: 5),
        _biz('b1', 'Кийим', day: 2),
        _biz('bx', 'Блокланган', status: 'blocked'),
        _biz('ba', 'Бегона', owner: _alien),
      ]);
      expect([for (final x in d.directions) x.name], ['Сидабилла', 'Кийим', 'Техника']);
      expect(d.hasChoice, isTrue);
    });

    test('ўз дўконида маҳсулот йўқ, йўналиш бор — ўз дўкони тугмаси йўқ; йўналиш ҳам йўқ — ўз дўкони қолади', () {
      final a = ShopDirections.build(ownerPhone: _owner, shopName: 'С', businesses: [_biz('b1', 'Кийим')], hasOwnItems: false);
      expect([for (final x in a.directions) x.businessId], ['b1']);
      expect(a.hasChoice, isFalse);
      final b = ShopDirections.build(ownerPhone: _owner, shopName: 'С', businesses: const [], hasOwnItems: false);
      expect([for (final x in b.directions) x.businessId], ['']);
    });
  });

  group('ShopDirections.initial — айнан тегишли йўналиш', () {
    final d = ShopDirections.build(ownerPhone: _owner, shopName: 'С', businesses: [_biz('b1', 'Кийим'), _biz('b2', 'Техника')]);

    test('аниқ businessId (харита/ҳавола) — ўша йўналиш', () {
      expect(d.initial(businessId: 'b2'), const ShopSelection.direction('b2'));
    });
    test('маҳсулот/видеодан — маҳсулотнинг йўналиши; ўз дўкони маҳсулоти — ўз дўкони', () {
      expect(d.initial(highlightBusinessId: 'b1'), const ShopSelection.direction('b1'));
      expect(d.initial(highlightBusinessId: ''), const ShopSelection.direction(''));
    });
    test('номаълум ёки блокланган йўналиш — хавфсиз: бутун дўкон («Барчаси»), бошқа дўкон эмас', () {
      expect(d.initial(businessId: 'yoq'), const ShopSelection.all());
      final withBlocked = ShopDirections.build(ownerPhone: _owner, shopName: 'С', businesses: [_biz('b1', 'К', status: 'blocked')]);
      expect(withBlocked.initial(businessId: 'b1'), const ShopSelection.direction(''), reason: 'ягона йўналиш — ўз дўкони');
    });
    test('мақсадсиз кирилса — «Барчаси»; йўналиш битта бўлса — ўша', () {
      expect(d.initial(), const ShopSelection.all());
      final one = ShopDirections.build(ownerPhone: _owner, shopName: 'С', businesses: [_biz('b1', 'К')], hasOwnItems: false);
      expect(one.initial(), const ShopSelection.direction('b1'));
    });
  });

  group('ShopDirections.itemsFor — бир дўкон маҳсулоти бошқасига адашиб ўтмайди', () {
    final d = ShopDirections.build(ownerPhone: _owner, shopName: 'С', businesses: [_biz('b1', 'Кийим'), _biz('b2', 'Техника')]);
    final items = [
      _item('o1', 'Нон'),
      _item('k1', 'Кўйлак', biz: 'b1'),
      _item('t1', 'Телевизор', biz: 'b2'),
      _item('t2', 'Блокли', biz: 'b2', status: 'blocked'),
      _item('x1', 'Ёт эга', biz: 'b1', owner: _alien),
      _item('z1', 'Блокланган йўналишники', biz: 'bx'),
    ];
    List<String> ids(ShopSelection s) => [for (final i in d.itemsFor(s, items, ownerPhone: _owner)) i.id];

    test('йўналиш бўйича', () {
      expect(ids(const ShopSelection.direction('b1')), ['k1']);
      expect(ids(const ShopSelection.direction('b2')), ['t1']);
      expect(ids(const ShopSelection.direction('')), ['o1']);
    });
    test('«Барчаси» — фақат фаол, фақат шу эганинг, фақат маълум йўналишлар', () {
      expect(ids(const ShopSelection.all()), ['o1', 'k1', 't1']);
    });
    test('меҳмон (йўналишлар ўқилмади) — йўналиш тугмаси йўқ, барча фаол маҳсулот кўринади', () {
      final g = ShopDirections.build(ownerPhone: _owner, shopName: 'С', businesses: const [], businessesKnown: false);
      expect(g.hasChoice, isFalse);
      expect(g.initial(businessId: 'b1'), const ShopSelection.all());
      expect([for (final i in g.itemsFor(const ShopSelection.all(), items, ownerPhone: _owner)) i.id], ['o1', 'k1', 't1', 'z1']);
    });
  });

  group('ShopDirections.filter — дўкон ичида қидирув ва тур', () {
    final items = [
      _item('a', 'Қизил кўйлак'),
      _item('b', 'Шим', desc: 'кўйлак билан'),
      _item('c', 'Тикиш хизмати', kind: 'service'),
    ];
    test('сўз бўйича (номда кучлироқ — олдин), тур бўйича', () {
      expect([for (final i in ShopDirections.filter(items, query: 'кўйлак')) i.id], ['a', 'b']);
      expect([for (final i in ShopDirections.filter(items, kind: 'service')) i.id], ['c']);
      expect(ShopDirections.filter(items, query: 'телевизор'), isEmpty);
      expect(ShopDirections.filter(items).length, 3);
    });
  });

  group('TvShopPublicScreen (виджет)', () {
    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(480 * 2, 1400 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: w));
      await tester.pumpAndSettle();
    }

    _FakeShop shop0() => _FakeShop(
          shop: const TvShop(ownerPhone: _owner, name: 'Сидабилла'),
          pages: [
            [_item('o1', 'Нон'), _item('k1', 'Кўйлак', biz: 'b1'), _item('t1', 'Телевизор', biz: 'b2')],
          ],
        );
    final bizs = [_biz('b1', 'Сидабилла — Кийим', day: 1), _biz('b2', 'Сидабилла — Техника', day: 2)];

    // UniqueKey: кетма-кет `pump`да эски State қайта ишлатилмасин (ҳар бири — янги кириш).
    TvShopPublicScreen screen(_FakeShop s, {String businessId = '', String highlight = '', Object? bizError}) => TvShopPublicScreen(
          key: UniqueKey(),
          ownerPhone: _owner,
          businessId: businessId,
          highlightItemId: highlight,
          shopRepository: s,
          businessRepository: _FakeBiz(bizs, error: bizError),
          loadChannelInfo: false,
        );

    testWidgets('маҳсулотдан кирилди (Техника) — Техника танланган, карточкаси, фақат унинг маҳсулоти; «Барчаси» — ҳаммаси', (tester) async {
      await pump(tester, screen(shop0(), highlight: 't1'));
      expect(find.text('Сидабилла'), findsWidgets, reason: 'онлайн дўкон номи');
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('shop_dir_b2'))).selected, isTrue);
      expect(find.byKey(const ValueKey('shop_dir_card')), findsOneWidget);
      expect(find.text('Гурлан, Навоий 5'), findsOneWidget);
      expect(find.text('Телевизор'), findsOneWidget);
      expect(find.text('Кўйлак'), findsNothing);
      expect(find.text('Нон'), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('shop_dir_all')));
      await tester.tap(find.byKey(const ValueKey('shop_dir_all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shop_dir_card')), findsNothing);
      for (final t in ['Нон', 'Кўйлак', 'Телевизор']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('харитадан (businessId) — шу йўналиш; номаълум businessId — «Барчаси» (бошқа дўкон эмас)', (tester) async {
      await pump(tester, screen(shop0(), businessId: 'b1'));
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('shop_dir_b1'))).selected, isTrue);
      expect(find.text('Кўйлак'), findsOneWidget);
      expect(find.text('Телевизор'), findsNothing);

      await pump(tester, screen(shop0(), businessId: 'yoq_obyekt'));
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('shop_dir_all'))).selected, isTrue);
    });

    testWidgets('дўкон ичида қидирув: топилади / «ҳеч нарса топилмади»', (tester) async {
      await pump(tester, screen(shop0()));
      await tester.enterText(find.byKey(const ValueKey('shop_search')), 'телевизор');
      await tester.pumpAndSettle();
      expect(find.text('Телевизор'), findsOneWidget);
      expect(find.text('Нон'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('shop_search')), 'самолёт');
      await tester.pumpAndSettle();
      expect(find.text('shop_search_none'), findsOneWidget);
    });

    testWidgets('юзлаб маҳсулот: «Яна кўрсатиш» кейинги саҳифани олади (такрорсиз)', (tester) async {
      final s = _FakeShop(
        shop: const TvShop(ownerPhone: _owner, name: 'С'),
        pages: [
          [_item('p1', 'Биринчи')],
          [_item('p1', 'Биринчи'), _item('p2', 'Иккинчи')],
        ],
      );
      await pump(tester, screen(s));
      expect(find.text('Иккинчи'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('shop_load_more')));
      await tester.tap(find.byKey(const ValueKey('shop_load_more')));
      await tester.pumpAndSettle();
      expect(find.text('Иккинчи'), findsOneWidget);
      expect(find.text('Биринчи'), findsOneWidget);
      expect(find.byKey(const ValueKey('shop_load_more')), findsNothing, reason: 'охирги саҳифа');
      expect(s.pageCalls, 2);
    });

    testWidgets('меҳмон: йўналишлар ўқилмади — тугмаларсиз, барча маҳсулот', (tester) async {
      await pump(tester, screen(shop0(), businessId: 'b1', bizError: StateError('permission-denied')));
      expect(find.byKey(const ValueKey('shop_dir_all')), findsNothing);
      for (final t in ['Нон', 'Кўйлак', 'Телевизор']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('блокланган дўкон — «вақтинча мавжуд эмас», маҳсулот сўралмайди', (tester) async {
      final s = shop0()..shop = const TvShop(ownerPhone: _owner, name: 'С', status: 'blocked');
      await pump(tester, screen(s));
      expect(find.byKey(const ValueKey('unavailable_shop_unavailable')), findsOneWidget);
      expect(s.pageCalls, 0);
    });
  });
}

class _FakeShop implements TvShopRepository {
  _FakeShop({this.shop, required this.pages});

  TvShop? shop;
  final List<List<TvShopItem>> pages;
  int pageCalls = 0;

  @override
  Future<TvShop?> fetchShop(String ownerPhone) async => shop;

  @override
  Future<ShopItemsPage> fetchOwnerPage(String ownerPhone, {int limit = 100, DocumentSnapshot<Map<String, dynamic>>? after}) async {
    final i = pageCalls;
    pageCalls += 1;
    final items = i < pages.length ? pages[i] : const <TvShopItem>[];
    return ShopItemsPage(items: items, cursor: null, hasMore: i + 1 < pages.length);
  }

  @override
  Future<TvShopItem?> fetchItem(String itemId) async {
    for (final p in pages) {
      for (final i in p) {
        if (i.id == itemId) return i;
      }
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FakeBiz extends BusinessRepository {
  _FakeBiz(this.rows, {this.error});

  final List<Business> rows;
  final Object? error;

  @override
  Future<List<Business>> fetchByOwner(String ownerId) async {
    if (error != null) throw error!;
    return rows;
  }
}

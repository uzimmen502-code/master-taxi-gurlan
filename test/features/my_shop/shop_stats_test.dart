import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/data/business_repository.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/my_shop/pending_shop_link.dart';
import 'package:ava_gurlan/features/my_shop/screens/shop_stats_screen.dart';
import 'package:ava_gurlan/features/my_shop/shop_stats.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_item_detail_screen.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_public_screen.dart';
import 'package:ava_gurlan/features/tv_market/services/shop_stats_recorder.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 6-босқич (эга қарори 2026-10-25): сотувчи статистикаси — фақат ўлчанадиган кўрсаткичлар.
const _owner = '998901111111';

TvShopItem _item(String id, {String status = 'active', String biz = ''}) => TvShopItem(
      id: id, ownerPhone: _owner, ownerName: 'x', title: 'Товар $id', price: 1000, photoUrl: '', kind: 'product',
      districtId: '', districtLabel: '', status: status, businessId: biz,
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(480 * 2, 1400 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

class _FakeShop implements TvShopRepository {
  _FakeShop(this.items);
  final List<TvShopItem> items;
  @override
  Future<TvShop?> fetchShop(String ownerPhone) async => const TvShop(ownerPhone: _owner, name: 'Сидабилла');
  @override
  Future<ShopItemsPage> fetchOwnerPage(String ownerPhone, {int limit = 100, DocumentSnapshot<Map<String, dynamic>>? after}) async =>
      ShopItemsPage(items: items, cursor: null, hasMore: false);
  @override
  Future<TvShopItem?> fetchItem(String itemId) async => items.where((i) => i.id == itemId).firstOrNull;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FakeBiz extends BusinessRepository {
  @override
  Future<List<Business>> fetchByOwner(String ownerId) async => const [
        Business(id: 'm1', ownerId: _owner, name: 'Кийим', category: BusinessCategory.retail, phone: '1', lat: 41, lng: 60),
      ];
}

void main() {
  final sent = <Map<String, Object?>>[];
  setUp(() {
    sent.clear();
    ShopStatsRecorder.resetForTest();
    ShopStatsRecorder.sink = (d) async => sent.add(d);
  });
  tearDown(() => ShopStatsRecorder.sink = null);

  group('ShopStatsSummary', () {
    test('кунлар йиғиндиси, манбалар, энг кўп кўрилган маҳсулотлар', () {
      final s = ShopStatsSummary.fromDays([
        {'shopViews': 3, 'productViews': 2, 'src': {'map': 2, 'qr': 1}, 'items': {'a': 2}},
        {'shopViews': 1, 'productViews': 5, 'src': {'map': 1, 'market': 5}, 'items': {'a': 1, 'b': 4}},
      ], days: 7);
      expect([s.shopViews, s.productViews, s.src('map'), s.src('qr'), s.src('market'), s.src('link')], [4, 7, 3, 1, 5, 0]);
      expect([for (final e in s.topItems()) '${e.key}:${e.value}'], ['b:4', 'a:3']);
    });

    test('кун — Тошкент вақти (сервер билан бир хил)', () {
      expect(shopStatsDayKey(DateTime.utc(2026, 10, 25, 19, 30)), '20261026');
      expect(shopStatsDayKey(DateTime.utc(2026, 10, 25, 18, 59)), '20261025');
    });
  });

  group('ShopStatsRecorder', () {
    test('бир сессияда бир объект бир марта; нотаниш манба — other', () async {
      ShopStatsRecorder.shopView(ownerPhone: _owner, source: 'map');
      ShopStatsRecorder.shopView(ownerPhone: _owner, source: 'map');
      ShopStatsRecorder.shopView(ownerPhone: _owner, businessId: 'm1', source: 'hack');
      ShopStatsRecorder.productView(ownerPhone: _owner, itemId: 'a', source: 'video');
      await Future<void>.delayed(Duration.zero);
      expect(sent.length, 3);
      expect(sent[1]['source'], 'other');
      expect(sent[1]['businessId'], 'm1');
      expect([sent[2]['kind'], sent[2]['itemId']], ['product_view', 'a']);
    });
  });

  group('Экранлар кўришни билдиради', () {
    testWidgets('маҳсулот экрани: фаол — product_view манба билан; блокланган — йўқ', (tester) async {
      await _pump(tester, TvShopItemDetailScreen(item: _item('a'), loadLatest: (_) async => _item('a'), source: 'map'));
      expect(sent.single, {'kind': 'product_view', 'ownerPhone': _owner, 'itemId': 'a', 'source': 'map'});
      sent.clear();
      await _pump(tester, TvShopItemDetailScreen(key: UniqueKey(), item: _item('b'), loadLatest: (_) async => _item('b', status: 'blocked')));
      expect(sent, isEmpty);
    });

    testWidgets('дўкон саҳифаси: shop_view — очилган йўналиш ва манба билан', (tester) async {
      await _pump(tester, TvShopPublicScreen(
        ownerPhone: _owner,
        businessId: 'm1',
        source: 'qr',
        shopRepository: _FakeShop([_item('k', biz: 'm1')]),
        businessRepository: _FakeBiz(),
        loadChannelInfo: false,
      ));
      expect(sent.single, {'kind': 'shop_view', 'ownerPhone': _owner, 'businessId': 'm1', 'source': 'qr'});
    });

    test('веб-ҳавола манбаи: ?src=qr — qr, бўлмаса link', () {
      PendingShopLink.captureFromUrl(Uri.parse('https://x.app/?shop=AbCdEfGh23&src=qr'));
      expect(PendingShopLink.source, 'qr');
      PendingShopLink.captureFromUrl(Uri.parse('https://x.app/?shop=AbCdEfGh23'));
      expect(PendingShopLink.source, 'link');
      PendingShopLink.take();
    });
  });

  group('ShopStatsScreen', () {
    testWidgets('рақамлар, манбалар, маҳсулот номлари, видео; 30 кун — қайта юклаш', (tester) async {
      final asked = <int>[];
      await _pump(tester, ShopStatsScreen(
        phone: _owner,
        loadSummary: (d) async {
          asked.add(d);
          return ShopStatsSummary.fromDays([
            {'shopViews': 4, 'productViews': 7, 'src': {'map': 3, 'product': 2}, 'items': {'a': 5}},
          ], days: d);
        },
        loadTitles: () async => {'a': 'Қизил кўйлак'},
        loadVideoViews: () async => 120,
      ));
      expect(find.descendant(of: find.byKey(const ValueKey('stats_shop_views')), matching: find.text('4')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('stats_product_views')), matching: find.text('7')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats_src_map')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats_src_product')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats_src_link')), findsNothing, reason: '0 — кўрсатилмайди');
      expect(find.text('Қизил кўйлак'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stats_30')));
      await tester.pumpAndSettle();
      expect(asked, [7, 30]);
    });

    testWidgets('кўриш йўқ — «ҳали йўқ»', (tester) async {
      await _pump(tester, ShopStatsScreen(
        phone: _owner,
        loadSummary: (d) async => ShopStatsSummary.fromDays(const [], days: d),
        loadTitles: () async => const {},
        loadVideoViews: () async => 0,
      ));
      expect(find.byKey(const ValueKey('stats_empty')), findsOneWidget);
    });
  });
}

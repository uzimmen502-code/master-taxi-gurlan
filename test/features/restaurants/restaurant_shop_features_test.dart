import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/home_search_kind.dart';
import 'package:ava_gurlan/features/my_shop/pending_shop_link.dart';
import 'package:ava_gurlan/features/my_shop/screens/shop_stats_screen.dart';
import 'package:ava_gurlan/features/my_shop/shop_stats.dart';
import 'package:ava_gurlan/features/my_shop/widgets/shop_link_sheet.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_growth_tiles.dart';
import 'package:ava_gurlan/features/restaurants/open_restaurant_checked.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_screen.dart';
import 'package:ava_gurlan/features/tv_market/services/shop_stats_recorder.dart';
import 'package:ava_gurlan/models/search_index_entry.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Онлайн дўкон воситалари кафе-ресторанга (2026-10-25): доимий ҳавола + QR, кўришлар статистикаси,
/// глобал қидирув ва ҳавола орқали очиш (очиш вақтида текширув).
const _url = 'https://master-taxi-gurlan.web.app/s/AbCdEfGh23';

Restaurant _r({String status = 'approved'}) => Restaurant(id: 'r1', name: 'Гурлан ош', status: status);

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(480 * 2, 1400 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

Future<BuildContext> _ctx(WidgetTester tester) async {
  late BuildContext ctx;
  await _pump(tester, Scaffold(body: Builder(builder: (c) {
    ctx = c;
    return const SizedBox();
  })));
  return ctx;
}

void main() {
  final sent = <Map<String, Object?>>[];
  setUp(() {
    sent.clear();
    ShopStatsRecorder.resetForTest();
    ShopStatsRecorder.sink = (d) async => sent.add(d);
  });
  tearDown(() => ShopStatsRecorder.sink = null);

  group('Ҳавола ва QR (ресторан панели, «Дўкон» таби)', () {
    testWidgets('тасдиқланган: тугма дўконнинг ўша варағини очади — ҳавола, QR, кафе сарлавҳаси', (tester) async {
      var asked = 0;
      await _pump(tester, Scaffold(body: RestaurantLinkTile(restaurant: _r(), loadLink: () async {
        asked++;
        return _url;
      })));
      expect(find.text('restaurant_link_tile_sub'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restaurant_link_tile')));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.byType(ShopLinkSheet), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text(_url), findsOneWidget);
      expect(find.text('restaurant_link_hint'), findsOneWidget);
      expect(find.text('shop_link_title'), findsNothing, reason: 'дўкон сарлавҳаси эмас');
    });

    testWidgets('тасдиқланмаган/тўхтатилган: тугма ўчиқ, сабаби ёзилган; ҳавола сўралмайди', (tester) async {
      var asked = 0;
      await _pump(tester, Scaffold(body: RestaurantLinkTile(restaurant: _r(status: 'suspended'), loadLink: () async {
        asked++;
        return _url;
      })));
      expect(find.text('restaurant_link_not_approved'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restaurant_link_tile')));
      await tester.pumpAndSettle();
      expect(asked, 0);
      expect(find.byType(ShopLinkSheet), findsNothing);
    });

    testWidgets('сервер RESTAURANT_NOT_APPROVED қайтарса — тушунарли матн, QR йўқ', (tester) async {
      await _pump(tester, Scaffold(body: ShopLinkSheet(
        title: 'Гурлан ош',
        loadLink: ({String businessId = ''}) async =>
            throw FirebaseFunctionsException(message: 'x', code: 'failed-precondition', details: {'code': 'RESTAURANT_NOT_APPROVED'}),
      )));
      expect(find.text('restaurant_link_not_approved'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });
  });

  group('Кўришлар статистикаси (ресторан панели, «Ҳисобот» таби)', () {
    testWidgets('дўконнинг ўша экрани: кафе/таом кўришлари, манбалар, таом номлари; видео жами йўқ', (tester) async {
      await _pump(tester, Scaffold(body: RestaurantViewsTile(
        restaurant: _r(),
        loadSummary: (d) async => ShopStatsSummary.fromDays([
          {'restaurantViews': 5, 'dishViews': 9, 'src': {'list': 3, 'qr': 2, 'section': 4}, 'items': {'osh': 6}},
        ], days: d, mainKey: 'restaurantViews', itemKey: 'dishViews'),
        loadTitles: () async => {'osh': 'Ош'},
      )));
      await tester.tap(find.byKey(const ValueKey('restaurant_views_tile')));
      await tester.pumpAndSettle();
      expect(find.byType(ShopStatsScreen), findsOneWidget);
      expect(find.text('stats_restaurant_views'), findsOneWidget);
      expect(find.text('stats_dish_views'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('stats_shop_views')), matching: find.text('5')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('stats_product_views')), matching: find.text('9')), findsOneWidget);
      for (final k in ['list', 'qr', 'section']) {
        expect(find.byKey(ValueKey('stats_src_$k')), findsOneWidget, reason: k);
      }
      expect(find.text('Ош'), findsOneWidget);
      expect(find.text('stats_top_dishes'), findsOneWidget);
      expect(find.byKey(const ValueKey('stats_video_total')), findsNothing, reason: 'ўлчанмаган рақам кўрсатилмайди');
      expect(find.text('stats_rules_restaurant'), findsOneWidget);
    });

    test('ShopStatsSummary: ресторан ҳисоблагич номлари; дўкон стандарти ўзгармаган', () {
      final r = ShopStatsSummary.fromDays([
        {'restaurantViews': 2, 'dishViews': 3, 'shopViews': 100},
        {'restaurantViews': 1, 'dishViews': 1},
      ], days: 7, mainKey: 'restaurantViews', itemKey: 'dishViews');
      expect([r.shopViews, r.productViews], [3, 4]);
      final s = ShopStatsSummary.fromDays([{'shopViews': 2, 'productViews': 1}], days: 7);
      expect([s.shopViews, s.productViews], [2, 1]);
    });
  });

  group('ShopStatsRecorder: ресторан ва таом кўриши', () {
    test('тўлиқ маълумот; бир сессияда бир марта; бўш ID юборилмайди; нотаниш манба — other', () async {
      ShopStatsRecorder.restaurantView(restaurantId: 'r1', source: 'list');
      ShopStatsRecorder.restaurantView(restaurantId: 'r1', source: 'map');
      ShopStatsRecorder.restaurantView(restaurantId: '', source: 'map');
      ShopStatsRecorder.dishView(restaurantId: 'r1', itemId: 'osh', source: 'restaurant');
      ShopStatsRecorder.dishView(restaurantId: 'r1', itemId: '', source: 'restaurant');
      ShopStatsRecorder.dishView(restaurantId: 'r2', itemId: 'osh', source: 'hack');
      await Future<void>.delayed(Duration.zero);
      expect(sent, [
        {'kind': 'restaurant_view', 'restaurantId': 'r1', 'source': 'list'},
        {'kind': 'dish_view', 'restaurantId': 'r1', 'itemId': 'osh', 'source': 'restaurant'},
        {'kind': 'dish_view', 'restaurantId': 'r2', 'itemId': 'osh', 'source': 'other'},
      ]);
    });
  });

  group('Очиш вақтида текширув (ҳавола, қидирув)', () {
    testWidgets('тасдиқланган — меню очилади ва кўриш манба билан қайд этилади', (tester) async {
      final ctx = await _ctx(tester);
      Widget? pushed;
      await openRestaurantChecked(ctx, 'r1',
          source: 'search', load: (_) async => _r(), canOpenModule: () async => true, push: (w) => pushed = w);
      expect(pushed, isA<RestaurantScreen>());
      expect((pushed! as RestaurantScreen).restaurant.id, 'r1');
      await tester.pump();
      expect(sent.single, {'kind': 'restaurant_view', 'restaurantId': 'r1', 'source': 'search'});
    });

    testWidgets('тўхтатилган / йўқ / ўқиб бўлмади — «вақтинча мавжуд эмас», экран очилмайди, кўриш ёзилмайди', (tester) async {
      final ctx = await _ctx(tester);
      final loads = <Future<Restaurant?> Function(String)>[
        (_) async => _r(status: 'suspended'),
        (_) async => _r(status: 'closed'),
        (_) async => null,
        (_) async => throw Exception('permission-denied'),
      ];
      for (final load in loads) {
        Widget? pushed;
        await openRestaurantChecked(ctx, 'r1', source: 'link', load: load, canOpenModule: () async => true, push: (w) => pushed = w);
        await tester.pump();
        expect(pushed, isNull);
        expect(find.text('tv_market_restaurant_unavailable'), findsOneWidget);
        ScaffoldMessenger.of(ctx).removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }
      expect(sent, isEmpty);
    });

    testWidgets('модул ёпиқ — ресторан ўқилмайди ҳам', (tester) async {
      final ctx = await _ctx(tester);
      var loaded = 0;
      Widget? pushed;
      await openRestaurantChecked(ctx, 'r1', source: 'link', load: (_) async {
        loaded++;
        return _r();
      }, canOpenModule: () async => false, push: (w) => pushed = w);
      await tester.pump();
      expect([loaded, pushed], [0, null]);
    });

    testWidgets('веб-ҳавола (/?shop=<id>) ресторанга ечилса — ресторан очувчига ўтади (манба qr)', (tester) async {
      final ctx = await _ctx(tester);
      final opened = <String>[];
      PendingShopLink.captureFromUrl(Uri.parse('https://x.app/?shop=AbCdEfGh23&src=qr'));
      await PendingShopLink.openIfAny(ctx,
          resolve: (_) async => (ownerPhone: '', businessId: '', restaurantId: 'r1'),
          openRestaurant: (c, rid, src) async => opened.add('$rid|$src'),
          push: (_) => fail('дўкон экрани очилмаслиги керак'));
      expect(opened, ['r1|qr']);
    });
  });

  group('Глобал қидирув', () {
    test('ресторан тури «Маҳсулот» тоифасида (дўкон каби)', () {
      const e = SearchIndexEntry(id: 'restaurant_r1', type: SearchIndexEntry.typeRestaurant, moduleId: 'restaurants', title: 'Гурлан ош', sourceId: 'r1');
      expect(homeSearchKindOf(e), HomeSearchKind.product);
      expect(SearchIndexEntry.typeRestaurant, 'restaurant');
    });
  });
}

// Ресторан менюси UI/UX қайта лойиҳаси (эга тасдиғи, 2026-10-24):
//  1) намуна ресторан — «+» йўқ, баннер, эълон матни яшириш, барча қўшиш йўллари ёпиқ;
//  2) ном/тавсиф тўлиқ кенгликда, степпер қатор матнини «сакратмайди», босиш майдони 44;
//  3) ≤3 категория — чиплар, 4+ — рейл (104 dp, битта сўз сиғади);
//  4) ҳедер: муқовасиз бўш блок йўқ, скролда йиғилади;
//  5) қатор баландлиги — соф ҳисоб.

import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/theme/ava_tokens.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/cuisine.dart';
import 'package:ava_gurlan/features/restaurants/domain/menu_row_metrics.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_screen.dart';
import 'package:ava_gurlan/features/restaurants/widgets/menu_category_nav.dart';
import 'package:ava_gurlan/features/restaurants/widgets/restaurant_cart_actions.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

const _plain = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved');
const _demo = Restaurant(
  id: 'd1',
  name: 'Munira — uy qandolatchisi',
  status: 'approved',
  isDemo: true,
  announcement: 'Намуна · Namuna · Пример — буюртма қабул қилинмайди',
);

MenuItem _item(String id, String name, String cat, {int price = 40000, String description = '', int sort = 0}) =>
    MenuItem(id: id, name: name, price: price, description: description, categoryId: cat, sort: sort);

class _Repo implements RestaurantsRepository {
  _Repo(this.restaurant, {this.categories = 2, this.perCat = 3, this.longNames = false});

  final Restaurant restaurant;
  final int categories;
  final int perCat;
  final bool longNames;

  static const _catNames = ['Tortlar', 'Shirinliklar', 'Ichimliklar', 'Salatlar', 'Issiq taomlar'];

  @override
  Stream<Restaurant?> watchRestaurant(String id) => Stream.value(restaurant);

  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) => Stream.value([
        for (var c = 0; c < categories; c++) MenuCategory(id: 'c$c', name: _catNames[c], sort: c),
      ]);

  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) => Stream.value([
        for (var c = 0; c < categories; c++)
          for (var i = 0; i < perCat; i++)
            _item(
              'c${c}i$i',
              longNames ? 'Juda uzun nomli maxsus bayram taomi c$c-$i ${'xizmat ' * 3}' : 'Taom c$c-$i',
              'c$c',
              description: 'Tavsif c$c-$i',
              sort: i,
            ),
      ]);

  @override
  Future<List<Cuisine>> listCuisines({bool force = false}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

TvClip _clip(String itemId) => TvClip(
      id: 'clip-$itemId',
      videoUrl: 'https://x/$itemId.mp4',
      posterUrl: '',
      title: 'Obzor',
      price: 0,
      districtId: 'gurlan',
      districtLabel: 'Gurlan',
      ownerPhone: '998901234567',
      ownerName: 'Ali',
      category: 'product',
      status: 'active',
      processingStatus: 'ready',
      createdAt: DateTime(2026, 10, 1),
      rejectReason: '',
      linkKind: 'restaurant_item',
      linkId: 'r1',
      linkItemId: itemId,
    );

Future<RestaurantCart> _pump(
  WidgetTester t, {
  Restaurant restaurant = _plain,
  int categories = 2,
  int perCat = 3,
  bool longNames = false,
  double textScale = 1.0,
  double width = 360,
  Map<String, TvClip> clips = const {},
  RestaurantCart? cart,
}) async {
  t.view.physicalSize = Size(width * 3, 800 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final c = cart ?? RestaurantCart();
  await t.pumpWidget(l10nApp(
    textScale: textScale,
    home: RestaurantScreen(
      key: UniqueKey(),
      restaurant: restaurant,
      repository: _Repo(restaurant, categories: categories, perCat: perCat, longNames: longNames),
      cart: c,
      itemClipsLoader: (_) async => clips,
      restaurantVideoLoader: () async => null,
      dishStatsLoader: (_) async => const {},
    ),
  ));
  await t.pumpAndSettle();
  return c;
}

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('Restaurant.canTakeOrdersNow — ЯГОНА қоида', () {
    test('намуна — ҳеч қачон (очиқ бўлса ҳам, олдиндан буюртма бўлса ҳам)', () {
      expect(_demo.canTakeOrdersNow, isFalse);
      expect(const Restaurant(id: 'x', name: 'x', isDemo: true, acceptsPreorder: true).canTakeOrdersNow, isFalse);
    });

    test('оддий очиқ ресторан — ҳа; ёпиқ ва олдиндан буюртмасиз — йўқ; ёпиқ, лекин олдиндан буюртма — ҳа', () {
      expect(_plain.canTakeOrdersNow, isTrue);
      final closed = Restaurant(
        id: 'x',
        name: 'x',
        pausedUntil: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(closed.isOpenNow, isFalse);
      expect(closed.canTakeOrdersNow, isFalse);
      final preorder = Restaurant(
        id: 'x',
        name: 'x',
        acceptsPreorder: true,
        pausedUntil: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(preorder.canTakeOrdersNow, isTrue);
    });
  });

  group('1) намуна ресторан: менюни кўриш мумкин, буюртма йўқ', () {
    testWidgets('«+» йўқ, баннер бор, сервер ёзган «Намуна · Namuna · Пример» эълон матни кўрсатилмайди', (t) async {
      await _pump(t, restaurant: _demo);
      expect(find.byKey(const ValueKey('demo-banner')), findsOneWidget);
      expect(find.text(tr('restaurants_demo_banner')), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsNothing, reason: 'намунада «+» кўрсатилмайди');
      expect(find.textContaining('Namuna ·'), findsNothing, reason: 'қотирилган уч тилли матн яширилади');
      expect(find.byIcon(Icons.campaign_outlined), findsNothing);
      expect(find.byKey(const ValueKey('closed-notice')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('оддий ресторанда баннер йўқ, «+» бор', (t) async {
      await _pump(t);
      expect(find.byKey(const ValueKey('demo-banner')), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsWidgets);
    });

    testWidgets('қатор босилса таом варағи очилади: намуна изоҳи, тугма ўчиқ («Намуна — буюртма йўқ»), сават бўш', (t) async {
      final cart = await _pump(t, restaurant: _demo);
      await t.tap(find.byKey(const ValueKey('menu-row-c0i0')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-demo')), findsOneWidget);
      final btn = t.widget<FilledButton>(find.byKey(const ValueKey('dish-sheet-add')));
      expect(btn.onPressed, isNull);
      expect(find.text(tr('restaurants_demo_btn')), findsOneWidget);
      expect(cart.isEmpty, isTrue);
    });

    testWidgets('иккинчи қатлам: addToCartOrAskSwitch намунага таом қўшмайди, хабар кўрсатади', (t) async {
      final cart = RestaurantCart();
      late BuildContext ctx;
      await t.pumpWidget(l10nApp(home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }))));
      final ok = await addToCartOrAskSwitch(ctx, cart: cart, item: _item('a', 'A', 'c'), restaurant: _demo);
      await t.pump();
      expect(ok, isFalse);
      expect(cart.isEmpty, isTrue);
      expect(find.text(tr('restaurants_err_RESTAURANT_DEMO')), findsOneWidget);
    });
  });

  group('2) қатор: тўлиқ кенглик, «сакрамайди», босиш майдони 44', () {
    testWidgets('таом номи кенглиги степпер «+» → «− 2 +» бўлганда ЎЗГАРМАЙДИ', (t) async {
      await _pump(t);
      final name = find.descendant(of: find.byKey(const ValueKey('menu-row-c0i0')), matching: find.text('Taom c0-0'));
      final before = t.getSize(name).width;
      final topBefore = t.getTopLeft(name);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('menu-row-c0i0')), matching: find.byIcon(Icons.add_rounded)));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('menu-row-c0i0')), matching: find.byIcon(Icons.remove_rounded)), findsOneWidget);
      expect(t.getSize(name).width, before);
      expect(t.getTopLeft(name), topBefore, reason: 'матн жойидан силжимайди');
    });

    testWidgets('расмсиз қаторда ном тўлиқ кенгликда (≥ 300 dp); бўш «санчқи» плиткаси йўқ', (t) async {
      await _pump(t);
      final row = find.byKey(const ValueKey('menu-row-c0i0'));
      expect(find.descendant(of: row, matching: find.byIcon(Icons.restaurant_rounded)), findsNothing);
      final nameBox = t.getSize(find.descendant(of: row, matching: find.text('Taom c0-0')));
      final rowBox = t.getSize(row);
      expect(rowBox.width, 360);
      // Ном Expanded ичида: матннинг ўзи қисқа, лекин унинг устуни қатор кенглигининг деярли ҳаммаси.
      final col = t.getSize(find.descendant(of: row, matching: find.byType(Expanded)).first);
      expect(col.width, greaterThan(300), reason: 'матн устуни ≈ 340 dp (аввал ≈118)');
      expect(nameBox.height, lessThan(24));
    });

    testWidgets('видеоси бор таомда расм плиткаси кўринади, матн устуни торайган, лекин ном ўқилади', (t) async {
      await _pump(t, clips: {'c0i0': _clip('c0i0')});
      final row = find.byKey(const ValueKey('menu-row-c0i0'));
      expect(find.descendant(of: row, matching: find.byIcon(Icons.restaurant_rounded)), findsOneWidget);
      expect(find.byKey(const ValueKey('item-video-c0i0')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('«+» босиш майдони камида 44×44', (t) async {
      await _pump(t);
      final inkWell = find.ancestor(
        of: find.descendant(of: find.byKey(const ValueKey('menu-row-c0i0')), matching: find.byIcon(Icons.add_rounded)),
        matching: find.byType(InkWell),
      );
      // Энг яқин InkWell — «+» нинг ўзи (қатор InkWell'и эмас): унинг ўлчами 44.
      final size = t.getSize(inkWell.first);
      expect(size.width, greaterThanOrEqualTo(AvaTap.minSize));
      expect(size.height, greaterThanOrEqualTo(AvaTap.minSize));
    });

    testWidgets('экран ўқувчи: «+» ва «−» таом номи билан аталади', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t);
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(tr('restaurants_a11y_add').replaceAll('{name}', 'Taom c0-0')))), findsWidgets);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('menu-row-c0i0')), matching: find.byIcon(Icons.add_rounded)));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(tr('restaurants_a11y_remove').replaceAll('{name}', 'Taom c0-0')))), findsWidgets);
      handle.dispose();
    });

    testWidgets('чегараланган «+» (ўчиқ) ҳам ҳолат билан кўринади ва босилмайди', (t) async {
      final cart = RestaurantCart();
      await _pump(t, cart: cart);
      // 50 та (default чегара) қўшамиз — «+» ўчади.
      final item = _item('c0i0', 'Taom c0-0', 'c0');
      for (var i = 0; i < Restaurant.defaultMaxQtyPerItem; i++) {
        cart.add(item, restaurant: _plain);
      }
      await t.pumpAndSettle();
      final plus = find.descendant(of: find.byKey(const ValueKey('menu-row-c0i0')), matching: find.byIcon(Icons.add_rounded));
      final ink = t.widget<InkWell>(find.ancestor(of: plus, matching: find.byType(InkWell)).first);
      expect(ink.onTap, isNull);
    });
  });

  group('3) категорияларга ўтиш: чиплар / рейл', () {
    test('menuNavModeFor', () {
      expect(menuNavModeFor(0), MenuNavMode.none);
      expect(menuNavModeFor(1), MenuNavMode.none);
      expect(menuNavModeFor(2), MenuNavMode.chips);
      expect(menuNavModeFor(3), MenuNavMode.chips);
      expect(menuNavModeFor(4), MenuNavMode.rail);
      expect(menuNavModeFor(9), MenuNavMode.rail);
    });

    testWidgets('2 категория: чиплар бор, рейл йўқ, таом рўйхати тўлиқ кенгликда', (t) async {
      await _pump(t, categories: 2);
      expect(find.byType(MenuCategoryChips), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-chip-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-chip-1')), findsOneWidget);
      expect(find.byType(MenuCategoryTile), findsNothing);
      expect(t.getSize(find.byKey(const ValueKey('menu-row-c0i0'))).width, 360);
    });

    testWidgets('чип босилса рўйхат шу бўлимга скролл қилинади ва чип фаол бўлади; тепага қайтса — биринчи чип', (t) async {
      await _pump(t, categories: 2, perCat: 10);
      expect(t.widget<MenuCategoryChips>(find.byType(MenuCategoryChips)).active, 0);
      await t.tap(find.byKey(const ValueKey('menu-chip-1')));
      await t.pumpAndSettle();
      final scrollable = t.state<ScrollableState>(find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)));
      expect(scrollable.position.pixels, greaterThan(0));
      expect(t.widget<MenuCategoryChips>(find.byType(MenuCategoryChips)).active, 1);
      await t.tap(find.byKey(const ValueKey('menu-chip-0')));
      await t.pumpAndSettle();
      expect(t.widget<MenuCategoryChips>(find.byType(MenuCategoryChips)).active, 0);
    });

    testWidgets('чипда саватдаги таомлар сони белгиси', (t) async {
      final cart = await _pump(t, categories: 2);
      expect(find.descendant(of: find.byKey(const ValueKey('menu-chip-1')), matching: find.text('1')), findsNothing);
      cart.add(_item('c1i0', 'Taom c1-0', 'c1'), restaurant: _plain);
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('menu-chip-1')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('menu-chip-0')), matching: find.text('1')), findsNothing);
    });

    testWidgets('чип босиш майдони 44 dp дан кам эмас', (t) async {
      await _pump(t, categories: 2);
      expect(t.getSize(find.byKey(const ValueKey('menu-chip-0'))).height, greaterThanOrEqualTo(AvaTap.minSize));
    });

    testWidgets('1 категория: ўтиш панели йўқ', (t) async {
      await _pump(t, categories: 1);
      expect(find.byType(MenuCategoryChips), findsNothing);
      expect(find.byType(MenuCategoryTile), findsNothing);
      expect(find.byKey(const ValueKey('menu-row-c0i0')), findsOneWidget);
    });

    testWidgets('4 категория: чап рейл (104 dp), чиплар йўқ', (t) async {
      await _pump(t, categories: 4, perCat: 3);
      expect(find.byType(MenuCategoryChips), findsNothing);
      expect(find.byType(MenuCategoryTile), findsNWidgets(4));
      final tileW = t.getSize(find.byType(MenuCategoryTile).first).width;
      expect(tileW, kMenuRailWidth);
      expect(kMenuRailWidth, 104);
      expect(t.takeException(), isNull);
    });

    test('fitCategoryFontSize: қисқа сўз — асосий ўлчам; узун сўз — кичраяди, лекин min дан кам эмас; сиғган сўз ўртасидан бўлинмайди', () {
      const scaler = TextScaler.noScaling;
      expect(fitCategoryFontSize(name: 'Tort', maxWidth: 80, scaler: scaler), 12.5);
      final s = fitCategoryFontSize(name: 'Ширинликлар', maxWidth: 70, scaler: scaler);
      expect(s, lessThan(12.5));
      expect(s, greaterThanOrEqualTo(10.5));
      // Топилган ўлчамда энг узун сўз ҳақиқатан сиғади (агар min дан юқори бўлса).
      if (s > 10.5) {
        final p = TextPainter(
          text: TextSpan(text: 'Ширинликлар', style: TextStyle(fontSize: s, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(p.width, lessThanOrEqualTo(70));
      }
      // Ҳеч қачон сиғмайдиган — min.
      expect(fitCategoryFontSize(name: 'Ширинликлар', maxWidth: 10, scaler: scaler), 10.5);
      // Бўш / ноль кенглик — хавфсиз.
      expect(fitCategoryFontSize(name: '', maxWidth: 70, scaler: scaler), 12.5);
      expect(fitCategoryFontSize(name: 'Тортлар', maxWidth: 0, scaler: scaler), 12.5);
      // Кўп сўзли ном: энг узун сўз ўлчанади, сўзлар орасидан ўралади.
      expect(fitCategoryFontSize(name: 'Иссиқ таомлар ва салатлар', maxWidth: 80, scaler: scaler), greaterThanOrEqualTo(10.5));
    });
  });

  group('4) ҳедер', () {
    testWidgets('муқова расми йўқ — бўш 96 dp блок чизилмайди; ном ҳедерда (2 қатор), AppBar сарлавҳаси бўш', (t) async {
      await _pump(t);
      expect(find.byKey(const ValueKey('restaurant-cover')), findsNothing);
      expect(find.byKey(const ValueKey('restaurant-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('appbar-title')), findsNothing);
    });

    testWidgets('скролда ҳедер йиғилади (AppBar сарлавҳасида ном), тепага қайтса ёйилади', (t) async {
      await _pump(t, categories: 2, perCat: 12);
      final header = find.byKey(const ValueKey('restaurant-name'));
      final h0 = t.getTopLeft(header).dy;
      await t.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('appbar-title')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.drag(find.byType(CustomScrollView), const Offset(0, 2000));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('appbar-title')), findsNothing);
      expect(t.getTopLeft(header).dy, h0, reason: 'ҳедер аввалги жойига қайтди');
    });

    testWidgets('қисқа меню (скролл йўқ) — ҳедер йиғилмайди', (t) async {
      await _pump(t, categories: 2, perCat: 1);
      await t.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('appbar-title')), findsNothing);
    });

    testWidgets('намуна баннери ҳедер йиғилганда ҳам кўриниб туради', (t) async {
      await _pump(t, restaurant: _demo, categories: 2, perCat: 12);
      await t.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('appbar-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('demo-banner')), findsOneWidget);
    });
  });

  group('5) қатор баландлиги — соф ҳисоб (MenuRowMetrics)', () {
    MenuRowMetrics m(
      List<MenuRowSample> items, {
      double w = 360,
      double scale = 1,
      bool tiers = false,
      bool stepper = true,
    }) =>
        MenuRowMetrics.compute(
          items: items,
          listWidth: w,
          scaler: TextScaler.linear(scale),
          direction: TextDirection.ltr,
          hasTiers: tiers,
          showStepper: stepper,
        );

    const short = MenuRowSample(name: 'Osh', priceText: '40 000 сўм', hasTile: false);
    const long = MenuRowSample(
      name: 'Juda uzun nomli maxsus bayram taomi xizmat xizmat xizmat xizmat',
      priceText: '40 000 сўм',
      hasTile: false,
    );

    test('қисқа номлар — 1 қатор; узун ном — 2 қатор (3 дан ошмайди) ва қатор баландроқ', () {
      final a = m([short]);
      final b = m([short, long]);
      expect(a.nameLines, 1);
      expect(b.nameLines, 2);
      expect(b.itemHeight, greaterThan(a.itemHeight));
      final huge = m([MenuRowSample(name: 'x ' * 200, priceText: '1', hasTile: false)]);
      expect(huge.nameLines, 2);
    });

    test('тор экран ва катта шрифтда баландлик ўсади; ҳеч қачон 0 ёки манфий эмас', () {
      expect(m([short], scale: 1.6).itemHeight, greaterThan(m([short]).itemHeight));
      expect(m([short], w: 200).itemHeight, greaterThan(60));
      expect(m(const []).itemHeight, greaterThan(60));
    });

    test('миқдорга чегирма ҳинти нархнинг тагида: 44 dp степпер қаторига сиғади (баландлик ўзгармайди), сиғмаса — ўсади', () {
      expect(m([short], tiers: true).itemHeight, m([short]).itemHeight, reason: '1.0× да нарх + ҳинт ≤ 44');
      expect(m([short], tiers: true, scale: 2).itemHeight, greaterThan(m([short], scale: 2).itemHeight), reason: 'катта шрифтда ҳинт қатор баландлигини оширади');
      expect(m([short], tiers: true, stepper: false).itemHeight, greaterThan(m([short], stepper: false).itemHeight));
    });

    test('степпер йўқ (намуна) — қатор ихчамроқ; расмли қатор сиғмаса степпер нархнинг остига ўтади', () {
      // Тест шрифти Ahem (ҳар белги = шрифт ўлчами кенгликда): нарх матни қисқа олинади.
      const tile = MenuRowSample(name: 'Osh', priceText: '1 000', hasTile: true);
      expect(m([short], stepper: false).itemHeight, lessThan(m([short]).itemHeight));
      final wide = m([tile], w: 360);
      final narrow = m([tile], w: 256); // 4+ категория: рейл кенглиги айрилган
      expect(wide.stackedWithTile, isFalse);
      expect(narrow.stackedWithTile, isTrue);
      expect(narrow.itemHeight, greaterThan(wide.itemHeight));
      // Степпер йўқ — ҳеч қачон stacked эмас.
      expect(m([tile], w: 256, stepper: false).stackedWithTile, isFalse);
    });

    test('textWidth: расм плиткаси 82 dp олади', () {
      expect(MenuRowMetrics.textWidth(360, hasTile: false) - MenuRowMetrics.textWidth(360, hasTile: true), 82);
    });
  });

  group('чегара ҳолатлар: катта шрифт, тор экран, узун номлар — overflow йўқ', () {
    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('чиплар · узун номлар · шрифт ×$scale · 320 dp', (t) async {
        await _pump(t, categories: 3, perCat: 4, longNames: true, textScale: scale, width: 320);
        expect(t.takeException(), isNull);
      });

      testWidgets('рейл · узун номлар · шрифт ×$scale · 320 dp · видео плиткаси', (t) async {
        await _pump(
          t,
          categories: 5,
          perCat: 3,
          longNames: true,
          textScale: scale,
          width: 320,
          clips: {for (var c = 0; c < 5; c++) for (var i = 0; i < 3; i++) 'c${c}i$i': _clip('c${c}i$i')},
        );
        expect(t.takeException(), isNull);
      });

      testWidgets('намуна · шрифт ×$scale · 320 dp', (t) async {
        await _pump(t, restaurant: _demo, categories: 2, perCat: 3, textScale: scale, width: 320);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('саватга қўшилганда (степпер кенгаяди) катта шрифтда overflow йўқ', (t) async {
      final cart = await _pump(t, categories: 5, perCat: 3, longNames: true, textScale: 1.6, width: 320);
      cart.add(_item('c0i0', 'x', 'c0', price: 1200000), restaurant: _plain);
      cart.add(_item('c0i0', 'x', 'c0', price: 1200000), restaurant: _plain);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('l10n: янги калитлар уч тилда', () {
    const keys = ['restaurants_demo_banner', 'restaurants_demo_btn', 'restaurants_a11y_add', 'restaurants_a11y_remove'];
    for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      test('$lang — калитлар бор, бўш эмас; {name} ўрни бор', () {
        final map = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
        for (final k in keys) {
          expect((map[k] as String?)?.trim().isNotEmpty, isTrue, reason: '$k йўқ: $lang');
        }
        expect(map['restaurants_a11y_add'], contains('{name}'));
        expect(map['restaurants_a11y_remove'], contains('{name}'));
      });
    }
  });
}

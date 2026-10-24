// Таом тафсилоти варағи (эга 2026-10-23): қатор/лента карточкаси босилса таом ҳақида тўлиқ маълумот,
// шу таомга изоҳ, менюда таомга фокус, иккинчи босишдан ҳимоя. Сават/буюртмада изоҳ ва сервер билан мослик.

import 'dart:async';
import 'dart:io';

import 'package:ava_gurlan/core/theme/ava_tokens.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/cuisine.dart';
import 'package:ava_gurlan/features/restaurants/domain/dish_facts.dart';
import 'package:ava_gurlan/features/restaurants/domain/dish_stats.dart';
import 'package:ava_gurlan/features/restaurants/domain/menu_scroll_sync.dart';
import 'package:ava_gurlan/features/restaurants/domain/qty_tiers.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_sections.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_order_screen.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_screen.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurants_list_screen.dart';
import 'package:ava_gurlan/features/restaurants/widgets/dish_detail_sheet.dart';
import 'package:ava_gurlan/features/restaurants/widgets/restaurant_cart_sheet.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/server_checkout.dart';
import 'restaurants_l10n_harness.dart';

const _rest = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved');

MenuItem _item({
  String id = 'osh',
  String name = 'Osh',
  int price = 40000,
  String description = '',
  DishFacts facts = DishFacts.empty,
  List<QtyTier> tiers = const [],
  bool available = true,
  String categoryId = 'c1',
  int sort = 0,
}) =>
    MenuItem(id: id, name: name, price: price, description: description, facts: facts, qtyTiers: tiers, available: available, categoryId: categoryId, sort: sort);

TvClip _clip() => TvClip(
      id: 'clip1',
      videoUrl: 'https://x/clip1.mp4',
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
      linkItemId: 'osh',
    );

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('RestaurantCart: таомга изоҳ', () {
    test('изоҳ саватдаги таомга ёзилади, кесилади (100), тозаланади; саватда йўқ таомга ёзилмайди', () {
      final cart = RestaurantCart();
      cart.setNote('osh', 'piyozsiz');
      expect(cart.noteOf('osh'), '', reason: 'саватда йўқ таом — изоҳ ёзилмайди');

      cart.add(_item(), restaurant: _rest);
      cart.setNote('osh', '  piyozsiz  ');
      expect(cart.noteOf('osh'), 'piyozsiz');
      cart.setNote('osh', 'x' * 150);
      expect(cart.noteOf('osh').length, RestaurantCart.maxItemNote);
      expect(RestaurantCart.maxItemNote, 100);
    });

    test('миқдор ўзгарса изоҳ сақланади; қатор ўчса — изоҳ ҳам; qayta qo\'shilsa bo\'sh', () {
      final cart = RestaurantCart();
      cart.add(_item(), restaurant: _rest);
      cart.setNote('osh', 'achchiq');
      cart.add(_item(), restaurant: _rest);
      expect(cart.qtyOf('osh'), 2);
      expect(cart.noteOf('osh'), 'achchiq');
      cart.decrement('osh');
      expect(cart.noteOf('osh'), 'achchiq');
      cart.decrement('osh');
      expect(cart.qtyOf('osh'), 0);
      cart.add(_item(), restaurant: _rest);
      expect(cart.noteOf('osh'), '', reason: 'чиқарилган таомнинг эски изоҳи қайтмайди');
    });

    test('toOrderItems: изоҳ фақат бўш бўлмаса юборилади (эски сервер/форматга мос)', () {
      final cart = RestaurantCart();
      cart.add(_item(), restaurant: _rest);
      cart.add(_item(id: 'somsa', name: 'Somsa', price: 10000), restaurant: _rest);
      cart.setNote('osh', 'piyozsiz');
      final items = cart.toOrderItems();
      expect(items.firstWhere((m) => m['itemId'] == 'osh'), {'itemId': 'osh', 'qty': 1, 'note': 'piyozsiz'});
      expect(items.firstWhere((m) => m['itemId'] == 'somsa'), {'itemId': 'somsa', 'qty': 1});
    });

    test('setNote ўзгармаса тингловчиларни безовта қилмайди', () {
      final cart = RestaurantCart();
      cart.add(_item(), restaurant: _rest);
      cart.setNote('osh', 'a');
      var calls = 0;
      cart.addListener(() => calls++);
      cart.setNote('osh', ' a ');
      expect(calls, 0);
      cart.setNote('osh', 'b');
      expect(calls, 1);
    });

    test('сервер билан мослик: изоҳ узунлиги MAX_ITEM_NOTE билан бир хил', skip: serverParitySkip, () {
      final js = _read('functions/restaurant_orders.js');
      expect(int.parse(RegExp(r'const MAX_ITEM_NOTE = (\d+);').firstMatch(js)!.group(1)!), RestaurantCart.maxItemNote);
    });
  });

  group('OrderItem.note ва MenuScrollSync.offsetOfItem', () {
    test('буюртма таомида изоҳ ўқилади; эски буюртмада (изоҳсиз) ва нотўғри типда — бўш', () {
      expect(OrderItem.fromMap({'name': 'Osh', 'note': ' piyozsiz '}).note, 'piyozsiz');
      expect(OrderItem.fromMap({'name': 'Osh'}).note, '');
      expect(OrderItem.fromMap({'name': 'Osh', 'note': 5}).note, '');
    });

    test('таом offset\'и: бўлим бошидан индекс × баландлик; охирги қисқа бўлимда maxScrollExtent дан ошмайди; индекс қисилади', () {
      final s = MenuScrollSync(sectionItemCounts: [3, 4], headerHeight: 40, itemHeight: 100);
      // 1-бўлим: 0..(40+300); 2-бўлим сарлавҳаси 340 да.
      expect(s.offsetOfItem(0, 0), 0);
      expect(s.offsetOfItem(0, 2), 200);
      expect(s.offsetOfItem(1, 0), 340);
      expect(s.offsetOfItem(1, 3), 640);
      expect(s.offsetOfItem(1, 3, maxScrollExtent: 500), 500);
      expect(s.offsetOfItem(1, 99), 640, reason: 'индекс бўлим чегарасига қисилади');
      expect(s.offsetOfItem(9, 0), 340, reason: 'бўлим ҳам қисилади');
      expect(MenuScrollSync(sectionItemCounts: const [], headerHeight: 40, itemHeight: 100).offsetOfItem(0, 0), 0);
    });
  });

  group('DishDetailSheet', () {
    Future<RestaurantCart> pumpSheet(
      WidgetTester t, {
      MenuItem? item,
      Restaurant restaurant = _rest,
      RestaurantCart? cart,
      DishStats? stats,
      TvClip? clip,
      void Function(TvClip)? onPlayVideo,
      VoidCallback? onOpenMenu,
      VoidCallback? onCheckout,
      Future<List<Cuisine>> Function()? cuisineLoader,
      double textScale = 1.0,
    }) async {
      t.view.physicalSize = const Size(390 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final c = cart ?? RestaurantCart();
      await t.pumpWidget(l10nApp(
        textScale: textScale,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: DishDetailSheet(
              item: item ?? _item(),
              restaurant: restaurant,
              cart: c,
              stats: stats,
              clip: clip,
              onPlayVideo: onPlayVideo,
              onOpenMenu: onOpenMenu,
              onCheckout: onCheckout,
              cuisineLoader: cuisineLoader,
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      return c;
    }

    testWidgets('тўлиқ маълумот: тўлиқ тавсиф, порция/грамм/теглар/кухна, КБЖУ, поғоналар, ★ баҳо', (t) async {
      const long = 'Mazali palov: guruch, sabzi, go\'sht va ziravorlar bilan dimlab pishiriladi. Ustiga qatiq va achchiq-chuchuk qo\'shiladi.';
      await pumpSheet(
        t,
        item: _item(
          description: long,
          facts: const DishFacts(
            servings: 4,
            weightG: 800,
            kcal: 500,
            protein: 30,
            fat: 20,
            carbs: 50,
            cuisineGroup: 'national',
            cuisineId: 'national_osh',
            tags: ['light'],
          ),
          tiers: const [QtyTier(minQty: 10, price: 36000), QtyTier(minQty: 30, price: 32000)],
        ),
        stats: const DishStats(ratingSum: 45, ratingCount: 10),
        cuisineLoader: () async => const [Cuisine(id: 'national_osh', name: 'Ош', group: 'national', names: {'uz_Latn': 'Osh taomlari'})],
      );
      expect(find.text(long), findsOneWidget, reason: 'тавсиф қирқилмайди');
      expect(find.text(tr('restaurants_dish_serves').replaceAll('{n}', '4')), findsOneWidget);
      expect(find.text(tr('restaurants_dish_grams').replaceAll('{n}', '800')), findsOneWidget);
      expect(find.text(tr('restaurants_m_dish_tag_light')), findsOneWidget);
      expect(find.text('Osh taomlari'), findsOneWidget, reason: 'кухна номи');
      expect(find.byKey(const ValueKey('dish-sheet-nutrition')), findsOneWidget);
      expect(find.text(tr('restaurants_m_dish_kcal_short').replaceAll('{n}', '500')), findsOneWidget);
      expect(find.text(tr('restaurants_dish_grams').replaceAll('{n}', '30')), findsOneWidget, reason: 'оқсил');
      expect(find.byKey(const ValueKey('dish-sheet-tier-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-sheet-tier-30')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-sheet-rating')), findsOneWidget);
      expect(find.text('4.5 · ${tr('restaurants_dish_rating_count').replaceAll('{n}', '10')}'), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-sheet-new')), findsNothing);
      expect(find.byKey(const ValueKey('dish-sheet-per-person')), findsOneWidget, reason: '4 кишилик — бир кишилик нарх');
    });

    testWidgets('факт ва тавсифсиз таом: фақат ном, нарх ва «Янги»; баҳо 5 тадан кам — ★ йўқ', (t) async {
      await pumpSheet(t, stats: const DishStats(ratingSum: 16, ratingCount: 4));
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-sheet-description')), findsNothing);
      expect(find.byKey(const ValueKey('dish-sheet-facts')), findsNothing);
      expect(find.byKey(const ValueKey('dish-sheet-tiers')), findsNothing);
      expect(find.byKey(const ValueKey('dish-sheet-rating')), findsNothing);
      expect(find.byKey(const ValueKey('dish-sheet-new')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-sheet-open-menu')), findsNothing, reason: 'менюдан очилганда «Менюни кўриш» йўқ');
    });

    testWidgets('кухна номи юкланмаса — варақ ишлайверади, чип йўқ', (t) async {
      await pumpSheet(
        t,
        item: _item(facts: const DishFacts(servings: 2, cuisineGroup: 'national', cuisineId: 'national_osh')),
        cuisineLoader: () async => throw StateError('offline'),
      );
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('dish-sheet-cuisine')), findsNothing);
      expect(find.text(tr('restaurants_dish_serves').replaceAll('{n}', '2')), findsOneWidget);
    });

    testWidgets('саватга қўшиш → степпер + таомга изоҳ майдони; изоҳ саватга тушади; миқдор +/−; 0 бўлса майдон йўқ ва изоҳ тозаланади', (t) async {
      final cart = await pumpSheet(t);
      expect(find.byKey(const ValueKey('dish-sheet-note')), findsNothing, reason: 'саватда йўқ таомга изоҳ йўқ');
      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      expect(cart.qtyOf('osh'), 1);
      expect(find.byKey(const ValueKey('dish-sheet-note')), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey('dish-sheet-note')), 'piyozsiz');
      await t.pump();
      expect(cart.noteOf('osh'), 'piyozsiz');
      expect(cart.toOrderItems().single['note'], 'piyozsiz', reason: 'серверга кетадиган сават қатори');

      await t.tap(find.byKey(const ValueKey('dish-sheet-plus')));
      await t.pumpAndSettle();
      expect(cart.qtyOf('osh'), 2);
      expect(t.widget<Text>(find.byKey(const ValueKey('dish-sheet-qty'))).data, '2');
      expect(cart.noteOf('osh'), 'piyozsiz');

      await t.tap(find.byKey(const ValueKey('dish-sheet-minus')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dish-sheet-minus')));
      await t.pumpAndSettle();
      expect(cart.qtyOf('osh'), 0);
      expect(find.byKey(const ValueKey('dish-sheet-note')), findsNothing);
      expect(find.byKey(const ValueKey('dish-sheet-add')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const ValueKey('dish-sheet-note'))).controller!.text, '', reason: 'эски изоҳ қайтмайди');
    });

    testWidgets('ресторан чегараси (maxQtyPerItem=2): 2 га етганда «+» ўчади', (t) async {
      const limited = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved', maxQtyPerItem: 2);
      final cart = await pumpSheet(t, restaurant: limited);
      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dish-sheet-plus')));
      await t.pumpAndSettle();
      expect(cart.qtyOf('osh'), 2);
      final plus = t.widget<InkWell>(find.descendant(of: find.byKey(const ValueKey('dish-sheet-plus')), matching: find.byType(InkWell)));
      expect(plus.onTap, isNull);
    });

    testWidgets('тугаган таом: хабар + ўчиқ тугма; саватга тушмайди', (t) async {
      final cart = await pumpSheet(t, item: _item(available: false));
      expect(find.byKey(const ValueKey('dish-sheet-sold-out')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('dish-sheet-add'))).onPressed, isNull);
      expect(cart.isEmpty, isTrue);
    });

    testWidgets('ёпиқ ресторан: олдиндан буюртма олмаса — ўчиқ; олса — ёқиқ', (t) async {
      final paused = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved', pausedUntil: DateTime.now().add(const Duration(hours: 2)));
      await pumpSheet(t, restaurant: paused);
      expect(find.byKey(const ValueKey('dish-sheet-closed')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('dish-sheet-add'))).onPressed, isNull);

      final preorder = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved', pausedUntil: DateTime.now().add(const Duration(hours: 2)), acceptsPreorder: true);
      await pumpSheet(t, restaurant: preorder);
      expect(find.byKey(const ValueKey('dish-sheet-closed')), findsNothing);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('dish-sheet-add'))).onPressed, isNotNull);
    });

    testWidgets('бошқа ресторан савати бор: «тозалаймизми?» диалоги; тасдиқланса сават алмашади, бекор қилинса — ўзгармайди', (t) async {
      final cart = RestaurantCart();
      cart.add(_item(id: 'x', name: 'Boshqa'), restaurant: const Restaurant(id: 'r2', name: 'Boshqa joy', status: 'approved'));
      await pumpSheet(t, cart: cart);
      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text(tr('cancel')));
      await t.pumpAndSettle();
      expect(cart.restaurantId, 'r2');

      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      await t.tap(find.text(tr('restaurants_cart_switch_ok')));
      await t.pumpAndSettle();
      expect(cart.restaurantId, 'r1');
      expect(cart.qtyOf('osh'), 1);
    });

    testWidgets('миқдорга чегирма: қўлланган поғона белгиланади, кейингиси ҳақида ҳинт', (t) async {
      final cart = RestaurantCart();
      final item = _item(tiers: const [QtyTier(minQty: 3, price: 36000), QtyTier(minQty: 5, price: 32000)]);
      await pumpSheet(t, item: item, cart: cart);
      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-tier-next')), findsOneWidget, reason: '1 дона: яна 2 та → 36 000');
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      await t.tap(find.byKey(const ValueKey('dish-sheet-plus')));
      await t.tap(find.byKey(const ValueKey('dish-sheet-plus')));
      await t.pumpAndSettle();
      expect(cart.qtyOf('osh'), 3);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget, reason: '3 тадан поғона қўлланди');
      final applied = find.descendant(of: find.byKey(const ValueKey('dish-sheet-tier-3')), matching: find.byIcon(Icons.check_circle_rounded));
      expect(applied, findsOneWidget);
    });

    testWidgets('лентадан очилганда (onCheckout бор): таом саватга тушгач пастки тугма «Буюртма бериш · сават жами →»; босилса callback; «Тайёр» йўқ', (t) async {
      var checkouts = 0;
      final cart = await pumpSheet(t, onCheckout: () => checkouts++);
      expect(find.byKey(const ValueKey('dish-sheet-checkout')), findsNothing, reason: 'сават бўш — аввал «Саватга қўшиш»');
      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-done')), findsNothing);
      final label = '${tr('restaurants_checkout')} · 40 000 ${tr('sum')} →';
      expect(find.descendant(of: find.byKey(const ValueKey('dish-sheet-checkout')), matching: find.text(label)), findsOneWidget);
      // Жами — бутун САВАТ (бошқа таомлар билан), шу қатор эмас.
      cart.add(_item(id: 'somsa', name: 'Somsa', price: 10000), restaurant: _rest);
      await t.pumpAndSettle();
      expect(find.text('${tr('restaurants_checkout')} · 50 000 ${tr('sum')} →'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('dish-sheet-checkout')));
      expect(checkouts, 1);
    });

    testWidgets('менюдан очилганда (onCheckout йўқ): пастки тугма «Тайёр» ва варақни ёпади', (t) async {
      await pumpSheet(t);
      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-sheet-checkout')), findsNothing);
    });

    testWidgets('«Менюни кўриш» фақат лентадан очилганда; босилса callback', (t) async {
      var opened = 0;
      await pumpSheet(t, onOpenMenu: () => opened++);
      expect(find.text('Gurlan osh'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('dish-sheet-open-menu')));
      expect(opened, 1);
    });

    testWidgets('видео белгиси: клип бор — ▶ босилса callback; клип йўқ — белги йўқ', (t) async {
      TvClip? played;
      await pumpSheet(t, clip: _clip(), onPlayVideo: (c) => played = c);
      await t.tap(find.byKey(const ValueKey('item-video-osh')));
      expect(played?.id, 'clip1');
      await pumpSheet(t);
      expect(find.byKey(const ValueKey('item-video-osh')), findsNothing);
    });

    testWidgets('катта шрифт (2×) ва тор экран: хато ва overflow йўқ', (t) async {
      await pumpSheet(
        t,
        textScale: 2.0,
        item: _item(
          description: 'Juda uzun tavsif ' * 8,
          facts: const DishFacts(servings: 4, weightG: 800, kcal: 500, protein: 30, fat: 20, carbs: 50, tags: ['light', 'kids']),
          tiers: const [QtyTier(minQty: 10, price: 36000)],
        ),
        onOpenMenu: () {},
      );
      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('RestaurantScreen: қатор босилса варақ, «+» эса варақсиз; менюда таомга фокус', () {
    Future<RestaurantCart> pumpMenu(WidgetTester t, {String? focus, int perCat = 12, RestaurantCart? cart}) async {
      t.view.physicalSize = const Size(390 * 3, 900 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final c = cart ?? RestaurantCart();
      await t.pumpWidget(l10nApp(
        home: RestaurantScreen(
          key: UniqueKey(), // ҳар чақирувда ЯНГИ ҳолат (initState қайта ишлайди)
          restaurant: _rest,
          repository: _MenuRepo(perCat: perCat),
          cart: c,
          focusItemId: focus,
          itemClipsLoader: (_) async => const {},
          restaurantVideoLoader: () async => null,
          dishStatsLoader: (_) async => const {},
        ),
      ));
      await t.pumpAndSettle();
      return c;
    }

    testWidgets('қатор босилса таом варағи очилади; «+» босилса варақсиз саватга тушади', (t) async {
      final cart = await pumpMenu(t);
      await t.tap(find.byKey(const ValueKey('menu-row-a0')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsOneWidget);
      expect(find.text('Taom a0'), findsWidgets);
      expect(find.byKey(const ValueKey('dish-sheet-open-menu')), findsNothing, reason: 'мижоз аллақачон менюда');
      // Варақда қўшамиз ва ёпамиз → менюдаги қатор ҳам янгиланади.
      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dish-sheet-done')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsNothing);
      expect(cart.qtyOf('a0'), 1);

      // «+» (қатор ичида) варақни очмайди.
      final row = find.byKey(const ValueKey('menu-row-a1'));
      await t.tap(find.descendant(of: row, matching: find.byIcon(Icons.add_rounded)));
      await t.pumpAndSettle();
      expect(cart.qtyOf('a1'), 1);
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsNothing);
    });

    testWidgets('focusItemId: меню ўша таомгача скролл қилинади ва қатор ёритилади; фокussиз — бошида', (t) async {
      await pumpMenu(t);
      expect(find.byKey(const ValueKey('menu-row-b9')), findsNothing, reason: 'фокуссиз 2-бўлим охири кўринмайди');

      await pumpMenu(t, focus: 'b9');
      expect(find.byKey(const ValueKey('menu-row-b9')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-highlight-b9')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-row-a0')), findsNothing, reason: 'меню 1-таомдан узоқлашди');
      expect(t.takeException(), isNull);
    });

    Future<void> pumpOpenCart(WidgetTester t, RestaurantCart cart) async {
      t.view.physicalSize = const Size(390 * 3, 900 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: RestaurantScreen(
          restaurant: _rest,
          repository: _MenuRepo(perCat: 2),
          cart: cart,
          openCartOnStart: true,
          itemClipsLoader: (_) async => const {},
          restaurantVideoLoader: () async => null,
          dishStatsLoader: (_) async => const {},
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('openCartOnStart: сават тўла бўлса экран очилгач сават варағи ўзи очилади', (t) async {
      await pumpOpenCart(t, RestaurantCart()..add(_item(id: 'a0', name: 'Taom a0'), restaurant: _rest));
      expect(find.byKey(const ValueKey('cart-open-a0')), findsOneWidget);
    });

    testWidgets('openCartOnStart: сават бўш бўлса бўш варақ очилмайди', (t) async {
      await pumpOpenCart(t, RestaurantCart());
      expect(find.byKey(const ValueKey('cart-open-a0')), findsNothing);
      expect(find.text(tr('restaurants_cart_empty')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('focusItemId ўчирилган таом — меню бошида қолади, хато йўқ', (t) async {
      await pumpMenu(t, focus: 'yoq');
      expect(find.byKey(const ValueKey('menu-row-a0')), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<Color?>), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('сават варағи: таом изоҳи кўринади, номи босилса таом варағи очилади', (t) async {
      final cart = RestaurantCart();
      cart.add(_item(), restaurant: _rest);
      cart.setNote('osh', 'piyozsiz');
      MenuItem? opened;
      await t.pumpWidget(l10nApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showRestaurantCartSheet(context, cart: cart, restaurant: _rest, onCheckout: () {}, onOpenItem: (i) => opened = i),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('${tr('restaurants_note')}: piyozsiz'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('cart-open-osh')));
      expect(opened?.id, 'osh');
    });
  });

  group('Таом тагидаги ёзувлар: ихчам, ҳарфлар ораси кенг, ўқиладиган', () {
    test('AvaText.dishNote: 12 px дан кичик эмас, ҳарф ораси кенгайтирилган, қатор баландлиги caption билан бир хил (меню қатори ҳисоби ўзгармайди)', () {
      expect(AvaText.dishNote.fontSize, greaterThanOrEqualTo(12), reason: '12 px дан кичик ўқилмайди');
      expect(AvaText.dishNote.letterSpacing, AvaText.feedRowLetterSpacing);
      expect(AvaText.dishNote.letterSpacing, greaterThan(0));
      expect(AvaText.dishNote.height, AvaText.caption.height);
    });

    Future<void> pumpTierMenu(WidgetTester t, {double textScale = 1.0}) async {
      t.view.physicalSize = const Size(360 * 3, 900 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        textScale: textScale,
        home: RestaurantScreen(
          key: UniqueKey(),
          restaurant: _rest,
          repository: _MenuRepo(perCat: 2, tiered: true),
          cart: RestaurantCart(),
          itemClipsLoader: (_) async => const {},
          restaurantVideoLoader: () async => null,
          dishStatsLoader: (_) async => {'a0': const DishStats(ratingSum: 46, ratingCount: 10)},
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('нарх + ★ бир қаторда, чегирма ҳинти нархнинг ТАГИДА; нарх кичрайиб кетмайди (15 px, 2026-10-24 қайта лойиҳа)', (t) async {
      await pumpTierMenu(t);
      final price = find.descendant(of: find.byKey(const ValueKey('menu-row-a0')), matching: find.textContaining('40 000'));
      final hint = find.byKey(const Key('tier-hint-a0'));
      final rating = find.byKey(const Key('dish-rating-a0'));
      expect(price, findsOneWidget);
      expect(hint, findsOneWidget);
      expect(rating, findsOneWidget);
      expect(t.getTopLeft(hint).dy, greaterThan(t.getBottomLeft(price).dy - 1), reason: 'ҳинт нархнинг остида');
      expect((t.getTopLeft(rating).dy - t.getTopLeft(price).dy).abs(), lessThan(8), reason: '★ нарх билан бир қаторда');
      // Нарх FittedBox орқали кичрайтирилмайди: ўлчами 15 px · 1.2 га яқин.
      expect(t.getSize(price).height, closeTo(15 * 1.2, 2));
      expect(t.takeException(), isNull);
    });

    testWidgets('тавсиф ҳамма қаторда БИР қатор (чегирмали таом бор менюда ҳам): қатор баландлиги бир хил, нарх/степпер бир чизиқда', (t) async {
      await pumpTierMenu(t);
      final d = t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('menu-row-a1')), matching: find.textContaining('Uzun tavsif')));
      expect(d.maxLines, 1);
      final withTier = t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('menu-row-a0')), matching: find.textContaining('Uzun tavsif')));
      expect(withTier.maxLines, 1);
    });

    testWidgets('катта шрифт (1.6×) ва тор экран (360): меню қаторида overflow йўқ', (t) async {
      await pumpTierMenu(t, textScale: 1.6);
      expect(t.takeException(), isNull);
    });
  });

  group('«Барчаси» лентаси: таом босилса варақ; иккинчи босишдан ҳимоя', () {
    const feedOn = RestaurantSectionsConfig(stages: {'all': 'public'});

    Future<_FeedRepo> pumpFeed(WidgetTester t, _FeedRepo repo, {void Function(Restaurant)? onOpen, void Function(BuildContext, TvClip)? clipOpener, RestaurantCart? cart}) async {
      t.view.physicalSize = const Size(2400 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: RestaurantsListScreen(
          key: UniqueKey(),
          repository: repo,
          cart: cart ?? RestaurantCart(),
          currentUid: '998912000001',
          userLat: 41.8406,
          userLng: 60.3917,
          locate: () async => null,
          onOpenRestaurant: onOpen,
          itemClipsLoader: (_) async => {'osh': _clip()},
          itemClipOpener: clipOpener,
        ),
      ));
      await t.pumpAndSettle();
      return repo;
    }

    setUp(RestaurantsListScreen.resetLastKnownConfig);

    testWidgets('таом босилса: юкланиш чизиғи → таом варағи (ресторан экрани эмас); таом ва ресторан ҳужжатлари БИР марта олинади', (t) async {
      final repo = _FeedRepo(config: feedOn);
      await pumpFeed(t, repo);
      await t.tap(find.byKey(const ValueKey('dish-r1_osh')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsOneWidget);
      expect(find.text('Tafsilot osh'), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-sheet-open-menu')), findsOneWidget);
      expect(find.byKey(const ValueKey('item-video-osh')), findsOneWidget, reason: 'таом видеоси бор');
      expect(repo.restaurantReads, 1);
      expect(repo.itemReads, 1);
      expect(repo.statReads, 1, reason: '500 та эмас — фақат шу таомнинг баҳоси');
    });

    testWidgets('ҳужжатлар юкланаётганда иккинчи босиш иккинчи экран/варақ очмайди; юкланиш чизиғи кўринади', (t) async {
      final gate = Completer<void>();
      final repo = _FeedRepo(config: feedOn, gate: gate.future);
      await pumpFeed(t, repo);
      await t.tap(find.byKey(const ValueKey('dish-r1_osh')));
      await t.pump();
      expect(find.byKey(const ValueKey('dish-opening')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('dish-r1_osh')));
      await t.pump();
      gate.complete();
      await t.pumpAndSettle();
      expect(repo.restaurantReads, 1, reason: 'иккинчи босиш янги сўров очмади');
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsOneWidget, reason: 'битта варақ');
      expect(find.byKey(const ValueKey('dish-opening')), findsNothing);
    });

    testWidgets('баҳо/видео юкланмаса ҳам варақ очилади (ихтиёрий қўшимча)', (t) async {
      final repo = _FeedRepo(config: feedOn, failStat: true);
      await pumpFeed(t, repo);
      await t.tap(find.byKey(const ValueKey('dish-r1_osh')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-sheet-new')), findsOneWidget);
    });

    testWidgets('ресторан ҳужжати олинмаса — хато хабари, ҳимоя қулфи ечилади (қайта босиш мумкин)', (t) async {
      final repo = _FeedRepo(config: feedOn, restaurantMissing: true);
      await pumpFeed(t, repo);
      await t.tap(find.byKey(const ValueKey('dish-r1_osh')));
      await t.pumpAndSettle();
      expect(find.text(tr('restaurants_dish_open_failed')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsNothing);
      expect(find.byKey(const ValueKey('dish-opening')), findsNothing);
      await t.tap(find.byKey(const ValueKey('dish-r1_osh')));
      await t.pumpAndSettle();
      expect(repo.restaurantReads, 2, reason: 'қулф ечилган');
    });

    testWidgets('лентадан саватга қўшиб «Буюртма бериш»: варақ ёпилади, ресторан экрани САВАТ ВАРАҒИ очиқ ҳолда очилади (лентада сават панели йўқ)', (t) async {
      final cart = RestaurantCart();
      await pumpFeed(t, _FeedRepo(config: feedOn), cart: cart);
      await t.tap(find.byKey(const ValueKey('dish-r1_osh')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dish-sheet-add')));
      await t.pumpAndSettle();
      expect(cart.qtyOf('osh'), 1);
      await t.tap(find.byKey(const ValueKey('dish-sheet-checkout')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsNothing, reason: 'варақ ёпилди');
      expect(find.byType(RestaurantScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-open-osh')), findsOneWidget, reason: 'сават варағи очиқ');
      expect(find.text(tr('restaurants_checkout')), findsWidgets);
    });

    testWidgets('«Менюни кўриш» — сават варағисиз, таомга фокус билан', (t) async {
      final cart = RestaurantCart();
      await pumpFeed(t, _FeedRepo(config: feedOn), cart: cart);
      await t.tap(find.byKey(const ValueKey('dish-r1_osh')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dish-sheet-open-menu')));
      await t.pumpAndSettle();
      expect(find.byType(RestaurantScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-open-osh')), findsNothing);
    });

    testWidgets('варақдаги ▶ видеони очади', (t) async {
      TvClip? played;
      await pumpFeed(t, _FeedRepo(config: feedOn), clipOpener: (_, c) => played = c);
      await t.tap(find.byKey(const ValueKey('dish-r1_osh')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('item-video-osh')));
      expect(played?.id, 'clip1');
    });
  });

  group('Буюртмада таом изоҳи', () {
    testWidgets('мижоз буюртма экрани: изоҳ таом тагида; изоҳсиз таомда йўқ', (t) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final order = OrderModel(
        id: 'o1',
        type: 'restaurant',
        total: 50000,
        status: 'accepted',
        restaurantStatus: 'accepted',
        items: const [
          OrderItem(itemId: 'osh', name: 'Osh', count: 1, lineTotal: 40000, note: 'piyozsiz'),
          OrderItem(itemId: 'somsa', name: 'Somsa', count: 1, lineTotal: 10000),
        ],
      );
      await t.pumpWidget(l10nApp(home: RestaurantOrderScreen(orderId: 'o1', repository: _OrderRepo(order))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-item-note-osh')), findsOneWidget);
      expect(find.text('${tr('restaurants_note')}: piyozsiz'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-item-note-somsa')), findsNothing);
    });
  });

  group('3 тилда янги матнлар', () {
    test('барча янги калитлар uz_Cyrl / uz_Latn / ru да бор ва бўш эмас; плейсхолдерлар мос', () {
      const keys = [
        'restaurants_dish_add_cart',
        'restaurants_dish_done',
        'restaurants_dish_view_menu',
        'restaurants_dish_note_title',
        'restaurants_dish_note_hint',
        'restaurants_dish_nutrition_title',
        'restaurants_dish_grams',
        'restaurants_dish_tiers_title',
        'restaurants_dish_rating_count',
      ];
      for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        final m = loadLang(lang);
        for (final k in keys) {
          expect((m[k] ?? '').trim(), isNotEmpty, reason: '$lang $k');
        }
        expect(m['restaurants_dish_grams'], contains('{n}'), reason: '$lang grams');
        expect(m['restaurants_dish_rating_count'], contains('{n}'), reason: '$lang rating count');
      }
    });
  });
}

String _read(String path) => File(path).readAsStringSync();

class _MenuRepo implements RestaurantsRepository {
  _MenuRepo({this.perCat = 12, this.tiered = false});

  final int perCat;

  /// `a0` — миқдорга чегирмали, қолганлари оддий; ҳаммасида узун тавсиф.
  final bool tiered;

  @override
  Stream<Restaurant?> watchRestaurant(String id) => Stream.value(_rest);

  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) =>
      Stream.value(const [MenuCategory(id: 'c1', name: 'Asosiy', sort: 1), MenuCategory(id: 'c2', name: 'Ichimlik', sort: 2)]);

  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) => Stream.value([
        for (var i = 0; i < perCat; i++)
          _item(
            id: 'a$i',
            name: 'Taom a$i',
            categoryId: 'c1',
            sort: i,
            description: tiered ? 'Uzun tavsif: guruch, sabzi, go\'sht va ziravorlar bilan dimlab pishiriladi' : '',
            tiers: tiered && i == 0 ? const [QtyTier(minQty: 10, price: 36000)] : const [],
          ),
        for (var i = 0; i < perCat; i++) _item(id: 'b$i', name: 'Ichimlik b$i', categoryId: 'c2', sort: i),
      ]);

  @override
  Future<List<Cuisine>> listCuisines({bool force = false}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _OrderRepo implements RestaurantsRepository {
  _OrderRepo(this.order);

  final OrderModel order;

  @override
  Stream<OrderModel?> watchOrder(String id) => Stream.value(order);

  @override
  Future<Restaurant?> getRestaurant(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FeedRepo implements RestaurantsRepository {
  _FeedRepo({required this.config, this.gate, this.failStat = false, this.restaurantMissing = false});

  final RestaurantSectionsConfig config;

  /// Ресторан ҳужжати шу Future тугагунча кутади (юкланиш пайтини тақлид қилади).
  final Future<void>? gate;
  final bool failStat;
  final bool restaurantMissing;
  int restaurantReads = 0;
  int itemReads = 0;
  int statReads = 0;

  @override
  Future<RestaurantSectionsConfig> getSectionsConfig({bool force = false}) async => config;

  @override
  Future<SectionDishesResult> fetchSectionDishes(RestaurantSection section, {required double lat, required double lng, int limit = 200}) async =>
      SectionDishesResult([
        SectionDish(
          restaurantId: 'r1',
          itemId: 'osh',
          name: 'Osh',
          price: 40000,
          restaurantName: 'Gurlan osh',
          restaurantLat: 41.85,
          restaurantLng: 60.39,
          listedAt: DateTime.now().subtract(const Duration(days: 90)),
        ),
      ]);

  @override
  Future<List<Cuisine>> listCuisines({bool force = false}) async => const [];

  @override
  Future<Restaurant?> getRestaurant(String id) async {
    restaurantReads++;
    await gate;
    return restaurantMissing ? null : _rest;
  }

  @override
  Future<MenuItem?> getMenuItem(String restaurantId, String itemId) async {
    itemReads++;
    return _item(id: itemId, name: 'Tafsilot $itemId', description: 'To\'liq tavsif');
  }

  @override
  Future<DishStats> getDishStat(String restaurantId, String itemId) async {
    statReads++;
    if (failStat) throw StateError('offline');
    return const DishStats(ratingSum: 48, ratingCount: 10);
  }

  @override
  Stream<List<Restaurant>> watchNearby({required double lat, required double lng, double radiusKm = 20, int perCellLimit = 50}) =>
      Stream.value(const [_rest]);

  @override
  Stream<List<Restaurant>> watchApproved({int limit = 50}) => Stream.value(const [_rest]);

  // Ресторан экрани очилганда (тафсилот варағидан «Буюртма бериш» / «Менюни кўриш»).
  @override
  Stream<Restaurant?> watchRestaurant(String id) => Stream.value(_rest);

  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) => Stream.value(const [MenuCategory(id: 'c1', name: 'Asosiy', sort: 1)]);

  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) => Stream.value([_item(id: 'osh', name: 'Osh')]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

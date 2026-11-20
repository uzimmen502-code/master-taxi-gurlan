// «AVA Супермаркет» 2-босқич (эга 2026-11-21): Тезкор харид, Ҳафталик сават, тарих/қайта буюртма,
// етишмовчилик, «Буни ҳам қўшасизми?», админ импорт ва етишмовчилик. Сервер — сохта (тармоқсиз).
import 'dart:async';
import 'dart:typed_data';

import 'package:ava_gurlan/core/utils/idempotency_keys.dart';
import 'package:ava_gurlan/features/admin_web/screens/supermarket_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_supermarket_service.dart';
import 'package:ava_gurlan/features/supermarket/data/sm_lists_repository.dart';
import 'package:ava_gurlan/features/supermarket/data/supermarket_repository.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_cart.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_cross_sell.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_list.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_offer.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_shortage.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_taxonomy.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_cart_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_checkout_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_order_history_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_quick_buy_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_weekly_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/supermarket_home_screen.dart';
import 'package:ava_gurlan/features/supermarket/supermarket_controller.dart';
import 'package:ava_gurlan/features/supermarket/widgets/sm_shortage_panel.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sm_fixture.dart';

/// Фикстура таксономияси + `pairs` (пиёз → картошка, сут; картошка → пиёз).
final _tx = SmTaxonomy.fromMap({
  'version': 4,
  'categories': [
    {
      'id': 'vegetables',
      'order': 1,
      'icon': 'vegetable',
      'names': n('Сабзавотлар'),
      'groups': [
        {'id': 'onion', 'order': 1, 'names': n('Пиёз'), 'unit': 'kg', 'step': 0.5, 'weighed': true, 'pairs': ['potato', 'milk', 'onion', 'ghost']},
        {'id': 'potato', 'order': 2, 'names': n('Картошка'), 'unit': 'kg', 'step': 1, 'weighed': true, 'pairs': ['onion']},
      ],
    },
    {
      'id': 'dairy',
      'order': 2,
      'icon': 'dairy',
      'names': n('Сут маҳсулотлари'),
      'groups': [
        {'id': 'milk', 'order': 1, 'names': n('Сут'), 'unit': 'pack', 'step': 1},
      ],
    },
  ],
});

SupermarketController _controller({FakeSupermarketApi? api, SmCart? cart}) {
  final c = SupermarketController(api: api ?? FakeSupermarketApi());
  c.setCatalogForTest(_tx, smOffersFixture(), access: smAccessFixture, cart: cart ?? SmCart.empty);
  return c;
}

Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

Finder _k(String k) => find.byKey(ValueKey(k));

class _FakeStore implements SmListsStore {
  _FakeStore([List<SmList>? initial]) : lists = [...?initial];

  final List<SmList> lists;
  final created = <SmList>[];
  final updated = <SmList>[];
  final deleted = <String>[];
  bool failSave = false;

  @override
  Future<List<SmList>> load() async => List.of(lists);

  @override
  Future<String> create(SmList list) async {
    if (failSave) throw Exception('offline');
    created.add(list);
    final id = 'L${lists.length + 1}';
    lists.add(SmList(id: id, name: list.name, items: list.items, remind: list.remind));
    return id;
  }

  @override
  Future<void> update(SmList list) async {
    updated.add(list);
    final i = lists.indexWhere((l) => l.id == list.id);
    if (i >= 0) lists[i] = list;
  }

  @override
  Future<void> delete(String listId) async {
    deleted.add(listId);
    lists.removeWhere((l) => l.id == listId);
  }
}

OrderModel _order(String id, {String status = 'delivered', List<Map<String, dynamic>> items = const [], DateTime? at}) => OrderModel(
      id: id,
      type: 'platform',
      subtype: 'supermarket',
      total: 25000,
      status: status,
      createdAt: at ?? DateTime(2026, 11, 20, 18, 5),
      items: [for (final m in items) OrderItem.fromMap(m)],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'user_phone': '+998901234567'});
    SupermarketAccessCache.resetForTest();
  });

  Future<void> tall(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  group('таксономия pairs', () {
    test('ўзи ва такрор ташланади; эски ҳужжатда — бўш', () {
      expect(_tx.group('onion')!.pairs, ['potato', 'milk', 'ghost']);
      expect(smTaxonomyFixture.group('onion')!.pairs, isEmpty);
    });
  });

  group('Буни ҳам қўшасизми?', () {
    test('саватдаги таклиф ва гуруҳ таклиф қилинмайди; энг арзон, нарх бўйича, ≤ 6', () {
      final cart = SmCart.empty.add('o_red_cheap', 1000);
      final c = _controller(cart: cart);
      final ids = c.crossSell.map((o) => o.id).toList();
      expect(ids, ['p1', 'm1'], reason: 'potato 6000 < milk 12000; onion (саватда) йўқ; ghost — таклифи йўқ');
      // Картошка ҳам саватда — фақат сут қолади.
      final c2 = _controller(cart: cart.add('p1', 1000));
      expect(c2.crossSell.map((o) => o.id), ['m1']);
      // Чегара: 8 та жуфт гуруҳ — 6 та.
      final many = SmTaxonomy.fromMap({
        'categories': [
          {
            'id': 'x',
            'groups': [
              {'id': 'g0', 'unit': 'kg', 'pairs': [for (var i = 1; i <= 8; i++) 'g$i']},
              for (var i = 1; i <= 8; i++) {'id': 'g$i', 'unit': 'kg'},
            ],
          },
        ],
      });
      final offers = [for (var i = 0; i <= 8; i++) offer('x$i', group: 'g$i', price: 1000 + i, variety: '')];
      final byG = <String, List<SmOffer>>{for (final o in offers) o.groupId: [o]};
      final out = smCrossSell(SmCart.empty.add('x0', 500),
          taxonomy: many, offers: {for (final o in offers) o.id: o}, offersByGroup: byG);
      expect(out.map((o) => o.id), ['x1', 'x2', 'x3', 'x4', 'x5', 'x6']);
    });

    testWidgets('саватда бўлим; бир босишда қўшилади ва рўйхатдан чиқади', (t) async {
      await tall(t);
      final c = _controller(cart: SmCart.empty.add('o_red_cheap', 1000));
      await t.pumpWidget(_app(SmCartScreen(controller: c, listsStore: _FakeStore())));
      await t.pumpAndSettle();
      expect(_k('sm_cross_sell'), findsOneWidget);
      expect(_k('sm_cross_add_p1'), findsOneWidget);
      expect(_k('sm_cross_add_o_red_cheap'), findsNothing);
      await t.tap(_k('sm_cross_add_p1'));
      await t.pumpAndSettle();
      expect(c.cart.qtyOf('p1'), 1000);
      expect(_k('sm_cross_add_p1'), findsNothing);
    });
  });

  group('Тезкор харид', () {
    testWidgets('«＋» танлов йўқ — ойна; танлаб қўшилади; кейинги «＋» — ўша таклиф, ойнасиз', (t) async {
      await tall(t);
      final c = _controller();
      await t.pumpWidget(_app(SmQuickBuyScreen(controller: c)));
      await t.pumpAndSettle();
      expect(_k('sm_quick_row_onion'), findsOneWidget);
      expect(_k('sm_quick_cat_all'), findsOneWidget);
      await t.tap(_k('sm_quick_add_onion'));
      await t.pumpAndSettle();
      expect(_k('sm_pick_sheet'), findsOneWidget, reason: 'пиёзда бир неча таклиф — танлов керак');
      expect(t.widget<FilledButton>(_k('sm_pick_add')).onPressed, isNull, reason: 'таклиф танланмаган');
      // Нав: биринчиси — энг арзон таклифли нав (white); қизилга ўтиб, арзонини танлаймиз.
      await t.tap(_k('sm_pick_variety_red'));
      await t.pumpAndSettle();
      await t.tap(_k('sm_pick_offer_o_red_cheap'));
      await t.pumpAndSettle();
      await t.tap(_k('sm_qty_inc'));
      await t.pumpAndSettle();
      await t.tap(_k('sm_pick_add'));
      await t.pumpAndSettle();
      expect(_k('sm_pick_sheet'), findsNothing);
      expect(c.cart.qtyOf('o_red_cheap'), 1000, reason: '0,5 + 0,5');
      expect(_k('sm_quick_in_cart_onion'), findsOneWidget);
      expect(_k('sm_quick_row_onion'), findsOneWidget, reason: 'ўша рўйхатга қайтди');
      await t.tap(_k('sm_quick_add_onion'));
      await t.pumpAndSettle();
      expect(_k('sm_pick_sheet'), findsNothing);
      expect(c.cart.qtyOf('o_red_cheap'), 1500, reason: 'танланган таклиф + бир қадам');
    });

    testWidgets('ягона таклифли гуруҳ — дарҳол қўшилади; категория фильтри; қидирув', (t) async {
      await tall(t);
      final c = _controller();
      await t.pumpWidget(_app(SmQuickBuyScreen(controller: c)));
      await t.pumpAndSettle();
      await t.tap(_k('sm_quick_add_potato'));
      await t.pumpAndSettle();
      expect(_k('sm_pick_sheet'), findsNothing);
      expect(c.cart.qtyOf('p1'), 1000);
      await t.ensureVisible(_k('sm_quick_cat_dairy'));
      await t.pumpAndSettle();
      await t.tap(_k('sm_quick_cat_dairy'));
      await t.pumpAndSettle();
      expect(_k('sm_quick_row_milk'), findsOneWidget);
      expect(_k('sm_quick_row_onion'), findsNothing);
      await t.ensureVisible(_k('sm_quick_cat_all'));
      await t.pumpAndSettle();
      await t.tap(_k('sm_quick_cat_all'));
      await t.pumpAndSettle();
      await t.enterText(_k('sm_quick_search'), 'Пиёз');
      await t.pumpAndSettle();
      expect(_k('sm_quick_row_onion'), findsOneWidget);
      expect(_k('sm_quick_row_potato'), findsNothing);
    });

    test('quickSelected: танлов → сават → ягона; тугаган танлов эсланмайди', () {
      final c = _controller();
      expect(c.quickSelected('onion'), isNull);
      expect(c.quickSelected('potato')?.id, 'p1');
      c.addToCart('o_white', 500);
      expect(c.quickSelected('onion')?.id, 'o_white');
      c.quickPicks['onion'] = 'o_red_oos';
      expect(c.quickSelected('onion')?.id, 'o_white');
      c.quickPicks['onion'] = 'o_red_exp';
      expect(c.quickSelected('onion')?.id, 'o_red_exp');
    });
  });

  group('рўйхатни солиштириш (тоза)', () {
    final offers = {for (final o in smOffersFixture()) o.id: o};
    final byGroup = <String, List<SmOffer>>{};
    for (final o in smOffersFixture()) {
      if (o.visible) (byGroup[o.groupId] ??= []).add(o);
    }
    List<SmCompareLine> cmp(List<SmListItem> items, [Map<String, int> prev = const {}]) =>
        smCompareItems(items, offers: offers, offersByGroup: byGroup, previousPrices: prev);

    test('ўша таклиф: нарх ўзгармаган — ok; ўзгарган — priceChanged; номаълум — ok', () {
      final l = cmp([const SmListItem(groupId: 'onion', varietyId: 'red', offerId: 'o_red_exp', qtyMilli: 1000)], {'o_red_exp': 7000});
      expect(l.single.status, SmCompareStatus.ok);
      final l2 = cmp([const SmListItem(groupId: 'onion', varietyId: 'red', offerId: 'o_red_exp', qtyMilli: 1000)], {'o_red_exp': 6500});
      expect(l2.single.status, SmCompareStatus.priceChanged);
      expect(l2.single.previousPrice, 6500);
      expect(l2.single.offer!.price, 7000);
      expect(cmp([const SmListItem(groupId: 'onion', offerId: 'o_red_exp', qtyMilli: 1000)]).single.status, SmCompareStatus.ok);
    });

    test('таклиф тугаган/йўқолган — шу навдан энг арзони (differentPack); нав йўқ — гуруҳдан', () {
      final a = cmp([const SmListItem(groupId: 'onion', varietyId: 'red', offerId: 'o_red_oos', qtyMilli: 1000)]).single;
      expect(a.status, SmCompareStatus.differentPack);
      expect(a.offer!.id, 'o_red_cheap');
      expect(a.previousOffer!.id, 'o_red_oos');
      final b = cmp([const SmListItem(groupId: 'onion', offerId: 'deleted_offer', qtyMilli: 1000)]).single;
      expect(b.status, SmCompareStatus.differentPack);
      expect(b.offer!.id, 'o_white', reason: 'гуруҳдаги энг арзон (4000)');
      final c = cmp([const SmListItem(groupId: 'onion', varietyId: 'red', qtyMilli: 1000)]).single;
      expect(c.status, SmCompareStatus.ok, reason: 'таклифсиз (намуна) қатор — янги танлов, «ўзгарди» эмас');
      expect(c.offer!.id, 'o_red_cheap');
    });

    test('гуруҳда ҳеч нарса йўқ — unavailable, саватга қўшилмайди', () {
      final l = cmp([
        const SmListItem(groupId: 'empty', qtyMilli: 1000),
        const SmListItem(groupId: 'nope', offerId: 'x', qtyMilli: 1000),
        const SmListItem(groupId: 'potato', offerId: 'p1', qtyMilli: 2000),
      ]);
      expect(l.map((e) => e.status), [SmCompareStatus.unavailable, SmCompareStatus.unavailable, SmCompareStatus.ok]);
      expect(smCompareToCartLines(l).map((e) => (e.productId, e.qtyMilli)), [('p1', 2000)]);
    });

    test('миқдор: қадамга тўғриланади; қолдиқдан ошса камаяди (qtyLimited); танланмагани қўшилмайди', () {
      final o = offer('lim', price: 1000, stock: 1.5);
      final l = smCompareItems([const SmListItem(groupId: 'onion', offerId: 'lim', qtyMilli: 2700)],
          offers: {'lim': o}, offersByGroup: {'onion': [o]}).single;
      expect(l.qtyMilli, 1500);
      expect(l.qtyLimited, isTrue);
      final two = cmp([
        const SmListItem(groupId: 'potato', offerId: 'p1', qtyMilli: 1400),
        const SmListItem(groupId: 'milk', offerId: 'm1', qtyMilli: 1000),
      ]);
      expect(two.first.qtyMilli, 1000, reason: 'қадам 1');
      expect(smCompareToCartLines(two, selected: {1}).map((e) => e.productId), ['m1']);
    });

    test('намуна: 11 маҳсулот (seed id) — таксономияда йўқлари ташланади, миқдор қадамга мос', () {
      expect(kSmTemplateItems.map((e) => e.groupId), [
        'beef', 'potato', 'onion', 'carrot', 'rice', 'bread', 'cottonseed_oil', 'chicken_eggs', 'milk', 'apple', 'drinking_water',
      ]);
      final items = smTemplateItems(_tx);
      expect(items.map((i) => (i.groupId, i.qtyMilli)), [('potato', 3000), ('onion', 2000), ('milk', 2000)]);
      expect(items.every((i) => i.offerId.isEmpty), isTrue);
    });

    test('қайта буюртма: олинган қатор ташланади; аввалги нарх буюртмадан', () {
      final r = smReorderItems(smOrderLineRefs([
        {'productId': 'o_red_exp', 'groupId': 'onion', 'varietyId': 'red', 'price': 6000, 'qty': 1.5},
        {'productId': 'm1', 'groupId': 'milk', 'price': 12000, 'qty': 1, 'removed': {'reason': 'x'}},
        {'productId': '', 'groupId': 'milk', 'qty': 1},
      ]));
      expect(r.items.single.offerId, 'o_red_exp');
      expect(r.items.single.qtyMilli, 1500);
      expect(r.prices, {'o_red_exp': 6000});
      expect(cmp(r.items, r.prices).single.status, SmCompareStatus.priceChanged);
    });

    test('рўйхат модели: шартнома шакли, бир хил маҳсулот бирлашади, чегара 100', () {
      var l = const SmList(id: 'a', name: ' Ҳафта ');
      l = l.addItem(const SmListItem(groupId: 'onion', offerId: 'o1', varietyId: 'red', qtyMilli: 500));
      l = l.addItem(const SmListItem(groupId: 'onion', offerId: 'o1', varietyId: 'red', qtyMilli: 1000));
      l = l.addItem(const SmListItem(groupId: 'milk', qtyMilli: 2000));
      expect(l.items.length, 2);
      expect(l.toMap(), {
        'name': 'Ҳафта',
        'items': [
          {'groupId': 'onion', 'varietyId': 'red', 'offerId': 'o1', 'qty': 1.5},
          {'groupId': 'milk', 'qty': 2},
        ],
        'remind': {'enabled': false, 'weekday': 6, 'minute': 600},
      });
      final back = SmList.fromMap('a', {...l.toMap(), 'items': [...(l.toMap()['items'] as List), {'groupId': '', 'qty': 1}, 'junk']});
      expect(back.items.length, 2);
      var big = const SmList(id: 'b', name: 'x');
      for (var i = 0; i < 105; i++) {
        big = big.addItem(SmListItem(groupId: 'g$i', qtyMilli: 1000));
      }
      expect(big.items.length, kSmListItemsMax);
    });
  });

  group('эслатма формаси', () {
    test('ҳафта куни 1..7, вақт 0..1439 (чегаралар)', () {
      expect(smRemindProblems(const SmRemind(weekday: 1, minute: 0)), isEmpty);
      expect(smRemindProblems(const SmRemind(weekday: 7, minute: 1439)), isEmpty);
      expect(smRemindProblems(const SmRemind(weekday: 0, minute: 600)), ['sm_err_remind_weekday']);
      expect(smRemindProblems(const SmRemind(weekday: 8, minute: 1440)), ['sm_err_remind_weekday', 'sm_err_remind_time']);
      expect(smRemindProblems(const SmRemind(weekday: 3, minute: -1)), ['sm_err_remind_time']);
      expect(SmRemind.fromMap({'enabled': true, 'weekday': 9, 'minute': 10}).enabled, isFalse, reason: 'бузилган — ўчиқ');
      expect(smListProblems(const SmList(id: '', name: '  ')), ['sm_err_list_name_empty']);
      expect(smListProblems(SmList(id: '', name: 'x' * 41)), ['sm_err_list_name_long']);
      expect(smListProblems(SmList(id: '', name: 'x' * 40)), isEmpty);
    });

    testWidgets('муҳаррир: эслатма ёқилади, кун ва вақт; бўш ном — хато; сақлаш — шартнома', (t) async {
      await tall(t);
      final c = _controller();
      final store = _FakeStore();
      await t.pumpWidget(_app(SmListEditorScreen(
        controller: c,
        store: store,
        memo: SmListPriceMemo(),
        initial: SmList(id: '', name: 'Ҳафта', items: smTemplateItems(_tx)),
        existingCount: 0,
        pickTime: (_, __) async => const TimeOfDay(hour: 9, minute: 30),
      )));
      await t.pumpAndSettle();
      expect(_k('sm_remind_note'), findsOneWidget, reason: 'буюртма бермаслиги очиқ айтилади');
      expect(_k('sm_remind_weekday'), findsNothing);
      await t.tap(_k('sm_remind_toggle'));
      await t.pumpAndSettle();
      await t.tap(_k('sm_remind_weekday'));
      await t.pumpAndSettle();
      await t.tap(find.text('sm_weekday_2').last);
      await t.pumpAndSettle();
      await t.tap(_k('sm_remind_time'));
      await t.pumpAndSettle();
      await t.tap(_k('sm_list_remove_0'));
      await t.pumpAndSettle();
      await t.enterText(_k('sm_list_name'), '   ');
      await t.tap(_k('sm_list_save'));
      await t.pumpAndSettle();
      expect(find.text('sm_err_list_name_empty'), findsOneWidget);
      expect(store.created, isEmpty);
      await t.enterText(_k('sm_list_name'), 'Шанба бозори');
      await t.tap(_k('sm_list_save'));
      await t.pumpAndSettle();
      final saved = store.created.single;
      expect(saved.name, 'Шанба бозори');
      expect(saved.items.map((i) => i.groupId), ['onion', 'milk']);
      expect(saved.toMap()['remind'], {'enabled': true, 'weekday': 2, 'minute': 570});
    });

    testWidgets('10 та рўйхат бор — янгиси сақланмайди', (t) async {
      await tall(t);
      final store = _FakeStore([for (var i = 0; i < kSmMaxLists; i++) SmList(id: 'l$i', name: 'L$i')]);
      await t.pumpWidget(_app(SmListEditorScreen(
          controller: _controller(), store: store, memo: SmListPriceMemo(), initial: const SmList(id: '', name: 'Янги'))));
      await t.pumpAndSettle();
      await t.tap(_k('sm_list_save'));
      await t.pumpAndSettle();
      expect(find.text('sm_err_list_limit'), findsOneWidget);
      expect(store.created, isEmpty);
    });
  });

  group('Ҳафталик сават — ҳеч қачон буюртма бермайди', () {
    testWidgets('биринчи марта: икки танлов; намуна → муҳаррир → сақлаш → рўйхат', (t) async {
      await tall(t);
      final store = _FakeStore();
      await t.pumpWidget(_app(SmWeeklyScreen(controller: _controller(), store: store)));
      await t.pumpAndSettle();
      expect(_k('sm_weekly_start_empty'), findsOneWidget);
      expect(_k('sm_weekly_start_template'), findsOneWidget);
      expect(_k('sm_never_orders_note'), findsOneWidget);
      expect(find.textContaining('family'), findsNothing);
      await t.tap(_k('sm_weekly_start_template'));
      await t.pumpAndSettle();
      expect(_k('sm_list_item_0'), findsOneWidget);
      expect(_k('sm_list_item_2'), findsOneWidget);
      await t.tap(_k('sm_list_save'));
      await t.pumpAndSettle();
      expect(store.created.single.items.length, 3);
      expect(_k('sm_weekly_list_L1'), findsOneWidget);
    });

    testWidgets('«Жорий нархларда саватга қўшиш»: солиштириш → тасдиқ → ФАҚАТ сават', (t) async {
      await tall(t);
      final api = FakeSupermarketApi();
      final c = _controller(api: api);
      final list = SmList(id: 'L1', name: 'Ҳафта', items: const [
        SmListItem(groupId: 'onion', varietyId: 'red', offerId: 'o_red_exp', qtyMilli: 1000),
        SmListItem(groupId: 'onion', varietyId: 'red', offerId: 'o_red_oos', qtyMilli: 500),
        SmListItem(groupId: 'empty', qtyMilli: 1000),
        SmListItem(groupId: 'milk', offerId: 'm1', qtyMilli: 2000),
      ]);
      final memo = SmListPriceMemo();
      await memo.save('L1', {'o_red_exp': 6000, 'm1': 12000});
      await t.pumpWidget(_app(SmSavedListScreen(controller: c, store: _FakeStore([list]), memo: memo, list: list)));
      await t.pumpAndSettle();
      await t.tap(_k('sm_list_to_cart'));
      await t.pumpAndSettle();
      expect(_k('sm_compare_dialog'), findsOneWidget);
      expect(find.text('sm_compare_price_changed'), findsOneWidget);
      expect(find.text('sm_compare_different'), findsOneWidget);
      expect(find.text('sm_compare_unavailable'), findsOneWidget);
      expect(_k('sm_compare_note'), findsOneWidget);
      expect(c.cart.isEmpty, isTrue, reason: 'тасдиқсиз ҳеч нарса қўшилмайди');
      // Сутни олиб ташлаймиз (мижоз танлови).
      await t.tap(_k('sm_compare_row_3'));
      await t.pump();
      await t.tap(_k('sm_compare_confirm'));
      await t.pumpAndSettle();
      expect(c.cart.lines.map((l) => (l.productId, l.qtyMilli)), [('o_red_exp', 1000), ('o_red_cheap', 500)]);
      expect(api.payloads, isEmpty, reason: 'placeSupermarketOrder ЧАҚИРИЛМАЙДИ');
      expect(find.byType(SmCheckoutScreen), findsNothing);
      expect(_k('sm_list_added_snack'), findsOneWidget);
      expect(await memo.load('L1'), {'o_red_exp': 7000, 'o_red_oos': 3000, 'm1': 12000}, reason: 'кейинги солиштириш асоси');
    });

    testWidgets('бекор — сават ўзгармайди', (t) async {
      await tall(t);
      final c = _controller();
      const list = SmList(id: 'L1', name: 'Ҳ', items: [SmListItem(groupId: 'potato', offerId: 'p1', qtyMilli: 1000)]);
      await t.pumpWidget(_app(SmSavedListScreen(controller: c, store: _FakeStore([list]), memo: SmListPriceMemo(), list: list)));
      await t.pumpAndSettle();
      await t.tap(_k('sm_list_to_cart'));
      await t.pumpAndSettle();
      await t.tap(find.text('sm_cancel'));
      await t.pumpAndSettle();
      expect(c.cart.isEmpty, isTrue);
    });

    testWidgets('саватдан «Ҳафталик сават сифатида сақлаш» — таклифлар ва миқдорлар', (t) async {
      await tall(t);
      final store = _FakeStore();
      final c = _controller(cart: SmCart.empty.add('o_red_cheap', 1500).add('m1', 2000));
      await t.pumpWidget(_app(SmCartScreen(controller: c, listsStore: store)));
      await t.pumpAndSettle();
      await t.ensureVisible(_k('sm_cart_save_weekly'));
      await t.tap(_k('sm_cart_save_weekly'));
      await t.pumpAndSettle();
      await t.tap(_k('sm_list_save'));
      await t.pumpAndSettle();
      expect(store.created.single.toMap()['items'], [
        {'groupId': 'onion', 'varietyId': 'red', 'offerId': 'o_red_cheap', 'qty': 1.5},
        {'groupId': 'milk', 'offerId': 'm1', 'qty': 2},
      ]);
    });

    testWidgets('бош саҳифа чиплари очади (тез орада эмас)', (t) async {
      await tall(t);
      final c = _controller();
      await t.pumpWidget(_app(SupermarketHomeScreen(controller: c, listsStore: _FakeStore(), ordersLoader: () async => const [])));
      await t.pumpAndSettle();
      await t.tap(_k('sm_chip_quick'));
      await t.pumpAndSettle();
      expect(find.byType(SmQuickBuyScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(_k('sm_chip_weekly'));
      await t.pumpAndSettle();
      expect(find.byType(SmWeeklyScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(_k('sm_chip_orders'));
      await t.pumpAndSettle();
      expect(_k('sm_history_empty'), findsOneWidget);
    });
  });

  group('буюртмалар тарихи', () {
    testWidgets('ҳолат чипи, сана, жами; босилса — тафсилот; «Қайта буюртма» — қайта текширилиб саватга', (t) async {
      await tall(t);
      final api = FakeSupermarketApi();
      final c = _controller(api: api);
      final opened = <String>[];
      final orders = [
        _order('A1', items: [
          {'productId': 'o_red_exp', 'groupId': 'onion', 'varietyId': 'red', 'price': 7000, 'qty': 1},
          {'productId': 'o_red_oos', 'groupId': 'onion', 'varietyId': 'red', 'price': 3000, 'qty': 0.5},
          {'productId': 'm1', 'groupId': 'milk', 'price': 12000, 'qty': 1, 'removed': {'reason': 'x'}},
        ]),
        _order('A2', status: 'cancelled'),
      ];
      await t.pumpWidget(_app(SmOrderHistoryScreen(
        controller: c,
        loader: () async => orders,
        openDetail: (_, o) => opened.add(o.id),
      )));
      await t.pumpAndSettle();
      expect(find.text('sm_step_delivered'), findsOneWidget);
      expect(find.text('sm_status_cancelled'), findsOneWidget);
      expect(find.text('20.11.2026 18:05'), findsNWidgets(2));
      await t.tap(_k('sm_history_A1'));
      await t.pumpAndSettle();
      expect(opened, ['A1']);
      await t.tap(_k('sm_history_reorder_A1'));
      await t.pumpAndSettle();
      expect(find.text('sm_compare_different'), findsOneWidget, reason: 'тугаган таклиф ўрнига бошқаси');
      await t.tap(_k('sm_compare_confirm'));
      await t.pumpAndSettle();
      expect(c.cart.lines.map((l) => (l.productId, l.qtyMilli)), [('o_red_exp', 1000), ('o_red_cheap', 500)]);
      expect(c.cart.qtyOf('m1'), 0, reason: 'олинган қатор қайтмайди');
      expect(api.payloads, isEmpty);
    });
  });

  group('етишмовчилик', () {
    Map<String, dynamic> item({String state = 'shortage', Object? options}) => {
          'productId': 'o_red_exp',
          'name': 'Қизил пиёз',
          'price': 7000,
          'qty': 2,
          'groupId': 'onion',
          'state': state,
          'options': options ?? {'availableQty': 1, 'substitutes': ['o_red_cheap', 'o_white', 'o_red_exp']},
        };

    test('парс ва payload (шартнома); бошқа ҳолат — йўқ', () {
      final s = SmShortage.fromItem(item())!;
      expect(s.qtyMilli, 2000);
      expect(s.availableQtyMilli, 1000);
      expect(s.substitutes, ['o_red_cheap', 'o_white'], reason: 'ўзи ташланади');
      expect(s.canReduce, isTrue);
      expect(SmShortage.fromItem(item(state: 'ok')), isNull);
      expect(SmShortage.fromItem({...item(), 'removed': {'r': 1}}), isNull);
      expect(SmShortage.fromItem(item(options: {'availableQty': 0}))!.canReduce, isFalse);
      final sub = offer('o_white', price: 4000, variety: 'white');
      expect(smShortageWalletDelta(s, SmShortageChoice.substitute, substitute: sub), 8000 - 14000);
      expect(smShortageWalletDelta(s, SmShortageChoice.reduce), -7000);
      expect(smShortageWalletDelta(s, SmShortageChoice.remove), -14000);
      expect(
          smShortagePayload(orderId: 'O', shortage: s, choice: SmShortageChoice.substitute, substitute: sub, clientRequestId: 'k'),
          {'orderId': 'O', 'productId': 'o_red_exp', 'choice': 'substitute', 'offerId': 'o_white', 'qty': 2, 'clientRequestId': 'k'});
      expect(smShortagePayload(orderId: 'O', shortage: s, choice: SmShortageChoice.reduce, clientRequestId: 'k'),
          {'orderId': 'O', 'productId': 'o_red_exp', 'choice': 'reduce', 'qty': 1, 'clientRequestId': 'k'});
      expect(smShortagePayload(orderId: 'O', shortage: s, choice: SmShortageChoice.remove, clientRequestId: 'k'),
          {'orderId': 'O', 'productId': 'o_red_exp', 'choice': 'remove', 'clientRequestId': 'k'});
    });

    testWidgets('танловлар; юбориш пайтида ўчиқ; тармоқ хатосида ЎША калит; натижа', (t) async {
      await tall(t);
      final api = FakeSupermarketApi();
      final gate = Completer<void>();
      api.shortageResults.addAll([const SmCallError('sm_err_network', 'unavailable'), gate.future]);
      var n = 0;
      final keys = IdempotencyKeys(generator: () => 'key${++n}');
      final o = _order('ORD', status: 'accepted', items: [item()]);
      await t.pumpWidget(_app(Scaffold(body: ListView(children: [SmShortagePanel(order: o, api: api, keys: keys)]))));
      await t.pumpAndSettle();
      expect(_k('sm_shortage_o_red_exp'), findsOneWidget);
      expect(_k('sm_shortage_sub_o_red_cheap'), findsOneWidget);
      expect(_k('sm_shortage_sub_o_white'), findsOneWidget);
      expect(_k('sm_shortage_reduce'), findsOneWidget);
      expect(_k('sm_shortage_remove'), findsOneWidget);
      expect(find.text('sm_shortage_wallet_refund'), findsNWidgets(4), reason: 'иккала ўрнини босувчи арзон + камайтириш + олиш');
      expect(t.widget<FilledButton>(_k('sm_shortage_submit_o_red_exp')).onPressed, isNull, reason: 'танлов йўқ');
      await t.tap(_k('sm_shortage_sub_o_white'));
      await t.pump();
      await t.tap(_k('sm_shortage_submit_o_red_exp'));
      await t.pumpAndSettle();
      expect(find.text('sm_err_network'), findsOneWidget);
      await t.tap(_k('sm_shortage_submit_o_red_exp'));
      await t.pump();
      expect(t.widget<FilledButton>(_k('sm_shortage_submit_o_red_exp')).onPressed, isNull, reason: 'юбориш пайтида ўчиқ');
      gate.complete();
      await t.pumpAndSettle();
      expect(api.shortagePayloads.map((p) => p['clientRequestId']), ['key1', 'key1']);
      expect(api.shortagePayloads.last['offerId'], 'o_white');
      expect(_k('sm_shortage_done_o_red_exp'), findsOneWidget);
    });

    testWidgets('ҳамён етмаса — сервер матни ва тўлдириш; аниқ раддан кейин янги калит', (t) async {
      await tall(t);
      final api = FakeSupermarketApi()
        ..extraOffers = [offer('dear', price: 20000)]
        ..shortageResults.add(const SmCallError('sm_err_insufficient_funds', 'INSUFFICIENT_FUNDS',
            messages: {'uz_Cyrl': 'Ҳамёнда маблағ етарли эмас', 'uz_Latn': 'x', 'ru': 'y'}));
      var n = 0;
      var topUps = 0;
      final keys = IdempotencyKeys(generator: () => 'key${++n}');
      final o = _order('ORD', status: 'accepted', items: [item(options: {'availableQty': 0, 'substitutes': ['dear']})]);
      await t.pumpWidget(_app(Scaffold(
          body: ListView(children: [SmShortagePanel(order: o, api: api, keys: keys, openTopUp: (_) => topUps++)]))));
      await t.pumpAndSettle();
      expect(_k('sm_shortage_reduce'), findsNothing, reason: 'мавжуди 0 — камайтириш йўқ');
      expect(find.text('sm_shortage_wallet_charge'), findsOneWidget);
      await t.tap(_k('sm_shortage_sub_dear'));
      await t.pump();
      await t.tap(_k('sm_shortage_submit_o_red_exp'));
      await t.pumpAndSettle();
      expect(find.text('Ҳамёнда маблағ етарли эмас'), findsOneWidget);
      await t.tap(_k('sm_shortage_topup_o_red_exp'));
      expect(topUps, 1);
      await t.tap(_k('sm_shortage_remove'));
      await t.pump();
      await t.tap(_k('sm_shortage_submit_o_red_exp'));
      await t.pumpAndSettle();
      expect(api.shortagePayloads.map((p) => p['clientRequestId']), ['key1', 'key2']);
      expect(api.shortagePayloads.last['choice'], 'remove');
    });

    testWidgets('етишмовчилик йўқ — панел бўш', (t) async {
      await t.pumpWidget(_app(Scaffold(body: SmShortagePanel(order: _order('X', items: [item(state: '')]), api: FakeSupermarketApi()))));
      expect(find.byType(SmShortageCard), findsNothing);
    });
  });

  group('админ', () {
    testWidgets('Excel импорт: шаблон → файл → сонлар + хато қаторлар → тасдиқ → натижа', (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final s = _FakeImportAdmin();
      final saved = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SmImportAdminTab(
            service: s,
            pickFile: () async => (name: 'narxlar.xlsx', bytes: Uint8List.fromList([1, 2, 3])),
            saveFile: (name, _) async => saved.add(name),
            newRequestId: () => 'rid-1',
          ),
        ),
      ));
      await t.tap(_k('sm_import_template'));
      await t.pumpAndSettle();
      expect(saved, ['sm.xlsx']);
      await t.tap(_k('sm_import_pick'));
      await t.pumpAndSettle();
      expect(s.previewCalls.single, ('narxlar.xlsx', 3, 'rid-1'));
      expect(find.text('Янги: 2'), findsOneWidget);
      expect(find.text('Хато: 1'), findsOneWidget);
      expect(_k('sm_import_err_5'), findsOneWidget);
      expect(find.textContaining('PRICE_INVALID'), findsOneWidget);
      await t.tap(_k('sm_import_confirm'));
      await t.pumpAndSettle();
      expect(s.confirmCalls, ['b1']);
      expect(_k('sm_import_result'), findsOneWidget);
      expect(find.text('Янгиланди: 1'), findsOneWidget);
      await t.tap(_k('sm_import_new'));
      await t.pumpAndSettle();
      expect(_k('sm_import_pick'), findsOneWidget);
    });

    testWidgets('импорт: сервер рад этса — Кирилл хато, ёзувсиз', (t) async {
      final s = _FakeImportAdmin()..failPreview = true;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SmImportAdminTab(service: s, pickFile: () async => (name: 'a.xlsx', bytes: Uint8List(2))),
        ),
      ));
      await t.tap(_k('sm_import_pick'));
      await t.pumpAndSettle();
      expect(_k('sm_import_error'), findsOneWidget);
      expect(s.confirmCalls, isEmpty);
    });

    test('етишмовчилик формаси текшируви (мусбат/манфий/чегара)', () {
      expect(smShortageAdminProblems(orderedQty: 2, availableQty: 0, substitutes: const []), isEmpty);
      expect(smShortageAdminProblems(orderedQty: 2, availableQty: 1.5, substitutes: const ['a', 'b', 'c']), isEmpty);
      expect(smShortageAdminProblems(orderedQty: 2, availableQty: 2, substitutes: const []), hasLength(1));
      expect(smShortageAdminProblems(orderedQty: 2, availableQty: -1, substitutes: const []), hasLength(1));
      expect(smShortageAdminProblems(orderedQty: 2, availableQty: null, substitutes: const []), hasLength(1));
      expect(smShortageAdminProblems(orderedQty: 2, availableQty: 1, substitutes: const ['a', 'b', 'c', 'd']), hasLength(1));
    });

    testWidgets('буюртмада етишмовчилик: миқдор + 3 тагача ўрнини босувчи → сервер', (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final s = _FakeImportAdmin();
      final order = {
        'id': 'ord1',
        'type': 'platform',
        'subtype': 'supermarket',
        'status': 'accepted',
        'items': [
          {'productId': 'o_red_exp', 'groupId': 'onion', 'name': 'Пиёз', 'qty': 2, 'smUnit': 'kg', 'weighed': true},
          {'productId': 'm1', 'groupId': 'milk', 'name': 'Сут', 'qty': 1, 'smUnit': 'pack', 'state': 'shortage'},
        ],
      };
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SmOrdersAdminTab(service: s, orders: Stream.value([order])))));
      await t.pumpAndSettle();
      expect(_k('sm_admin_shortage_ord1_m1'), findsNothing, reason: 'аллақачон етишмовчилик');
      expect(find.textContaining('ЕТИШМОВЧИЛИК'), findsOneWidget);
      await t.tap(_k('sm_admin_shortage_ord1_o_red_exp'));
      await t.pumpAndSettle();
      expect(_k('sm_admin_shortage_sub_o_red_oos'), findsNothing, reason: 'фақат сотувдагилар');
      expect(_k('sm_admin_shortage_sub_m1'), findsNothing, reason: 'фақат шу гуруҳ');
      await t.enterText(_k('sm_admin_shortage_qty'), '2');
      await t.tap(_k('sm_admin_shortage_confirm'));
      await t.pumpAndSettle();
      expect(find.text('Мавжуд миқдор буюртмадагидан кам бўлиши керак'), findsOneWidget);
      await t.enterText(_k('sm_admin_shortage_qty'), '1,5');
      await t.tap(_k('sm_admin_shortage_sub_o_white'));
      await t.tap(_k('sm_admin_shortage_sub_o_red_cheap'));
      await t.pump();
      await t.tap(_k('sm_admin_shortage_confirm'));
      await t.pumpAndSettle();
      final r = s.shortages.single;
      expect((r.$1, r.$2, r.$3), ('ord1', 'o_red_exp', 1.5));
      expect(r.$4, ['o_white', 'o_red_cheap']);
    });
  });

  group('катта шрифт 1.5 / 320 px — overflow йўқ (2-босқич)', () {
    final screens = <String, Widget Function(SupermarketController c)>{
      'quick': (c) => SmQuickBuyScreen(controller: c),
      'weekly_first': (c) => SmWeeklyScreen(controller: c, store: _FakeStore()),
      'weekly_saved': (c) => SmWeeklyScreen(controller: c, store: _FakeStore([const SmList(id: 'a', name: 'Ҳафталик сават — шанба', remind: SmRemind(enabled: true))])),
      'editor': (c) => SmListEditorScreen(
            controller: c,
            store: _FakeStore(),
            memo: SmListPriceMemo(),
            initial: SmList(id: '', name: 'Ҳафта', items: smTemplateItems(_tx), remind: const SmRemind(enabled: true)),
          ),
      'saved': (c) => SmSavedListScreen(
            controller: c,
            store: _FakeStore(),
            memo: SmListPriceMemo(),
            list: SmList(id: 'a', name: 'Ҳафта', items: smTemplateItems(_tx), remind: const SmRemind(enabled: true)),
          ),
      'history': (c) => SmOrderHistoryScreen(controller: c, loader: () async => [_order('A1'), _order('A2', status: 'new')]),
      'cart_cross': (c) => SmCartScreen(controller: c, listsStore: _FakeStore()),
      'shortage': (c) => Scaffold(
            body: ListView(children: [
              SmShortagePanel(
                order: _order('O', status: 'accepted', items: [
                  {'productId': 'o_red_exp', 'name': 'Қизил пиёз, Гурлан, сараланган', 'price': 7000, 'qty': 2, 'state': 'shortage',
                    'options': {'availableQty': 1, 'substitutes': ['o_red_cheap', 'o_white']}},
                ]),
                api: FakeSupermarketApi(),
              ),
            ]),
          ),
    };
    for (final e in screens.entries) {
      testWidgets(e.key, (t) async {
        await t.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final c = _controller(cart: SmCart.empty.add('o_red_cheap', 1500));
        await t.pumpWidget(_app(e.value(c), textScale: 1.5));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final list = find.byType(Scrollable);
        if (list.evaluate().isNotEmpty) {
          await t.drag(list.first, const Offset(0, -3000));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
      });
    }

    testWidgets('ихчам ойна', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = _controller();
      await t.pumpWidget(_app(SmQuickBuyScreen(controller: c), textScale: 1.5));
      await t.pumpAndSettle();
      await t.tap(_k('sm_quick_add_onion'));
      await t.pumpAndSettle();
      await t.tap(_k('sm_pick_offer_o_white'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('солиштириш ойнаси', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = _controller();
      await t.pumpWidget(_app(
          SmSavedListScreen(
            controller: c,
            store: _FakeStore(),
            memo: SmListPriceMemo(),
            list: const SmList(id: 'a', name: 'Ҳ', items: [
              SmListItem(groupId: 'onion', offerId: 'o_red_oos', varietyId: 'red', qtyMilli: 1000),
              SmListItem(groupId: 'empty', qtyMilli: 1000),
            ]),
          ),
          textScale: 1.5));
      await t.pumpAndSettle();
      await t.tap(_k('sm_list_to_cart'));
      await t.pumpAndSettle();
      expect(_k('sm_compare_dialog'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}

class _FakeImportAdmin extends AdminSupermarketService {
  final previewCalls = <(String, int, String)>[];
  final confirmCalls = <String>[];
  final shortages = <(String, String, num, List<String>)>[];
  bool failPreview = false;

  @override
  Future<({String fileName, Uint8List bytes})> importTemplate() async => (fileName: 'sm.xlsx', bytes: Uint8List(4));

  @override
  Future<SmImportPreview> importPreview({required String fileName, required Uint8List bytes, required String clientRequestId}) async {
    previewCalls.add((fileName, bytes.length, clientRequestId));
    if (failPreview) throw const AdminSupermarketException('Сервер рад этди (FILE_NOT_XLSX)');
    return SmImportPreview.fromMap({
      'batchId': 'b1',
      'counts': {'total': 4, 'create': 2, 'update': 1, 'unchanged': 0, 'errors': 1},
      'rows': [
        {'row': 2, 'productId': 'p_a', 'title': 'Пиёз', 'action': 'create'},
        {'row': 5, 'productId': 'p_b', 'title': 'Сут', 'action': 'error', 'errors': ['PRICE_INVALID']},
      ],
    });
  }

  @override
  Future<SmImportResult> importConfirm(String batchId) async {
    confirmCalls.add(batchId);
    return SmImportResult.fromMap({
      'status': 'done',
      'counts': {'created': 2, 'updated': 1, 'unchanged': 0, 'error': 0},
      'rows': const [],
    });
  }

  @override
  Future<List<SmOffer>> loadOffers(SmTaxonomy tx) async => smOffersFixture();

  @override
  Future<void> reportShortage(String orderId, String productId, num availableQty, List<String> substitutes) async =>
      shortages.add((orderId, productId, availableQty, substitutes));
}

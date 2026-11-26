// «Менинг ҳафталик харид саватчам» (эга 2026-11-28): ягона саватча — тўр/чиплар, нишон, гуруҳ таклифлари,
// пастки панел, ярим экран, сарлавҳа (туғилган кун 15 кун), миграция, эслатмалар йўли, l10n, overflow.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:ava_gurlan/features/supermarket/data/sm_basket_birthdays.dart';
import 'package:ava_gurlan/features/supermarket/data/sm_lists_repository.dart';
import 'package:ava_gurlan/features/supermarket/data/supermarket_repository.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_basket.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_cart.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_holiday.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_list.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_offer.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_taxonomy.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_basket_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_holiday_screen.dart' show holidayBasketCheckout;
import 'package:ava_gurlan/features/supermarket/screens/sm_weekly_screen.dart';
import 'package:ava_gurlan/features/supermarket/supermarket_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sm_fixture.dart';

final _tx = SmTaxonomy.fromMap({
  'version': 3,
  'categories': [
    {
      'id': 'vegetables',
      'order': 1,
      'icon': 'vegetable',
      'names': n('Сабзавотлар'),
      'groups': [
        {'id': 'onion', 'order': 1, 'names': n('Пиёз'), 'unit': 'kg', 'step': 0.5, 'weighed': true},
        {'id': 'potato', 'order': 2, 'names': n('Картошка'), 'unit': 'kg', 'step': 1, 'weighed': true},
        {'id': 'empty', 'order': 3, 'names': n('Бўш'), 'unit': 'kg', 'step': 1},
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
    {
      'id': 'household',
      'order': 9,
      'icon': 'household',
      'names': n('Уй-рўзғор'),
      'groups': [
        {'id': 'napkins', 'order': 1, 'names': n('Салфетка'), 'unit': 'pack', 'step': 1},
      ],
    },
    {
      'id': 'holiday_sweets',
      'order': 10,
      'icon': 'holiday',
      'names': n('Байрам ва ширинликлар'),
      'groups': [
        {'id': 'cake', 'order': 1, 'names': n('Торт'), 'unit': 'piece', 'step': 1},
        {'id': 'candies', 'order': 2, 'names': n('Конфетлар'), 'unit': 'kg', 'step': 0.5, 'weighed': true},
      ],
    },
  ],
});

List<SmOffer> _offers() => [
      ...smOffersFixture(),
      offer('nap1', group: 'napkins', price: 8000, variety: '', varietyNames: const {}, unit: 'pack', step: 1, weighed: false),
      offer('cake1', group: 'cake', price: 150000, variety: 'napoleon', varietyNames: n('Наполеон'), unit: 'piece', step: 1, weighed: false),
      offer('cake2', group: 'cake', price: 90000, variety: 'medovik', varietyNames: n('Медовик'), unit: 'piece', step: 1, weighed: false),
      offer('cnd1', group: 'candies', price: 60000, variety: '', varietyNames: const {}, unit: 'kg', step: 0.5),
    ];

SupermarketController _controller({FakeSupermarketApi? api}) {
  final c = SupermarketController(api: api ?? FakeSupermarketApi());
  c.setCatalogForTest(_tx, _offers(), access: smAccessFixture);
  c.deliveryArea = const GeoArea(regionId: 'xorazm', districtId: 'gurlan', districtLabel: 'Гурлан');
  return c;
}

class _Store implements SmListsStore {
  _Store([List<SmList>? initial]) : lists = [...?initial];
  final List<SmList> lists;
  final created = <SmList>[];
  final updated = <SmList>[];

  @override
  Future<List<SmList>> load() async => List.of(lists);

  @override
  Future<String> create(SmList list) async {
    created.add(list);
    final id = list.id.isEmpty ? 'auto${lists.length + 1}' : list.id;
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
  Future<void> delete(String listId) async => lists.removeWhere((l) => l.id == listId);
}

Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

Finder _k(String k) => find.byKey(ValueKey(k));

Future<SmBasketBirthdays> _noBirthdays() async => (own: null, spouse: null);

final _today = DateTime(2026, 11, 28);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'user_phone': '+998901234567'}));

  Future<void> tall(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  SmBasketScreen screen(
    SupermarketController c,
    _Store store, {
    bool holiday = false,
    SmHolidayCheckout? checkout,
    void Function(BuildContext, SmHolidayCheckout)? onCheckout,
    SmBasketBirthdaysLoader? birthdays,
    String? openListId,
  }) =>
      SmBasketScreen(
        controller: c,
        store: store,
        birthdays: birthdays ?? _noBirthdays,
        today: _today,
        holiday: holiday,
        checkout: checkout,
        openListId: openListId,
        openCheckout: onCheckout ?? (_, __) {},
        saveDelay: Duration.zero,
      );

  // ─── Миграция ──────────────────────────────────────────────────────────────
  group('миграция: қайси рўйхат саватча', () {
    final old = SmList(id: 'L1', name: 'Эски', updatedAt: DateTime(2026, 11, 1));
    final newer = SmList(id: 'L2', name: 'Янги', updatedAt: DateTime(2026, 11, 20));
    final occ = SmList(id: 'L3', name: 'Наврўз', occasionId: 'navruz', updatedAt: DateTime(2026, 11, 25));

    test('бўш — саватча йўқ (биринчи ўзгаришда weekly_basket яратилади)', () {
      final p = smPickBasket(const []);
      expect(p.basket, isNull);
      expect(p.others, isEmpty);
    });
    test('энг охирги ОДДИЙ рўйхат саватча; қолганлари «Бошқа рўйхатларим»да (ўчирилмайди)', () {
      final p = smPickBasket([old, occ, newer]);
      expect(p.basket!.id, 'L2');
      expect(p.others.map((l) => l.id), ['L3', 'L1']);
    });
    test('weekly_basket ҳужжати ҳар доим устун; эслаб қолинган id — кейин', () {
      const wb = SmList(id: kSmBasketListId, name: 'С');
      expect(smPickBasket([old, newer, wb]).basket!.id, kSmBasketListId);
      expect(smPickBasket([old, newer], remembered: 'L1').basket!.id, 'L1');
      expect(smPickBasket([old, newer], remembered: 'gone').basket!.id, 'L2');
    });
    test('фақат байрам рўйхатлари — энг охиргиси', () {
      expect(smPickBasket([occ]).basket!.id, 'L3');
    });
  });

  // ─── Сарлавҳа ──────────────────────────────────────────────────────────────
  group('сарлавҳа: ўзи ёки турмуш ўртоғи туғилган кунига ≤15 кун', () {
    final today = DateTime(2026, 11, 28);
    test('чегаралар 16 / 15 / 0 / ўтгандан кейин', () {
      expect(smDaysToBirthday(today, DateTime(1990, 12, 14)), 16);
      expect(smBasketBirthdayMode(today: today, own: DateTime(1990, 12, 14)), isFalse, reason: '16 кун');
      expect(smBasketBirthdayMode(today: today, own: DateTime(1990, 12, 13)), isTrue, reason: '15 кун');
      expect(smBasketBirthdayMode(today: today, own: DateTime(1990, 11, 28)), isTrue, reason: 'ўша куни');
      expect(smDaysToBirthday(today, DateTime(1990, 11, 27)), 364, reason: 'кеча эди');
      expect(smBasketBirthdayMode(today: today, own: DateTime(1990, 11, 27)), isFalse, reason: 'ўтгандан кейин — оддий');
    });
    test('турмуш ўртоғи (spouseId орқали) ҳам; турмуш ўртоғи йўқ — фақат ўзи', () {
      expect(smBasketBirthdayMode(today: today, own: DateTime(1990, 6, 1), spouse: DateTime(1992, 12, 5)), isTrue);
      expect(smBasketBirthdayMode(today: today, own: DateTime(1990, 6, 1)), isFalse);
      expect(smBasketBirthdayMode(today: today), isFalse);
    });
    test('йил оралиғи ва 29 феврал', () {
      expect(smDaysToBirthday(DateTime(2026, 12, 25), DateTime(1990, 1, 5)), 11);
      expect(smDaysToBirthday(DateTime(2027, 2, 20), DateTime(2000, 2, 29)), 8, reason: 'кабиса эмас — 28 феврал');
      expect(smDaysToBirthday(DateTime(2028, 2, 20), DateTime(2000, 2, 29)), 9);
    });
    test('калитлар', () {
      expect(smBasketTitleKey(birthday: false), 'smb_title');
      expect(smBasketTitleKey(birthday: true), 'smb_title_birthday');
      expect(smBasketImage(birthday: true), 'assets/images/home/card_birthday_basket_v1.webp');
      expect(smBasketImage(birthday: false), 'assets/images/home/card_weekly_basket_v1.webp');
      for (final f in [kSmBasketImageBirthday, kSmBasketImageWeekly]) {
        expect(File(f).existsSync(), isTrue, reason: f);
        expect(File(f).lengthSync(), lessThan(60 * 1024));
      }
    });
  });

  // ─── Тўр ва гуруҳлар ───────────────────────────────────────────────────────
  group('тўр, чиплар, гуруҳ таклифлари', () {
    final c = _controller();
    test('«Барчаси» — сотувдаги ҳамма гуруҳ (такрорсиз); таклифсиз гуруҳ йўқ', () {
      expect(smBasketGroups(_tx, c.offersByGroup).map((g) => g.id), ['onion', 'potato', 'milk', 'napkins', 'cake', 'candies']);
      expect(smBasketCategories(_tx, c.offersByGroup).map((x) => x.id), ['vegetables', 'dairy', 'household', 'holiday_sweets']);
    });
    test('категория чипи: фақат шу категория; «Байрам ва ширинликлар»да салфетка ҳам', () {
      expect(smBasketGroups(_tx, c.offersByGroup, categoryId: 'dairy').map((g) => g.id), ['milk']);
      expect(smBasketGroups(_tx, c.offersByGroup, categoryId: 'holiday_sweets').map((g) => g.id), ['cake', 'candies', 'napkins']);
      expect(smBasketGroups(_tx, c.offersByGroup, categoryId: 'household').map((g) => g.id), ['napkins']);
    });
    test('гуруҳ таклифлари: фақат сотувдагилари, энг арзони олдин', () {
      expect(smBasketGroupOffers(c.offersByGroup['onion']).map((o) => o.id), ['o_white', 'o_red_cheap', 'o_red_exp']);
      expect(smBasketGroupOffers(c.offersByGroup['cake']).map((o) => o.id), ['cake2', 'cake1']);
      expect(smBasketGroupOffers(null), isEmpty);
    });
  });

  group('миқдор, нишон, йиғинди (тоза)', () {
    final c = _controller();
    final onion = c.offers['o_red_cheap']!;
    final white = c.offers['o_white']!;
    final g = _tx.group('onion')!;

    test('қўйиш / ўзгартириш / 0 — олиб ташлаш; қадамга тўғриланади', () {
      var b = const SmList(id: '', name: 'b');
      b = smBasketSetOffer(b, onion, 500);
      expect(smBasketQtyOf(b, 'o_red_cheap'), 500);
      b = smBasketSetOffer(b, onion, 1500);
      expect(b.items.single.qtyMilli, 1500);
      b = smBasketSetOffer(b, onion, 1200);
      expect(b.items.single.qtyMilli, 1000, reason: '0,5 қадамга');
      b = smBasketSetOffer(b, onion, 0);
      expect(b.items, isEmpty);
    });
    test('намунадаги «ихтиёрий таклиф» қатори аниқ таклиф танланганда олиб ташланади', () {
      var b = const SmList(id: '', name: 'b', items: [SmListItem(groupId: 'onion', qtyMilli: 2000), SmListItem(groupId: 'milk', qtyMilli: 1000)]);
      b = smBasketSetOffer(b, onion, 1000);
      expect(b.items.map((i) => '${i.groupId}:${i.offerId}'), ['milk:', 'onion:o_red_cheap']);
    });
    test('нишон: бир хил бирлик — йиғинди (2 кг); йўқ — null', () {
      var b = smBasketSetOffer(const SmList(id: '', name: 'b'), onion, 1500);
      b = smBasketSetOffer(b, white, 500);
      final bd = smBasketGroupBadge(b, g, c.offers)!;
      expect([bd.qtyMilli, bd.unit, bd.lines], [2000, 'kg', 2]);
      expect(smBasketGroupBadge(b, _tx.group('milk')!, c.offers), isNull);
    });
    test('нишон: турли бирлик — қаторлар сони', () {
      final b = SmList(id: '', name: 'b', items: [
        const SmListItem(groupId: 'onion', offerId: 'o_red_cheap', qtyMilli: 1000),
        const SmListItem(groupId: 'onion', offerId: 'm1', qtyMilli: 1000),
      ]);
      final bd = smBasketGroupBadge(b, g, c.offers)!;
      expect([bd.unit, bd.lines], ['', 2]);
    });
    test('йиғинди: жорий нарх; сотувда йўғи ҳисобланмайди', () {
      final b = SmList(id: '', name: 'b', items: [
        const SmListItem(groupId: 'onion', offerId: 'o_red_cheap', qtyMilli: 1500),
        const SmListItem(groupId: 'cake', offerId: 'cake2', qtyMilli: 1000),
        const SmListItem(groupId: 'empty', qtyMilli: 1000),
      ]);
      final t = smBasketTotals(b, c.offers, c.offersByGroup);
      expect([t.count, t.total, t.unavailable], [3, 7500 + 90000, 1]);
    });
  });

  // ─── Экранлар ──────────────────────────────────────────────────────────────
  group('экран', () {
    testWidgets('тўр 2 устун; чип фильтрлайди; гуруҳ → таклифлар (арзони олдин) → қадам бўйича; нишон ва панел дарҳол', (t) async {
      await tall(t);
      final store = _Store();
      final c = _controller();
      await t.pumpWidget(_app(screen(c, store)));
      await t.pumpAndSettle();
      expect(find.text('smb_title'), findsOneWidget);
      expect(_k('smb_group_onion'), findsOneWidget);
      expect(_k('smb_group_cake'), findsOneWidget);
      expect(_k('smb_group_empty'), findsNothing, reason: 'таклифсиз гуруҳ');
      // 2 устун: биринчи икки плитка бир қаторда.
      expect(t.getTopLeft(_k('smb_group_onion')).dy, t.getTopLeft(_k('smb_group_potato')).dy);
      expect(t.getTopLeft(_k('smb_group_onion')).dx, lessThan(t.getTopLeft(_k('smb_group_potato')).dx));

      await t.dragUntilVisible(_k('smb_chip_holiday_sweets'), _k('smb_chips'), const Offset(-200, 0));
      await t.ensureVisible(_k('smb_chip_holiday_sweets'));
      await t.pumpAndSettle();
      await t.tap(_k('smb_chip_holiday_sweets'));
      await t.pumpAndSettle();
      expect(_k('smb_group_onion'), findsNothing);
      expect(_k('smb_group_napkins'), findsOneWidget);
      await t.dragUntilVisible(_k('smb_chip_all'), _k('smb_chips'), const Offset(300, 0));
      await t.ensureVisible(_k('smb_chip_all'));
      await t.pumpAndSettle();
      await t.tap(_k('smb_chip_all'));
      await t.pumpAndSettle();

      await t.tap(_k('smb_group_onion'));
      await t.pumpAndSettle();
      final ys = [for (final id in ['o_white', 'o_red_cheap', 'o_red_exp']) t.getTopLeft(_k('smb_offer_$id')).dy];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue, reason: 'арзони олдин');
      expect(_k('smb_offer_o_red_oos'), findsNothing);
      final inc = find.descendant(of: _k('smb_qty_o_red_cheap'), matching: _k('sm_qty_inc'));
      await t.tap(inc);
      await t.pump();
      await t.tap(inc);
      await t.pump();
      expect(find.descendant(of: _k('smb_qty_o_red_cheap'), matching: find.text('1 sm_unit_kg')), findsOneWidget, reason: '0,5 + 0,5');
      expect(t.widget<Text>(_k('smb_bar_text')).data, contains('1 · '));
      expect(t.widget<Text>(_k('smb_bar_text')).data, contains('5'));

      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.descendant(of: _k('smb_badge_onion'), matching: find.text('1 sm_unit_kg')), findsOneWidget);
      expect(store.created.single.id, kSmBasketListId, reason: 'янги мижоз — weekly_basket');
      expect(store.created.single.items.single.offerId, 'o_red_cheap');
    });

    testWidgets('орқага — тўр ўша жойда қолади (scroll сақланади)', (t) async {
      await t.binding.setSurfaceSize(const Size(360, 520));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(screen(_controller(), _Store())));
      await t.pumpAndSettle();
      final grid = find.byType(GridView);
      await t.drag(grid, const Offset(0, -150));
      await t.pumpAndSettle();
      final before = t.state<ScrollableState>(find.descendant(of: grid, matching: find.byType(Scrollable))).position.pixels;
      expect(before, greaterThan(0));
      await t.tap(find.descendant(of: find.byType(GridView), matching: find.byType(InkWell)).hitTestable().first);
      await t.pumpAndSettle();
      expect(find.byType(SmBasketGroupScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      final after = t.state<ScrollableState>(find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable))).position.pixels;
      expect(after, before);
    });

    testWidgets('ярим экран: − / +, олиб ташлаш, жами; «Расмийлаштириш» → сават (тенг миқдор, қайта босилса ҳам икки баробар эмас), weekly', (t) async {
      await tall(t);
      final store = _Store([
        const SmList(id: kSmBasketListId, name: 'С', items: [
          SmListItem(groupId: 'onion', varietyId: 'red', offerId: 'o_red_cheap', qtyMilli: 1000),
          SmListItem(groupId: 'cake', offerId: 'cake2', qtyMilli: 1000),
        ]),
      ]);
      final c = _controller();
      final opened = <SmHolidayCheckout>[];
      await t.pumpWidget(_app(screen(c, store, onCheckout: (_, ch) => opened.add(ch))));
      await t.pumpAndSettle();
      expect(t.widget<Text>(_k('smb_bar_text')).data, '2 · ${_money(5000 + 90000)}');
      await t.tap(_k('smb_bar'));
      await t.pumpAndSettle();
      expect(_k('smb_sheet'), findsOneWidget);
      await t.tap(find.descendant(of: _k('smb_line_qty_0'), matching: _k('sm_qty_inc')));
      await t.pump();
      expect(t.widget<Text>(_k('smb_line_total_0')).data, _money(7500));
      await t.ensureVisible(_k('smb_line_remove_1'));
      await t.pumpAndSettle();
      await t.tap(_k('smb_line_remove_1'));
      await t.pump();
      expect(_k('smb_line_1'), findsNothing);
      expect(t.widget<Text>(_k('smb_sheet_total')).data, _money(7500));
      expect(t.widget<Text>(_k('smb_bar_text')).data, '1 · ${_money(7500)}');

      await t.tap(_k('smb_checkout'));
      await t.pumpAndSettle();
      expect(opened.single.origin, 'weekly');
      expect(c.cart.lines.map((l) => '${l.productId}:${l.qtyMilli}'), ['o_red_cheap:1500']);
      expect(_k('smb_sheet'), findsNothing, reason: 'ярим экран ёпилди');
      // Қайта.
      await t.tap(_k('smb_bar'));
      await t.pumpAndSettle();
      await t.tap(_k('smb_checkout'));
      await t.pumpAndSettle();
      expect(c.cart.lines.map((l) => '${l.productId}:${l.qtyMilli}'), ['o_red_cheap:1500']);
      expect(store.lists.single.items.single.qtyMilli, 1500, reason: 'сақланди');
    });

    testWidgets('байрам контексти: манба holiday, совға (қариндош) сақланади', (t) async {
      await tall(t);
      final store = _Store([
        const SmList(id: kSmBasketListId, name: 'С', items: [SmListItem(groupId: 'cake', offerId: 'cake1', qtyMilli: 1000)]),
      ]);
      final opened = <SmHolidayCheckout>[];
      final gift = holidayBasketCheckout(
          birthday: true, gift: const SmHolidayCheckout(asGift: true, recipientName: 'Ali', recipientPhone: '998907654321'));
      await t.pumpWidget(_app(screen(_controller(), store, holiday: true, checkout: gift, onCheckout: (_, ch) => opened.add(ch))));
      await t.pumpAndSettle();
      await t.tap(_k('smb_bar'));
      await t.pumpAndSettle();
      await t.tap(_k('smb_checkout'));
      await t.pumpAndSettle();
      final ch = opened.single;
      expect([ch.origin, ch.occasionId, ch.asGift, ch.recipientName], ['holiday', 'birthday', true, 'Ali']);
    });

    testWidgets('нарх ўзгарган / сотувда йўқ — аввал мижоз тасдиғи (солиштириш ойнаси)', (t) async {
      await tall(t);
      final memo = SmListPriceMemo();
      await memo.save(kSmBasketListId, {'o_red_cheap': 4000});
      final store = _Store([
        const SmList(id: kSmBasketListId, name: 'С', items: [
          SmListItem(groupId: 'onion', offerId: 'o_red_cheap', qtyMilli: 1000),
          SmListItem(groupId: 'empty', qtyMilli: 1000),
        ]),
      ]);
      final c = _controller();
      final opened = <SmHolidayCheckout>[];
      await t.pumpWidget(_app(SmBasketScreen(
        controller: c,
        store: store,
        memo: memo,
        birthdays: _noBirthdays,
        openCheckout: (_, ch) => opened.add(ch),
        saveDelay: Duration.zero,
      )));
      await t.pumpAndSettle();
      await t.tap(_k('smb_bar'));
      await t.pumpAndSettle();
      expect(_k('smb_line_unavailable_1'), findsOneWidget);
      await t.tap(_k('smb_checkout'));
      await t.pumpAndSettle();
      expect(_k('sm_compare_dialog'), findsOneWidget);
      expect(find.text('sm_compare_price_changed'), findsOneWidget);
      expect(c.cart.isEmpty, isTrue);
      await t.tap(_k('sm_compare_confirm'));
      await t.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(c.cart.lines.single.productId, 'o_red_cheap');
    });

    testWidgets('сарлавҳа: туғилган кунга 15 кун — «Туғилган кун саватчаси»; 16 — оддий', (t) async {
      await tall(t);
      await t.pumpWidget(_app(screen(_controller(), _Store(), birthdays: () async => (own: DateTime(1990, 12, 13), spouse: null))));
      await t.pumpAndSettle();
      expect(find.text('smb_title_birthday'), findsOneWidget);
      expect(_k('smb_header_birthday'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_app(screen(_controller(), _Store(), birthdays: () async => (own: DateTime(1990, 12, 14), spouse: null))));
      await t.pumpAndSettle();
      expect(find.text('smb_title'), findsOneWidget);
      expect(_k('smb_header_weekly'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_app(screen(_controller(), _Store(), birthdays: () async => (own: null, spouse: DateTime(1991, 12, 1)))));
      await t.pumpAndSettle();
      expect(find.text('smb_title_birthday'), findsOneWidget, reason: 'турмуш ўртоғи');
    });

    testWidgets('миграция: аввалги рўйхатлар — энг охиргиси саватча (update, create йўқ), қолгани «Бошқа рўйхатларим»', (t) async {
      await tall(t);
      final store = _Store([
        SmList(id: 'L1', name: 'Эски', updatedAt: DateTime(2026, 11, 1)),
        SmList(id: 'L2', name: 'Ҳафталик', updatedAt: DateTime(2026, 11, 20), remind: const SmRemind(enabled: true, weekday: 6, minute: 600), items: const [
          SmListItem(groupId: 'potato', offerId: 'p1', qtyMilli: 2000),
        ]),
      ]);
      await t.pumpWidget(_app(screen(_controller(), store)));
      await t.pumpAndSettle();
      expect(find.descendant(of: _k('smb_badge_potato'), matching: find.text('2 sm_unit_kg')), findsOneWidget);
      expect(find.text('smb_other_lists'), findsOneWidget);
      await t.tap(_k('smb_group_onion'));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: _k('smb_qty_o_white'), matching: _k('sm_qty_inc')));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(store.created, isEmpty);
      expect(store.updated.last.id, 'L2');
      expect(store.updated.last.remind.enabled, isTrue, reason: 'эслатма сақланди');
      expect(store.updated.last.items.map((i) => i.offerId), ['p1', 'o_white']);
      await t.tap(_k('smb_others'));
      await t.pumpAndSettle();
      expect(find.byType(SmOtherListsScreen), findsOneWidget);
      expect(_k('sm_weekly_list_L1'), findsOneWidget);
      expect(_k('sm_weekly_list_L2'), findsNothing);
    });

    testWidgets('эслатма push\'и бошқа рўйхат id билан — ўша рўйхат очилади; саватча id — саватча', (t) async {
      await tall(t);
      final lists = [
        SmList(id: 'L1', name: 'Эски', updatedAt: DateTime(2026, 11, 1)),
        SmList(id: 'L2', name: 'Ҳафталик', updatedAt: DateTime(2026, 11, 20)),
      ];
      await t.pumpWidget(_app(screen(_controller(), _Store(lists), openListId: 'L1')));
      await t.pumpAndSettle();
      expect(find.byType(SmSavedListScreen), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_app(screen(_controller(), _Store(lists), openListId: 'L2')));
      await t.pumpAndSettle();
      expect(find.byType(SmSavedListScreen), findsNothing);
      expect(_k('smb_group_onion'), findsOneWidget);
    });

    testWidgets('ҳафталик эслатма созламаси — саватчага ёзилади', (t) async {
      await tall(t);
      final store = _Store([const SmList(id: kSmBasketListId, name: 'С')]);
      await t.pumpWidget(_app(screen(_controller(), store)));
      await t.pumpAndSettle();
      await t.tap(_k('smb_remind'));
      await t.pumpAndSettle();
      await t.tap(_k('smb_remind_toggle'));
      await t.pumpAndSettle();
      await t.tap(_k('smb_remind_save'));
      await t.pumpAndSettle();
      expect(store.updated.last.remind.enabled, isTrue);
      expect(store.updated.last.remind.weekday, 6);
    });
  });

  // ─── Эслатмалар йўли ───────────────────────────────────────────────────────
  group('байрам эслатмалари → саватча', () {
    test('basket / меҳмонлар / совға / байрам рўйхати — ҳаммаси саватча; ресторан ва бозор ўзгармаган', () {
      HolidayRoute r(Map<String, String> d) => holidayRouteOf(holidayPushTarget(d)!);
      expect(r({'type': 'holiday_self_birthday'}), HolidayRoute.basket);
      expect(r({'type': 'holiday_self_birthday', 'targetType': 'holiday_basket', 'mode': 'guests'}), HolidayRoute.basketGuests);
      expect(r({'type': 'holiday_reminder', 'occasionId': 'navruz', 'targetType': 'holiday_basket', 'mode': 'gift'}), HolidayRoute.basketGift);
      expect(r({'type': 'holiday_reminder', 'occasionId': 'navruz'}), HolidayRoute.occasionList);
      expect(r({'type': 'holiday_reminder', 'occasionId': 'qurbon_hayit', 'targetType': 'market', 'market': 'livestock'}), HolidayRoute.market);
      expect(r({'type': 'holiday_self_birthday', 'targetType': 'restaurants_preorder'}), HolidayRoute.restaurantsPreorder);
    });
    test('расмийлаштириш маълумоти: совға режими, туғилган кун id, манба holiday', () {
      final g = holidayBasketCheckout(occasionId: 'navruz', gift: const SmHolidayCheckout(asGift: true));
      expect([g.occasionId, g.asGift, g.origin], ['navruz', true, 'holiday']);
      expect(holidayBasketCheckout(birthday: true).occasionId, 'birthday');
      expect(holidayBasketCheckout().occasionId, '');
    });
    test('payload: ҳафталик — weekly, байрам — holiday; сана ва бонус иккисида', () {
      Map<String, dynamic> p(String o) => smHolidayOrderPayload(
          clientRequestId: 'k12345678', cart: SmCart.empty.add('p1', 1000), address: const {}, slotId: 's1', deliveryDate: '2026-11-30', origin: o);
      expect(p('weekly')['origin'], 'weekly');
      expect(p('holiday')['origin'], 'holiday');
      expect(p('evil')['origin'], 'holiday');
      expect(p('weekly')['useIncentive'], isTrue);
      expect(p('weekly')['deliveryDate'], '2026-11-30');
    });
  });

  // ─── l10n ──────────────────────────────────────────────────────────────────
  test('саватча калитлари 3 тилда, бўш эмас; uz_Latn янги алифбода', () {
    final maps = {
      for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) l: jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>,
    };
    final keys = {for (final k in maps['uz_Cyrl']!.keys) if (k.startsWith('smb_')) k};
    expect(keys.length, greaterThanOrEqualTo(14));
    for (final k in [...keys, 'hb_home_caption', 'sm_chip_weekly', 'sm_cart_save_weekly']) {
      for (final l in maps.keys) {
        expect((maps[l]![k] as String?)?.trim() ?? '', isNotEmpty, reason: '$l $k');
      }
      expect(RegExp(r"o'|g'|o‘|g‘|sh|ch", caseSensitive: false).hasMatch(maps['uz_Latn']![k] as String), isFalse, reason: k);
    }
    expect(maps['uz_Cyrl']!['smb_title'], 'Менинг ҳафталик харид саватчам');
    expect(maps['uz_Cyrl']!['smb_title_birthday'], 'Туғилган кун саватчаси');
    expect(maps['uz_Latn']!['smb_title'], 'Mening haftalik xarid savatçam');
    expect(maps['uz_Latn']!['smb_title_birthday'], 'Tuğilgan kun savatçasi');
    expect(maps['ru']!['smb_title'], 'Моя недельная корзина покупок');
    expect(maps['ru']!['smb_title_birthday'], 'Корзина ко дню рождения');
    for (final l in ['uz_Latn', 'ru']) {
      expect({for (final k in maps[l]!.keys) if (k.startsWith('smb_')) k}, keys, reason: '$l — бир хил калитлар');
    }
  });

  // ─── Overflow ──────────────────────────────────────────────────────────────
  group('катта шрифт 1.5 / 320 px — overflow йўқ (саватча)', () {
    Future<void> pump(WidgetTester t, Widget w) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(w, textScale: 1.5));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }

    final filled = [
      const SmList(id: kSmBasketListId, name: 'С', items: [
        SmListItem(groupId: 'onion', offerId: 'o_red_cheap', qtyMilli: 1500),
        SmListItem(groupId: 'onion', offerId: 'o_white', qtyMilli: 500),
        SmListItem(groupId: 'cake', offerId: 'cake1', qtyMilli: 1000),
        SmListItem(groupId: 'empty', qtyMilli: 1000),
      ]),
      SmList(id: 'L9', name: 'Бошқа', updatedAt: DateTime(2020)),
    ];

    testWidgets('тўр (+ туғилган кун сарлавҳаси, нишонлар, панел)', (t) async {
      await pump(t, screen(_controller(), _Store(filled), birthdays: () async => (own: DateTime(1990, 12, 1), spouse: null)));
      await t.drag(find.byType(GridView), const Offset(0, -2000));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
    testWidgets('гуруҳ таклифлари', (t) async {
      await pump(t, screen(_controller(), _Store(filled)));
      await t.tap(_k('smb_group_onion'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.drag(find.byType(ListView).last, const Offset(0, -2000));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
    testWidgets('ярим экран', (t) async {
      await pump(t, screen(_controller(), _Store(filled)));
      await t.tap(_k('smb_bar'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
    testWidgets('эслатма', (t) async {
      await pump(t, screen(_controller(), _Store(filled)));
      await t.tap(_k('smb_remind'));
      await t.pumpAndSettle();
      await t.tap(_k('smb_remind_toggle'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}

String _money(int v) => formatMoney(v);

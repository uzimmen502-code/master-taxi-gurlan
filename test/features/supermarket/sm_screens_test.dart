import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:ava_gurlan/core/utils/idempotency_keys.dart';
import 'package:ava_gurlan/features/ads/screens/cheap_products_screen.dart' show aralashPlatformBadgeKey;
import 'package:ava_gurlan/features/home/widgets/home_markets_block.dart';
import 'package:ava_gurlan/features/supermarket/data/supermarket_repository.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_access.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_cart.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_order_progress.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_cart_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_checkout_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_group_screen.dart';
import 'package:ava_gurlan/features/supermarket/screens/supermarket_home_screen.dart';
import 'package:ava_gurlan/features/supermarket/supermarket_controller.dart';
import 'package:ava_gurlan/features/supermarket/widgets/sm_order_cancel_bar.dart';
import 'package:ava_gurlan/features/supermarket/widgets/sm_order_progress_view.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:ava_gurlan/models/platform_product.dart';
import 'package:ava_gurlan/repositories/platform_products_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sm_fixture.dart';

SupermarketController _controller({FakeSupermarketApi? api, SmCart? cart, SmAccess? access}) {
  final c = SupermarketController(api: api ?? FakeSupermarketApi());
  c.setCatalogForTest(smTaxonomyFixture, smOffersFixture(), access: access ?? smAccessFixture, cart: cart);
  c.deliveryArea = const GeoArea(regionId: 'xorazm', districtId: 'gurlan', districtLabel: 'Гурлан');
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'user_phone': '+998901234567'});
    SupermarketAccessCache.resetForTest();
  });

  /// Узун рўйхатлар (ListView ялқов қуради) — баланд экран.
  Future<void> tall(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  group('1. бош саҳифа', () {
    testWidgets('категориялар (гуруҳ сони; бўш гуруҳ саналмайди), чиплар, қидирув, сават нишони', (t) async {
      final c = _controller(cart: SmCart.empty.add('p1', 1000));
      await t.pumpWidget(_app(SupermarketHomeScreen(controller: c)));
      await t.pumpAndSettle();
      expect(_k('sm_category_vegetables'), findsOneWidget);
      expect(_k('sm_category_dairy'), findsOneWidget);
      expect(c.visibleGroups(smTaxonomyFixture.category('vegetables')!).map((g) => g.id), ['onion', 'potato']);
      for (final id in ['products', 'quick', 'weekly']) {
        expect(_k('sm_chip_$id'), findsOneWidget);
      }
      await t.tap(_k('sm_chip_quick'));
      await t.pump();
      expect(find.text('sm_soon'), findsOneWidget, reason: '2-босқич — «тез орада»');
      expect(find.text('1'), findsWidgets, reason: 'сават нишони');
      await t.enterText(_k('sm_search'), 'piyoz');
      await t.pump();
      expect(_k('sm_group_onion'), findsOneWidget);
      expect(_k('sm_category_vegetables'), findsNothing);
      await t.enterText(_k('sm_search'), 'zzzz');
      await t.pump();
      expect(_k('sm_search_none'), findsOneWidget);
    });

    testWidgets('рухсат йўқ — огоҳлантириш (каталог кўринади)', (t) async {
      final c = _controller(access: const SmAccess(allowed: false));
      await t.pumpWidget(_app(SupermarketHomeScreen(controller: c)));
      await t.pumpAndSettle();
      expect(_k('sm_not_available'), findsOneWidget);
      expect(_k('sm_category_vegetables'), findsOneWidget);
    });
  });

  group('2. категория', () {
    testWidgets('гуруҳ нархи — фақат мавжуд энг арзон таклифдан', (t) async {
      final c = _controller();
      await t.pumpWidget(_app(SupermarketHomeScreen(controller: c)));
      await t.pumpAndSettle();
      await t.tap(_k('sm_category_vegetables'));
      await t.pumpAndSettle();
      expect(_k('sm_group_onion'), findsOneWidget);
      expect(_k('sm_group_empty'), findsNothing);
      final price = t.widget<Text>(_k('sm_group_price_onion')).data!;
      expect(price, 'sm_price_from', reason: 'тестда lang йўқ — калит; қиймат пастда');
    });
  });

  group('3. гуруҳ', () {
    testWidgets('нав → нарх ўсиши; тугагани ўчиқ; яширин йўқ; қўшиш + бирлашиш', (t) async {
      await tall(t);
      final c = _controller();
      await t.pumpWidget(_app(SmGroupScreen(controller: c, group: smTaxonomyFixture.group('onion')!)));
      await t.pumpAndSettle();
      // Биринчи нав — энг арзон таклифи бор нав (white 4 000).
      expect(_k('sm_offer_o_white'), findsOneWidget);
      await t.tap(_k('sm_variety_red'));
      await t.pumpAndSettle();
      final order = t.widgetList<SmOfferCard>(find.byType(SmOfferCard)).map((w) => w.offer.id).toList();
      expect(order, ['o_red_cheap', 'o_red_exp', 'o_red_oos'], reason: 'ASC, тугагани охирида');
      expect(_k('sm_offer_o_red_hidden'), findsNothing);
      expect(_k('sm_offer_oos_o_red_oos'), findsOneWidget);
      expect(t.widget<FilledButton>(_k('sm_offer_add_o_red_oos')).onPressed, isNull);
      expect(_k('sm_weighed_note'), findsOneWidget);
      expect(t.widget<Text>(_k('sm_offer_price_o_red_cheap')).data, contains(formatMoney(5000)));

      // Қадам 0,5 кг: бошланғич 0,5 → + → 1 кг; сатр суммаси 5 000.
      final card = _k('sm_offer_o_red_cheap');
      await t.tap(find.descendant(of: card, matching: _k('sm_qty_inc')));
      await t.pump();
      expect(t.widget<Text>(_k('sm_offer_total_o_red_cheap')).data, formatMoney(5000));
      await t.tap(_k('sm_offer_add_o_red_cheap'));
      await t.pump();
      expect(_k('sm_added_snack'), findsOneWidget);
      await t.tap(_k('sm_offer_add_o_red_cheap'));
      await t.ensureVisible(_k('sm_offer_add_o_red_exp'));
      await t.tap(_k('sm_offer_add_o_red_exp'));
      await t.pump();
      expect(c.cart.lines.map((l) => '${l.productId}:${l.qtyMilli}'), ['o_red_cheap:2000', 'o_red_exp:500']);
      // Сақланди (илова қайта очилганда ҳам).
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      final stored = await t.runAsync(() => SmCartStore().load());
      expect(stored!.count, 2);
    });

    testWidgets('пакет: бирлик нархи кўрсатилади', (t) async {
      final c = _controller();
      await t.pumpWidget(_app(SmGroupScreen(controller: c, group: smTaxonomyFixture.group('milk')!)));
      await t.pumpAndSettle();
      expect(_k('sm_offer_unit_price_m1'), findsOneWidget);
    });

    testWidgets('саватдан «Ўзгартириш»: бошқа таклиф танланса — алмашади', (t) async {
      final c = _controller(cart: SmCart.empty.add('o_red_exp', 1000));
      await t.pumpWidget(_app(SmCartScreen(controller: c)));
      await t.pumpAndSettle();
      await t.tap(_k('sm_cart_edit_o_red_exp'));
      await t.pumpAndSettle();
      expect(find.text('sm_choose_this'), findsWidgets);
      await t.tap(_k('sm_offer_add_o_red_cheap'));
      await t.pumpAndSettle();
      expect(c.cart.lines.map((l) => l.productId), ['o_red_cheap']);
    });
  });

  group('4. сават', () {
    testWidgets('±, олиб ташлаш, жами; тугаган қатор — расмийлаштириш ўчиқ', (t) async {
      await tall(t);
      final c = _controller(cart: SmCart.empty.add('o_red_cheap', 1000).add('o_red_oos', 500));
      await t.pumpWidget(_app(SmCartScreen(controller: c)));
      await t.pumpAndSettle();
      expect(t.widget<Text>(_k('sm_cart_goods_total')).data, formatMoney(5000));
      expect(t.widget<FilledButton>(_k('sm_checkout_btn')).onPressed, isNull);
      expect(_k('sm_cart_unavailable_note'), findsOneWidget);
      await t.tap(_k('sm_cart_remove_o_red_oos'));
      await t.pump();
      expect(t.widget<FilledButton>(_k('sm_checkout_btn')).onPressed, isNotNull);
      await t.tap(find.descendant(of: _k('sm_cart_line_o_red_cheap'), matching: _k('sm_qty_inc')));
      await t.pump();
      expect(c.cart.qtyOf('o_red_cheap'), 1500);
      for (var i = 0; i < 3; i++) {
        await t.tap(find.descendant(of: _k('sm_cart_line_o_red_cheap'), matching: _k('sm_qty_dec')));
        await t.pump();
      }
      expect(c.cart.isEmpty, isTrue, reason: '0 — қатор олиб ташланади');
      expect(_k('sm_cart_empty'), findsOneWidget);
    });
  });

  group('5. расмийлаштириш', () {
    Future<void> fill(WidgetTester t) async {
      await t.pumpAndSettle();
      await t.enterText(_k('sm_addr_phone'), '+998 90 123 45 67');
      await t.ensureVisible(_k('sm_slot_s1'));
      await t.tap(_k('sm_slot_s1'));
      await t.pump();
    }

    testWidgets('тармоқ хатосида қайта уриниш — ЎША clientRequestId; муваффақиятдан кейин сават бўш', (t) async {
      await tall(t);
      final api = FakeSupermarketApi()..placeResults.add(const SmCallError('sm_err_network', 'unavailable'));
      final c = _controller(api: api, cart: SmCart.empty.add('o_red_cheap', 1000));
      var n = 0;
      await t.pumpWidget(_app(SmCheckoutScreen(
        controller: c,
        balance: Stream.value(1000000),
        keys: IdempotencyKeys(generator: () => 'key-${++n}'),
        pickArea: (_) async => null,
      )));
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(_k('sm_confirm')).onPressed, isNull, reason: 'вақт танланмаган');
      await fill(t);
      await t.ensureVisible(_k('sm_confirm'));
      await t.tap(_k('sm_confirm'));
      await t.pumpAndSettle();
      expect(_k('sm_checkout_error'), findsOneWidget);
      await t.tap(_k('sm_confirm'));
      await t.pumpAndSettle();
      expect(api.payloads.map((p) => p['clientRequestId']), ['key-1', 'key-1']);
      expect(api.payloads.last['slotId'], 's1');
      expect(api.payloads.last['day'], 'today');
      expect((api.payloads.last['address'] as Map)['phone'], '+998 90 123 45 67');
      expect(_k('sm_order_done'), findsOneWidget);
      expect(c.cart.isEmpty, isTrue);
    });

    testWidgets('юбориш пайтида тугма ўчиқ (иккинчи босиш — иккинчи буюртма эмас)', (t) async {
      await tall(t);
      final done = Completer<SmPlaceResult>();
      final api = FakeSupermarketApi()..placeResults.add(done.future);
      final c = _controller(api: api, cart: SmCart.empty.add('o_red_cheap', 1000));
      await t.pumpWidget(_app(SmCheckoutScreen(controller: c, balance: Stream.value(1000000))));
      await fill(t);
      await t.ensureVisible(_k('sm_confirm'));
      await t.tap(_k('sm_confirm'));
      await t.pump();
      expect(t.widget<FilledButton>(_k('sm_confirm')).onPressed, isNull);
      await t.tap(_k('sm_confirm'), warnIfMissed: false);
      expect(api.payloads.length, 1);
      done.complete(const SmPlaceResult(orderId: 'o', goodsTotal: 1, fee: 1, hold: 2));
      await t.pumpAndSettle();
    });

    testWidgets('сервер рад этса — янги калит; ҳамён етмаса — тўлдириш (етишмаган сумма)', (t) async {
      await tall(t);
      final api = FakeSupermarketApi()
        ..placeResults.add(const SmCallError('sm_err_insufficient_funds', 'failed-precondition'));
      final c = _controller(api: api, cart: SmCart.empty.add('o_red_cheap', 2000));
      var n = 0;
      int? topUp;
      await t.pumpWidget(_app(SmCheckoutScreen(
        controller: c,
        balance: Stream.value(1000),
        keys: IdempotencyKeys(generator: () => 'key-${++n}'),
        openTopUp: (_, s) => topUp = s,
      )));
      await fill(t);
      // goods 10 000 + 10% тортиладиган 1 000 + 11% 1 100 = 12 100; ҳамёнда 1 000.
      expect(t.widget<Text>(_k('sm_hold')).data, formatMoney(12100));
      expect(t.widget<Text>(_k('sm_weighed_hold')).data, formatMoney(1000));
      await t.ensureVisible(_k('sm_topup'));
      await t.tap(_k('sm_topup'));
      expect(topUp, 11100);
      await t.ensureVisible(_k('sm_confirm'));
      await t.tap(_k('sm_confirm'));
      await t.pumpAndSettle();
      expect(find.text('sm_err_insufficient_funds'), findsOneWidget);
      await t.tap(_k('sm_confirm'));
      await t.pumpAndSettle();
      expect(api.payloads.map((p) => p['clientRequestId']), ['key-1', 'key-2']);
    });
  });

  group('5b. сервер матни ва туман рухсати', () {
    testWidgets('туман бўйича рухсат сўралади; рад — сервер матни, тугма ўчиқ', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = FakeSupermarketApi(
        access: const SmAccess(
          allowed: false,
          reason: 'DISTRICT_NOT_SERVED',
          messages: {'uz_Cyrl': 'Бу ҳудудга ҳозирча етказиб бермаймиз.', 'uz_Latn': 'x', 'ru': 'y'},
        ),
      );
      final c = _controller(api: api, cart: SmCart.empty.add('o_red_cheap', 1000));
      await t.pumpWidget(_app(SmCheckoutScreen(controller: c, balance: Stream.value(1000000))));
      await t.pumpAndSettle();
      expect(api.accessDistricts, ['gurlan']);
      expect(find.text('Бу ҳудудга ҳозирча етказиб бермаймиз.'), findsOneWidget);
      expect(t.widget<FilledButton>(_k('sm_confirm')).onPressed, isNull);
    });

    testWidgets('буюртма рад этилса — сервер берган 3 тилли матн кўрсатилади', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = FakeSupermarketApi()
        ..placeResults.add(const SmCallError('sm_err_out_of_stock', 'OUT_OF_STOCK',
            messages: {'uz_Cyrl': 'Маҳсулот етарли эмас.', 'uz_Latn': 'Mahsulot yetarli emas.', 'ru': 'Недостаточно товара.'}));
      final c = _controller(api: api, cart: SmCart.empty.add('o_red_cheap', 1000));
      await t.pumpWidget(_app(SmCheckoutScreen(controller: c, balance: Stream.value(1000000))));
      await t.pumpAndSettle();
      await t.enterText(_k('sm_addr_phone'), '+998901234567');
      await t.tap(_k('sm_slot_s1'));
      await t.pump();
      await t.tap(_k('sm_confirm'));
      await t.pumpAndSettle();
      expect(find.text('Маҳсулот етарли эмас.'), findsOneWidget);
    });
  });

  group('6b. мижоз бекори', () {
    OrderModel o(String status) =>
        OrderModel(id: 'ord1', type: 'platform', subtype: 'supermarket', total: 1, status: status, items: const []);
    testWidgets('new — тугма, тасдиқдан кейин сервер чақирилади', (t) async {
      final calls = <String>[];
      await t.pumpWidget(_app(Scaffold(body: SmOrderCancelBar(order: o('new'), cancel: (id) async => calls.add(id)))));
      await t.tap(_k('sm_cancel_btn'));
      await t.pumpAndSettle();
      await t.tap(_k('sm_cancel_confirm'));
      await t.pumpAndSettle();
      expect(calls, ['ord1']);
      expect(_k('sm_cancel_done'), findsOneWidget);
    });
    testWidgets('accepted — тугма йўқ, дўстона изоҳ; delivered — ҳеч нарса', (t) async {
      await t.pumpWidget(_app(Scaffold(body: SmOrderCancelBar(order: o('accepted'), cancel: (_) async {}))));
      expect(_k('sm_cancel_btn'), findsNothing);
      expect(_k('sm_cancel_unavailable'), findsOneWidget);
      await t.pumpWidget(_app(Scaffold(body: SmOrderCancelBar(order: o('delivered'), cancel: (_) async {}))));
      expect(_k('sm_cancel_unavailable'), findsNothing);
    });
  });

  group('6. буюртма ҳолати', () {
    testWidgets('5 босқич: ready → 3 таси ёниқ', (t) async {
      await t.pumpWidget(_app(const Scaffold(body: SmOrderProgressView(status: 'ready'))));
      expect(_k('sm_step_accepted_on'), findsOneWidget);
      expect(_k('sm_step_preparing_on'), findsOneWidget);
      expect(_k('sm_step_ready_on'), findsOneWidget);
      expect(_k('sm_step_courier_off'), findsOneWidget);
      expect(_k('sm_step_delivered_off'), findsOneWidget);
      await t.pumpWidget(_app(const Scaffold(body: SmOrderProgressView(status: '???'))));
      expect(_k('sm_order_progress'), findsNothing);
    });
  });

  group('бош саҳифа дарвозаси', () {
    Future<void> pump(WidgetTester t, {required bool module, required bool allowed}) async {
      await t.binding.setSurfaceSize(const Size(400, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeMarketsBlock(
              key: ValueKey('$module-$allowed'),
              onOpen: (_) {},
              isVisible: (id) => id == 'supermarket' ? module : true,
              loadSupermarketAccess: () async => allowed,
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('модул ВА сервер рухсати бўлса — блок ТЕПАСИДА; акс ҳолда йўқ', (t) async {
      await pump(t, module: true, allowed: true);
      final sm = _k('home_lite_card_market_supermarket');
      expect(sm, findsOneWidget);
      expect(t.getTopLeft(sm).dy, lessThan(t.getTopLeft(_k('home_lite_card_market_electronics')).dy));
      await pump(t, module: true, allowed: false);
      expect(_k('home_lite_card_market_supermarket'), findsNothing);
      await pump(t, module: false, allowed: true);
      expect(_k('home_lite_card_market_supermarket'), findsNothing);
    });

    test('visibleHomeMarkets: рухсатсиз супермаркет йўқ', () {
      expect(visibleHomeMarkets((_) => true).first.id, isNot('supermarket'));
      expect(visibleHomeMarkets((_) => true, supermarketAllowed: true).first.id, 'supermarket');
      expect(File(kHomeMarketEntries.first.imagePath!).existsSync(), isTrue);
    });
  });

  group('Улгуржи / Аралаш', () {
    test('Улгуржида platform_products йўқ (kPlatformInWholesale=false); Аралаш белгиси', () {
      expect(kPlatformInWholesale, isFalse);
      final src = File('lib/features/wholesale/screens/wholesale_market_screen.dart').readAsStringSync();
      expect(src.contains('kPlatformInWholesale'), isTrue, reason: 'Улгуржи экрани байроқни ўқийди');
      const sm = PlatformProduct(id: 'a', name: 'A', price: 1, supermarketGroupId: 'onion');
      const plain = PlatformProduct(id: 'b', name: 'B', price: 1);
      expect(aralashPlatformBadgeKey(sm), 'sm_badge');
      expect(aralashPlatformBadgeKey(plain), 'wholesale_screen_title');
      expect(sm.isSupermarket, isTrue);
    });
  });

  group('катта шрифт 1.5 / 320 px — overflow йўқ', () {
    for (final screen in ['home', 'group', 'cart', 'checkout']) {
      testWidgets(screen, (t) async {
        await t.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final c = _controller(cart: SmCart.empty.add('o_red_cheap', 1500).add('m1', 1000));
        final w = switch (screen) {
          'home' => SupermarketHomeScreen(controller: c),
          'group' => SmGroupScreen(controller: c, group: smTaxonomyFixture.group('onion')!),
          'cart' => SmCartScreen(controller: c),
          _ => SmCheckoutScreen(controller: c, balance: Stream.value(10)),
        };
        await t.pumpWidget(_app(w, textScale: 1.5));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        // Пастгача айлантириб — ҳамма қисм чизилсин.
        final list = find.byType(Scrollable).first;
        await t.drag(list, const Offset(0, -3000));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  test('lang: sm_* калитлари 3 тилда; лотинда янги ҳарфлар (o\' g\' sh ch йўқ)', () {
    Map<String, dynamic> read(String l) => jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;
    final cyr = read('uz_Cyrl'), lat = read('uz_Latn'), ru = read('ru');
    final used = <String>{};
    for (final f in Directory('lib/features/supermarket').listSync(recursive: true).whereType<File>()) {
      for (final m in RegExp(r"tr\(\s*'((?:sm|home_market_supermarket)_[a-z_]+)'").allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    used.addAll(['sm_badge', 'sm_title', 'home_market_supermarket_title', 'home_market_supermarket_slogan']);
    used.addAll(['kg', 'l', 'piece', 'pack', 'bunch'].map((u) => 'sm_unit_$u'));
    used.addAll(kSmOrderStepKeys.values);
    used.addAll(kSmErrorKeys.values);
    used.addAll(['sm_err_network', 'sm_err_generic', 'sm_err_load', 'sm_day_today', 'sm_day_tomorrow']);
    used.removeWhere((k) => k == 'sm_unit_' || k == 'sm_day_' || k.endsWith('_'));
    final keys = {...cyr.keys.where((k) => k.startsWith('sm_')), ...used};
    for (final k in keys) {
      for (final m in [cyr, lat, ru]) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: k);
      }
      final v = lat[k] as String;
      expect(RegExp("[oOgG]['ʻ‘’]").hasMatch(v), isFalse, reason: '$k: $v');
      expect(RegExp(r'sh|ch|Sh|Ch').hasMatch(v), isFalse, reason: '$k: $v');
      expect(RegExp('[Ѐ-ӿ]').hasMatch(v), isFalse, reason: '$k: $v');
    }
    expect(cyr['sm_search_hint'], 'Қайси маҳсулот керак?');
    expect(cyr['sm_out_of_stock'], 'Ҳозир мавжуд эмас');
    expect(cyr['home_market_supermarket_title'], 'AVA Супермаркет');
  });
}

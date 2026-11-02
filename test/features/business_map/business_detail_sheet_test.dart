import 'dart:async';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_pin.dart';
import 'package:ava_gurlan/features/business_map/domain/pin_filter.dart';
import 'package:ava_gurlan/features/business_map/widgets/business_detail_sheet.dart';
import 'package:ava_gurlan/features/deal_chat/data/deal_chat_repository.dart';
import 'package:ava_gurlan/features/deal_chat/screens/deal_chat_screen.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_screen.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:ava_gurlan/features/tv_market/services/shop_stats_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Объект варағидаги маҳсулотлар қатори учун: каталог бўш (Firebase'сиз).
class _NoShop extends Fake implements TvShopRepository {
  @override
  Future<List<TvShopItem>> fetchByBusiness(
    String businessId, {
    String ownerPhone = '',
    bool onlyActive = true,
    int limit = 200,
  }) async =>
      const [];
}

/// Битта сўровда берилган таклифлар.
class _OneShop extends Fake implements TvShopRepository {
  _OneShop(this.items);
  final List<TvShopItem> items;
  @override
  Future<List<TvShopItem>> fetchByBusiness(
    String businessId, {
    String ownerPhone = '',
    bool onlyActive = true,
    int limit = 200,
  }) async =>
      items;
}

/// «Ёзиш» чати: очиш чақирувлари ёзилади, чат экрани бўш оқимлар билан (Firebase'сиз).
class _FakeDeal extends Fake implements DealChatRepository {
  final openCalls = <(String, String)>[];
  @override
  Future<String> openChat(String productId, {String source = 'wholesale'}) async {
    openCalls.add((productId, source));
    return 'bz-${productId}_998902222222';
  }

  @override
  Stream<DealChat?> watchChat(String chatId) => const Stream.empty();
  @override
  Stream<List<DealMessage>> watchMessages(String chatId, {int limit = 200}) => const Stream.empty();
}

/// Ресторанга уланган объект варағи — ҳақиқий модал варақда ([BusinessDetailSheet.show] каби), ўқиш ва экран
/// очиш сохта.
Future<void> _openLinked(
  WidgetTester tester,
  BusinessPin pin, {
  required Future<Restaurant?> Function(String id) load,
  required void Function(Widget screen) push,
}) async {
  tester.view.physicalSize = const Size(400 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(), // ҳар чақирувда янги дарахт (бир тестда бир неча марта очилади)
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                useSafeArea: true,
                builder: (_) => BusinessDetailSheet(pin: pin, shopRepository: _NoShop(), loadRestaurant: load, pushScreen: push),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

BusinessPin _linkedBiz({String restaurantId = 'r1', String status = 'active'}) => BusinessPin.fromBusiness(Business(
      id: 'b1',
      ownerId: '998901111111',
      name: 'Бахор кафе',
      category: BusinessCategory.food,
      phone: '998901234567',
      lat: 41.84,
      lng: 60.39,
      restaurantId: restaurantId,
      status: status,
    ));

Restaurant _rest({String status = 'approved'}) =>
    Restaurant.fromMap('r1', {'name': 'Бахор кафе', 'status': status, 'lat': 41.84, 'lng': 60.39});

/// Локализация делегати АТАЙЛАБ уланмаган: `context.tr` калитнинг ўзини қайтаради.
Future<void> _open(WidgetTester tester, BusinessPin pin) async {
  tester.view.physicalSize = const Size(400 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => BusinessDetailSheet.show(context, pin),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

BusinessPin _biz({String phone = '998901234567', String hours = '09:00–21:00'}) => BusinessPin(
      source: BusinessSource.business,
      id: 'b1',
      name: 'Гурлан авто-мойка',
      category: BusinessCategory.auto,
      lat: 41.84,
      lng: 60.39,
      subtitle: 'авто-мойка',
      description: 'Ҳар куни очиқ',
      phone: phone,
      address: 'Гурлан, Навоий кўчаси 5',
      hours: hours,
      website: 'example.uz',
    );

void main() {
  group('BusinessDetailSheet', () {
    testWidgets('тўлиқ маълумот: ном, тур, тавсиф, манзил, иш вақти, телефон, сайт ва тугмалар', (tester) async {
      await _open(tester, _biz());
      expect(find.text('Гурлан авто-мойка'), findsOneWidget);
      expect(find.text('business_cat_auto'), findsOneWidget);
      expect(find.text('авто-мойка'), findsOneWidget);
      expect(find.text('Ҳар куни очиқ'), findsOneWidget);
      expect(find.text('Гурлан, Навоий кўчаси 5'), findsOneWidget);
      expect(find.text('09:00–21:00'), findsOneWidget);
      expect(find.text('998901234567'), findsOneWidget);
      expect(find.text('example.uz'), findsOneWidget);
      expect(find.text('bizmap_call'), findsOneWidget);
      expect(find.text('bizmap_route'), findsOneWidget);
      // оддий объектда модул экрани тугмалари йўқ
      expect(find.text('bizmap_open_menu'), findsNothing);
      expect(find.text('bizmap_open_ev'), findsNothing);
    });

    testWidgets('бўш майдонлар қатор чиқармайди; телефонсиз — «қўнғироқ» йўқ, «йўналиш» бор', (tester) async {
      const pin = BusinessPin(
        source: BusinessSource.business,
        id: 'b2',
        name: 'Дўкон',
        category: BusinessCategory.retail,
        lat: 41.3,
        lng: 69.2,
      );
      await _open(tester, pin);
      expect(find.text('Дўкон'), findsOneWidget);
      expect(find.byIcon(Icons.phone_outlined), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      expect(find.byIcon(Icons.place_outlined), findsNothing);
      expect(find.text('bizmap_call'), findsNothing);
      expect(find.text('bizmap_route'), findsOneWidget);
    });

    testWidgets('кафе: «менюни очиш» тугмаси; зарядка: «станциялар» тугмаси', (tester) async {
      final r = Restaurant.fromMap('r1', {
        'name': 'Ошхона', 'status': 'approved', 'lat': 41.8, 'lng': 60.3, 'contactPhone': '998901112233',
      });
      await _open(tester, BusinessPin.fromRestaurant(r)!);
      expect(find.text('bizmap_open_menu'), findsOneWidget);
      expect(find.text('bizmap_open_ev'), findsNothing);
    });

    testWidgets('EV нуқтаси: ўз экранини очиш тугмаси', (tester) async {
      const pin = BusinessPin(
        source: BusinessSource.evStation,
        id: 'e1',
        name: 'TOK BOR',
        category: BusinessCategory.auto,
        lat: 41.3,
        lng: 69.2,
      );
      await _open(tester, pin);
      expect(find.text('bizmap_open_ev'), findsOneWidget);
      expect(find.text('bizmap_open_menu'), findsNothing);
    });
  });

  group('BusinessDetailSheet — ресторан бўлимига уланган объект (битта белги, эга 2026-11-03)', () {
    final sent = <Map<String, Object?>>[];
    setUp(() {
      sent.clear();
      ShopStatsRecorder.resetForTest();
      ShopStatsRecorder.sink = (d) async => sent.add(d);
    });
    tearDown(() => ShopStatsRecorder.sink = null);

    testWidgets('«Меню» бор (дўкон тугмаси ҳам); босилса — ўқиш пайтида айланувчи белги, кейин варақ ёпилиб меню очилади',
        (tester) async {
      final gate = Completer<Restaurant?>();
      final asked = <String>[];
      final pushed = <Widget>[];
      await _openLinked(tester, _linkedBiz(), load: (id) {
        asked.add(id);
        return gate.future;
      }, push: pushed.add);
      expect(find.byKey(const ValueKey('biz_open_menu')), findsOneWidget);
      expect(find.text('bizmap_open_menu'), findsOneWidget);
      expect(find.byKey(const ValueKey('biz_open_shop')), findsOneWidget, reason: 'кафенинг маҳсулотлари бўлиши мумкин');

      await tester.tap(find.byKey(const ValueKey('biz_open_menu')));
      await tester.pump();
      expect(find.byKey(const ValueKey('biz_open_menu_loading')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('biz_open_menu')));
      await tester.pump();
      expect(asked, ['r1'], reason: 'ўқиш пайтида иккинчи босиш янги сўров очмайди');

      gate.complete(_rest());
      await tester.pumpAndSettle();
      expect(pushed, hasLength(1));
      expect(pushed.single, isA<RestaurantScreen>());
      expect((pushed.single as RestaurantScreen).restaurant.id, 'r1');
      expect(find.text('Бахор кафе'), findsNothing, reason: 'варақ ёпилди');
      expect(sent, [
        {'kind': 'restaurant_view', 'restaurantId': 'r1', 'source': 'map'},
      ]);
    });

    testWidgets('уланмаган ёки блокланган объектда «Меню» йўқ', (tester) async {
      Future<Restaurant?> load(String _) async => fail('ўқилмаслиги керак');
      await _openLinked(tester, _linkedBiz(restaurantId: ''), load: load, push: (_) => fail('очилмаслиги керак'));
      expect(find.byKey(const ValueKey('biz_open_menu')), findsNothing);
      expect(find.text('bizmap_open_menu'), findsNothing);

      await _openLinked(tester, _linkedBiz(status: 'blocked'), load: load, push: (_) => fail('очилмаслиги керак'));
      expect(find.byKey(const ValueKey('biz_open_menu')), findsNothing);
    });

    testWidgets('ресторан йўқ / тасдиқланмаган / ўқиб бўлмади — «вақтинча мавжуд эмас», меню очилмайди, кўриш ёзилмайди',
        (tester) async {
      final loads = <Future<Restaurant?> Function(String)>[
        (_) async => null,
        (_) async => _rest(status: 'suspended'),
        (_) async => throw Exception('permission-denied'),
      ];
      for (final load in loads) {
        final pushed = <Widget>[];
        await _openLinked(tester, _linkedBiz(), load: load, push: pushed.add);
        await tester.tap(find.byKey(const ValueKey('biz_open_menu')));
        await tester.pumpAndSettle();
        expect(pushed, isEmpty);
        expect(find.text('tv_market_restaurant_unavailable'), findsOneWidget);
        // Варақ ёпилади: хабар харита экранида, варақ уни ёпиб турмасин.
        expect(find.byKey(const ValueKey('biz_open_menu')), findsNothing);
        expect(find.text('open'), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.text('open'))).removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }
      expect(sent, isEmpty);
    });
  });

  group('BusinessDetailSheet — харидор юзаси S3 (эга 2026-11-03)', () {
    const owner = '998901111111';
    const me = '998902222222';

    BusinessPin bizPin({String ownerId = owner, String status = 'active', BusinessCategory cat = BusinessCategory.personal}) =>
        BusinessPin.fromBusiness(Business(
          id: 'b1',
          ownerId: ownerId,
          name: 'Гулбаҳор салони',
          category: cat,
          phone: '998901234567',
          lat: 41.84,
          lng: 60.39,
          status: status,
        ));

    Future<_FakeDeal> openBiz(WidgetTester tester, BusinessPin pin, {String? myPhone}) async {
      SharedPreferences.setMockInitialValues({if (myPhone != null) 'user_phone': myPhone});
      final repo = _FakeDeal();
      tester.view.physicalSize = const Size(400 * 2, 1600 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => BusinessDetailSheet(pin: pin, shopRepository: _NoShop(), dealChatRepository: repo),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('бошқанинг объекти: «Ёзиш» бор; босилса — source business, productId = объект ID, чат очилади',
        (tester) async {
      final repo = await openBiz(tester, bizPin(), myPhone: me);
      expect(find.byKey(const ValueKey('biz_write')), findsOneWidget);
      expect(find.text('deal_chat_write'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('biz_write')));
      // Чат экрани хабар кутиб айланувчи белги кўрсатади — pumpAndSettle эмас.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(repo.openCalls, [('b1', 'business')]);
      expect(find.byType(DealChatScreen), findsOneWidget);
      // Чат ёпилса — варақ қайтади.
      Navigator.of(tester.element(find.byType(DealChatScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biz_write')), findsOneWidget);
    });

    testWidgets('ўз объекти (рақам шакли фарқ қилса ҳам) — «Ёзиш» йўқ', (tester) async {
      await openBiz(tester, bizPin(), myPhone: '+998 90 111 11 11');
      expect(find.byKey(const ValueKey('biz_write')), findsNothing);
      expect(find.byKey(const ValueKey('biz_open_shop')), findsOneWidget, reason: 'бошқа тугмалар жойида');
    });

    testWidgets('блокланган ёки эгасиз объект — «Ёзиш» йўқ', (tester) async {
      await openBiz(tester, bizPin(status: 'blocked'), myPhone: me);
      expect(find.byKey(const ValueKey('biz_write')), findsNothing);
      await openBiz(tester, bizPin(ownerId: 'admin'), myPhone: me);
      expect(find.byKey(const ValueKey('biz_write')), findsNothing);
    });

    testWidgets('меҳмон: «Ёзиш» бор; босилса — сервер чақирилмайди, варақ ёпилади, рўйхатдан ўтиш хабари',
        (tester) async {
      final repo = await openBiz(tester, bizPin());
      await tester.tap(find.byKey(const ValueKey('biz_write')));
      await tester.pumpAndSettle();
      expect(repo.openCalls, isEmpty);
      expect(find.byKey(const ValueKey('biz_write')), findsNothing, reason: 'варақ ёпилди');
      expect(find.text('deal_chat_login_required'), findsOneWidget);
    });

    testWidgets('каталог тугмаси тур профилидан: хизмат / дўкон / овқатланиш', (tester) async {
      await openBiz(tester, bizPin(), myPhone: me);
      expect(find.text('biz_open_services'), findsOneWidget);
      expect(find.text('shop_go_to_shop'), findsNothing);
      await openBiz(tester, bizPin(cat: BusinessCategory.retail), myPhone: me);
      expect(find.text('shop_go_to_shop'), findsOneWidget);
      await openBiz(tester, bizPin(cat: BusinessCategory.food), myPhone: me);
      expect(find.text('biz_open_page'), findsOneWidget);
    });

    testWidgets('таклифлар қатори сарлавҳаси — тур профилидан', (tester) async {
      SharedPreferences.setMockInitialValues({'user_phone': me});
      final item = TvShopItem(
        id: 's1', ownerPhone: owner, ownerName: 'x', title: 'Соч олиш', price: 30000, photoUrl: '',
        kind: 'service', districtId: 'd', districtLabel: '', businessId: 'b1',
      );
      tester.view.physicalSize = const Size(400 * 2, 1600 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: BusinessDetailSheet(pin: bizPin(), shopRepository: _OneShop([item]), dealChatRepository: _FakeDeal())),
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('biz_products_title'))).data, 'biz_catalog_services');
    });

    group('кўриш статистикаси', () {
      final sent = <Map<String, Object?>>[];
      setUp(() {
        sent.clear();
        ShopStatsRecorder.resetForTest();
        ShopStatsRecorder.sink = (d) async => sent.add(d);
      });
      tearDown(() => ShopStatsRecorder.sink = null);

      test('эгаси бор объект варағи — shop_view (объект, map), бир марта', () {
        BusinessDetailSheet.recordView(bizPin());
        BusinessDetailSheet.recordView(bizPin());
        expect(sent, [
          {'kind': 'shop_view', 'ownerPhone': owner, 'businessId': 'b1', 'source': 'map'},
        ]);
      });

      test('блокланган, эгасиз объект ва бошқа нуқталар — ёзилмайди', () {
        BusinessDetailSheet.recordView(bizPin(status: 'blocked'));
        BusinessDetailSheet.recordView(bizPin(ownerId: 'admin'));
        BusinessDetailSheet.recordView(_biz());
        expect(sent, isEmpty);
      });
    });
  });

  group('filterPins / categoriesPresent', () {
    BusinessPin p(String name, BusinessCategory c, {String sub = '', String addr = ''}) => BusinessPin(
          source: BusinessSource.business, id: name, name: name, category: c, lat: 1, lng: 1, subtitle: sub, address: addr,
        );
    final pins = [
      p('Аvto Moyka', BusinessCategory.auto, sub: 'мойка'),
      p('Нон дўкони', BusinessCategory.retail, addr: 'Гурлан'),
      p('Кафе Бахор', BusinessCategory.food),
      p('Импорт база', BusinessCategory.foreignTrade),
    ];

    test('фильтрсиз — ҳаммаси; тур бўйича; ном/кичик тур/манзил бўйича (регистрсиз)', () {
      expect(filterPins(pins).length, 4);
      expect(filterPins(pins, category: BusinessCategory.food).map((e) => e.name), ['Кафе Бахор']);
      expect(filterPins(pins, query: 'НОН').map((e) => e.name), ['Нон дўкони']);
      expect(filterPins(pins, query: 'мойка').map((e) => e.name), ['Аvto Moyka']);
      expect(filterPins(pins, query: 'гурлан').map((e) => e.name), ['Нон дўкони']);
      expect(filterPins(pins, query: '   ').length, 4);
    });

    test('тур ва қидирув бирга; ҳеч нарса топилмаса — бўш', () {
      expect(filterPins(pins, category: BusinessCategory.auto, query: 'нон'), isEmpty);
      expect(filterPins(pins, category: BusinessCategory.retail, query: 'нон').length, 1);
    });

    test('categoriesPresent: фақат бор турлар, enum тартибида', () {
      expect(categoriesPresent(pins), [
        BusinessCategory.retail,
        BusinessCategory.food,
        BusinessCategory.auto,
        BusinessCategory.foreignTrade,
      ]);
      expect(categoriesPresent(const []), isEmpty);
    });
  });
}

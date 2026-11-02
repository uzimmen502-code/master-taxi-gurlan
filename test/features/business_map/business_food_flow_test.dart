// «Менинг бизнесим» овқатланиш объекти → ресторан бўлими (меню) занжири (эга, 2026-11-03).
// Firebase'сиз: репозиторийлар алмаштирилган; матн — калитнинг ўзи (локализациясиз).

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/business_food_flow.dart';
import 'package:ava_gurlan/features/business_map/data/business_repository.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_subtypes.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/domain/venue_type.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_panel_screen.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_form.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BizRepo extends BusinessRepository {
  final links = <String>[];
  Object? linkFailsWith;

  @override
  Future<void> linkRestaurant(String businessId, String restaurantId) async {
    links.add('$businessId->$restaurantId');
    if (linkFailsWith != null) throw linkFailsWith!;
  }
}

class _RestRepo implements RestaurantsRepository {
  _RestRepo(this.mine, {this.failMine = false});

  final List<Restaurant> mine;
  final bool failMine;
  final watchedOwners = <String>[];

  @override
  Stream<List<Restaurant>> watchMine(String ownerUid) {
    watchedOwners.add(ownerUid);
    return failMine ? Stream.error(StateError('offline')) : Stream.value(mine);
  }

  // Панел очилганини текшириш учун етарли: ресторан ҳужжати йўқ — «топилмади» ҳолати.
  @override
  Stream<Restaurant?> watchRestaurant(String id) => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Business _food(
  String id, {
  String subtype = '',
  String restaurantId = '',
  bool online = false,
  BusinessCategory category = BusinessCategory.food,
  String openingHours = '',
}) =>
    Business(
      id: id,
      ownerId: '998901111111',
      name: 'Gurlan osh markazi',
      category: category,
      subtype: subtype,
      description: 'Milliy taomlar',
      phone: '998907654321',
      lat: online ? 0 : 41.84,
      lng: online ? 0 : 60.39,
      address: online ? '' : 'Gurlan, Navoiy ko‘chasi 5',
      online: online,
      restaurantId: restaurantId,
      openingHours: openingHours,
    );

const _cafe1 = Restaurant(id: 'c1', name: 'Plov markazi', legalType: 'yatt', ownerUid: '998901111111', status: 'approved');
const _cafe2 = Restaurant(id: 'c2', name: 'Choyxona 2', legalType: 'llc', ownerUid: '998901111111', status: 'applied');
const _home1 = Restaurant(id: 'h1', name: 'Uy oshxonasi', legalType: 'individual', ownerUid: '998901111111', status: 'approved');

Future<void> _run(
  WidgetTester t,
  Business b, {
  required _BizRepo biz,
  required _RestRepo rest,
  Set<String> linked = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(1200 * 2, 2400 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => openBusinessMenuFlow(
            context,
            b,
            businessRepo: biz,
            restaurantsRepo: rest,
            linkedRestaurantIds: linked,
          ),
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
}

void main() {
  group('соф қоидалар', () {
    test('менюга фақат харитадаги овқатланиш объекти уланади', () {
      expect(businessCanHaveMenu(_food('f1')), isTrue);
      expect(businessCanHaveMenu(_food('f1', online: true)), isFalse, reason: 'онлайн — сервер BUSINESS_ONLINE');
      expect(businessCanHaveMenu(_food('r1', category: BusinessCategory.retail)), isFalse);
      expect(businessCanHaveMenu(_food('a1', category: BusinessCategory.auto)), isFalse);
      expect(businessCanHaveMenu(Business.ownShop(ownerId: '998901111111', name: 'Do‘kon')), isFalse);
    });

    test('уй ошпази тури исталган тил/ёзувда аниқланади', () {
      for (final s in ['Уй ошпази', 'Uy oshpazi', 'Домашний повар', 'Уйда овқат тайёрлаш', 'uyda ovqat tayyorlash', '  уй ошпази ']) {
        expect(isHomeCookBusiness(_food('f', subtype: s)), isTrue, reason: s);
      }
      for (final s in ['', 'Кафе', 'Ресторан', 'Ошхона', 'Ошпаз', 'Уй ошпазим']) {
        expect(isHomeCookBusiness(_food('f', subtype: s)), isFalse, reason: s);
      }
    });

    test('муассаса тури: Ресторан → restaurant, Чойхона → chaikhana, бошқаси → cafe, уй ошпази → йўқ', () {
      expect(venueTypeForBusiness(_food('f', subtype: 'Ресторан')), VenueType.restaurant);
      expect(venueTypeForBusiness(_food('f', subtype: 'Restoran')), VenueType.restaurant);
      expect(venueTypeForBusiness(_food('f', subtype: 'Чойхона')), VenueType.chaikhana);
      expect(venueTypeForBusiness(_food('f', subtype: 'Choyxona')), VenueType.chaikhana);
      expect(venueTypeForBusiness(_food('f', subtype: 'Чайхана')), VenueType.chaikhana, reason: 'рус номи');
      for (final s in ['', 'Кафе', 'Ошхона', 'Пицца', 'Қаҳвахона', 'Бобомнинг ошхонаси']) {
        expect(venueTypeForBusiness(_food('f', subtype: s)), VenueType.cafe, reason: s);
      }
      expect(venueTypeForBusiness(_food('f', subtype: 'Уй ошпази')), isNull);
    });

    test('мослаштиришда ишлатилган тайёр турлар «Аниқроқ тури» рўйхатида бор (номи ўзгарса тест йиқилади)', () {
      final food = [for (final e in BusinessSubtypes.data[BusinessCategory.food]!) e.$1];
      for (final s in [...kHomeCookFoodSubtypes, 'Ресторан', 'Чойхона']) {
        expect(food, contains(s));
      }
    });

    test('иш вақти: «09:00–21:00» каби матн тушунилади, қолгани — йўқ (сервер чегаралари)', () {
      expect(parseBusinessHours('09:00–21:00'), (open: '09:00', close: '21:00'));
      expect(parseBusinessHours('9:00-21:30'), (open: '09:00', close: '21:30'));
      expect(parseBusinessHours(' 9.00 — 22.00 '), (open: '09:00', close: '22:00'));
      expect(parseBusinessHours('00:00-23:59'), (open: '00:00', close: '23:59'));
      for (final s in ['', '09:00', 'har kuni', '24:00-10:00', '09:60-10:00', '09:00–21:00, dam olish yakshanba']) {
        expect(parseBusinessHours(s), isNull, reason: s);
      }
    });

    test('объектдан олдиндан тўлдириш: кафе формаси тўлиқ ва дарров тўғри', () {
      final p = restaurantPrefillFromBusiness(_food('f1', subtype: 'Ресторан', openingHours: '10:00–23:00'));
      expect(p.name, 'Gurlan osh markazi');
      expect(p.description, 'Milliy taomlar');
      expect(p.address, 'Gurlan, Navoiy ko‘chasi 5');
      expect(p.contactPhone, '998907654321');
      expect([p.lat, p.lng], [41.84, 60.39]);
      expect(p.venueType, VenueType.restaurant);
      expect([p.openTime, p.closeTime], ['10:00', '23:00']);

      final d = RestaurantFormData(legalType: RestaurantFormData.cafeLegalTypes.first, venueRequired: true);
      p.applyTo(d);
      expect(d.validate(), isEmpty);
      final payload = d.toRegisterPayload();
      expect(payload['venueType'], 'restaurant');
      expect(payload['openingHours'], {'open': '10:00', 'close': '23:00'});
      expect(payload['contactPhone'], '998907654321');
    });

    test('applyTo: бўш/нотўғри қиймат тегилмайди; уй ошпазида муассаса тури эътиборсиз', () {
      final d = RestaurantFormData(name: 'Eski', contactPhone: '998900000000');
      const RestaurantRegisterPrefill(lat: 41.0, venueType: 'restaurant', openTime: '25:00', closeTime: '10:00').applyTo(d);
      expect(d.name, 'Eski');
      expect(d.contactPhone, '998900000000');
      expect(d.hasLocation, isFalse, reason: 'фақат lat — жой қўйилмайди');
      expect(d.venueType, isNull, reason: 'уй ошпази (individual)');
      expect(d.alwaysOpen, isTrue);

      final cafe = RestaurantFormData(legalType: 'yatt');
      const RestaurantRegisterPrefill(venueType: 'home').applyTo(cafe);
      expect(cafe.venueType, isNull, reason: 'home — танлов рўйхатида йўқ');
    });
  });

  group('openBusinessMenuFlow', () {
    testWidgets('объект уланган — ресторан панели «Меню» таби билан, сўров ва улаш йўқ', (t) async {
      final biz = _BizRepo();
      final rest = _RestRepo(const [_cafe1]);
      await _run(t, _food('f1', restaurantId: 'r7'), biz: biz, rest: rest);
      final panel = t.widget<RestaurantPanelScreen>(find.byType(RestaurantPanelScreen));
      expect(panel.restaurantId, 'r7');
      expect(panel.initialTab, RestaurantPanelScreen.menuTab);
      expect(panel.initialTab, 1);
      expect(rest.watchedOwners, isEmpty);
      expect(biz.links, isEmpty);
    });

    testWidgets('овқатланиш бўлмаган ёки онлайн объект — ҳеч нарса очилмайди', (t) async {
      final biz = _BizRepo();
      final rest = _RestRepo(const [_cafe1]);
      await _run(t, _food('a1', category: BusinessCategory.auto), biz: biz, rest: rest);
      await _run(t, _food('o1', online: true), biz: biz, rest: rest);
      expect(find.byType(RestaurantPanelScreen), findsNothing);
      expect(find.byType(RestaurantRegisterScreen), findsNothing);
      expect(find.text('bizmap_menu_sheet_title'), findsNothing);
      expect(rest.watchedOwners, isEmpty);
    });

    testWidgets('мос ресторанлар бор — варақ: фақат шу тур ва бошқа объектга уланмаганлари + «Янги меню очиш»', (t) async {
      final rest = _RestRepo(const [_cafe1, _cafe2, _home1]);
      await _run(t, _food('f1', subtype: 'Кафе'), biz: _BizRepo(), rest: rest, linked: {'c2'});
      expect(rest.watchedOwners, ['998901111111']);
      expect(find.text('bizmap_menu_sheet_title'), findsOneWidget);
      expect(find.text('Plov markazi'), findsOneWidget);
      expect(find.text('restaurants_m_status_approved'), findsOneWidget);
      expect(find.text('Choyxona 2'), findsNothing, reason: 'бошқа объектга уланган');
      expect(find.text('Uy oshxonasi'), findsNothing, reason: 'уй ошпази — кафе объектига таклиф қилинмайди');
      expect(find.text('bizmap_menu_new'), findsOneWidget);
      expect(find.byType(RestaurantRegisterScreen), findsNothing);
    });

    testWidgets('мавжуд ресторан танланса — улаш, «уланди» хабари, панел «Меню» таби', (t) async {
      final biz = _BizRepo();
      await _run(t, _food('f1'), biz: biz, rest: _RestRepo(const [_cafe1]));
      await t.tap(find.byKey(const ValueKey('biz_menu_pick_c1')));
      await t.pumpAndSettle();
      expect(biz.links, ['f1->c1']);
      expect(find.text('bizmap_menu_linked'), findsOneWidget);
      final panel = t.widget<RestaurantPanelScreen>(find.byType(RestaurantPanelScreen));
      expect([panel.restaurantId, panel.initialTab], ['c1', 1]);
    });

    testWidgets('улаш: RESTAURANT_ALREADY_LINKED — ўз хабари, панел очилмайди, хом хато йўқ', (t) async {
      final biz = _BizRepo()
        ..linkFailsWith = FirebaseFunctionsException(
            code: 'already-exists', message: 'raw server text', details: {'code': 'RESTAURANT_ALREADY_LINKED'});
      await _run(t, _food('f1'), biz: biz, rest: _RestRepo(const [_cafe1]));
      await t.tap(find.byKey(const ValueKey('biz_menu_pick_c1')));
      await t.pumpAndSettle();
      expect(find.text('bizmap_menu_already_linked'), findsOneWidget);
      expect(find.text('bizmap_menu_link_failed'), findsNothing);
      expect(find.text('raw server text'), findsNothing);
      expect(find.byType(RestaurantPanelScreen), findsNothing);
    });

    // Бошқа хато (блокланган объект, тармоқ …) — умумий хабар.
    Future<void> expectGenericLinkError(WidgetTester t, Object err) async {
      final biz = _BizRepo()..linkFailsWith = err;
      await _run(t, _food('f1'), biz: biz, rest: _RestRepo(const [_cafe1]));
      await t.tap(find.byKey(const ValueKey('biz_menu_pick_c1')));
      await t.pumpAndSettle();
      expect(find.text('bizmap_menu_link_failed'), findsOneWidget);
      expect(find.text('bizmap_menu_already_linked'), findsNothing);
      expect(find.text('raw'), findsNothing);
      expect(find.byType(RestaurantPanelScreen), findsNothing);
    }

    testWidgets('улаш: BUSINESS_BLOCKED — умумий хабар', (t) async {
      await expectGenericLinkError(
        t,
        FirebaseFunctionsException(code: 'failed-precondition', message: 'raw', details: {'code': 'BUSINESS_BLOCKED'}),
      );
    });

    testWidgets('улаш: тармоқ хатоси (коди йўқ) — умумий хабар', (t) async {
      await expectGenericLinkError(t, StateError('raw'));
    });

    testWidgets('варақ ёпилса — ҳеч нарса', (t) async {
      final biz = _BizRepo();
      await _run(t, _food('f1'), biz: biz, rest: _RestRepo(const [_cafe1]));
      await t.tapAt(const Offset(10, 10)); // варақ ташқариси
      await t.pumpAndSettle();
      expect(find.text('bizmap_menu_sheet_title'), findsNothing);
      expect(biz.links, isEmpty);
      expect(find.byType(RestaurantRegisterScreen), findsNothing);
    });

    testWidgets('варақда «Янги меню очиш» — рўйхатдан ўтиш экрани', (t) async {
      await _run(t, _food('f1'), biz: _BizRepo(), rest: _RestRepo(const [_cafe1]));
      await t.tap(find.byKey(const ValueKey('biz_menu_new')));
      await t.pumpAndSettle();
      expect(find.byType(RestaurantRegisterScreen), findsOneWidget);
    });

    testWidgets('мос ресторан йўқ — дарров рўйхатдан ўтиш: объектдан тўлдирилган, «Меню» таби, очилгач улаш', (t) async {
      final biz = _BizRepo();
      final rest = _RestRepo(const [_home1, _cafe2]);
      await _run(t, _food('f1', subtype: 'Чойхона', openingHours: '08:00–22:00'), biz: biz, rest: rest, linked: {'c2'});
      expect(find.text('bizmap_menu_sheet_title'), findsNothing);
      final screen = t.widget<RestaurantRegisterScreen>(find.byType(RestaurantRegisterScreen));
      expect(screen.homeCook, isFalse);
      expect(screen.repository, same(rest));
      expect(screen.panelInitialTab, RestaurantPanelScreen.menuTab);
      final p = screen.prefill!;
      expect([p.name, p.address, p.contactPhone], ['Gurlan osh markazi', 'Gurlan, Navoiy ko‘chasi 5', '998907654321']);
      expect([p.lat, p.lng], [41.84, 60.39]);
      expect(p.venueType, VenueType.chaikhana);
      expect([p.openTime, p.closeTime], ['08:00', '22:00']);

      expect(biz.links, isEmpty, reason: 'ресторан очилмагунча улаш йўқ');
      await screen.onRegistered!('r9');
      expect(biz.links, ['f1->r9']);
    });

    testWidgets('уй ошпази объекти — уй ошпази сифатида рўйхатдан ўтиш (муассаса тури йўқ); фақат уй ошпазлари таклиф', (t) async {
      final rest = _RestRepo(const [_cafe1, _home1]);
      await _run(t, _food('f1', subtype: 'Уй ошпази'), biz: _BizRepo(), rest: rest);
      expect(find.text('Uy oshxonasi'), findsOneWidget);
      expect(find.text('Plov markazi'), findsNothing);
      await t.tap(find.byKey(const ValueKey('biz_menu_new')));
      await t.pumpAndSettle();
      final screen = t.widget<RestaurantRegisterScreen>(find.byType(RestaurantRegisterScreen));
      expect(screen.homeCook, isTrue);
      expect(screen.prefill!.venueType, isNull);
    });

    testWidgets('ресторанларни ўқиб бўлмаса — бўш деб: дарров янги меню (рўйхатдан ўтиш)', (t) async {
      await _run(t, _food('f1'), biz: _BizRepo(), rest: _RestRepo(const [_cafe1], failMine: true));
      expect(find.text('bizmap_menu_sheet_title'), findsNothing);
      expect(find.byType(RestaurantRegisterScreen), findsOneWidget);
    });
  });
}

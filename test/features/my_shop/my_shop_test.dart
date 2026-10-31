import 'dart:async';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/home/widgets/ava_business_sheet.dart';
import 'package:ava_gurlan/features/my_shop/my_shop_presence.dart';
import 'package:ava_gurlan/features/my_shop/open_my_shop.dart';
import 'package:ava_gurlan/features/my_shop/screens/main_shop_screen.dart';
import 'package:ava_gurlan/features/my_shop/screens/my_shop_screen.dart';
import 'package:ava_gurlan/features/my_shop/widgets/shop_name_dialog.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Менинг дўконим»: бир нечта дўкон, дўкон номи, биринчи кириш. Локализация
/// делегати АТАЙЛАБ уланмаган: `context.tr` калитнинг ўзини қайтаради
/// (`ava_create_sheet_test.dart` каби).

const _phone = '998901234567';

Future<bool> _no(String _) async => false;
Future<bool> _yes(String _) async => true;
Future<int> _zero(String _) async => 0;

Business _biz(String id, String name, BusinessCategory c, {String address = ''}) => Business(
      id: id,
      ownerId: _phone,
      name: name,
      category: c,
      phone: _phone,
      lat: 41.0,
      lng: 60.0,
      address: address,
    );

Widget _app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// «Дўконингиз очилди!» табриги (эга, 2026-10-31) — калит (локализациясиз).
final _openedTitle = find.text('my_shop_opened_title');

/// Табрикдаги «Маҳсулот қўшиш» — ойна ёпилади, чақирувчи кейинги экранни очади.
Future<void> _tapCelebration(WidgetTester tester) async {
  expect(find.text('my_shop_opened_add_products'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('celebration_ok')));
  await tester.pumpAndSettle();
  expect(_openedTitle, findsNothing);
}

void main() {
  // Табрик «бир марта» белгиси ([CelebrationOnce]) — ҳар тест тоза хотира билан.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('MyShopPresence', () {
    Future<MyShopPresence> load({
      Future<bool> Function(String)? ads,
      Future<bool> Function(String)? seller,
      Future<bool> Function(String)? main,
      Future<int> Function(String)? others,
    }) =>
        MyShopPresence.load(
          _phone,
          hasAds: ads ?? _no,
          hasSeller: seller ?? _no,
          hasMainShop: main ?? _no,
          countOtherShops: others ?? _zero,
        );

    test('ҳеч нарса йўқ — қатор «очиш» оқимида қолади', () async {
      final p = await load();
      expect(p, MyShopPresence.none);
      expect(p.any, isFalse);
    });

    test('фақат Аҳоли эълони — Аҳоли сегменти', () async {
      final p = await load(ads: _yes);
      expect(p.any, isTrue);
      expect(p.initialSegment, 0);
    });

    test('фақат улгуржи сотувчи — Улгуржи сегменти', () async {
      final p = await load(seller: _yes);
      expect(p.any, isTrue);
      expect(p.initialSegment, 1);
    });

    test('иккаласи бор — Аҳоли сегменти', () async {
      final p = await load(ads: _yes, seller: _yes);
      expect(p.initialSegment, 0);
    });

    test('фақат номи сақланган tv_shops — асосий дўкон бор', () async {
      final p = await load(main: _yes);
      expect(p.any, isTrue);
      expect(p.hasMainContent, isTrue);
    });

    test('фақат Бизнес харитаси дўкони — асосий дўконда маҳсулот йўқ', () async {
      final p = await load(others: (_) async => 2);
      expect(p.any, isTrue);
      expect(p.hasMainContent, isFalse);
      expect(p.otherShops, 2);
    });

    test('битта текширув йиқилса — қолганлари сақланади, хато отилмайди', () async {
      final p = await load(
        ads: (_) async => throw StateError('boom'),
        seller: _yes,
        others: (_) async => throw StateError('boom'),
      );
      expect(p.retail, isFalse);
      expect(p.wholesale, isTrue);
      expect(p.otherShops, 0);
    });

    test('фақат чакана ва улгуржи объектлар «дўкон» ҳисобланади', () {
      expect(MyShopPresence.isShopCategory(_biz('1', 'a', BusinessCategory.retail)), isTrue);
      expect(MyShopPresence.isShopCategory(_biz('2', 'b', BusinessCategory.wholesale)), isTrue);
      expect(MyShopPresence.isShopCategory(_biz('3', 'c', BusinessCategory.food)), isFalse);
    });
  });

  group('validShopName', () {
    test('чегаралар: 1 белги — яроқсиз, 2 ва 60 — яроқли, 61 — яроқсиз', () {
      expect(validShopName('a'), isNull);
      expect(validShopName('ab'), 'ab');
      expect(validShopName('a' * kShopNameMaxLength), 'a' * kShopNameMaxLength);
      expect(validShopName('a' * (kShopNameMaxLength + 1)), isNull);
    });

    test('бўшлиқлар тозаланади, бўш матн яроқсиз', () {
      expect(validShopName('  Barakat    kiyim '), 'Barakat kiyim');
      expect(validShopName('   '), isNull);
      expect(validShopName(''), isNull);
    });
  });

  group('MyShopScreen (кўп дўкон)', () {
    Future<void> open(
      WidgetTester tester, {
      List<Business> shops = const [],
      String name = '',
      bool canCreate = true,
    }) async {
      _bigView(tester);
      await tester.pumpWidget(_app(MyShopScreen(
        key: UniqueKey(),
        phone: _phone,
        canCreateShop: canCreate,
        businesses: Stream.value(shops),
        loadMainName: () async => name,
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('дўкон номи билан; «асосий/бошқа» ёрлиқлари йўқ', (tester) async {
      await open(tester, name: 'Barakat kiyim');
      expect(find.text('Barakat kiyim'), findsOneWidget);
      expect(find.text('my_shop_main_title'), findsNothing);
      expect(find.text('my_shop_other_title'), findsNothing);
    });

    testWidgets('ном қўйилмаган — «Менинг дўконим» (ёрлиқсиз)', (tester) async {
      await open(tester);
      // Сарлавҳада ва карточкада — иккитаси.
      expect(find.text('my_shop_title'), findsNWidgets(2));
      expect(find.text('my_shop_main_title'), findsNothing);
    });

    testWidgets('бир нечта қўшимча дўкон кўринади, чакана/улгуржи бўлмаганлари — йўқ', (tester) async {
      await open(tester, shops: [
        _biz('1', 'Kiyim do‘koni', BusinessCategory.retail, address: 'Gurlan'),
        _biz('2', 'Ulgurji ombor', BusinessCategory.wholesale),
        _biz('3', 'Oshxona', BusinessCategory.food),
      ]);
      expect(find.text('my_shop_other_title'), findsNothing);
      expect(find.text('Kiyim do‘koni'), findsOneWidget);
      // «Чакана/Улгуржи» тури кўрсатилмайди, фақат манзил.
      expect(find.text('business_cat_retail'), findsNothing);
      expect(find.text('business_cat_wholesale'), findsNothing);
      expect(find.text('Gurlan'), findsOneWidget);
      expect(find.text('Ulgurji ombor'), findsOneWidget);
      expect(find.text('Oshxona'), findsNothing);
    });

    testWidgets('дўконлар рўйхати ўқилмоқда — асосий карточка ва кичик индикатор; келгач индикатор йўқолади', (tester) async {
      _bigView(tester);
      final ctrl = StreamController<List<Business>>();
      addTearDown(ctrl.close);
      await tester.pumpWidget(_app(MyShopScreen(
        phone: _phone,
        businesses: ctrl.stream,
        loadMainName: () async => 'Asosiy',
      )));
      await tester.pump();
      expect(find.text('Asosiy'), findsOneWidget, reason: 'асосий дўкон барибир кўринади');
      expect(find.byKey(const ValueKey('my_shop_list_loading')), findsOneWidget);

      ctrl.add([_biz('b1', 'Kiyim do‘koni', BusinessCategory.retail)]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('my_shop_list_loading')), findsNothing);
      expect(find.text('Kiyim do‘koni'), findsOneWidget);
    });

    testWidgets('рўйхат хатоси — индикатор эмас, хато матни', (tester) async {
      _bigView(tester);
      await tester.pumpWidget(_app(MyShopScreen(
        phone: _phone,
        businesses: Stream<List<Business>>.error(StateError('x')),
        loadMainName: () async => 'Asosiy',
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('my_shop_list_loading')), findsNothing);
      expect(find.text('bizmap_err_generic'), findsOneWidget);
    });

    testWidgets('«Янги дўкон» тугмаси фақат Бизнес харитаси очиқ бўлса', (tester) async {
      await open(tester);
      expect(find.text('my_shop_new_shop'), findsOneWidget);
      await open(tester, canCreate: false);
      expect(find.text('my_shop_new_shop'), findsNothing);
    });

    // Дўконни ўчириш (эга, 2026-10-26: «Дўконни ўчириш йўқ, тузат»).
    Future<List<String>> openWithDelete(WidgetTester tester, {Object? error}) async {
      _bigView(tester);
      final deleted = <String>[];
      await tester.pumpWidget(_app(MyShopScreen(
        key: UniqueKey(),
        phone: _phone,
        businesses: Stream.value([_biz('b1', 'Kiyim do‘koni', BusinessCategory.retail, address: 'Gurlan')]),
        loadMainName: () async => 'Asosiy',
        deleteShop: (id) async {
          if (error != null) throw error;
          deleted.add(id);
        },
      )));
      await tester.pumpAndSettle();
      return deleted;
    }

    Future<void> chooseDelete(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('my_shop_menu_b1')));
      await tester.pumpAndSettle();
      expect(find.text('my_shop_rename'), findsOneWidget, reason: '«⋮» ичида таҳрир ҳам бор');
      await tester.tap(find.text('bizmap_delete'));
      await tester.pumpAndSettle();
    }

    testWidgets('қўшимча дўкон: «⋮» → Ўчириш → тасдиқ → deleteMyBusiness шу ID билан', (tester) async {
      final deleted = await openWithDelete(tester);
      await chooseDelete(tester);
      expect(find.text('my_shop_delete_title'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('my_shop_delete_confirm')));
      await tester.pumpAndSettle();
      expect(deleted, ['b1']);
      expect(find.text('bizmap_deleted'), findsOneWidget);
    });

    testWidgets('бекор қилинса — ҳеч нарса ўчирилмайди', (tester) async {
      final deleted = await openWithDelete(tester);
      await chooseDelete(tester);
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);
    });

    testWidgets('блокланган дўкон — тушунарли хабар, хом хато йўқ', (tester) async {
      await openWithDelete(tester, error: FirebaseFunctionsException(
        code: 'failed-precondition', message: 'raw', details: {'code': 'BUSINESS_BLOCKED'}));
      await chooseDelete(tester);
      await tester.tap(find.byKey(const ValueKey('my_shop_delete_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('my_shop_delete_blocked'), findsOneWidget);
      expect(find.text('raw'), findsNothing);
    });

    // Янги дўкондан кейин маҳсулотлар экрани дарров (эга, 2026-10-26: «маъқул», «ҳа»).
    Future<void> openWithForm(WidgetTester tester, Object? formResult, {bool tapNew = true}) async {
      _bigView(tester);
      await tester.pumpWidget(_app(MyShopScreen(
        key: UniqueKey(),
        phone: _phone,
        businesses: Stream.value([_biz('n1', 'Yangi do‘kon', BusinessCategory.retail)]),
        loadMainName: () async => 'Asosiy',
        openForm: (context, existing) async => formResult,
        productsScreen: (shop) => Scaffold(body: Text('PRODUCTS ${shop.id}')),
      )));
      await tester.pumpAndSettle();
      if (!tapNew) return;
      await tester.tap(find.text('my_shop_new_shop'));
      await tester.pumpAndSettle();
    }

    // Табрик (эга, 2026-10-31): янги дўкон — бир марта, «Маҳсулот қўшиш»дан кейин маҳсулотлар.
    testWidgets('янги дўкон сақланди (ID қайтди) — аввал табрик, «Маҳсулот қўшиш»дан кейин шу дўконнинг маҳсулотлари', (tester) async {
      await openWithForm(tester, 'n1');
      expect(_openedTitle, findsOneWidget);
      expect(find.text('my_shop_opened_sub'), findsOneWidget);
      expect(find.textContaining('PRODUCTS'), findsNothing, reason: 'табрик ёпилмагунча маҳсулотлар очилмайди');
      await _tapCelebration(tester);
      expect(find.text('PRODUCTS n1'), findsOneWidget);
    });

    testWidgets('табрик шу дўкон учун БИР МАРТА: ўша ID яна қайтса — табриксиз, маҳсулотлар дарров', (tester) async {
      await openWithForm(tester, 'n1');
      await _tapCelebration(tester);
      Navigator.of(tester.element(find.text('PRODUCTS n1'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('my_shop_new_shop'));
      await tester.pumpAndSettle();
      expect(_openedTitle, findsNothing);
      expect(find.text('PRODUCTS n1'), findsOneWidget);
    });

    testWidgets('таҳрир/филиал (true) ёки бекор (null) — маҳсулотлар экрани ва табрик йўқ', (tester) async {
      await openWithForm(tester, true);
      expect(find.textContaining('PRODUCTS'), findsNothing);
      expect(_openedTitle, findsNothing);
      await openWithForm(tester, null);
      expect(find.textContaining('PRODUCTS'), findsNothing);
      expect(_openedTitle, findsNothing);
    });

    testWidgets('таҳрир («⋮» → номини ўзгартириш): форма ID қайтарса ҳам — табрик ва маҳсулотлар йўқ', (tester) async {
      await openWithForm(tester, 'n1', tapNew: false);
      await tester.tap(find.byKey(const ValueKey('my_shop_menu_n1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('my_shop_rename'));
      await tester.pumpAndSettle();
      expect(_openedTitle, findsNothing);
      expect(find.textContaining('PRODUCTS'), findsNothing);
    });

    // Асосий дўконни ўчириш (эга, 2026-10-26: «аввал ичидаги дўконлар ўчирилсин хабари билан ўчирилсин»).
    Future<List<String>> openMain(WidgetTester tester, {List<Business> shops = const [], Object? error}) async {
      _bigView(tester);
      final calls = <String>[];
      await tester.pumpWidget(_app(MyShopScreen(
        key: UniqueKey(),
        phone: _phone,
        businesses: Stream.value(shops),
        loadMainName: () async => 'Asosiy',
        deleteMainShop: () async {
          calls.add('deleteMain');
          if (error != null) throw error;
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('my_shop_menu_main')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('bizmap_delete'));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('асосий дўкон: ичида дўконлар бор — огоҳлантиришда сони, тасдиқдан кейин БАРЧАСИ ўчади (эга, 2026-10-26)', (tester) async {
      final calls = await openMain(tester, shops: [
        _biz('b1', 'Ichki', BusinessCategory.retail),
        _biz('b2', 'Ombor', BusinessCategory.wholesale),
      ]);
      expect(find.byKey(const ValueKey('my_shop_main_has_inner')), findsNothing, reason: 'аввалги тўсиқ йўқ');
      final body = tester.widget<Text>(find.byKey(const ValueKey('my_shop_main_delete_body')));
      expect(body.data, 'my_shop_main_delete_body_all', reason: 'сони билан огоҳлантириш (тест локализациясиз — калит)');
      await tester.tap(find.byKey(const ValueKey('my_shop_main_delete_confirm')));
      await tester.pumpAndSettle();
      expect(calls, ['deleteMain']);
      expect(find.text('my_shop_main_deleted'), findsOneWidget);
    });

    testWidgets('асосий дўкон: огоҳлантиришда бекор — ҳеч нарса ўчмайди', (tester) async {
      final calls = await openMain(tester, shops: [_biz('b1', 'Ichki', BusinessCategory.retail)]);
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('асосий дўкон: ичида дўкон йўқ — тасдиқдан кейин ўчирилади', (tester) async {
      final calls = await openMain(tester);
      expect(find.text('my_shop_main_delete_body'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('my_shop_main_delete_confirm')));
      await tester.pumpAndSettle();
      expect(calls, ['deleteMain']);
      expect(find.text('my_shop_main_deleted'), findsOneWidget);
    });

    testWidgets('асосий дўкон: сервер SHOP_HAS_INNER_SHOPS қайтарса ҳам — ўша хабар', (tester) async {
      await openMain(tester, error: FirebaseFunctionsException(
          code: 'failed-precondition', message: 'raw', details: {'code': 'SHOP_HAS_INNER_SHOPS'}));
      await tester.tap(find.byKey(const ValueKey('my_shop_main_delete_confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('my_shop_main_has_inner')), findsOneWidget);
    });

    testWidgets('асосий дўкон: блокланган — тушунарли матн, хом хато йўқ', (tester) async {
      await openMain(tester, error: FirebaseFunctionsException(
          code: 'failed-precondition', message: 'raw', details: {'code': 'SHOP_BLOCKED'}));
      await tester.tap(find.byKey(const ValueKey('my_shop_main_delete_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('my_shop_delete_blocked'), findsOneWidget);
      expect(find.text('raw'), findsNothing);
    });
  });

  group('MainShopScreen (асосий дўкон)', () {
    Future<List<String>> open(
      WidgetTester tester, {
      String name = '',
      int segment = 0,
      Future<void> Function(String)? save,
    }) async {
      _bigView(tester);
      final saved = <String>[];
      await tester.pumpWidget(_app(MainShopScreen(
        key: UniqueKey(),
        phone: _phone,
        initialSegment: segment,
        loadName: () async => name,
        saveName: save ?? (n) async => saved.add(n),
        retailView: (_) => const Center(child: Text('RETAIL')),
        wholesaleView: (_) => const Center(child: Text('WHOLESALE')),
      )));
      await tester.pumpAndSettle();
      return saved;
    }

    testWidgets('сарлавҳада ном; йўқ бўлса «Асосий дўкон»', (tester) async {
      await open(tester, name: 'Barakat kiyim');
      expect(find.text('Barakat kiyim'), findsOneWidget);
      await open(tester);
      expect(find.text('my_shop_title'), findsOneWidget);
      expect(find.text('my_shop_main_title'), findsNothing);
    });

    testWidgets('бошланғич сегмент: 0 — Аҳоли, 1 — Улгуржи', (tester) async {
      await open(tester);
      expect(find.text('RETAIL'), findsOneWidget);
      await open(tester, segment: 1);
      expect(find.text('WHOLESALE'), findsOneWidget);
    });

    testWidgets('фақат икки бўлим: Аҳоли бозори ва Улгуржи — AVAGram бўлими йўқ', (tester) async {
      await open(tester);
      expect(find.text('tv_shop_to_market'), findsOneWidget);
      expect(find.text('home_module_wholesale'), findsOneWidget);
      expect(find.text('AVAGram'), findsNothing);
      expect(find.byType(Tab), findsNWidgets(2));
    });

    testWidgets('номни ўзгартириш: тўғри ном сақланади ва сарлавҳа янгиланади', (tester) async {
      final saved = await open(tester, name: 'Eski');
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Yangi   nom ');
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      expect(saved, ['Yangi nom']);
      expect(find.text('Yangi nom'), findsOneWidget);
    });

    testWidgets('1 белгили ном — хато, сақланмайди, ойна очиқ', (tester) async {
      final saved = await open(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a');
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.text('my_shop_name_err'), findsOneWidget);
    });

    testWidgets('сақлаш йиқилса — содда хато, ойна очиқ, ном ўзгармайди', (tester) async {
      await open(
        tester,
        name: 'Eski',
        save: (_) async => throw StateError('permission-denied'),
      );
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Yangi');
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      expect(find.text('my_shop_name_save_failed'), findsOneWidget);
      expect(find.text('permission-denied'), findsNothing);
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Eski'), findsOneWidget);
    });
  });

  group('«＋» қатори ва биринчи кириш варағи', () {
    Future<void> openCreate(WidgetTester tester, {required bool hasShop}) async {
      _bigView(tester);
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAvaCreateSheet(context, hasShop: hasShop),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('дўкони бор эга — «Менинг онлайн дўконим» (эга, 2026-10-26)', (tester) async {
      await openCreate(tester, hasShop: true);
      expect(find.text('home_my_shop_online'), findsOneWidget);
      expect(find.text('my_shop_title'), findsNothing);
      expect(find.text('my_shop_row_sub'), findsOneWidget);
      expect(find.text('home_create_shop_online'), findsNothing);
    });

    testWidgets('дўкони йўқ эга — «Онлайн Дўкон очиш»', (tester) async {
      await openCreate(tester, hasShop: false);
      expect(find.text('home_create_shop_online'), findsOneWidget);
      expect(find.text('my_shop_title'), findsNothing);
    });

    testWidgets('ном ихтиёрий: бўш қолдириб давом этиш — Аҳоли, номсиз', (tester) async {
      AvaFirstShop? result;
      _bigView(tester);
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await showAvaFirstShopSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('my_shop_continue'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.name, '');
      expect(result!.target, AvaShopTarget.retail);
    });

    testWidgets('яроқсиз (1 белги) ном — хато, варақ ёпилмайди', (tester) async {
      AvaFirstShop? result;
      _bigView(tester);
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await showAvaFirstShopSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a');
      await tester.tap(find.text('my_shop_continue'));
      await tester.pumpAndSettle();
      expect(find.text('my_shop_name_err'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('ном + Улгуржи танланса — тозаланган ном ва Улгуржи', (tester) async {
      AvaFirstShop? result;
      _bigView(tester);
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await showAvaFirstShopSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Barakat   kiyim ');
      await tester.tap(find.text('home_module_wholesale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('my_shop_continue'));
      await tester.pumpAndSettle();
      expect(result!.name, 'Barakat kiyim');
      expect(result!.target, AvaShopTarget.wholesale);
    });
  });

  group('openMyShop (« + » менюси ва видеодаги «Дўкон» тугмаси учун ягона оқим)', () {
    /// Оқимни ишга туширади; ўтказилган экранлар ва сақланган номлар қайтади.
    Future<({List<Widget> pushed, List<String> saved})> run(
      WidgetTester tester, {
      required MyShopPresence presence,
      bool canCreate = true,
      bool preferMain = false,
      AvaFirstShop? first,
      bool saveFails = false,
      Set<AvaShopTarget> targets = const {AvaShopTarget.retail, AvaShopTarget.wholesale},
      List<Set<AvaShopTarget>>? asked,
    }) async {
      _bigView(tester);
      final pushed = <Widget>[];
      final saved = <String>[];
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => openMyShop(
                context,
                phone: _phone,
                presence: presence,
                canCreateShop: canCreate,
                preferMain: preferMain,
                push: (w) async => pushed.add(w),
                shopTargets: targets,
                askFirstShop: (_, allowed) async {
                  asked?.add(allowed);
                  return first;
                },
                saveName: (phone, name) async {
                  if (saveFails) throw StateError('permission-denied');
                  saved.add('$phone|$name');
                },
              ),
              child: const Text('go'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return (pushed: pushed, saved: saved);
    }

    testWidgets('дўкони бор + харита очиқ — дўконлар рўйхати', (tester) async {
      final r = await run(tester, presence: const MyShopPresence(retail: true));
      expect(r.pushed.single, isA<MyShopScreen>());
      expect((r.pushed.single as MyShopScreen).canCreateShop, isTrue);
    });

    testWidgets('фақат улгуржи сотувчи, харита ёпиқ, қўшимча дўкон йўқ — асосий дўкон, Улгуржи сегменти', (tester) async {
      final r = await run(
        tester,
        presence: const MyShopPresence(wholesale: true),
        canCreate: false,
      );
      final screen = r.pushed.single as MainShopScreen;
      expect(screen.initialSegment, 1);
      expect(screen.openAddOnStart, isFalse);
    });

    testWidgets('фақат tv_shops бор, харита ёпиқ — алоҳида AVAGram карточкаси йўқ: тўғридан-тўғри асосий дўкон', (tester) async {
      final r = await run(
        tester,
        presence: const MyShopPresence(mainShop: true),
        canCreate: false,
      );
      expect(r.pushed.single, isA<MainShopScreen>());
    });

    testWidgets('видеодаги «Дўкон» тугмаси: рўйхатсиз, тўғридан-тўғри асосий дўкон', (tester) async {
      final r = await run(
        tester,
        presence: const MyShopPresence(retail: true, otherShops: 2),
        canCreate: true,
        preferMain: true,
      );
      final screen = r.pushed.single as MainShopScreen;
      expect(screen.initialSegment, 0);
    });

    testWidgets('қўшимча дўкон бор — харита ёпиқ бўлса ҳам рўйхат', (tester) async {
      final r = await run(
        tester,
        presence: const MyShopPresence(otherShops: 1),
        canCreate: false,
      );
      expect(r.pushed.single, isA<MyShopScreen>());
    });

    testWidgets('дўкони йўқ, варақ бекор қилинди — ҳеч нарса очилмайди, ном ёзилмайди, табрик йўқ', (tester) async {
      final r = await run(tester, presence: MyShopPresence.none);
      expect(r.pushed, isEmpty);
      expect(r.saved, isEmpty);
      expect(_openedTitle, findsNothing);
    });

    testWidgets('биринчи кириш: ном сақланади, табрик, «Маҳсулот қўшиш»дан кейин Аҳоли бозорида форма дарҳол очилади', (tester) async {
      final r = await run(
        tester,
        presence: MyShopPresence.none,
        first: const AvaFirstShop(name: 'Barakat kiyim', target: AvaShopTarget.retail),
      );
      expect(r.saved, ['$_phone|Barakat kiyim']);
      expect(_openedTitle, findsOneWidget);
      expect(r.pushed, isEmpty, reason: 'табрик ёпилмагунча асосий дўкон очилмайди');
      await _tapCelebration(tester);
      final screen = r.pushed.single as MainShopScreen;
      expect(screen.initialSegment, 0);
      expect(screen.openAddOnStart, isTrue);
    });

    testWidgets('биринчи кириш табриги эга телефони бўйича БИР МАРТА: иккинчи марта — табриксиз, дарров дўкон', (tester) async {
      const first = AvaFirstShop(name: '', target: AvaShopTarget.retail);
      final a = await run(tester, presence: MyShopPresence.none, first: first);
      await _tapCelebration(tester);
      expect(a.pushed.single, isA<MainShopScreen>());

      final b = await run(tester, presence: MyShopPresence.none, first: first);
      expect(_openedTitle, findsNothing);
      expect(b.pushed.single, isA<MainShopScreen>());
    });

    testWidgets('биринчи кириш, номсиз, Улгуржи — ном ёзилмайди, форма автоматик очилмайди, табрик йўқ (сотувчи ҳали тасдиқланмаган)', (tester) async {
      final r = await run(
        tester,
        presence: MyShopPresence.none,
        first: const AvaFirstShop(name: '', target: AvaShopTarget.wholesale),
      );
      expect(r.saved, isEmpty);
      expect(_openedTitle, findsNothing);
      final screen = r.pushed.single as MainShopScreen;
      expect(screen.initialSegment, 1);
      expect(screen.openAddOnStart, isFalse);
    });

    testWidgets('ном сақланмаса — содда хабар, дўкон барибир очилади (табрикдан кейин)', (tester) async {
      final r = await run(
        tester,
        presence: MyShopPresence.none,
        first: const AvaFirstShop(name: 'Barakat', target: AvaShopTarget.retail),
        saveFails: true,
      );
      expect(find.text('my_shop_name_save_failed'), findsOneWidget);
      expect(find.text('permission-denied'), findsNothing);
      await _tapCelebration(tester);
      expect(r.pushed.single, isA<MainShopScreen>());
    });

    testWidgets('дўкони бор эга — табрик йўқ (у аввал очилган)', (tester) async {
      final r = await run(tester, presence: const MyShopPresence(retail: true));
      expect(_openedTitle, findsNothing);
      expect(r.pushed.single, isA<MyShopScreen>());
    });

    testWidgets('Н-4: вараққа фақат очиқ бозорлар узатилади', (tester) async {
      final asked = <Set<AvaShopTarget>>[];
      final r = await run(
        tester,
        presence: MyShopPresence.none,
        targets: const {AvaShopTarget.wholesale},
        asked: asked,
        first: const AvaFirstShop(name: '', target: AvaShopTarget.wholesale),
      );
      expect(asked.single, {AvaShopTarget.wholesale});
      expect((r.pushed.single as MainShopScreen).initialSegment, 1);
    });

    testWidgets('Н-4: ҳеч бир бозор очиқ эмас — варақ очилмайди, ҳеч нарса push қилинмайди', (tester) async {
      final asked = <Set<AvaShopTarget>>[];
      final r = await run(
        tester,
        presence: MyShopPresence.none,
        targets: const {},
        asked: asked,
        first: const AvaFirstShop(name: 'Barakat', target: AvaShopTarget.retail),
      );
      expect(asked, isEmpty);
      expect(r.pushed, isEmpty);
      expect(r.saved, isEmpty);
    });

    testWidgets('Н-4: рухсат этилмаган бозор қайтса — очилмайди, табрик йўқ', (tester) async {
      final r = await run(
        tester,
        presence: MyShopPresence.none,
        targets: const {AvaShopTarget.wholesale},
        first: const AvaFirstShop(name: '', target: AvaShopTarget.retail),
      );
      expect(r.pushed, isEmpty);
      expect(_openedTitle, findsNothing);
    });
  });

  group('Н-4: биринчи дўкон варағи — фақат очиқ бозорлар', () {
    test('avaOpenableShopTargets — модул ҳолатидан', () {
      expect(avaOpenableShopTargets((_) => true),
          {AvaShopTarget.retail, AvaShopTarget.wholesale});
      expect(avaOpenableShopTargets((id) => id == 'wholesale_market'),
          {AvaShopTarget.wholesale});
      expect(avaOpenableShopTargets((id) => id == 'cheap_products_home'),
          {AvaShopTarget.retail});
      expect(avaOpenableShopTargets((_) => false), isEmpty);
    });

    Future<({AvaFirstShop? Function() result})> pumpSheet(
        WidgetTester tester, Set<AvaShopTarget> allowed) async {
      AvaFirstShop? result;
      _bigView(tester);
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async =>
                  result = await showAvaFirstShopSheet(context, allowed: allowed),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (result: () => result);
    }

    testWidgets('иккаласи очиқ — танлов кўринади, Аҳоли олдиндан танланган', (tester) async {
      final s = await pumpSheet(tester, {AvaShopTarget.retail, AvaShopTarget.wholesale});
      expect(find.byType(SegmentedButton<AvaShopTarget>), findsOneWidget);
      expect(find.text('home_create_shop_where'), findsOneWidget);
      await tester.tap(find.text('my_shop_continue'));
      await tester.pumpAndSettle();
      expect(s.result()!.target, AvaShopTarget.retail);
    });

    testWidgets('фақат Улгуржи очиқ — танлов йўқ, Улгуржи танланган', (tester) async {
      final s = await pumpSheet(tester, {AvaShopTarget.wholesale});
      expect(find.byType(SegmentedButton<AvaShopTarget>), findsNothing);
      expect(find.text('home_create_shop_where'), findsNothing);
      expect(find.text('tv_shop_to_market'), findsNothing);
      await tester.tap(find.text('my_shop_continue'));
      await tester.pumpAndSettle();
      expect(s.result()!.target, AvaShopTarget.wholesale);
    });

    testWidgets('фақат Аҳоли очиқ — танлов йўқ, Аҳоли танланган', (tester) async {
      final s = await pumpSheet(tester, {AvaShopTarget.retail});
      expect(find.byType(SegmentedButton<AvaShopTarget>), findsNothing);
      expect(find.text('home_module_wholesale'), findsNothing);
      await tester.tap(find.text('my_shop_continue'));
      await tester.pumpAndSettle();
      expect(s.result()!.target, AvaShopTarget.retail);
    });

    testWidgets('ҳеч бири очиқ эмас — варақ очилмайди, null', (tester) async {
      final s = await pumpSheet(tester, const {});
      expect(find.text('my_shop_continue'), findsNothing);
      expect(s.result(), isNull);
    });
  });
}
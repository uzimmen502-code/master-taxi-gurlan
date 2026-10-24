import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/home/widgets/ava_business_sheet.dart';
import 'package:ava_gurlan/features/my_shop/my_shop_presence.dart';
import 'package:ava_gurlan/features/my_shop/open_my_shop.dart';
import 'package:ava_gurlan/features/my_shop/screens/main_shop_screen.dart';
import 'package:ava_gurlan/features/my_shop/screens/my_shop_screen.dart';
import 'package:ava_gurlan/features/my_shop/widgets/shop_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
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

    testWidgets('«Янги дўкон» тугмаси фақат Бизнес харитаси очиқ бўлса', (tester) async {
      await open(tester);
      expect(find.text('my_shop_new_shop'), findsOneWidget);
      await open(tester, canCreate: false);
      expect(find.text('my_shop_new_shop'), findsNothing);
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

    testWidgets('дўкони бор эга — «Менинг дўконим»', (tester) async {
      await openCreate(tester, hasShop: true);
      expect(find.text('my_shop_title'), findsOneWidget);
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
                askFirstShop: (_) async => first,
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

    testWidgets('дўкони йўқ, варақ бекор қилинди — ҳеч нарса очилмайди, ном ёзилмайди', (tester) async {
      final r = await run(tester, presence: MyShopPresence.none);
      expect(r.pushed, isEmpty);
      expect(r.saved, isEmpty);
    });

    testWidgets('биринчи кириш: ном сақланади, Аҳоли бозорида форма дарҳол очилади', (tester) async {
      final r = await run(
        tester,
        presence: MyShopPresence.none,
        first: const AvaFirstShop(name: 'Barakat kiyim', target: AvaShopTarget.retail),
      );
      expect(r.saved, ['$_phone|Barakat kiyim']);
      final screen = r.pushed.single as MainShopScreen;
      expect(screen.initialSegment, 0);
      expect(screen.openAddOnStart, isTrue);
    });

    testWidgets('биринчи кириш, номсиз, Улгуржи — ном ёзилмайди, форма автоматик очилмайди', (tester) async {
      final r = await run(
        tester,
        presence: MyShopPresence.none,
        first: const AvaFirstShop(name: '', target: AvaShopTarget.wholesale),
      );
      expect(r.saved, isEmpty);
      final screen = r.pushed.single as MainShopScreen;
      expect(screen.initialSegment, 1);
      expect(screen.openAddOnStart, isFalse);
    });

    testWidgets('ном сақланмаса — содда хабар, дўкон барибир очилади', (tester) async {
      final r = await run(
        tester,
        presence: MyShopPresence.none,
        first: const AvaFirstShop(name: 'Barakat', target: AvaShopTarget.retail),
        saveFails: true,
      );
      expect(find.text('my_shop_name_save_failed'), findsOneWidget);
      expect(find.text('permission-denied'), findsNothing);
      expect(r.pushed.single, isA<MainShopScreen>());
    });
  });
}
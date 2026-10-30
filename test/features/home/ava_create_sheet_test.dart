import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/ava_bottom_nav.dart';
import 'package:ava_gurlan/models/driver_roles.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «＋» → «Менинг бизнесим» (эга, 2026-10-16). Локализация делегати АТАЙЛАБ
/// уланмаган: `context.tr` калитнинг ўзини қайтаради.

/// Варақани очади; [tapKey] берилса шу қаторни босиб, натижани қайтаради.
Future<AvaCreateAction?> _open(
  WidgetTester tester, {
  String? tapKey,
  DriverRoles roles = DriverRoles.none,
  Set<AvaCreateAction> hidden = const {},
  Map<AvaCreateAction, AvaRowLock> locked = const {},
}) async {
  tester.view.physicalSize = const Size(400 * 2, 2000 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  AvaCreateAction? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await showAvaCreateSheet(
                context,
                driverRoles: roles,
                hidden: hidden,
                locked: locked,
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
  if (tapKey != null) {
    await tester.tap(find.text(tapKey));
    await tester.pumpAndSettle();
  }
  return result;
}

const _allKeys = [
  // «Менинг бизнесим» — сарлавҳасиз, энг юқорида ягона қатор (эга, 2026-10-23).
  'home_create_business_map',
  'home_create_video',
  'home_create_ad',
  'home_create_service',
  'home_create_shop_online',
  'home_create_driver',
  'home_create_courier',
  'home_create_cargo',
  'home_create_home_cook',
  'restaurants_m_open_cafe',
  'book_menu_title',
  'home_module_chatgpt',
];

void main() {
  group('AvaCreateGates.compute (эга, 2026-10-30: Q-1 кўринсин-у босилмасин, Q-2 вебда видео — иловада)', () {
    ModuleStatus Function(String) only(Map<String, ModuleStatus> m) =>
        (id) => m[id] ?? ModuleStatus.enabled;

    test('ҳаммаси очиқ (мобил) — яширин ҳам, ёпиқ ҳам йўқ', () {
      final g = AvaCreateGates.compute(statusOf: only({}), isWeb: false);
      expect(g.hidden, isEmpty);
      expect(g.locked, isEmpty);
    });

    test('«Тез кунда»/«Ҳамкорлик» — кўринади, лекин ёпиқ; модул ID хабар учун сақланади', () {
      final g = AvaCreateGates.compute(
        statusOf: only({'restaurants': ModuleStatus.soon, 'jobs': ModuleStatus.comingSoon}),
        isWeb: false,
      );
      expect(g.hidden, isEmpty);
      expect(g.locked[AvaCreateAction.cafe], AvaRowLock.soon);
      expect(g.locked[AvaCreateAction.homeCook], AvaRowLock.soon);
      expect(g.locked[AvaCreateAction.ad], AvaRowLock.soon);
      expect(g.locked[AvaCreateAction.service], AvaRowLock.soon);
      expect(g.blockedModule[AvaCreateAction.cafe], 'restaurants');
    });

    test('админда ёпиқ (hidden) — банд умуман йўқ; аввал дарвозасиз бўлган видео/эълон/AI ҳам', () {
      final g = AvaCreateGates.compute(
        statusOf: only({'tv_market': ModuleStatus.hidden, 'jobs': ModuleStatus.hidden, 'chatgpt': ModuleStatus.hidden}),
        isWeb: false,
      );
      expect(g.hidden, containsAll([AvaCreateAction.video, AvaCreateAction.ad, AvaCreateAction.service, AvaCreateAction.assistant]));
      expect(g.locked, isEmpty);
    });

    test('ҳайдовчи ва китоб — дарвозасиз (ҳеч қачон яширилмайди)', () {
      final g = AvaCreateGates.compute(statusOf: (_) => ModuleStatus.hidden, isWeb: false);
      expect(g.hidden, isNot(contains(AvaCreateAction.driver)));
      expect(g.hidden, isNot(contains(AvaCreateAction.book)));
    });

    test('дўкон: бозорлардан бири очиқ бўлса очиқ; иккаласи «Тез кунда» — ёпиқ; эгасида дўкон бор — доим очиқ', () {
      expect(
        AvaCreateGates.compute(statusOf: only({'cheap_products_home': ModuleStatus.hidden}), isWeb: false)
            .locked
            .containsKey(AvaCreateAction.shopOnline),
        isFalse,
      );
      final both = only({'cheap_products_home': ModuleStatus.soon, 'wholesale_market': ModuleStatus.hidden});
      expect(AvaCreateGates.compute(statusOf: both, isWeb: false).locked[AvaCreateAction.shopOnline], AvaRowLock.soon);
      expect(AvaCreateGates.compute(statusOf: both, isWeb: false).blockedModule[AvaCreateAction.shopOnline], 'cheap_products_home');
      expect(AvaCreateGates.compute(statusOf: both, isWeb: false, hasShop: true).locked, isEmpty);
    });

    test('вебда видео — «иловада»; модул ёпиқ бўлса яширинлиги устун', () {
      expect(AvaCreateGates.compute(statusOf: only({}), isWeb: true).locked, {AvaCreateAction.video: AvaRowLock.appOnly});
      final hiddenTv = AvaCreateGates.compute(statusOf: only({'tv_market': ModuleStatus.hidden}), isWeb: true);
      expect(hiddenTv.hidden, contains(AvaCreateAction.video));
      expect(hiddenTv.locked, isEmpty);
    });
  });

  testWidgets('ёпиқ банд кўринади, белги чиқади, «›» йўқ; босилса амал қайтади (чақирувчи очмайди)', (tester) async {
    final picked = await _open(
      tester,
      tapKey: 'restaurants_m_open_cafe',
      locked: {AvaCreateAction.cafe: AvaRowLock.soon, AvaCreateAction.video: AvaRowLock.appOnly},
    );
    expect(picked, AvaCreateAction.cafe);
  });

  testWidgets('ёпиқ бандлар белгиси: «Тез кунда» ва «Иловада» матнлари', (tester) async {
    await _open(
      tester,
      locked: {AvaCreateAction.cafe: AvaRowLock.soon, AvaCreateAction.video: AvaRowLock.appOnly},
    );
    expect(find.text('home_create_pill_soon'), findsOneWidget);
    expect(find.text('home_create_pill_app_only'), findsOneWidget);
  });

  testWidgets('сарлавҳа «Менинг бизнесим» ва 12 банд гуруҳлар бўйича тартибда', (tester) async {
    await _open(tester);
    expect(find.text('home_create_title'), findsOneWidget);
    expect(find.text('home_create_subtitle'), findsOneWidget);
    var prevTop = -1.0;
    for (final key in _allKeys) {
      expect(find.text(key), findsOneWidget, reason: key);
      final top = tester.getTopLeft(find.text(key)).dy;
      expect(top, greaterThan(prevTop), reason: '$key тартиб бузилди');
      prevTop = top;
    }
  });

  testWidgets('«Менинг бизнесим» қатори энг юқорида, ҳеч қандай гуруҳ сарлавҳаси остида эмас; «Сотиш»да фақат онлайн дўкон', (tester) async {
    await _open(tester);
    final biz = tester.getTopLeft(find.text('home_create_business_map')).dy;
    final firstGroup = tester.getTopLeft(find.text('home_create_group_quick')).dy;
    expect(biz, lessThan(firstGroup), reason: 'ҳеч бир сарлавҳадан кейин эмас');
    // «Сотиш» гуруҳи сақланган ва онлайн дўкон унинг остида; бизнес қатори эса ундан юқорида.
    final sell = tester.getTopLeft(find.text('home_create_group_sell')).dy;
    final shop = tester.getTopLeft(find.text('home_create_shop_online')).dy;
    expect(sell, lessThan(shop));
    expect(biz, lessThan(sell));
  });

  testWidgets('«Менинг бизнесим» бир босишда тўғридан-тўғри шу амални қайтаради (оралиқ танлов варағи йўқ)', (tester) async {
    final picked = await _open(tester, tapKey: 'home_create_business_map');
    expect(picked, AvaCreateAction.businessMap);
  });

  testWidgets('модул яширин бўлса (hidden) «Менинг бизнесим» қатори ва унинг бўш гуруҳи чиқмайди', (tester) async {
    await _open(tester, hidden: {AvaCreateAction.businessMap});
    expect(find.text('home_create_business_map'), findsNothing);
    expect(find.text('home_create_group_quick'), findsOneWidget);
    expect(find.text('home_create_title'), findsOneWidget);
  });

  testWidgets('5 гуруҳ сарлавҳаси ўз тартибида; бўш гуруҳ кўрсатилмайди', (tester) async {
    await _open(tester);
    var prev = -1.0;
    for (final k in const [
      'home_create_group_quick',
      'home_create_group_sell',
      'home_create_group_work',
      'home_create_group_food',
      'home_create_group_help',
    ]) {
      expect(find.text(k), findsOneWidget, reason: k);
      final top = tester.getTopLeft(find.text(k)).dy;
      expect(top, greaterThan(prev), reason: k);
      prev = top;
    }
  });

  testWidgets('овқат модули яширин — «Овқат» гуруҳи ЎЗИ ҳам йўқ (бўш сарлавҳа қолмайди)', (tester) async {
    await _open(tester, hidden: {AvaCreateAction.homeCook, AvaCreateAction.cafe});
    expect(find.text('home_create_group_food'), findsNothing);
    expect(find.text('home_create_group_work'), findsOneWidget);
    expect(find.text('home_create_group_help'), findsOneWidget);
  });

  testWidgets('учта «тез» банд ҲАМ қатор кўринишида: ном, изоҳ ва ўқ (плитка эмас)', (tester) async {
    await _open(tester);
    for (final k in const ['home_create_video', 'home_create_ad', 'home_create_service']) {
      final label = tester.getTopLeft(find.text(k));
      final sub = tester.getTopLeft(find.text('${k}_sub'));
      expect(sub.dy, greaterThan(label.dy), reason: '$k изоҳи номи тагида');
      expect((sub.dx - label.dx).abs(), lessThan(1), reason: '$k изоҳи ном билан бир чизиқда');
    }
    // Учови ҳам бир устунда (горизонтал қатор): чап чегара бир хил.
    final xs = [
      for (final k in const ['home_create_video', 'home_create_ad', 'home_create_service'])
        tester.getTopLeft(find.text(k)).dx,
    ];
    expect(xs.toSet().length, 1);
  });

  testWidgets('«Онлайн Дўкон очиш» изоҳи бор; «Дўкон очиш» (AVAGram) банди ЙЎҚ (эга, 2026-10-17)', (tester) async {
    await _open(tester);
    expect(find.text('home_create_shop_online_hint'), findsOneWidget);
    expect(find.text('tv_shop_open_cta'), findsNothing);
    expect(find.text('tv_shop_open_hint'), findsNothing);
    // Изоҳ ўз банди тагида туради.
    final shop = tester.getTopLeft(find.text('home_create_shop_online')).dy;
    final hint = tester.getTopLeft(find.text('home_create_shop_online_hint')).dy;
    final next = tester.getTopLeft(find.text('home_create_driver')).dy;
    expect(hint, greaterThan(shop));
    expect(hint, lessThan(next));
  });

  testWidgets('эски «Маҳсулот қўшиш», «Сотувчи бўлиш» ва «Ҳайдовчи ёки курьер» йўқ', (tester) async {
    await _open(tester);
    for (final gone in const [
      'home_create_product',
      'home_create_seller',
      'work_entry_join',
      'work_entry_open',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
  });

  testWidgets('ҳар банд ўз амалини қайтаради', (tester) async {
    const expected = {
      'home_create_video': AvaCreateAction.video,
      'home_create_ad': AvaCreateAction.ad,
      'home_create_service': AvaCreateAction.service,
      'home_create_shop_online': AvaCreateAction.shopOnline,
      'home_create_driver': AvaCreateAction.driver,
      'home_create_courier': AvaCreateAction.courier,
      'home_create_home_cook': AvaCreateAction.homeCook,
      'restaurants_m_open_cafe': AvaCreateAction.cafe,
      'home_create_cargo': AvaCreateAction.cargo,
      'book_menu_title': AvaCreateAction.book,
      'home_module_chatgpt': AvaCreateAction.assistant,
    };
    for (final e in expected.entries) {
      final r = await _open(tester, tapKey: e.key);
      expect(r, e.value, reason: e.key);
    }
  });

  testWidgets('ҳайдовчи ва курьер матни/нуқтаси БИР-БИРИДАН МУСТАҚИЛ', (tester) async {
    // Фақат ҳайдовчи (шаҳарлараро фаол рейс): ҳайдовчи — «панели», курьер — «бўлиш».
    await _open(
      tester,
      roles: const DriverRoles(types: ['intercity'], active: {'intercity'}),
    );
    expect(find.text('home_create_driver_open'), findsOneWidget);
    expect(find.text('home_create_courier'), findsOneWidget);
    expect(find.text('home_create_courier_open'), findsNothing);
    expect(find.text('driver_chip_active'), findsOneWidget); // «Фаол» белгиси фақат фаол қаторда
  });

  testWidgets('курьер панели бор, ҳайдовчи эмас: фақат курьер қатори ўзгаради', (tester) async {
    await _open(
      tester,
      roles: const DriverRoles(courierStatus: 'approved', courierOnline: true),
    );
    expect(find.text('home_create_courier_open'), findsOneWidget);
    expect(find.text('home_create_driver'), findsOneWidget);
    expect(find.text('home_create_driver_open'), findsNothing);
    expect(find.text('driver_chip_active'), findsOneWidget); // «Фаол» белгиси фақат фаол қаторда
  });

  testWidgets('ариза ҳолатидаги курьер ҳали «Курьер бўлиш» (панел йўқ)', (tester) async {
    await _open(tester, roles: const DriverRoles(courierStatus: 'applied'));
    expect(find.text('home_create_courier'), findsOneWidget);
    expect(find.text('home_create_courier_open'), findsNothing);
  });

  testWidgets('яширин модул бандлари кўринмайди', (tester) async {
    await _open(
      tester,
      hidden: {AvaCreateAction.homeCook, AvaCreateAction.cafe, AvaCreateAction.cargo},
    );
    expect(find.text('home_create_home_cook'), findsNothing);
    expect(find.text('restaurants_m_open_cafe'), findsNothing);
    expect(find.text('home_create_cargo'), findsNothing);
    expect(find.text('home_create_video'), findsOneWidget);
    expect(find.text('home_module_chatgpt'), findsOneWidget);
  });

  testWidgets('кичик экранда рўйхат айланади: охирги банд етиб борилади, overflow йўқ', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 480 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    AvaCreateAction? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => result = await showAvaCreateSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('home_module_chatgpt'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('home_module_chatgpt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('home_module_chatgpt'));
    await tester.pumpAndSettle();
    expect(result, AvaCreateAction.assistant);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Онлайн Дўкон очиш» биринчи кириш варағи: Аҳоли бозори ва Улгуржи танлови', (tester) async {
    for (final e in const {
      'tv_shop_to_market': AvaShopTarget.retail,
      'home_module_wholesale': AvaShopTarget.wholesale,
    }.entries) {
      AvaFirstShop? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async => result = await showAvaFirstShopSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('home_create_shop_where'), findsOneWidget);
      await tester.tap(find.text(e.key));
      await tester.tap(find.text('my_shop_continue'));
      await tester.pumpAndSettle();
      expect(result?.target, e.value, reason: e.key);
    }
  });

  testWidgets('тизим шрифти 2× бўлса ҳам варақа 1.15× дан катталашмайди (изоҳ кесилмайди, overflow йўқ)', (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    Future<double> titleHeight(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showAvaCreateSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final h = tester.getSize(find.text('home_create_title')).height;
      expect(tester.takeException(), isNull);
      // Варақани ёпиб, кейинги ўлчамга ўтамиз.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      return h;
    }

    final base = await titleHeight(1.0);
    final big = await titleHeight(2.0);
    final capped = await titleHeight(1.15);
    // 2× ва 1.15× бир хил (чегара ишлаяпти); 1× дан катта.
    expect(big, closeTo(capped, 0.5));
    expect(big, greaterThan(base));
  });
}

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/ava_bottom_nav.dart';
import 'package:ava_gurlan/models/driver_roles.dart';
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
  'home_create_video',
  'home_create_ad',
  'home_create_service',
  'home_create_shop_online',
  'home_create_driver',
  'home_create_courier',
  'home_create_home_cook',
  'restaurants_m_open_cafe',
  'home_create_cargo',
  'book_menu_title',
  'home_module_chatgpt',
];

void main() {
  testWidgets('сарлавҳа «Менинг бизнесим» ва 11 банд ЭГА БЕРГАН ТАРТИБДА', (tester) async {
    await _open(tester);
    expect(find.text('home_create_title'), findsOneWidget);
    var prevTop = -1.0;
    for (final key in _allKeys) {
      expect(find.text(key), findsOneWidget, reason: key);
      final top = tester.getTopLeft(find.text(key)).dy;
      expect(top, greaterThan(prevTop), reason: '$key тартиб бузилди');
      prevTop = top;
    }
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
    expect(find.byType(DecoratedBox).evaluate().where(_isGreenDot).length, 1);
  });

  testWidgets('курьер панели бор, ҳайдовчи эмас: фақат курьер қатори ўзгаради', (tester) async {
    await _open(
      tester,
      roles: const DriverRoles(courierStatus: 'approved', courierOnline: true),
    );
    expect(find.text('home_create_courier_open'), findsOneWidget);
    expect(find.text('home_create_driver'), findsOneWidget);
    expect(find.text('home_create_driver_open'), findsNothing);
    expect(find.byType(DecoratedBox).evaluate().where(_isGreenDot).length, 1);
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

  testWidgets('«Онлайн Дўкон очиш» ичида Аҳоли бозори ва Улгуржи танлови', (tester) async {
    for (final e in const {
      'tv_shop_to_market': AvaShopTarget.retail,
      'home_module_wholesale': AvaShopTarget.wholesale,
    }.entries) {
      AvaShopTarget? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async => result = await showAvaShopTargetSheet(context),
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
      await tester.pumpAndSettle();
      expect(result, e.value, reason: e.key);
    }
  });
}

/// Яшил нуқта: 8×8 доирали `DecoratedBox`.
bool _isGreenDot(Element e) {
  final w = e.widget;
  if (w is! DecoratedBox) return false;
  final d = w.decoration;
  return d is BoxDecoration && d.shape == BoxShape.circle && d.color == Colors.green.shade600;
}

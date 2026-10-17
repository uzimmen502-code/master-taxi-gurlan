import 'package:ava_gurlan/features/platform_store/controllers/platform_store_controller.dart';
import 'package:ava_gurlan/features/platform_store/screens/platform_product_detail_screen.dart';
import 'package:ava_gurlan/features/platform_store/services/platform_cart_store.dart';
import 'package:ava_gurlan/l10n/app_localizations.dart';
import 'package:ava_gurlan/models/platform_product.dart';
import 'package:ava_gurlan/models/price_tier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Қурилмада кўрилган нуқсонлар (2026-10-17):
///  • поғона босилганда нарх шу ернинг ўзида ўзгармаётган эди;
///  • «Ўхшаш маҳсулотлар» экранга сиғмас эди (шрифт ×1.3);
///  • «Саватга» тугмаси катта эди.
/// Таржима файли (ҳақиқий I/O) ўрнига синхрон тест матнлари: тестлар
/// тартибдан мустақил ва тез.
class _StubL10n extends AppLocalizations {
  _StubL10n(super.locale);

  static const _s = {
    'price_sum_short': '{price} сўм',
    'platform_store_add': 'Саватга',
    'platform_store_go_cart': 'Саватга ўтиш',
    'platform_store_similar': 'Ўхшаш маҳсулотлар',
    'wholesale_price_tiers': 'Улгуржи нарх поғоналари',
    'wholesale_title': 'Улгуржи бозор',
    'platform_store_stock_left': 'Қолдиқ',
    'product_swipe_next_up': 'Кейинги маҳсулот учун юқорига суринг',
  };

  @override
  String translate(String key) => _s[key] ?? key;
}

class _StubDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _StubDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(_StubL10n(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
PlatformProduct _p(String id, String name, int mid) => PlatformProduct(
      id: id,
      name: name,
      price: mid,
      createdAt: DateTime.utc(2026, 10, 10),
      priceTiers: [
        PriceTier(minQty: 1, price: mid + 525),
        PriceTier(minQty: 10, price: mid),
        PriceTier(minQty: 50, price: mid - 525),
      ],
    );

Future<PlatformStoreController> _pump(
  WidgetTester tester, {
  double textScale = 1.3,
}) async {
  tester.view.physicalSize = const Size(393 * 3, 851 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final product = _p('a', 'МАКФА уни', 10500);
  final catalog = [
    product,
    _p('b', 'Суюқ порошок', 23000),
    _p('c', 'Чой Tess', 18000),
    _p('d', 'Ун Езоз', 9800),
  ];
  final ctrl = PlatformStoreController(cartStore: PlatformCartStore());
  await tester.pumpWidget(
    ChangeNotifierProvider<PlatformStoreController>.value(
      value: ctrl,
      child: MaterialApp(
        locale: const Locale('uz', 'Cyrl'),
        supportedLocales: const [Locale('uz', 'Cyrl')],
        localizationsDelegates: const [
          _StubDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: PlatformProductDetailScreen(product: product, catalog: catalog),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ctrl;
}

/// Сарлавҳадаги нарх (калит бўйича) — поғона чипи ва пастки панелдаги нархдан фарқли.
Finder _headlinePrice(String text) => find.byWidgetPredicate(
      (w) =>
          w is Text && w.data == text && w.key == const ValueKey('pd_headline_price'),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'user_phone': '998901112233'}));

  testWidgets('бошланиш: сарлавҳада 1–9 поғонаси нархи (11 025 сўм)',
      (tester) async {
    await _pump(tester);
    expect(_headlinePrice('11 025 сўм'), findsOneWidget);
  });

  testWidgets('поғонани босиш — сарлавҳадаги нарх ШУ ЕРНИНГ ЎЗИДА ўзгаради',
      (tester) async {
    final ctrl = await _pump(tester);
    await tester.tap(find.widgetWithText(InkWell, '10 500 сўм')); // 10–49 чипи
    await tester.pumpAndSettle();
    expect(ctrl.qtyOf('a'), 10);
    expect(_headlinePrice('10 500 сўм'), findsOneWidget);
    expect(_headlinePrice('11 025 сўм'), findsNothing);

    await tester.tap(find.widgetWithText(InkWell, '9 975 сўм')); // 50+ чипи
    await tester.pumpAndSettle();
    expect(ctrl.qtyOf('a'), 50);
    expect(_headlinePrice('9 975 сўм'), findsOneWidget);

    await tester.tap(find.widgetWithText(InkWell, '11 025 сўм')); // 1–9 га қайтиш
    await tester.pumpAndSettle();
    expect(ctrl.qtyOf('a'), 1);
    expect(_headlinePrice('11 025 сўм'), findsOneWidget);
  });

  testWidgets('шрифт ×1.3: ўхшашлар шу экранда, скролл керак эмас',
      (tester) async {
    await _pump(tester);
    final similarTitle = find.text('Ўхшаш маҳсулотлар');
    expect(similarTitle, findsOneWidget);
    final scrollable = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Scrollable),
    );
    final pos = tester.state<ScrollableState>(scrollable.first).position;
    expect(pos.maxScrollExtent, 0, reason: 'саҳифа битта экранга сиғиши керак');
    // Пастки панелдан юқорида.
    final bar = tester.getRect(find.byType(FilledButton).last);
    expect(tester.getRect(similarTitle).bottom, lessThan(bar.top));
  });

  testWidgets('шрифт ×1.0 ҳам сиғади', (tester) async {
    await _pump(tester, textScale: 1.0);
    final scrollable = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(scrollable.first).position.maxScrollExtent,
      0,
    );
  });

  testWidgets('«Саватга» тугмаси ихчам: баландлиги ≤ 44, экран кенглигидан тор',
      (tester) async {
    await _pump(tester);
    final btn = tester.getRect(find.widgetWithText(FilledButton, 'Саватга'));
    expect(btn.height, lessThanOrEqualTo(44));
    expect(btn.width, lessThan(393 * 0.6));
  });

  testWidgets('сават тўлганда: ± ва жами сумма шу панелда', (tester) async {
    final ctrl = await _pump(tester);
    await tester.tap(find.widgetWithText(InkWell, '10 500 сўм'));
    await tester.pumpAndSettle();
    // 10 × 10 500 = 105 000
    expect(find.text('105 000 сўм'), findsOneWidget);
    // Бошқа поғонага ўтилса, жами шу ернинг ўзида қайта ҳисобланади.
    await tester.tap(find.widgetWithText(InkWell, '9 975 сўм'));
    await tester.pumpAndSettle();
    expect(ctrl.qtyOf('a'), 50);
    expect(find.text('498 750 сўм'), findsOneWidget); // 50 × 9 975
  });
}

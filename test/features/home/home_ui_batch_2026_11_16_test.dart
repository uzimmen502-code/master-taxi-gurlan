// Эга 2026-11-16 UI тўплами: бозор карталари (авто-мослаш шиор, катта қалин стрелка, ўртадаги сарлавҳа),
// «Барча хизматларни кўриш» сарлавҳаси, свайп кўрсатмаси йўқлиги, «Сотувчининг бошқа маҳсулотлари» қатори,
// Уй-жой қидируви.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/features/home/widgets/home_markets_block.dart';
import 'package:ava_gurlan/features/home/widgets/home_services_olx_row.dart';
import 'package:ava_gurlan/features/home/widgets/service_spotlight_item.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:ava_gurlan/shared/widgets/seller_other_products_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _lang(String l) =>
    jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  tearDown(() {
    ServiceConfigHolder.resetForTest();
    SellerOtherProductsRow.debugReset();
  });

  group('fitMarketSloganFont', () {
    const scaler = TextScaler.noScaling;
    test('қисқа шиор — каттароқ шрифт, узун шиор — кичикроқ; иккаласи ҳам сиғади', () {
      final short = fitMarketSloganFont(text: 'Мол', maxWidth: 200, maxHeight: 60, textScaler: scaler);
      final long = fitMarketSloganFont(
        text: 'Сигир, қўй, эчки ва бошқа уй ҳайвонлари',
        maxWidth: 200,
        maxHeight: 60,
        textScaler: scaler,
      );
      expect(short.fits, isTrue);
      expect(long.fits, isTrue);
      expect(short.fontSize, greaterThan(long.fontSize));
      expect(short.fontSize, lessThanOrEqualTo(kHomeMarketSloganMaxFont));
      expect(long.fontSize, greaterThanOrEqualTo(kHomeMarketSloganMinFont));
      expect(short.maxLines, isNull);
    });

    test('танланган шрифт — ЭНГ КАТТА сиғадигани: 0.5 px каттаси сиғмайди', () {
      const text = 'Янги ва сифатли маҳсулотлар';
      final fit = fitMarketSloganFont(text: text, maxWidth: 150, maxHeight: 30, textScaler: scaler);
      expect(fit.fits, isTrue);
      if (fit.fontSize < kHomeMarketSloganMaxFont) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: TextStyle(fontSize: fit.fontSize + 0.5, height: kHomeMarketSloganLineHeight)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 150);
        expect(tp.height > 30 || tp.minIntrinsicWidth > 150, isTrue);
      }
    });

    test('9 px да ҳам сиғмаса — 9 px + ellipsis, қаторлар қутига мос', () {
      final fit = fitMarketSloganFont(text: 'жуда узун шиор ' * 40, maxWidth: 100, maxHeight: 20, textScaler: scaler);
      expect(fit.fits, isFalse);
      expect(fit.fontSize, kHomeMarketSloganMinFont);
      expect(fit.maxLines, greaterThanOrEqualTo(1));
    });
  });

  group('бозор картаси геометрияси', () {
    Future<void> pump(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeMarketsBlock(
              onOpen: (_) {},
              isVisible: (_) => true,
              loadTaxonomy: () async => MarketTaxonomy.fromMap(const {'version': 1, 'markets': {}}),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('сарлавҳа 15 px w700 ўртада; шиор пастки четдан 2 px, стрелкадан 1 px; стрелка ўнгдан 2 px', (t) async {
      await pump(t);
      for (final id in ['livestock', 'realty', 'aralash']) {
        final card = t.getRect(find.byKey(ValueKey('home_market_card_$id')));
        expect(card.height, kHomeMarketCardHeight);
        final title = t.widget<Text>(find.byKey(ValueKey('home_market_title_$id')));
        expect(title.textAlign, TextAlign.center);
        expect(title.style!.fontSize, 15);
        expect(title.style!.fontWeight, FontWeight.w700);
        expect(title.maxLines, 1);
        final arrow = t.getRect(find.byKey(ValueKey('home_market_arrow_$id')));
        expect(card.right - arrow.right, closeTo(kHomeMarketArrowRightGap, 0.01));
        expect(arrow.center.dy, closeTo(card.center.dy, 0.6), reason: 'стрелка вертикал марказда');
        final slogan = t.getRect(find.byKey(ValueKey('home_market_slogan_$id')));
        expect(card.bottom - slogan.bottom, greaterThanOrEqualTo(kHomeMarketSloganBottomGap - 0.01));
        expect(arrow.left - slogan.right, greaterThanOrEqualTo(1 - 0.01));
        final titleRect = t.getRect(find.byKey(ValueKey('home_market_title_$id')));
        expect(titleRect.top - card.top, closeTo(1, 0.01));
        expect(slogan.top - titleRect.bottom, closeTo(1, 0.01));
      }
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('қисқа шиор картада катта шрифт (≥ 11 px) — авто-мослаш ишлайди', (t) async {
      await pump(t);
      // Тестда tr = калит матни ('home_market_china_slogan') — қисқа ва бир хил узунликда.
      final s = t.widget<Text>(find.byKey(const ValueKey('home_market_slogan_china')));
      expect(s.style!.fontSize, greaterThan(11));
      expect(s.style!.height, kHomeMarketSloganLineHeight);
    });
  });

  group('«Барча хизматларни кўриш»', () {
    ServiceSpotlightItem item(String id) =>
        ServiceSpotlightItem(moduleId: id, label: id, onTap: () {}, icon: Icons.circle);

    testWidgets('қалин (w800), босилса — барча хизматлар; плиткалар йўқ', (t) async {
      ServiceConfigHolder.setForTest(
        defaults: ServiceModuleConfig({'jobs': ModuleStatus.enabled}),
        enforce: true,
      );
      var taps = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: HomeAllServicesHeader(items: [item('jobs')], onTap: () => taps++)),
      ));
      expect(find.byKey(const ValueKey('home_all_services_header')), findsOneWidget);
      expect(find.text('home_services_spotlight_title'), findsOneWidget);
      expect(HomeAllServicesHeader.titleStyle.fontWeight, FontWeight.w800);
      expect(find.byType(ListView), findsNothing);
      await t.tap(find.byKey(const ValueKey('home_all_services_header')));
      expect(taps, 1);
      expect(t.getSize(find.byKey(const ValueKey('home_all_services_header'))).height, greaterThanOrEqualTo(36));
    });

    testWidgets('дарвоза: биронта кўринадиган хизмат йўқ — сарлавҳа ҳам йўқ', (t) async {
      ServiceConfigHolder.setForTest(
        defaults: ServiceModuleConfig({'jobs': ModuleStatus.hidden}),
        enforce: true,
      );
      await t.pumpWidget(MaterialApp(home: Scaffold(body: HomeAllServicesHeader(items: [item('jobs')]))));
      expect(find.byKey(const ValueKey('home_all_services_header')), findsNothing);
    });

    test('матн 3 тилда', () {
      expect(_lang('uz_Cyrl')['home_services_spotlight_title'], 'Барча хизматларни кўриш');
      expect(_lang('uz_Latn')['home_services_spotlight_title'], 'Barça xizmatlarni köriş');
      expect(_lang('ru')['home_services_spotlight_title'], 'Посмотреть все услуги');
    });
  });

  group('свайп кўрсатмаси йўқ', () {
    test('«юқорига суринг» калитлари ва ишлатилиши йўқ', () {
      const keys = ['product_swipe_next_up', 'platform_store_swipe_next', 'tv_market_swipe_up'];
      for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        final m = _lang(l);
        for (final k in keys) {
          expect(m.containsKey(k), isFalse, reason: '$l/$k');
        }
      }
      for (final f in [
        'lib/features/ads/screens/ad_swipe_screen.dart',
        'lib/features/platform_store/screens/platform_product_detail_screen.dart',
        'lib/features/wholesale/screens/wholesale_product_detail_screen.dart',
        'lib/features/tv_market/screens/tv_shop_item_swipe_screen.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src.contains('product_swipe_next_up'), isFalse, reason: f);
        expect(src.contains('keyboard_double_arrow_up_rounded'), isFalse, reason: f);
        expect(src.contains('showNextHint'), isFalse, reason: f);
      }
    });
  });

  group('SellerOtherProductsRow', () {
    Future<void> pump(WidgetTester t, {required Future<int> Function() count, VoidCallback? onOpen, Widget? fallback}) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SellerOtherProductsRow(
            cacheKey: 'test:1',
            sellerName: 'Али',
            countActive: count,
            onOpen: onOpen ?? () {},
            fallback: fallback,
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('1 та фаол — қатор йўқ; 2 та — «Али · …» қатори ва стрелка', (t) async {
      await pump(t, count: () async => 1);
      expect(find.byKey(const ValueKey('seller_other_products_row')), findsNothing);
      SellerOtherProductsRow.debugReset();
      await t.pumpWidget(const SizedBox());
      await pump(t, count: () async => 2);
      expect(find.byKey(const ValueKey('seller_other_products_row')), findsOneWidget);
      expect(find.text('Али · seller_other_products'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    });

    testWidgets('босилса — onOpen (навигация мақсади); натижа сеансда кешланади (қайта count йўқ)', (t) async {
      var opened = 0;
      var calls = 0;
      await pump(t, count: () async { calls++; return 5; }, onOpen: () => opened++);
      await t.tap(find.byKey(const ValueKey('seller_other_products_row')));
      expect(opened, 1);
      await t.pumpWidget(const SizedBox());
      await pump(t, count: () async { calls++; return 5; });
      expect(calls, 1);
      expect(SellerOtherProductsRow.cached('test:1'), isTrue);
    });

    testWidgets('хато — қатор йўқ, fallback кўринади; кешга ёзилмайди', (t) async {
      await pump(t, count: () async => throw StateError('offline'), fallback: const Text('fallback'));
      expect(find.byKey(const ValueKey('seller_other_products_row')), findsNothing);
      expect(find.text('fallback'), findsOneWidget);
      expect(SellerOtherProductsRow.cached('test:1'), isNull);
    });

    test('матн 3 тилда', () {
      expect(_lang('uz_Cyrl')['seller_other_products'], 'Сотувчининг бошқа маҳсулотлари');
      expect(_lang('uz_Latn')['seller_other_products'], 'Sotuvçining boşqa mahsulotlari');
      expect(_lang('ru')['seller_other_products'], 'Другие товары продавца');
    });

    test('тафсилот экранлари ягона қаторни ишлатади (эски карточка/тугма йўқ)', () {
      final ad = File('lib/features/ads/screens/ad_details_screen.dart').readAsStringSync();
      expect(ad.contains('SellerOtherProductsRow('), isTrue);
      expect(ad.contains('countSellerActiveAds('), isTrue);
      expect(ad.contains('SellerAdsScreen(ownerId: ad.ownerId'), isTrue);
      expect(ad.contains('_SellerAdsCard'), isFalse);
      final tv = File('lib/features/tv_market/screens/tv_shop_item_detail_screen.dart').readAsStringSync();
      expect(tv.contains('SellerOtherProductsRow('), isTrue);
      expect(tv.contains('_SellerCard'), isFalse);
      final ws = File('lib/features/wholesale/screens/wholesale_product_detail_screen.dart').readAsStringSync();
      expect(ws.contains('SellerOtherProductsRow('), isTrue);
      expect(ws.contains('countActiveBySeller('), isTrue);
      expect(ws.contains('WholesaleSellerProductsScreen('), isTrue);
    });
  });

  group('Бозорлар қидируви (Уй-жойда йўқ — эга 2026-11-16: филтрлар орқали)', () {
    test('калит 3 тилда; бозорларда ягона майдон, «N та эълон» йўқ; Уй-жойда қидирув йўқ', () {
      for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        expect((_lang(l)['market_search_hint'] as String?)?.isNotEmpty, isTrue);
        expect(_lang(l).containsKey('market_count'), isFalse);
        expect(_lang(l).containsKey('realty_search_hint'), isFalse);
      }
      for (final f in [
        'lib/features/wholesale/screens/wholesale_market_screen.dart',
        'lib/features/ads/screens/cheap_products_screen.dart',
        'lib/features/markets/screens/market_screen.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src.contains('MarketSearchField('), isTrue, reason: f);
        expect(src.contains('kMarketAppBarHeight'), isTrue, reason: f);
        expect(src.contains('market_count'), isFalse, reason: f);
        expect(src.contains('.count('), isFalse, reason: f);
      }
      final realty = File('lib/features/realty/screens/realty_screen.dart').readAsStringSync();
      expect(realty.contains('MarketSearchField('), isFalse);
      expect(realty.contains('realty_search'), isFalse);
      expect(realty.contains('kMarketAppBarHeight'), isTrue);
      expect(realty.contains('.count('), isFalse);
    });
  });
}

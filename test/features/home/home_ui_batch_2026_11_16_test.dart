// Эга 2026-11-16 UI тўплами:
// «Барча хизматларни кўриш» сарлавҳаси, свайп кўрсатмаси йўқлиги, «Сотувчининг бошқа маҳсулотлари» қатори,
// Уй-жой қидируви.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/features/home/widgets/home_services_olx_row.dart';
import 'package:ava_gurlan/features/home/widgets/service_spotlight_item.dart';
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

  // Эски бозор картаси геометрияси (авто-мослаш шиор, қалин стрелка) тестлари олиб ташланди —
  // эга 2026-11-20 «енгил дизайн» карточкаси: test/features/home/home_lite_layout_test.dart.

  group('«Барча хизматларни кўриш»', () {
    ServiceSpotlightItem item(String id) =>
        ServiceSpotlightItem(moduleId: id, label: id, onTap: () {}, icon: Icons.circle);

    // Эга 2026-11-27: ёзув «Барча хизматлар» (home_services_all_title), 16/600, тўлиқ энли қатор + стрелка.
    testWidgets('16/600 + стрелка, босилса — барча хизматлар; плиткалар йўқ', (t) async {
      ServiceConfigHolder.setForTest(
        defaults: ServiceModuleConfig({'jobs': ModuleStatus.enabled}),
        enforce: true,
      );
      var taps = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: HomeAllServicesHeader(items: [item('jobs')], onTap: () => taps++)),
      ));
      expect(find.byKey(const ValueKey('home_all_services_header')), findsOneWidget);
      expect(find.text('home_services_all_title'), findsOneWidget);
      expect(find.text('home_services_spotlight_title'), findsNothing);
      expect(find.byKey(const ValueKey('home_all_services_chevron')), findsOneWidget);
      expect(HomeAllServicesHeader.titleStyle.fontSize, 16);
      expect(HomeAllServicesHeader.titleStyle.fontWeight, FontWeight.w600);
      final title = t.widget<Text>(find.byKey(const ValueKey('home_all_services_title')));
      expect(title.style?.fontSize, 16);
      expect(title.style?.fontWeight, FontWeight.w600);
      expect(find.byType(ListView), findsNothing);
      await t.tap(find.byKey(const ValueKey('home_all_services_header')));
      expect(taps, 1);
      expect(t.getSize(find.byKey(const ValueKey('home_all_services_header'))).height, greaterThanOrEqualTo(48));
      // Тўлиқ энли: стрелка ўнг четда (800 px экран).
      expect(t.getTopRight(find.byKey(const ValueKey('home_all_services_chevron'))).dx, greaterThan(760));
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
      expect(_lang('uz_Cyrl')['home_services_all_title'], 'Барча хизматлар');
      expect(_lang('uz_Latn')['home_services_all_title'], 'Barça xizmatlar');
      expect(_lang('ru')['home_services_all_title'], 'Все услуги');
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

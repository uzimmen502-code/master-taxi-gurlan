// STAGE 12 (эга, 2026-11-16): бош саҳифа — қидирув энг юқорида, «Бозорлар» блоки,
// Улгуржи/Хитой/Уй-жой плиткалари ва бўлимлари олиб ташланди.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/features/home/home_services_catalog.dart';
import 'package:ava_gurlan/features/home/widgets/home_markets_block.dart';
import 'package:ava_gurlan/features/home/widgets/service_spotlight_item.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _n(String s) => {'uz_Cyrl': '$s-cyr', 'uz_Latn': '$s-lat', 'ru': '$s-ru'};

final _taxonomy = MarketTaxonomy.fromMap({
  'version': 1,
  'markets': {
    for (final id in ['livestock', 'auto', 'farm', 'electronics', 'appliances'])
      id: {'moduleId': '${id}_market', 'order': 1, 'names': _n(id), 'slogan': _n('$id-slogan')},
    'meat': {
      'moduleId': 'meat_market',
      'order': 3,
      'names': _n('meat'),
      'slogan': _n('meat-slogan'),
      'sloganNoOrder': _n('meat-noorder'),
    },
  },
});

const _allIds = [
  'livestock_market',
  'auto_market',
  'meat_market',
  'farm_market',
  'electronics_market',
  'appliances_market',
  'realty',
  'wholesale_market',
  'china_market',
  'cheap_products_home',
];

Future<List<HomeMarketEntry>> _pump(
  WidgetTester t, {
  bool Function(String)? isVisible,
  Future<MarketTaxonomy> Function()? load,
}) async {
  final opened = <HomeMarketEntry>[];
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HomeMarketsBlock(
          onOpen: opened.add,
          isVisible: isVisible,
          loadTaxonomy: load ?? () async => _taxonomy,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return opened;
}

void main() {
  tearDown(ServiceConfigHolder.resetForTest);

  group('HomeMarketsBlock', () {
    testWidgets('ҳаммаси кўринса — 10 карточка эга тартибида', (t) async {
      await _pump(t, isVisible: (_) => true);
      expect(find.byKey(const ValueKey('home_markets_block')), findsOneWidget);
      expect(find.text('home_markets_block_title:'), findsOneWidget);
      final ids = ['livestock', 'auto', 'meat', 'farm', 'electronics', 'appliances', 'realty', 'wholesale', 'china', 'aralash'];
      final ys = [for (final id in ids) t.getTopLeft(find.byKey(ValueKey('home_market_card_$id'))).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: ids[i]);
      }
      expect(kHomeMarketEntries.map((e) => e.moduleId).toList(), _allIds);
    });

    testWidgets('дарвоза: фақат кўринадиган модул карточкаси; ҳеч бири бўлмаса — блок йўқ', (t) async {
      await _pump(t, isVisible: (id) => id == 'meat_market' || id == 'china_market');
      expect(find.byKey(const ValueKey('home_market_card_meat')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_market_card_china')), findsOneWidget);
      for (final id in ['livestock', 'auto', 'farm', 'electronics', 'appliances', 'realty', 'wholesale', 'aralash']) {
        expect(find.byKey(ValueKey('home_market_card_$id')), findsNothing, reason: id);
      }
      await _pump(t, isVisible: (_) => false);
      expect(find.byKey(const ValueKey('home_markets_block')), findsNothing);
    });

    testWidgets('сукут — HomeModuleGate.showInGrid (ServiceConfigHolder, enforce)', (t) async {
      ServiceConfigHolder.setForTest(
        defaults: ServiceModuleConfig({
          for (final id in _allIds) id: ModuleStatus.hidden,
          'auto_market': ModuleStatus.enabled,
          'cheap_products_home': ModuleStatus.comingSoon,
        }),
        enforce: true,
      );
      await _pump(t);
      expect(find.byKey(const ValueKey('home_market_card_auto')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_market_card_aralash')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_market_card_realty')), findsNothing);
      expect(find.byKey(const ValueKey('home_market_card_wholesale')), findsNothing);
    });

    testWidgets('босилганда — шу карточка ёзуви чақирувчига', (t) async {
      final opened = await _pump(t, isVisible: (_) => true);
      // 10 карта — тест экранидан пастга чиқади.
      await t.ensureVisible(find.byKey(const ValueKey('home_market_card_china')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('home_market_card_china')));
      await t.ensureVisible(find.byKey(const ValueKey('home_market_card_meat')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('home_market_card_meat')));
      expect(opened.map((e) => e.id).toList(), ['china', 'meat']);
    });

    // Эга 2026-11-16: 10 та картанинг ҳаммасида қисқа шиор — lang калитидан; карта баландлиги = расм (64).
    testWidgets('шиор: 10 та карта — lang калити; баландлик 64', (t) async {
      await _pump(t, isVisible: (_) => true);
      String slogan(String id) => t.widget<Text>(find.byKey(ValueKey('home_market_slogan_$id'))).data!;
      for (final id in ['livestock', 'auto', 'meat', 'farm', 'electronics', 'appliances', 'realty', 'wholesale', 'china', 'aralash']) {
        expect(slogan(id), 'home_market_${id}_slogan');
      }
      final row = find.descendant(
        of: find.byKey(const ValueKey('home_market_card_meat')),
        matching: find.byWidgetPredicate((w) => w is SizedBox && w.height == 64 && w.child is Row),
      );
      expect(row, findsOneWidget);
    });

    testWidgets('таксономия юкланмаса ҳам — шиорлар (lang) қолади, crash йўқ', (t) async {
      await _pump(t, isVisible: (_) => true, load: () async => throw StateError('offline'));
      expect(find.byKey(const ValueKey('home_market_card_livestock')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_market_slogan_livestock')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_market_slogan_realty')), findsOneWidget);
    });
  });

  group('taxonomyMarketSlogan', () {
    final meat = _taxonomy.market('meat');
    test('буюртма ёқилмаган — sloganNoOrder; ёқилган — slogan', () {
      expect(kMarketInAppOrderingEnabled, isFalse);
      expect(taxonomyMarketSlogan(meat, 'ru'), 'meat-noorder-ru');
      expect(taxonomyMarketSlogan(meat, 'uz_Latn', inAppOrdering: true), 'meat-slogan-lat');
    });
    test('sloganNoOrder йўқ — slogan; def йўқ — бўш', () {
      expect(taxonomyMarketSlogan(_taxonomy.market('farm'), 'ru'), 'farm-slogan-ru');
      expect(taxonomyMarketSlogan(null, 'ru'), '');
    });
    test('MarketDef sloganNoOrder ўқилади (ихтиёрий)', () {
      expect(meat!.sloganNoOrder['uz_Cyrl'], 'meat-noorder-cyr');
      expect(_taxonomy.market('auto')!.sloganNoOrder, isEmpty);
    });
  });

  testWidgets('хизматлар қатори: Улгуржи/Хитой/Уй-жой йўқ; buildHomeServices (Барча хизматлар) ўзгармаган',
      (t) async {
    late List<ServiceSpotlightItem> all;
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        all = buildHomeServices(
          context,
          a: HomeServiceActions(
            push: (_) async {},
            openModule: (_) async {},
            openYukModule: (_, __) async {},
            openPayment: (_) async {},
            openDating: () async {},
            showComingSoon: () {},
          ),
        );
        return const SizedBox();
      }),
    ));
    final row = homeRowServices(all).map((e) => e.moduleId).toSet();
    // «Барча хизматлар» экрани (плиткалар) — тўлиқ рўйхат ўзгармаган.
    final full = all.map((e) => e.moduleId).toSet();
    for (final id in ['wholesale_market', 'china_market', 'realty']) {
      expect(row.contains(id), isFalse, reason: id);
      expect(full.contains(id), isTrue, reason: id);
    }
    expect(row.contains('cheap_products_home'), isTrue);
    expect(row.length, all.length - 3);
  });

  group('home_screen.dart манбаси', () {
    final src = File('lib/features/home/home_screen.dart').readAsStringSync();
    // Эга 2026-11-16: қидирув аввалги жойига — хизматлар сарлавҳасидан кейин, «Бозорлар»дан олдин;
    // тасдиқ/буюртма/ҳамён AvaTopBar тагида қолади; доира плиткалар қатори бош саҳифада йўқ.
    test('тартиб: AvaTopBar → тасдиқ/буюртма/ҳамён → «Барча хизматларни кўриш» → қидирув → «Бозорлар»', () {
      final top = RegExp(r'AvaTopBar\(\s*onPickRegion').firstMatch(src)?.start ?? -1;
      final searchRe = RegExp(r'HomeGlobalSearchBar\(\s*key:');
      final search = searchRe.firstMatch(src)?.start ?? -1;
      final confirm = src.indexOf('const CustomerConfirmBanner()');
      final order = src.indexOf('_ActiveOrderSlot(onOpen:');
      final ticker = src.indexOf('HomeWalletTickerSlot(');
      final header = src.indexOf('HomeAllServicesHeader(');
      final block = src.indexOf('HomeMarketsBlock(onOpen: _openHomeMarket)');
      expect([top, search, confirm, order, ticker, header, block].every((i) => i > 0), isTrue);
      expect(top < confirm && confirm < order && order < ticker, isTrue);
      expect(ticker < header && header < search && search < block, isTrue);
      expect(src.contains('HomeServicesOlxRow('), isFalse, reason: 'доира плиткалар бош саҳифада йўқ');
      expect(src.contains('onTap: _openAllServices'), isTrue);
      // Виджет фақат бир жойда (изоҳдаги `HomeGlobalSearchBar(onIntent: …)` ҳисобга кирмайди).
      expect(RegExp(r'^\s*HomeGlobalSearchBar\(', multiLine: true).allMatches(src).length, 1);
      expect(searchRe.allMatches(src).length, 1);
      expect(src.contains('items: homeRowServices(buildHomeServices('), isTrue);
    });
    test('Улгуржи/Хитой/Уй-жой бўлимлари йўқ; Аралаш бўлими бор', () {
      expect(src.contains('HomeWholesaleSection('), isFalse);
      expect(src.contains('HomeRealtySection('), isFalse);
      expect(src.contains('HomeMarketSection('), isTrue);
    });
    test('карточка йўналиши — мавжуд, дарвозали helper\'лар', () {
      expect(src.contains('await openMarket(context, taxonomyId, push: _push);'), isTrue);
      expect(src.contains("await _openGated('realty', const RealtyScreen());"), isTrue);
      expect(src.contains('await _openWholesale(WholesaleProduct.marketWholesale);'), isTrue);
      expect(src.contains('await _openWholesale(WholesaleProduct.marketChina);'), isTrue);
      expect(src.contains("await _openModule(HomeModulesCatalog.byId('cheap_products_home'));"), isTrue);
    });
  });

  test('lang: янги калитлар 3 тилда, эга матнлари', () {
    Map<String, dynamic> read(String l) =>
        jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;
    final cyr = read('uz_Cyrl'), lat = read('uz_Latn'), ru = read('ru');
    const keys = [
      'home_markets_block_title',
      'home_search_hint_ava',
      'home_market_aralash_title',
      'home_market_realty_slogan',
      'home_market_wholesale_slogan',
      'home_market_china_slogan',
      'home_market_aralash_slogan',
    ];
    for (final k in keys) {
      for (final m in [cyr, lat, ru]) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: k);
      }
    }
    expect(cyr['home_markets_block_title'], 'Бозорлар');
    expect(lat['home_markets_block_title'], 'Bozorlar');
    expect(ru['home_markets_block_title'], 'Рынки');
    expect(cyr['home_search_hint_ava'], "AVA'да қидириш…");
    expect(lat['home_search_hint_ava'], "AVA'da qidiriş…");
    expect(ru['home_search_hint_ava'], 'Поиск в AVA…');
    expect(ru['home_market_aralash_title'], 'Смешанный рынок');
    // Эга 2026-11-16: Электроника ва Маиший техника бозорлари.
    expect(cyr['home_module_electronics_market'], 'Электроника бозори');
    expect(lat['home_module_electronics_market'], 'Elektronika bozori');
    expect(ru['home_module_electronics_market'], 'Рынок электроники');
    expect(cyr['home_module_appliances_market'], 'Маиший техника бозори');
    expect(lat['home_module_appliances_market'], 'Maişiy texnika bozori');
    expect(ru['home_module_appliances_market'], 'Рынок бытовой техники');
    expect(cyr['home_market_electronics_slogan'], 'Замонавий технологиялар — бир жойда!');
    expect(lat['home_market_electronics_slogan'], 'Zamonaviy texnologiyalar — bir joyda!');
    expect(ru['home_market_electronics_slogan'], 'Современные технологии — в одном месте!');
    expect(cyr['home_market_appliances_slogan'], 'Уйингизга қулайлик олиб келинг!');
    expect(lat['home_market_appliances_slogan'], 'Uyingizga qulaylik olib keling!');
    expect(ru['home_market_appliances_slogan'], 'Комфорт для вашего дома!');
    expect([cyr['market_short_electronics'], lat['market_short_electronics'], ru['market_short_electronics']],
        ['Электроника', 'Elektronika', 'Электроника']);
    expect([cyr['market_short_appliances'], lat['market_short_appliances'], ru['market_short_appliances']],
        ['Маиший техника', 'Maişiy texnika', 'Бытовая техника']);
    // Карточка расмлари мавжуд.
    for (final e in kHomeMarketEntries) {
      expect(File(e.imagePath).existsSync(), isTrue, reason: e.imagePath);
    }
  });
}

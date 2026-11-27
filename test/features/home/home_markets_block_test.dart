// STAGE 12 (эга, 2026-11-16) + «енгил дизайн» (эга 2026-11-20): «Бозорлар» блоки,
// Улгуржи/Хитой/Уй-жой плиткалари ва бўлимлари олиб ташланди.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/features/home/home_services_catalog.dart';
import 'package:ava_gurlan/features/home/widgets/home_lite_cards.dart';
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

// Эга тартиби (2026-11-28): Супермаркет, [саватча], Электроника, Маиший техника, Деҳқон, Гўшт, Мол, Хизматлар,
// Мошина, Уй-жой, Улгуржи, Заводлар, Хитой товарлари. «Аралаш бозор» карточкаси йўқ.
const _order = ['supermarket', 'electronics', 'appliances', 'farm', 'meat', 'livestock', 'services', 'auto', 'realty', 'wholesale', 'factories', 'china'];
const _allIds = [
  'supermarket',
  'electronics_market',
  'appliances_market',
  'farm_market',
  'meat_market',
  'livestock_market',
  'jobs',
  'auto_market',
  'realty',
  'wholesale_market',
  'business_map',
  'china_market',
];

Finder _card(String id) => find.byKey(ValueKey('home_lite_card_market_$id'));

Future<List<HomeMarketEntry>> _pump(
  WidgetTester t, {
  bool Function(String)? isVisible,
  Future<MarketTaxonomy> Function()? load,
  HomeLiteCardData? basket,
}) async {
  final opened = <HomeMarketEntry>[];
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HomeMarketsBlock(
          onOpen: opened.add,
          isVisible: isVisible,
          basketCard: basket,
          // «AVA Супермаркет» (эга 2026-11-20): сервер рухсати — тестда доим бор.
          loadSupermarketAccess: () async => true,
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
    testWidgets('ҳаммаси кўринса — 12 карточка эга тартибида (Супермаркет тепада, йиғилмайди)', (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await _pump(t, isVisible: (_) => true);
      expect(find.byKey(const ValueKey('home_markets_block')), findsOneWidget);
      expect(find.text('home_markets_block_title'), findsOneWidget);
      final ys = [for (final id in _order) t.getTopLeft(_card(id)).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: _order[i]);
      }
      expect(kHomeMarketEntries.map((e) => e.id).toList(), _order);
      expect(kHomeMarketEntries.map((e) => e.moduleId).toList(), _allIds);
    });

    testWidgets('дарвоза: фақат кўринадиган модул карточкаси; ҳеч бири бўлмаса — блок йўқ', (t) async {
      await _pump(t, isVisible: (id) => id == 'meat_market' || id == 'china_market' || id == 'jobs');
      expect(_card('meat'), findsOneWidget);
      expect(_card('china'), findsOneWidget);
      expect(_card('services'), findsOneWidget);
      for (final id in ['supermarket', 'livestock', 'auto', 'farm', 'electronics', 'appliances', 'realty', 'wholesale', 'factories']) {
        expect(_card(id), findsNothing, reason: id);
      }
      await _pump(t, isVisible: (_) => false);
      expect(find.byKey(const ValueKey('home_markets_block')), findsNothing);
    });

    testWidgets('сукут — HomeModuleGate.showInGrid (ServiceConfigHolder, enforce)', (t) async {
      ServiceConfigHolder.setForTest(
        defaults: ServiceModuleConfig({
          for (final id in _allIds) id: ModuleStatus.hidden,
          'auto_market': ModuleStatus.enabled,
          'business_map': ModuleStatus.comingSoon,
          'cheap_products_home': ModuleStatus.enabled,
        }),
        enforce: true,
      );
      await _pump(t);
      expect(_card('auto'), findsOneWidget);
      expect(_card('factories'), findsOneWidget, reason: 'Заводлар — business_map дарвозаси');
      expect(_card('aralash'), findsNothing, reason: 'эга 2026-11-28: «Аралаш бозор» карточкаси олиб ташланди');
      expect(_card('realty'), findsNothing);
      expect(_card('wholesale'), findsNothing);
      expect(_card('services'), findsNothing, reason: 'Хизматлар бозори — jobs дарвозаси');
    });

    testWidgets('босилганда — шу карточка ёзуви чақирувчига', (t) async {
      final opened = await _pump(t, isVisible: (_) => true);
      for (final id in ['china', 'meat', 'services', 'factories']) {
        await t.ensureVisible(_card(id));
        await t.pumpAndSettle();
        await t.tap(_card(id));
      }
      expect(opened.map((e) => e.id).toList(), ['china', 'meat', 'services', 'factories']);
      expect(opened.last.moduleId, 'business_map');
    });

    HomeLiteCardData basket(void Function() onTap) =>
        HomeLiteCardData(id: 'holiday', title: 'basket', caption: 'hb', icon: Icons.celebration_rounded, onTap: onTap);

    testWidgets('саватча карточкаси (эга 2026-11-28): Супермаркетдан кейин, Электроникадан олдин; босилса — ўз onTap', (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var taps = 0;
      await _pump(t, isVisible: (_) => true, basket: basket(() => taps++));
      final b = find.byKey(const ValueKey('home_lite_card_holiday'));
      expect(b, findsOneWidget);
      expect(t.getTopLeft(b).dy, greaterThan(t.getTopLeft(_card('supermarket')).dy));
      expect(t.getTopLeft(b).dy, lessThan(t.getTopLeft(_card('electronics')).dy));
      await t.tap(b);
      expect(taps, 1);
    });

    testWidgets('саватча: Супермаркет бўлмаса — биринчи; бозорлар йўқ бўлса ҳам блок саватча билан чиқади', (t) async {
      await _pump(t, isVisible: (id) => id == 'electronics_market', basket: basket(() {}));
      final b = find.byKey(const ValueKey('home_lite_card_holiday'));
      expect(t.getTopLeft(b).dy, lessThan(t.getTopLeft(_card('electronics')).dy));
      await _pump(t, isVisible: (_) => false, basket: basket(() {}));
      expect(find.byKey(const ValueKey('home_markets_block')), findsOneWidget);
      expect(b, findsOneWidget);
      await _pump(t, isVisible: (_) => true);
      expect(b, findsNothing, reason: 'basketCard null — карточка йўқ');
    });

    testWidgets('изоҳ: 11 та карта — lang калити; расм ўрни эни 100, баландлиги ≥ 64 (карточка бўйи)', (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await _pump(t, isVisible: (_) => true);
      for (final e in kHomeMarketEntries) {
        final cap = t.widget<Text>(find.byKey(ValueKey('home_lite_caption_market_${e.id}'))).data!;
        expect(cap, e.sloganKey);
        final img = t.getSize(find.byKey(ValueKey('home_lite_image_market_${e.id}')));
        expect(img.width, 100);
        expect(img.height, greaterThanOrEqualTo(64));
        expect(img.height, t.getSize(_card(e.id)).height, reason: 'расм карточка баландлигида');
      }
      expect(kHomeMarketEntries.firstWhere((e) => e.id == 'services').sloganKey, 'home_market_services_slogan');
    });

    testWidgets('таксономия юкланмаса ҳам — карточкалар қолади, crash йўқ', (t) async {
      await _pump(t, isVisible: (_) => true, load: () async => throw StateError('offline'));
      expect(_card('electronics'), findsOneWidget);
      expect(find.byKey(const ValueKey('home_lite_caption_market_electronics')), findsOneWidget);
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
    // Эга 2026-11-20 «енгил дизайн»: AvaTopBar → тасдиқ/буюртма/ҳамён↔баннер → қидирув → «Бозорлар» →
    // «Эълон ва хизматлар» → «Транспорт ва логистика» → «Янги эълонлар» → «Бошқа хизматлар» → «Барча хизматларни кўриш».
    test('тартиб — эга жойлашуви', () {
      final top = RegExp(r'AvaTopBar\(\s*onPickRegion').firstMatch(src)?.start ?? -1;
      final searchRe = RegExp(r'HomeGlobalSearchBar\(\s*key:');
      final search = searchRe.firstMatch(src)?.start ?? -1;
      final confirm = src.indexOf('const CustomerConfirmBanner()');
      final order = src.indexOf('_ActiveOrderSlot(onOpen:');
      final ticker = src.indexOf('HomeWalletTickerSlot(');
      final block = src.indexOf('HomeMarketsBlock(onOpen: _openHomeMarket, basketCard: _basketCard(), holidayMarketCard: _holidayMarketCard(), adminBypass: _smAdmin)');
      final adMarkets = src.indexOf('_adCarousel(HomeAdPlacement.markets)');
      final adServices = src.indexOf('_adCarousel(HomeAdPlacement.services)');
      final adTransport = src.indexOf('_adCarousel(HomeAdPlacement.transport)');
      final ads = src.indexOf("ValueKey('home_section_ads_services')");
      final transport = src.indexOf("ValueKey('home_section_transport')");
      final adsStrip = src.indexOf("titleKey: 'home_section_ads'");
      final aralash = src.indexOf('HomeMarketSection(');
      final ev = src.indexOf('HomeEvSection(');
      final biz = src.indexOf('HomeBusinessSection(');
      final avagram = src.indexOf('HomeAvagramSection(');
      final header = src.indexOf('HomeAllServicesHeader(');
      // Эга 2026-11-20 (2-тур): Аралаш тасмаси «Бозорлар»дан кейин; EV / Бизнес / AVAGram бўлимлари аввалгидек қайтди.
      // Эга 2026-11-27: «Барча хизматлар ›» — қидирув тагида, «Бозорлар»дан олдин; пастда йўқ (битта).
      // Эга 2026-11-28: реклама каруселлари — «Бозорлар»дан кейин (Аралаш тасмасидан олдин), «Эълон ва хизматлар» ва «Транспорт»дан кейин.
      final all = [top, confirm, order, ticker, search, header, block, adMarkets, aralash, ads, adServices, transport, adTransport, adsStrip, ev, biz, avagram];
      expect(RegExp(r'_adCarousel\(HomeAdPlacement\.').allMatches(src).length, 3);
      // Заводлар / Вакансиялар алоҳида бўлимлари олиб ташланди (карточкалар рўйхатларга кўчди).
      expect(src.contains("ValueKey('home_section_factories')"), isFalse);
      expect(src.contains("ValueKey('home_section_vacancies')"), isFalse);
      expect(RegExp(r'HomeAllServicesHeader\(').allMatches(src).length, 1);
      expect(all.every((i) => i > 0), isTrue, reason: '$all');
      for (var i = 1; i < all.length; i++) {
        expect(all[i], greaterThan(all[i - 1]), reason: 'index $i');
      }
      expect(src.contains('HomeServicesOlxRow('), isFalse, reason: 'доира плиткалар бош саҳифада йўқ');
      expect(src.contains('onTap: _openAllServices'), isTrue);
      expect(RegExp(r'^\s*HomeGlobalSearchBar\(', multiLine: true).allMatches(src).length, 1);
      expect(searchRe.allMatches(src).length, 1);
      expect(src.contains('items: homeRowServices(buildHomeServices('), isTrue);
    });
    test('карточкага алмашган бўлимлар йўқ; Аралаш/EV/Бизнес/AVAGram/«Янги эълонлар» бор; ресторан тасмаси бор (байроқ)', () {
      expect(src.contains('if (kHomeShowRestaurantsStrip) ...['), isTrue);
      expect(src.contains('const bool kHomeShowRestaurantsStrip = true;'), isTrue); // эга 2026-11-20 «б»
      expect(src.contains('const bool kHomeShowNewAdsStrip = true;'), isTrue);
      expect(src.contains('onOpenAd: _openMarketAd'), isTrue);
      expect(src.contains('onAddMine: () => _openMyBusinesses()'), isTrue);
      for (final w in [
        'HomeWholesaleSection(',
        'HomeRealtySection(',
        'HomeDatingSection(',
        'HomeIntercitySection(',
        'HomeYukLocalSection(',
        "titleKey: 'home_section_services'",
      ]) {
        expect(src.contains(w), isFalse, reason: w);
      }
      expect(RegExp(r'HomeAdsSection\(').allMatches(src).length, 1);
      expect(src.contains("adType: 'ad'"), isTrue);
    });
    test('карточка йўналиши — мавжуд, дарвозали helper\'лар', () {
      expect(src.contains('await openMarket(context, taxonomyId, push: _push);'), isTrue);
      expect(src.contains("await _openGated('realty', const RealtyScreen());"), isTrue);
      expect(src.contains('await _openWholesale(WholesaleProduct.marketWholesale);'), isTrue);
      expect(src.contains('await _openWholesale(WholesaleProduct.marketChina);'), isTrue);
      expect(src.contains("await _openGated('business_map', const FactoriesScreen());"), isTrue);
      // Хизматлар бозори — мавжуд хизматлар рўйхати (jobs, kind=service).
      expect(src.contains("await _openGated('jobs', const JobsScreen(kind: AdKind.service));"), isTrue);
    });
  });

  test('lang: калитлар 3 тилда, эга матнлари (2026-11-20)', () {
    Map<String, dynamic> read(String l) =>
        jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;
    final cyr = read('uz_Cyrl'), lat = read('uz_Latn'), ru = read('ru');
    for (final e in kHomeMarketEntries) {
      for (final m in [cyr, lat, ru]) {
        expect((m[e.titleKey] as String?)?.isNotEmpty, isTrue, reason: e.titleKey);
        expect((m[e.sloganKey] as String?)?.isNotEmpty, isTrue, reason: e.sloganKey);
      }
    }
    expect(cyr['home_markets_block_title'], 'Бозорлар');
    expect(lat['home_markets_block_title'], 'Bozorlar');
    expect(ru['home_markets_block_title'], 'Рынки');
    expect(cyr['home_search_hint_ava'], 'Маҳсулот ёки хизмат қидиринг');
    expect(lat['home_search_hint_ava'], 'Mahsulot yoki xizmat qidiring');
    expect(ru['home_search_hint_ava'], 'Найдите товар или услугу');
    // Эга берган изоҳлар (uz_Cyrl айнан).
    const owner = {
      'home_market_electronics_slogan': 'Телефон, компьютер ва гаджетлар',
      'home_market_auto_slogan': 'Автомобил ва эҳтиёт қисмлар',
      'home_market_livestock_slogan': 'Қорамол, қўй, эчки ва парранда — эгасидан',
      'home_market_meat_slogan': 'Гўшт ва балиқ — яқин сотувчилардан',
      'home_market_farm_slogan': 'Мева, сабзавот ва дон — деҳқондан',
      'home_market_appliances_slogan': 'Уй учун техника бир жойда',
      'home_market_services_slogan': 'Усталар ва мутахассислар хизматидан фойдаланинг',
      'home_market_realty_slogan': 'Сотиб олиш, сотиш ва ижара',
      'home_market_wholesale_slogan': 'Катта партияда қулай харид',
      'home_market_china_slogan': 'Хитой маҳсулотларига буюртма',
      'home_market_aralash_slogan': 'Барча бозорлардаги таклифлар',
      'home_market_services_title': 'Хизматлар бозори',
      'home_market_china_title': 'Хитой товарлари бозори',
    };
    owner.forEach((k, v) => expect(cyr[k], v, reason: k));
    // Янги лотин алифбоси (Ö Ğ Ş Ç): эски ' белгили o'/g' ва sh/ch йўқ.
    for (final e in kHomeMarketEntries) {
      final v = (lat[e.sloganKey] as String) + (lat[e.titleKey] as String);
      expect(RegExp("[oOgG]['ʻ‘]").hasMatch(v), isFalse, reason: v);
      expect(RegExp(r'sh|ch|Sh|Ch').hasMatch(v), isFalse, reason: v);
    }
    // Карточка расмлари мавжуд (Хизматлар бозори — вақтинча иконка, эга расм бергунча).
    for (final e in kHomeMarketEntries) {
      if (e.imagePath == null) {
        expect(e.icon, isNotNull, reason: e.id);
        continue;
      }
      expect(File(e.imagePath!).existsSync(), isTrue, reason: e.imagePath);
    }
  });

  // Эга 2026-11-28 «Админ устун бўлсин».
  test('visibleHomeMarkets: супермаркет модули ёпиқ — оддий фойдаланувчига йўқ, админга бор (сервер рухсати шарт)', () {
    bool hidden(String id) => id != 'supermarket';
    expect(visibleHomeMarkets(hidden, supermarketAllowed: true).any((e) => e.id == 'supermarket'), isFalse);
    expect(visibleHomeMarkets(hidden, supermarketAllowed: true, adminBypass: true).first.id, 'supermarket');
    expect(visibleHomeMarkets(hidden, supermarketAllowed: false, adminBypass: true).any((e) => e.id == 'supermarket'), isFalse);
    expect(visibleHomeMarkets(hidden, adminBypass: true).length, visibleHomeMarkets(hidden).length, reason: 'бошқа бозорларга таъсир йўқ');
  });

  testWidgets('админ: супермаркет модули ёпиқ — карточка бор (сервер рухсати сўралади)', (t) async {
    var asked = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HomeMarketsBlock(
      onOpen: (_) {},
      isVisible: (id) => id != 'supermarket',
      adminBypass: true,
      loadSupermarketAccess: () async { asked++; return true; },
      loadTaxonomy: () async => _taxonomy,
    )))));
    await t.pumpAndSettle();
    expect(asked, 1);
    expect(find.byKey(const ValueKey('home_lite_card_market_supermarket')), findsOneWidget);
  });
}

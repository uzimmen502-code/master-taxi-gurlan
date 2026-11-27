// Бош саҳифа «енгил дизайн» (эга 2026-11-20) скриншотлари — ҲАҚИҚИЙ виджетлар, сохта маълумот.
// Фақат `AVA_SCREENS=1` билан ишлайди (оддий тест прогонида ўтказиб юборилади):
//   $env:AVA_SCREENS='1'; flutter test test/features/home/home_lite_screens_test.dart
// Натижа: build/screens/*.png (375×812 dp, pixelRatio 2); home_full_light_N.png — тўлиқ саҳифа бўлаклари.
// Ҳар тестни алоҳида ишга туширинг (--plain-name): бир прогонда иккинчи MaterialApp тил юкини кутиб қолади.
//
// Чекловлар: «Янги эълонлар» тасмаси ва қидирув натижалари Firestore'дан ўқийди — бу ерда
// кўрсатилмайди (қидирув майдонининг ўзи кўринади); карточкалар рўйхати home_screen.dart
// даги каби ўша тартиб/дарвоза функцияларидан қурилади.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/favorites/favorites_controller.dart';
import 'package:ava_gurlan/features/home/widgets/ava_bottom_nav.dart';
import 'package:ava_gurlan/features/home/widgets/ava_top_bar.dart';
import 'package:ava_gurlan/features/home/widgets/home_global_search.dart';
import 'package:ava_gurlan/features/home/widgets/home_ads_section.dart';
import 'package:ava_gurlan/features/home/widgets/home_business_section.dart';
import 'package:ava_gurlan/services/location_service.dart';
import 'package:ava_gurlan/features/home/widgets/home_market_section.dart';
import 'package:ava_gurlan/features/home/widgets/home_restaurants_section.dart';
import 'package:ava_gurlan/features/ads/models/ad_model.dart';
import 'package:ava_gurlan/models/job_ad.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ava_gurlan/features/home/widgets/home_info_ticker.dart';
import 'package:ava_gurlan/features/home/widgets/home_lite_cards.dart';
import 'package:ava_gurlan/features/home/widgets/home_markets_block.dart';
import 'package:ava_gurlan/features/home/widgets/home_services_olx_row.dart';
import 'package:ava_gurlan/features/home/widgets/service_spotlight_item.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:ava_gurlan/l10n/app_localizations.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _enabled = Platform.environment['AVA_SCREENS'] == '1';

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Inter-$w.ttf').readAsBytesSync();
    inter.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await inter.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'C:\develop\flutter';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    await l.load();
  }
}

const _images = [
  'assets/images/home/banner_megaphone_v1.webp',
  'assets/images/ava_logo_mark.png',
  'assets/images/markets/market_electronics_v2.webp',
  'assets/images/markets/market_auto_v3.webp',
  'assets/images/markets/market_livestock_v3.webp',
  'assets/images/markets/market_meat_v2.webp',
  'assets/images/markets/market_farm_v2.webp',
  'assets/images/markets/market_appliances_v2.webp',
  'assets/images/markets/market_realty_v2.webp',
  'assets/images/markets/market_wholesale_v2.webp',
  'assets/images/markets/market_china_v2.webp',
  'assets/images/markets/market_aralash_v2.webp',
  'assets/images/home/card_dating_v1.webp',
  'assets/images/home/card_new_ads_v1.webp',
  'assets/images/home/card_post_v1.webp',
  'assets/images/home/card_pay_v1.webp',
  'assets/images/home/card_restaurants_v1.webp',
  'assets/images/home/card_intercity_v1.webp',
  'assets/images/home/card_marshrut_v1.webp',
  'assets/images/home/card_yuk_local_v1.webp',
  'assets/images/services/service_yuk_local.png',
  'assets/images/services/service_ev_charging.png',
  'assets/images/banners/banner_food.jpg',
  'assets/images/banners/banner_intercity.jpg',
  'assets/images/home/card_local_taxi_v1.webp',
  'assets/images/home/card_services_market_v1.webp',
  'assets/images/banners/banner_marshrut.jpg',
];

final _fakeShop = <TvShopItem>[
  for (final (i, title, market, price) in const [
    (1, 'Сигир, 3 ёшли', 'livestock', 18000000),
    (2, 'Chevrolet Cobalt 2022', 'auto', 145000000),
    (3, 'Мол гўшти, 1 кг', 'meat', 95000),
    (4, 'Помидор, 1 кг', 'farm', 12000),
    (5, 'Samsung Galaxy A55', 'electronics', 4300000),
  ])
    TvShopItem.fromMap('fake$i', {
      'title': title,
      'status': 'active',
      'market': market,
      'price': price,
      'districtId': '',
      'regionId': '',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 20, 12).subtract(Duration(minutes: i))),
    }),
];

class _FakeRestaurants extends RestaurantsRepository {
  static final _list = [
    Restaurant.fromMap('r1', const {'name': 'Гурлан Палов Маркази', 'status': 'approved', 'legalType': 'llc'}),
    Restaurant.fromMap('r2', const {'name': 'Дилноза опа ошхонаси', 'status': 'approved', 'legalType': 'individual'}),
    Restaurant.fromMap('r3', const {'name': 'Pizza Time', 'status': 'approved', 'legalType': 'llc'}),
  ];

  @override
  Stream<List<Restaurant>> watchApproved({int limit = 50}) => Stream.value(_list);
}

/// Скриншот учун сохта «харита»: кўча чизиқлари ва белгилар.
class _FakeMap extends StatelessWidget {
  const _FakeMap();

  @override
  Widget build(BuildContext context) {
    const pins = [Offset(0.2, 0.3), Offset(0.45, 0.55), Offset(0.7, 0.25), Offset(0.82, 0.7), Offset(0.3, 0.75), Offset(0.6, 0.45)];
    return LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _StreetsPainter())),
          for (final o in pins)
            Positioned(
              left: o.dx * box.maxWidth - 14,
              top: o.dy * box.maxHeight - 28,
              child: const Icon(Icons.location_on, size: 28, color: Color(0xFFE53935)),
            ),
        ],
      ),
    );
  }
}

class _StreetsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEAF0E4));
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 8;
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(Offset(0, size.height * i / 5), Offset(size.width, size.height * i / 5 + 20), road);
      canvas.drawLine(Offset(size.width * i / 5, 0), Offset(size.width * i / 5 - 30, size.height), road);
    }
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.85), 30, Paint()..color = const Color(0xFFBFDCF5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Preview extends StatelessWidget {
  const _Preview({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    String tr(String k) => AppLocalizations.of(context)!.translate(k);
    HomeLiteCardData card(String id, String title, String caption,
            {String? image, IconData? icon, HomeLiteImageFit fit = HomeLiteImageFit.cover}) =>
        HomeLiteCardData(id: id, title: tr(title), caption: tr(caption), imagePath: image, icon: icon, fit: fit, onTap: () {});
    final ads = <String, HomeLiteCardData>{
      'dating': card('dating', 'dating_short_label', 'home_lite_dating_caption', image: 'assets/images/home/card_dating_v1.webp'),
      'ads': card('ads', 'home_section_ads', 'home_lite_ads_caption',
          image: 'assets/images/home/card_new_ads_v1.webp'),
      'logistics': card('logistics', 'home_lite_post_title', 'home_lite_post_caption', image: 'assets/images/home/card_post_v1.webp'),
      'pay': card('pay', 'home_lite_pay_title', 'home_lite_pay_caption', image: 'assets/images/home/card_pay_v1.webp'),
      'restaurants': card('restaurants', 'home_lite_restaurants_title', 'home_lite_restaurants_caption',
          image: 'assets/images/home/card_restaurants_v1.webp'),
    };
    final transport = <String, HomeLiteCardData>{
      'intercity': card('intercity', 'home_module_intercity', 'home_lite_intercity_caption',
          image: 'assets/images/home/card_intercity_v1.webp'),
      'local_taxi': card('local_taxi', 'home_lite_local_taxi_title', 'home_lite_local_taxi_caption',
          image: 'assets/images/home/card_local_taxi_v1.webp'),
      'marshrut': card('marshrut', 'home_lite_marshrut_title', 'home_lite_marshrut_caption',
          image: 'assets/images/home/card_marshrut_v1.webp'),
      'yuk_local': card('yuk_local', 'home_lite_yuk_local_title', 'home_lite_yuk_local_caption',
          image: 'assets/images/home/card_yuk_local_v1.webp'),
      'yuk_intercity': card('yuk_intercity', 'home_lite_yuk_intercity_title', 'home_lite_yuk_intercity_caption',
          image: kHomeYukIntercityCardImage),
    };
    bool all(String _) => true;
    return Scaffold(
      backgroundColor: Theme.of(context).extension<AvaColors>()!.bg,
      bottomNavigationBar: AvaBottomNav(current: AvaNavTab.home, onTap: (_) {}, messagesBadge: 3),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AvaTopBar(onPickRegion: () {}),
            const SizedBox(height: 2),
            SizedBox(
              height: HomeInfoTicker.height,
              child: HomeInfoTicker(ads: const [], onCta: () {}),
            ),
            const SizedBox(height: 12),
            HomeGlobalSearchBar(onOpenEntry: (_) async {}, onOpenClip: (_) async {}),
            // «Барча хизматлар ›» — қидирув тагида, «Бозорлар»дан олдин (эга 2026-11-27).
            const SizedBox(height: AvaSpace.cardGap),
            HomeAllServicesHeader(
              items: [ServiceSpotlightItem(moduleId: 'jobs', label: 'jobs', icon: Icons.circle, onTap: () {})],
              onTap: () {},
            ),
            HomeMarketsBlock(
              onOpen: (_) {},
              isVisible: all,
              loadTaxonomy: () async => MarketTaxonomy.fromMap(const {'version': 1, 'markets': {}}),
            ),
            // Аралаш маҳсулот тасмаси (сохта маҳсулотлар, бозор белгилари).
            const SizedBox(height: AvaSpace.sectionMin),
            HomeMarketSection(
              onOpenAll: () {},
              onOpenAd: (_, __) {},
              onOpenShopItem: (_, __) {},
              watchAds: (_) => Stream.value(const <AdModel>[]),
              loadShop: () async => _fakeShop,
            ),
            HomeLiteSection(
              title: tr('home_lite_section_ads_services'),
              cards: [
                for (final id in homeAdsServicesCardIds(
                  isVisible: all,
                  viewerBirthDate: '${DateTime.now().year - 30}-01-01',
                  restaurantsAllowed: true,
                ))
                  ads[id]!,
              ],
            ),
            HomeLiteSection(
              title: tr('home_lite_section_transport'),
              cards: [for (final id in homeTransportCardIds(all)) transport[id]!],
            ),
            // Кафе-ресторанлар тасмаси (сохта: битта «Уй таоми»).
            const SizedBox(height: AvaSpace.homeSection),
            HomeRestaurantsSection(
              onOpenAll: () {},
              onOpenRestaurant: (_) {},
              repository: _FakeRestaurants(),
              accessCheck: () async => true,
              locate: () async => null,
            ),
            // «Янги эълонлар» тасмаси (эълон оқими бўш — намунавий қаторлар).
            const SizedBox(height: AvaSpace.homeSection),
            HomeAdsSection(
              adType: 'ad',
              titleKey: 'home_section_ads',
              onOpenAll: () {},
              onOpenAd: (_) {},
              watchJobs: () => Stream.value(const <JobAd>[]),
            ),
            // EV бўлими (харита) — бу ерда йўқ; ўрни: «Янги эълонлар»дан кейин, Бизнес харитасидан олдин.
            // Бизнес харитаси: телефон кўриниши (харита ўрнида СОХТА расм — GoogleMap тестда чизилмайди).
            const SizedBox(height: AvaSpace.sectionMin),
            HomeBusinessSection(
              onOpenMap: () {},
              onAddMine: () {},
              showMap: true,
              locate: () async => const LocationCoords(lat: 41.84, lng: 60.39),
              loadPins: (_, {required gps}) async => const [],
              mapBuilder: (_, __, ___) => const _FakeMap(),
            ),
            // AVAGram бўлими Firestore ўқийди — бу ерда йўқ (ўрни: шу ердан кейин).
          ],
          ),
        ),
      ),
    );
  }
}

Future<void> _shoot(WidgetTester t, {required String name, required ThemeData theme, double scale = 1.0, required List<String> stops}) async {
  final scroll = ScrollController();
  final key = GlobalKey();
  await t.binding.setSurfaceSize(const Size(375, 812));
  await t.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'),
      supportedLocales: const [
        Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'),
        Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn'),
        Locale('ru'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), padding: const EdgeInsets.only(top: 24)),
        child: child!,
      ),
      home: _Preview(scroll: scroll),
    ),
  ));
  // Тил файллари (AppLocalizations) асинхрон юкланади — экран шундан кейин қурилади.
  for (var i = 0; i < 20 && find.byType(_Preview).evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
  await t.runAsync(() async {
    final ctx = t.element(find.byType(_Preview));
    for (final p in _images) {
      await precacheImage(AssetImage(p), ctx);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await t.pump(const Duration(milliseconds: 500));
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await t.pump(const Duration(milliseconds: 500));
  Directory('build/screens').createSync(recursive: true);
  if (stops.length == 1 && stops.first == 'full') {
    // Тўлиқ саҳифа: юқоридан пастга кетма-кет кўриниш баландлигидаги бўлаклар.
    final step = scroll.position.viewportDimension;
    var i = 1;
    for (var off = 0.0;; off += step) {
      scroll.jumpTo(off.clamp(0.0, scroll.position.maxScrollExtent));
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await t.pump(const Duration(milliseconds: 100));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final idx = i++;
      await t.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('build/screens/${name}_$idx.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
      if (off >= scroll.position.maxScrollExtent) break;
    }
    stops = const [];
  }
  for (final stop in stops) {
    final target = switch (stop) {
      'top' => 0.0,
      'markets' => t.getTopLeft(find.byKey(const ValueKey('home_markets_block'))).dy + scroll.offset - 80,
      'sections' => t.getTopLeft(find.byKey(const ValueKey('home_lite_card_market_aralash'))).dy + scroll.offset - 80,
      _ => scroll.position.maxScrollExtent,
    };
    scroll.jumpTo(target.clamp(0.0, scroll.position.maxScrollExtent));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pump(const Duration(milliseconds: 100));
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/screens/${name}_$stop.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  expect(t.takeException(), isNull);
  await t.pumpWidget(const SizedBox());
  await t.binding.setSurfaceSize(null);
}

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    ServiceConfigHolder.setForTest(defaults: ServiceModuleConfig(const {'restaurants': ModuleStatus.enabled, 'jobs': ModuleStatus.enabled}));
    // ❤ чипи FirebaseAuth'га уланмасин (меҳмон).
    FavoritesController.debugInstance = FavoritesController(uidStream: Stream.value(''));
    await _loadFonts();
  });

  const stops = ['top', 'markets', 'sections', 'bottom'];

  testWidgets('light 375×812', (t) async {
    await _shoot(t, name: 'home_light', theme: AppTheme.light, stops: stops);
  }, skip: !_enabled);

  testWidgets('dark 375×812 (AvaColors.dark — иловада ҳали уланмаган)', (t) async {
    await _shoot(t, name: 'home_dark', theme: AppTheme.dark, stops: stops);
  }, skip: !_enabled);

  testWidgets('full page light (тасмалар сохта маълумот билан)', (t) async {
    await _shoot(t, name: 'home_full_light', theme: AppTheme.light, stops: const ['full']);
  }, skip: !_enabled);

  testWidgets('large text 1.5× light', (t) async {
    await _shoot(t, name: 'home_light_text150', theme: AppTheme.light, scale: 1.5, stops: const ['top', 'markets', 'bottom']);
  }, skip: !_enabled);
}

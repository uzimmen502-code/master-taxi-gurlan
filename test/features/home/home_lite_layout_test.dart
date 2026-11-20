// Эга 2026-11-20 «енгил дизайн»: бош саҳифа карточкалари тартиби, дарвозалари, ўлчамлари,
// катта шрифт (1.3 / 1.5) ва 360 px энда тошиш йўқлиги, 3 тил.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/ava_bottom_nav.dart';
import 'package:ava_gurlan/features/home/widgets/home_info_ticker.dart';
import 'package:ava_gurlan/features/home/widgets/home_lite_cards.dart';
import 'package:ava_gurlan/features/home/widgets/home_markets_block.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String _birthDateForAge(int age) => '${DateTime.now().year - age}-01-01';

bool _all(String _) => true;

Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Inter-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Map<String, dynamic> _lang(String l) =>
    jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;

HomeLiteCardData _card(String id, {String? image, HomeLiteImageFit fit = HomeLiteImageFit.cover}) => HomeLiteCardData(
      id: id,
      title: 'Шаҳарлараро такси',
      caption: 'Усталар ва мутахассислар хизматидан фойдаланинг',
      imagePath: image,
      icon: Icons.local_taxi_rounded,
      fit: fit,
      onTap: () {},
    );

void main() {
  group('«Эълон ва хизматлар» — тартиб ва дарвозалар', () {
    test('ҳаммаси очиқ, ёш 30 — Танишув · Янги эълонлар · Почта · Пул ўтказмалари · Кафе-ресторанлар', () {
      expect(
        homeAdsServicesCardIds(isVisible: _all, viewerBirthDate: _birthDateForAge(30), restaurantsAllowed: true),
        ['dating', 'ads', 'logistics', 'pay', 'restaurants'],
      );
    });

    test('Танишув: 17 — йўқ, 18 — бор, 45 — бор, 46 — йўқ, туғилган сана йўқ — йўқ', () {
      List<String> ids(String bd) =>
          homeAdsServicesCardIds(isVisible: _all, viewerBirthDate: bd, restaurantsAllowed: false);
      expect(ids(_birthDateForAge(17)).contains('dating'), isFalse);
      expect(ids(_birthDateForAge(18)).contains('dating'), isTrue);
      expect(ids(_birthDateForAge(45)).contains('dating'), isTrue);
      expect(ids(_birthDateForAge(46)).contains('dating'), isFalse);
      expect(ids('').contains('dating'), isFalse);
      // ёш мос, лекин модул ёпиқ — йўқ
      expect(
        homeAdsServicesCardIds(
          isVisible: (id) => id != 'dating',
          viewerBirthDate: _birthDateForAge(30),
          restaurantsAllowed: false,
        ).contains('dating'),
        isFalse,
      );
    });

    test('Пул ўтказмалари: биронта pay_* ёқилмаган — карта йўқ; биттаси етарли', () {
      List<String> ids(Set<String> on) => homeAdsServicesCardIds(
            isVisible: (id) => on.contains(id),
            viewerBirthDate: '',
            restaurantsAllowed: false,
          );
      expect(ids({}).contains('pay'), isFalse);
      expect(ids({'pay_click'}), ['pay']);
      expect(ids({'pay_paynet', 'pay_payme'}), ['pay']);
      expect(visiblePayModules((id) => id != 'pay_click'), ['pay_payme', 'pay_paynet']);
      expect(visiblePayModules((_) => false), isEmpty);
    });

    test('Почта жўнатиш — logistics дарвозаси; Янги эълонлар — jobs; Кафе — ўз дарвозаси', () {
      final ids = homeAdsServicesCardIds(
        isVisible: (id) => id != 'logistics' && id != 'jobs',
        viewerBirthDate: '',
        restaurantsAllowed: false,
      );
      expect(ids, ['pay']);
    });
  });

  group('«Транспорт ва логистика»', () {
    test('тартиб: Шаҳарлараро · Маҳаллий · Маршрут · Юк (туман ичида); халқаро йўқ', () {
      expect(homeTransportCardIds(_all), ['intercity', 'local_taxi', 'marshrut', 'yuk_local']);
      expect(homeTransportCardIds((id) => id == 'marshrut'), ['marshrut']);
      expect(kHomeTransportModuleIds.contains('yuk_intercity'), isFalse);
    });
    test('«Бошқа хизматлар»: AVAGram · Бизнес харитаси · Электр зарядлаш (ҳар бири ўз дарвозаси)', () {
      expect(homeMoreCardIds(_all), ['tv_market', 'business_map', 'ev_charging']);
      expect(homeMoreCardIds((id) => id == 'ev_charging'), ['ev_charging']);
    });
  });

  group('HomeLiteSection / HomeLiteCard', () {
    Future<void> pump(WidgetTester t, List<HomeLiteCardData> cards, {double scale = 1, double width = 360}) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: HomeLiteSection(title: 'Транспорт ва логистика', cards: cards),
            ),
          ),
        ),
      ));
    }

    testWidgets('ўлчамлар: сарлавҳа 18/600, карточка 16/600, изоҳ 14 ink2, радиус 16, расм 100×64, оралиқ 10', (t) async {
      await pump(t, [_card('a'), _card('b')]);
      final title = t.widget<Text>(find.byKey(const ValueKey('home_lite_section_title')));
      expect(title.style!.fontSize, 18);
      expect(title.style!.fontWeight, FontWeight.w600);
      final ct = t.widget<Text>(find.byKey(const ValueKey('home_lite_title_a')));
      expect(ct.style!.fontSize, 16);
      expect(ct.style!.fontWeight, FontWeight.w600);
      final cap = t.widget<Text>(find.byKey(const ValueKey('home_lite_caption_a')));
      expect(cap.style!.fontSize, 14);
      expect(cap.style!.color, AvaLight.ink2);
      final m = t.widget<Material>(find.byKey(const ValueKey('home_lite_card_a')));
      expect((m.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(16));
      expect(m.color, AvaLight.surface);
      final img = t.getSize(find.byKey(const ValueKey('home_lite_image_a')));
      expect(img.width, 100);
      expect(img.height, greaterThanOrEqualTo(64));
      expect(img.height, t.getSize(find.byKey(const ValueKey('home_lite_card_a'))).height);
      final gap = t.getTopLeft(find.byKey(const ValueKey('home_lite_card_b'))).dy -
          t.getBottomLeft(find.byKey(const ValueKey('home_lite_card_a'))).dy;
      expect(gap, inInclusiveRange(10, 12));
    });

    testWidgets('карточка йўқ — бўлим ҳам йўқ', (t) async {
      await pump(t, const []);
      expect(find.byKey(const ValueKey('home_lite_section_title')), findsNothing);
    });

    testWidgets('босилганда onTap', (t) async {
      var taps = 0;
      await pump(t, [
        HomeLiteCardData(id: 'x', title: 't', caption: 'c', icon: Icons.add, onTap: () => taps++),
      ]);
      await t.tap(find.byKey(const ValueKey('home_lite_card_x')));
      expect(taps, 1);
    });
  });

  group('катта шрифт ва тор экран — тошиш йўқ (ҳақиқий Inter шрифти)', () {
    for (final scale in [1.0, 1.3, 1.5]) {
      for (final width in [360.0, 320.0]) {
        testWidgets('scale $scale, эни $width', (t) async {
          await _loadInter();
          await t.binding.setSurfaceSize(Size(width, 2400));
          addTearDown(() => t.binding.setSurfaceSize(null));
          await t.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(size: Size(width, 2400), textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                bottomNavigationBar: AvaBottomNav(current: AvaNavTab.home, onTap: (_) {}, messagesBadge: 12),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const HomeInfoTicker(ads: []),
                      const SizedBox(height: 12),
                      // HomeGlobalSearchBar — Firestore'ни дарҳол очади, тестда йўқ (бир қаторли TextField).
                      HomeMarketsBlock(
                        onOpen: (_) {},
                        isVisible: _all,
                        loadTaxonomy: () async => MarketTaxonomy.fromMap(const {'version': 1, 'markets': {}}),
                      ),
                      HomeLiteSection(title: 'Эълон ва хизматлар', cards: [
                        _card('dating'),
                        _card('ads', image: 'assets/images/services/service_jobs.png', fit: HomeLiteImageFit.contain),
                        _card('restaurants', image: 'assets/images/banners/banner_food.jpg'),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ));
          await t.pump(const Duration(milliseconds: 100));
          expect(t.takeException(), isNull);
          // Расм ўрни катта шрифтда ҳам 100×64; карточка баландлиги ≥ 64.
          final img = t.getSize(find.byKey(const ValueKey('home_lite_image_market_electronics')));
          expect(img.width, 100);
          expect(img.height, greaterThanOrEqualTo(64));
          expect(t.getSize(find.byKey(const ValueKey('home_lite_card_market_electronics'))).height,
              greaterThanOrEqualTo(64));
          expect(t.getSize(find.byType(HomeInfoTicker)).height, HomeInfoTicker.height);
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  });

  test('lang: «енгил дизайн» калитлари 3 тилда, uz_Latn янги алифбода', () {
    final cyr = _lang('uz_Cyrl'), lat = _lang('uz_Latn'), ru = _lang('ru');
    const keys = [
      'home_lite_section_ads_services',
      'home_lite_section_transport',
      'home_lite_section_more',
      'home_lite_dating_caption',
      'home_lite_ads_caption',
      'home_lite_post_title',
      'home_lite_post_caption',
      'home_lite_pay_title',
      'home_lite_pay_caption',
      'home_lite_pay_sheet_title',
      'home_lite_restaurants_title',
      'home_lite_restaurants_caption',
      'home_lite_intercity_caption',
      'home_lite_local_taxi_title',
      'home_lite_local_taxi_caption',
      'home_lite_marshrut_title',
      'home_lite_marshrut_caption',
      'home_lite_yuk_local_title',
      'home_lite_yuk_local_caption',
      'home_lite_avagram_caption',
      'home_lite_business_map_title',
      'home_lite_business_map_caption',
      'home_lite_ev_title',
      'home_lite_ev_caption',
      'home_banner_default_title',
      'home_banner_default_caption',
      'home_banner_cta',
      'home_section_ads',
      'home_nav_cabinet',
    ];
    for (final k in keys) {
      for (final m in [cyr, lat, ru]) {
        expect((m[k] as String?)?.trim().isNotEmpty, isTrue, reason: k);
      }
      final l = lat[k] as String;
      expect(RegExp("[oOgG]['ʻ‘]").hasMatch(l), isFalse, reason: '$k: $l');
      expect(RegExp(r'sh|ch|Sh|Ch').hasMatch(l), isFalse, reason: '$k: $l');
    }
    // Эга матнлари (uz_Cyrl айнан).
    expect(cyr['home_section_ads'], 'Янги эълонлар');
    expect(cyr['home_lite_section_ads_services'], 'Эълон ва хизматлар');
    expect(cyr['home_lite_section_transport'], 'Транспорт ва логистика');
    expect(cyr['home_lite_post_title'], 'Почта жўнатиш');
    expect(cyr['home_lite_pay_title'], 'Пул ўтказмалари');
    expect(cyr['home_lite_restaurants_title'], 'Кафе-ресторанлар');
    expect(cyr['home_lite_local_taxi_title'], 'Маҳаллий такси');
    expect(cyr['home_lite_marshrut_title'], 'Маршрут такси');
    expect(cyr['home_lite_yuk_local_title'], 'Юк ташиш — туман ичида');
    expect(cyr['home_banner_default_title'], 'Мижозлар сизни AVAдан топсин');
    expect(cyr['home_banner_default_caption'], 'Хизматингизни эълон қилинг');
    expect(cyr['home_banner_cta'], 'Эълон бериш →');
    expect(cyr['home_nav_cabinet'], 'Профиль');
    // Матн КАТТА ҲАРФда эмас (sentence case).
    for (final k in ['home_banner_default_title', 'home_banner_default_caption']) {
      for (final m in [cyr, lat, ru]) {
        final v = m[k] as String;
        expect(v == v.toUpperCase(), isFalse, reason: '$k: $v');
      }
    }
  });
}

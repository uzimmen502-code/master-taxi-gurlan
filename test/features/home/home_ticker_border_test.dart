import 'dart:math' as math;

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/home_info_ticker.dart';
import 'package:ava_gurlan/models/home_ticker_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Бош экран баннери — «енгил дизайн» (эга 2026-11-20): қора хошия ва КАТТА ҲАРФ йўқ, фон #FFF3DF,
/// радиус 16, битта тўқ сариқ «Эълон бериш →» тугмаси, ўнгда ~18% карнай расми; фақат матн алмашади.
HomeTickerAd _ad(String id, String text) => HomeTickerAd(
      id: id, text: text, audience: 'all', durationSec: 6, scrollSpeed: 45,
      animationStyle: 'auto', fontSize: 13, priority: 0, active: true,
    );

Widget _app(List<HomeTickerAd> ads, {double width = 360, double scale = 1, VoidCallback? onCta}) => MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: HomeInfoTicker(ads: ads, random: math.Random(1), onCta: onCta),
            ),
          ),
        ),
      ),
    );

BoxDecoration _decoration(WidgetTester t) =>
    t.widget<Container>(find.byKey(const ValueKey('home_banner_box'))).decoration! as BoxDecoration;

String _title(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('home_banner_title')).last).data!;

void main() {
  testWidgets('кўриниш: хошиясиз, фон #FFF3DF, радиус 16, баландлик 86', (t) async {
    await t.pumpWidget(_app([_ad('a', 'Тошкентга такси? Шаҳарлараро такси!')]));
    final d = _decoration(t);
    expect(d.border, isNull, reason: 'қора хошия йўқ');
    expect(d.color, const Color(0xFFFFF3DF));
    expect(d.borderRadius, BorderRadius.circular(16));
    expect(t.getSize(find.byType(HomeInfoTicker)).height, HomeInfoTicker.height);
    // «Савол? Жавоб» — савол сарлавҳа, жавоб изоҳ; катта ҳарфга ўгирилмайди.
    expect(_title(t), 'Тошкентга такси?');
    expect(t.widget<Text>(find.byKey(const ValueKey('home_banner_caption'))).data, 'Шаҳарлараро такси!');
    expect(find.byKey(const ValueKey('home_banner_cta')), findsOneWidget);
    expect(find.text('home_banner_cta'), findsOneWidget);
  });

  testWidgets('сарлавҳа тўқ semi-bold, изоҳ кичикроқ кулранг; тугма тўқ сариқ', (t) async {
    await t.pumpWidget(_app([_ad('a', 'Савол? Жавоб')]));
    final title = t.widget<Text>(find.byKey(const ValueKey('home_banner_title')));
    final cap = t.widget<Text>(find.byKey(const ValueKey('home_banner_caption')));
    expect(title.style!.fontWeight, FontWeight.w600);
    expect(title.style!.color, AvaLight.ink);
    expect(cap.style!.color, AvaLight.ink2);
    expect(cap.style!.fontSize!, lessThan(title.style!.fontSize!));
    final cta = t.widget<Material>(find.byKey(const ValueKey('home_banner_cta')));
    expect(cta.color, AvaLight.brand);
  });

  testWidgets('админ матни йўқ — эга сукут матни; тугма onCta ни чақиради', (t) async {
    var taps = 0;
    await t.pumpWidget(_app(const [], onCta: () => taps++));
    expect(_title(t), 'home_banner_default_title');
    expect(t.widget<Text>(find.byKey(const ValueKey('home_banner_caption'))).data, 'home_banner_default_caption');
    await t.tap(find.byKey(const ValueKey('home_banner_cta')));
    expect(taps, 1);
  });

  testWidgets('расм ўрни ~18% кенгликда, расм йўли битта константа', (t) async {
    await t.pumpWidget(_app([_ad('a', 'Матн')], width: 360));
    final art = t.getSize(find.byKey(const ValueKey('home_banner_art')));
    // 360 − 22 px ички чет = 338 → 18% ≈ 61.
    expect(art.width, closeTo(338 * HomeInfoTicker.artWidthFactor, 1));
    expect(kHomeBannerArtAsset, 'assets/images/home/banner_megaphone_v1.webp');
  });

  testWidgets('матн 350 мс да алмашади (юқорига/пастдан), расм ва тугма қимирламайди', (t) async {
    await t.pumpWidget(_app([_ad('a', 'Биринчи'), _ad('b', 'Иккинчи')]));
    final first = _title(t);
    final artBefore = t.getRect(find.byKey(const ValueKey('home_banner_art')));
    final ctaBefore = t.getRect(find.byKey(const ValueKey('home_banner_cta')));
    await t.pump(HomeInfoTicker.textInterval);
    await t.pump(const Duration(milliseconds: 150));
    // Ўтиш пайтида иккала матн ҳам дарахтда (чиқувчи ва кирувчи).
    expect(find.byKey(const ValueKey('home_banner_title')), findsNWidgets(2));
    expect(t.getRect(find.byKey(const ValueKey('home_banner_art'))), artBefore);
    expect(t.getRect(find.byKey(const ValueKey('home_banner_cta'))), ctaBefore);
    await t.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('home_banner_title')), findsOneWidget);
    expect(_title(t), isNot(first));
    expect(HomeInfoTicker.textAnimation.inMilliseconds, inInclusiveRange(300, 400));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('баннерга тегилганда авто-алмашиш тўхтайди, қўйиб юборилгач давом этади', (t) async {
    await t.pumpWidget(_app([_ad('a', 'Биринчи'), _ad('b', 'Иккинчи')]));
    final first = _title(t);
    final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('home_banner_title'))));
    await t.pump(HomeInfoTicker.textInterval * 2);
    await t.pumpAndSettle();
    expect(_title(t), first, reason: 'босиб турилганда алмашмайди');
    await g.up();
    await t.pump(HomeInfoTicker.textInterval);
    await t.pumpAndSettle();
    expect(_title(t), isNot(first));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('чегара: узун матн, тор экран ва катта шрифт (1.5) — тошиш йўқ', (t) async {
    final long = 'Иловада истаган одам - Курьер бўлиши мумкин. Курьерлик қилинг ва даромад топинг! ' * 3;
    for (final scale in [1.0, 1.3, 1.5]) {
      await t.pumpWidget(_app([_ad('a', long)], width: 328, scale: scale));
      expect(t.takeException(), isNull, reason: 'scale $scale');
      expect(t.getSize(find.byType(HomeInfoTicker)).height, HomeInfoTicker.height);
    }
  });
}

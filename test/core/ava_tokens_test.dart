import 'dart:io';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x контраст нисбати.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('AvaColors — тема кенгайтмаси', () {
    test('ёруғ тема AvaColors.light ни олиб юради', () {
      expect(AppTheme.light.extension<AvaColors>(), same(AvaColors.light));
    });

    test('қоронғи тема AvaColors.dark ни олиб юради', () {
      expect(AppTheme.dark.extension<AvaColors>(), same(AvaColors.dark));
    });

    test('ёруғ ва қоронғи наборлар бир-биридан фарқ қилади', () {
      expect(AvaColors.light.bg, isNot(AvaColors.dark.bg));
      expect(AvaColors.light.ink, isNot(AvaColors.dark.ink));
      expect(AvaColors.light.brand, isNot(AvaColors.dark.brand));
    });

    test('lerp иккала четда ҳам аниқ қийматни беради', () {
      expect(AvaColors.light.lerp(AvaColors.dark, 0).bg, AvaColors.light.bg);
      expect(AvaColors.light.lerp(AvaColors.dark, 1).bg, AvaColors.dark.bg);
    });
  });

  group('Тема — тавсифдаги қийматлар', () {
    test('шрифт Inter', () {
      expect(AppTheme.light.textTheme.bodyMedium?.fontFamily, 'Inter');
    });

    // Регрессия қўриқчиси: эски темада `onSurface` = primaryDark эди, яъни
    // матн ранги сифатида ишлатиларди. `primaryDark` энди brand (кўк), шунинг
    // учун `onSurface` алоҳида `ink` га боғланган — акс ҳолда иловадаги
    // барча оддий матн кўкариб кетарди.
    test('onSurface — ink, brand эмас', () {
      expect(AppTheme.light.colorScheme.onSurface, AvaColors.light.ink);
      expect(
        AppTheme.light.colorScheme.onSurface,
        isNot(AvaColors.light.brand),
      );
      expect(AppTheme.dark.colorScheme.onSurface, AvaColors.dark.ink);
    });

    test('фон ва усти токенлардан', () {
      expect(AppTheme.light.scaffoldBackgroundColor, AvaColors.light.bg);
      expect(AppTheme.light.colorScheme.surface, AvaColors.light.surface);
      expect(AppTheme.dark.scaffoldBackgroundColor, AvaColors.dark.bg);
    });

    test('brightness тўғри', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });

    test('ўлчамлар тавсифга мос', () {
      expect(AvaRadius.card, 16); // эга 2026-11-20 «енгил дизайн» (аввал 12)
      expect(AvaRadius.search, 14);
      expect(AvaSpace.screen, 16);
      expect(AvaTap.minSize, 44);
      expect(AvaText.sectionTitle.fontSize, 16);
      // Avito редизайнидан кейин (commit 7806f87) саҳифада ЯГОНА «оғир»
      // нуқта — нарх; сарлавҳа эса w800 дан w600 га туширилган. Тест
      // ўшанда янгиланмай қолиб, шу пайтгача йиқилиб турган эди.
      expect(AvaText.sectionTitle.fontWeight, FontWeight.w600);
      expect(AvaText.price.fontWeight, FontWeight.w700);
      expect(AvaText.navLabel.fontSize, 11);
    });
  });

  group('AppColors — эски API янги токенларга боғланган', () {
    test('бренд номлари brand га', () {
      expect(AppColors.primary, AvaLight.brand);
      expect(AppColors.button, AvaLight.brand);
      // 2026-10-07: «Primary dark» — эганинг алоҳида ранги.
      expect(AppColors.primaryDark, AvaLight.brandPressed);
      expect(AppColors.onPrimary, AvaLight.brandInk);
      expect(AppColors.primaryText, AvaLight.brandText);
    });

    test('фон номлари bg га', () {
      expect(AppColors.scaffold, AvaLight.bg);
      expect(AppColors.moduleBg, AvaLight.bg);
    });

    test('эски лайм қийматлари қолмаган', () {
      const oldLime = Color(0xFFB7FF1A);
      const oldLimeDeep = Color(0xFF4E9F00);
      expect(AppColors.lime, isNot(oldLime));
      expect(AppColors.limeDeep, isNot(oldLimeDeep));
    });
  });

  group('Бренд палитраси — эга қарори 2026-10-07', () {
    test('эга берган қийматлар', () {
      expect(AvaLight.brand, const Color(0xFFFFA500));
      expect(AvaLight.brandPressed, const Color(0xFFE68A00));
      // Эга 2026-11-20 «енгил дизайн»: оч кулранг/оқ асос, ягона тўқ сариқ акцент.
      expect(AvaLight.brandSoft, const Color(0xFFFFF3DF));
      expect(AvaLight.bg, const Color(0xFFF7F8FA));
      expect(AvaLight.surface, const Color(0xFFFFFFFF));
      expect(AvaLight.ink, const Color(0xFF1F2328));
      expect(AvaLight.ink2, const Color(0xFF667085));
      expect(AvaLight.line, const Color(0xFFE8EBEF));
      expect(AvaLight.brandInk, const Color(0xFF171717));
      expect(AvaLight.brandText, const Color(0xFFA84D08));
    });

    // Positive: бренд устидаги матн ўқилади.
    test('бренд фони устидаги матн ≥ 4.5', () {
      expect(_contrast(AvaLight.brandInk, AvaLight.brand), greaterThanOrEqualTo(4.5));
      expect(_contrast(AvaLight.brandInk, AvaLight.brandPressed), greaterThanOrEqualTo(4.5));
    });

    // Negative: оқ матн бренд устида ЎҚИЛМАЙДИ — шунинг учун brandInk тўқ.
    test('оқ матн бренд устида < 4.5 (brandInk оқ бўлмаслиги керак)', () {
      expect(_contrast(const Color(0xFFFFFFFF), AvaLight.brand), lessThan(4.5));
      expect(AvaLight.brandInk, isNot(const Color(0xFFFFFFFF)));
    });

    // Boundary: brandText ҳам оқ карточкада, ҳам крем фонда AA (4.5) дан
    // ўтиши шарт. Регрессия қўриқчиси: аввалги `B45309` фонда 4.46 берарди.
    test('brandText: оқ устида ҳам, фонда ҳам ≥ 4.5', () {
      expect(_contrast(AvaLight.brandText, AvaLight.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(AvaLight.brandText, AvaLight.bg), greaterThanOrEqualTo(4.5));
    });

    // «Енгил дизайн» нейтраллари (эга 2026-11-20): иккиламчи матн ҳамма юзада AA, чегара оқда кўринади.
    test('нейтраллар — ўқилиш ва поғона', () {
      for (final bg in [AvaLight.surface, AvaLight.bg, AvaLight.surface2, AvaLight.chip, AvaLight.brandSoft]) {
        expect(_contrast(AvaLight.ink2, bg), greaterThanOrEqualTo(4.5), reason: '$bg');
        expect(_contrast(AvaLight.ink, bg), greaterThanOrEqualTo(7), reason: '$bg');
      }
      // positive: карточка (оқ) фондан ва чегара карточкадан ажралади
      expect(_contrast(AvaLight.surface, AvaLight.bg), greaterThan(1.03));
      expect(_contrast(AvaLight.line, AvaLight.surface), greaterThan(1.15));
      // negative: эски крем фон қайтиб келмасин
      expect(AvaLight.bg, isNot(const Color(0xFFFFF0D1)));
    });

    // Қоронғи палитра (PROPOSED, эга 2026-11-20): ягона тўқ сариқ акцент, матн AA.
    test('қоронғи: акцент тўқ сариқ, матн ўқилади', () {
      expect(AvaDark.brand.r, greaterThan(AvaDark.brand.b), reason: 'кўк эмас — тўқ сариқ');
      expect(_contrast(AvaDark.brandInk, AvaDark.brand), greaterThanOrEqualTo(4.5));
      for (final bg in [AvaDark.bg, AvaDark.surface, AvaDark.surface2]) {
        expect(_contrast(AvaDark.ink, bg), greaterThanOrEqualTo(7), reason: '$bg');
        expect(_contrast(AvaDark.ink2, bg), greaterThanOrEqualTo(4.5), reason: '$bg');
        expect(_contrast(AvaDark.brandText, bg), greaterThanOrEqualTo(4.5), reason: '$bg');
      }
    });

    test('бренд матн ранги сифатида темада ишлатилмайди', () {
      final t = AppTheme.light;
      final c = AvaColors.light;
      expect(t.colorScheme.onPrimary, c.brandInk);
      expect(t.colorScheme.onPrimaryContainer, c.brandText);
      expect(
        t.textButtonTheme.style?.foregroundColor?.resolve({}),
        c.brandText,
      );
      expect(
        t.outlinedButtonTheme.style?.foregroundColor?.resolve({}),
        c.brandText,
      );
      expect(t.appBarTheme.foregroundColor, c.brandInk);
      expect(t.colorScheme.onError, isNot(c.brandInk));
    });

    test('тугма босилганда Primary dark', () {
      final s = AppTheme.light.elevatedButtonTheme.style!;
      expect(s.backgroundColor?.resolve({}), AvaLight.brand);
      expect(s.backgroundColor?.resolve({WidgetState.pressed}), AvaLight.brandPressed);
      final f = AppTheme.light.filledButtonTheme.style!;
      expect(f.backgroundColor?.resolve({WidgetState.hovered}), AvaLight.brandPressed);
    });
  });

  group('Бўлим қаторлари матни (feedRow)', () {
    // Эга сўрови 2026-10-08: ҳарфлар ораси кенгроқ.
    test('ҳарфлар ораси кенгайтирилган (0 эмас)', () {
      expect(AvaText.feedRow.letterSpacing, AvaText.feedRowLetterSpacing);
      expect(AvaText.feedRow.letterSpacing, greaterThan(0));
    });

    // Чегара: «сочилиб» кетмаслиги учун шрифтнинг 5% идан ошмасин.
    test('ҳарф ораси шрифтнинг 5% идан ошмайди', () {
      expect(AvaText.feedRow.letterSpacing!,
          lessThanOrEqualTo(AvaText.feedRow.fontSize! * 0.05));
    });

    // Олдинги эга қарори (2026-09-26) бузилмаганини қўриқлайди.
    test('шрифт 12, қатор баландлиги аниқ 14 px — ўзгармаган', () {
      expect(AvaText.feedRow.fontSize, 12);
      expect(AvaText.feedRow.fontSize! * AvaText.feedRow.height!,
          closeTo(14, 1e-9));
    });
  });

  group('Шрифт файллари', () {
    // pubspec.yaml да эълон қилинган ҳар бир вазн ҳақиқатан жойида
    // турганини текширади — файл тасодифан ўчса, тест йиқилади.
    test('Inter нинг 5 вазни assets/fonts да бор', () {
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
        final f = File('assets/fonts/Inter-$w.ttf');
        expect(f.existsSync(), isTrue, reason: 'assets/fonts/Inter-$w.ttf yo‘q');
        expect(f.lengthSync(), greaterThan(10000));
      }
    });
  });
}

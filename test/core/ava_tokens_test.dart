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
      expect(AvaRadius.card, 12);
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
      expect(AvaLight.brandSoft, const Color(0xFFFFF0D1));
      expect(AvaLight.bg, const Color(0xFFFFF0D1));
      expect(AvaLight.ink, const Color(0xFF171717));
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
      expect(_contrast(const Color(0xFFB45309), AvaLight.bg), lessThan(4.5));
    });

    // Илиқ нейтраллар: қават поғонаси сақланади, иккиламчи матн ўқилади.
    test('илиқ нейтраллар — поғона ва ўқилиш', () {
      // positive: оқ рамка ↔ ботиқ майдон фарқи эскисидан (1.13) кам эмас
      expect(_contrast(AvaLight.surface, AvaLight.surface2), greaterThanOrEqualTo(1.13));
      // positive: карточка чизиғи крем фонда эскисидан (1.13) кучлироқ
      expect(_contrast(AvaLight.line, AvaLight.bg), greaterThan(1.13));
      // boundary: иккиламчи матн ботиқ майдон ва чипда AA
      expect(_contrast(AvaLight.ink2, AvaLight.surface2), greaterThanOrEqualTo(4.5));
      expect(_contrast(AvaLight.ink2, AvaLight.chip), greaterThanOrEqualTo(4.5));
      // negative: эски кўк-кулранг қийматлар қайтиб келмасин
      expect(AvaLight.surface2, isNot(const Color(0xFFEEF1F6)));
      expect(AvaLight.line, isNot(const Color(0xFFDFE4EC)));
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

import 'dart:io';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(AvaText.sectionTitle.fontWeight, FontWeight.w800);
      expect(AvaText.price.fontWeight, FontWeight.w800);
      expect(AvaText.navLabel.fontSize, 11);
    });
  });

  group('AppColors — эски API янги токенларга боғланган', () {
    test('бренд номлари brand га', () {
      expect(AppColors.primary, AvaLight.brand);
      expect(AppColors.primaryDark, AvaLight.brand);
      expect(AppColors.button, AvaLight.brand);
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

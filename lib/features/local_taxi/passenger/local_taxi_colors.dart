import 'package:flutter/material.dart';

import '../../../core/theme/ava_tokens.dart';

/// Маҳаллий такси (йўловчи) палитраси.
///
/// Илгари бу модул атайлаб teal палитрада эди — шаҳарларародан ажралиб
/// туриши учун. Янги дизайн тизимида битта бренд ранги бор, шунинг учун
/// teal олиб ташланди ва номлар [AvaColors] токенларига боғланди.
/// Модуллар энди ранг билан эмас, сарлавҳа ва иконка билан ажралади.
abstract final class LocalTaxiColors {
  /// AppBar / CTA / асосий бренд.
  static const Color primary = AvaLight.brand;

  /// Градиент ўрта / иккинчи бренд.
  static const Color primaryMid = AvaLight.brand;

  /// Ёруғ акцент.
  static const Color accent = AvaLight.brand;

  /// Экран фони.
  static const Color bg = AvaLight.bg;

  /// Карта / sheet.
  static const Color surface = AvaLight.surface;

  /// Юмшоқ фон.
  static const Color surfaceSoft = AvaLight.surface2;

  /// Чегара.
  static const Color border = AvaLight.line;

  /// Асосий матн.
  static const Color text = AvaLight.ink;

  /// Иккинчи матн.
  static const Color textMuted = AvaLight.ink2;

  /// Учинчи / иконка.
  static const Color textFaint = AvaLight.ink3;

  static const Color success = AvaLight.ok;
  static const Color successSoft = AvaLight.okSoft;

  static const Color danger = AvaLight.danger;
  static const Color dangerSoft = AvaLight.dangerSoft;

  static const Color warning = AvaLight.warn;
  static const Color warningSoft = AvaLight.warnSoft;

  static const Color onPrimary = AvaLight.brandInk;

  /// Қаердан нуқта.
  static const Color fromDot = AvaLight.ok;

  /// Қаерга нуқта.
  static const Color toDot = AvaLight.danger;
}

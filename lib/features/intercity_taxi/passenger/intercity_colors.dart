import 'package:flutter/material.dart';

import '../../../core/theme/ava_tokens.dart';

/// Шаҳарлараро такси (йўловчи) палитраси.
///
/// Эндиликда бу — [AvaColors] токенларининг шу модулдаги семантик номлари,
/// алоҳида палитра эмас: дизайн тизимида битта бренд ранги бор.
/// Янги код тўғридан-тўғри `context.ava` ишлатса ҳам бўлади.
abstract final class IntercityColors {
  /// Асосий бренд (AppBar, CTA).
  static const Color primary = AvaLight.brand;

  /// Градиент / иккинчи бренд.
  static const Color primaryMid = AvaLight.brand;

  /// Ёруғ акцент (chip, highlight).
  static const Color accent = AvaLight.brand;

  /// Экран фони.
  static const Color bg = AvaLight.bg;

  /// Карта / sheet юзаси.
  static const Color surface = AvaLight.surface;

  /// Юмшоқ фон.
  static const Color surfaceSoft = AvaLight.surface2;

  /// Карта чегараси.
  static const Color border = AvaLight.line;

  /// Асосий матн.
  static const Color text = AvaLight.ink;

  /// Иккинчи даража матн.
  static const Color textMuted = AvaLight.ink2;

  /// Учинчи даража / иконка.
  static const Color textFaint = AvaLight.ink3;

  /// Муваффақият / «бор жой» / нарх.
  static const Color success = AvaLight.ok;
  static const Color successSoft = AvaLight.okSoft;

  /// Хато / бекор.
  static const Color danger = AvaLight.danger;
  static const Color dangerSoft = AvaLight.dangerSoft;

  /// Огоҳлантириш / кутилмоқда.
  static const Color warning = AvaLight.warn;
  static const Color warningSoft = AvaLight.warnSoft;

  /// Маълумот / янги ҳайдовчи.
  static const Color info = AvaLight.brand;
  static const Color infoSoft = AvaLight.brandSoft;

  /// Рейтинг юлдузи.
  static const Color gold = AvaLight.warn;

  /// Бренд устидаги матн.
  static const Color onPrimary = AvaLight.brandInk;

  /// Қидирув «Қаердан» нуқтаси.
  static const Color fromDot = AvaLight.ok;

  /// Қидирув «Қаерга» нуқтаси.
  static const Color toDot = AvaLight.danger;
}

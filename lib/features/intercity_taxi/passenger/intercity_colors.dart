import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Шаҳарлараро такси (йўловчи) — AVA neon lime билан мутаносиб палитра.
///
/// Material `Colors.green/blue/orange` ишлатилмасин; шу класс орқали.
abstract final class IntercityColors {
  /// Асосий бренд (AppBar, CTA).
  static const Color primary = AppColors.limeDeep;

  /// Градиент / иккинчи бренд.
  static const Color primaryMid = AppColors.limeEdge;

  /// Ёруғ акцент (chip, highlight).
  static const Color accent = AppColors.limeMid;

  /// Экран фони.
  static const Color bg = AppColors.scaffold;

  /// Карта / sheet юзаси.
  static const Color surface = Color(0xFFFFFFFF);

  /// Юмшоқ яшил-оқ фон.
  static const Color surfaceSoft = Color(0xFFF4FBE6);

  /// Карта чегараси.
  static const Color border = AppColors.cardBorderMuted;

  /// Асосий матн.
  static const Color text = Color(0xFF102418);

  /// Иккинчи даража матн.
  static const Color textMuted = AppColors.sectionMuted;

  /// Учинчи даража / иконка.
  static const Color textFaint = Color(0xFF7A9460);

  /// Муваффақият / «бор жой» / нарх.
  static const Color success = AppColors.limeDeep;
  static const Color successSoft = Color(0xFFE8F5D0);

  /// Хато / бекор.
  static const Color danger = AppColors.error;
  static const Color dangerSoft = Color(0xFFFFEBEE);

  /// Огоҳлантириш / кутилмоқда.
  static const Color warning = AppColors.accentGold;
  static const Color warningSoft = Color(0xFFFFF8E1);

  /// Маълумот / янги ҳайдовчи.
  static const Color info = AppColors.limeEdge;
  static const Color infoSoft = Color(0xFFEEF8D8);

  /// Рейтинг юлдузи.
  static const Color gold = AppColors.accentGold;

  /// Тўқ бренд устидаги матн.
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Қидирув «Қаердан» нуқтаси.
  static const Color fromDot = AppColors.limeMid;

  /// Қидирув «Қаерга» нуқтаси.
  static const Color toDot = AppColors.error;
}

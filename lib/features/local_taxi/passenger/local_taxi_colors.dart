import 'package:flutter/material.dart';

/// Маҳаллий такси (йўловчи) — teal палитра.
///
/// Шаҳарлараро (`IntercityColors` neon lime) дан атайлаб фарқли.
abstract final class LocalTaxiColors {
  /// AppBar / CTA / асосий бренд.
  static const Color primary = Color(0xFF0F766E);

  /// Градиент ўрта / иккинчи бренд.
  static const Color primaryMid = Color(0xFF0D9488);

  /// Ёруғ акцент.
  static const Color accent = Color(0xFF14B8A6);

  /// Экран фони (lime эмас).
  static const Color bg = Color(0xFFE6F5F3);

  /// Карта / sheet.
  static const Color surface = Color(0xFFFFFFFF);

  /// Юмшоқ teal фон.
  static const Color surfaceSoft = Color(0xFFD5F0EC);

  /// Чегара.
  static const Color border = Color(0xFF9AD4CC);

  /// Асосий матн.
  static const Color text = Color(0xFF0A2F2C);

  /// Иккинчи матн.
  static const Color textMuted = Color(0xFF3D6B66);

  /// Учинчи / иконка.
  static const Color textFaint = Color(0xFF6A9A94);

  static const Color success = Color(0xFF0F766E);
  static const Color successSoft = Color(0xFFD5F0EC);

  static const Color danger = Color(0xFFB71C1C);
  static const Color dangerSoft = Color(0xFFFFEBEE);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSoft = Color(0xFFFFF7E6);

  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Қаердан нуқта.
  static const Color fromDot = Color(0xFF14B8A6);

  /// Қаерга нуқта.
  static const Color toDot = Color(0xFFEF4444);
}

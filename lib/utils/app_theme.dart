import 'package:flutter/material.dart';

// ══════════════════════════════════════
// TYPOGRAPHY
// ══════════════════════════════════════
class AppText {
  // Сарлавҳалар
  static const double titleLarge  = 18.0;
  static const double titleMedium = 16.0;
  static const double titleSmall  = 14.0;

  // Асосий матн
  static const double bodyLarge   = 14.0;
  static const double bodyMedium  = 13.0;
  static const double bodySmall   = 12.0;

  // Ёрлиқлар
  static const double labelLarge  = 12.0;
  static const double labelSmall  = 11.0;
  static const double labelTiny   = 10.0;
}

// ══════════════════════════════════════
// COLOURS — модулларга уйғун
// ══════════════════════════════════════
class AppColors {
  // Асосий
  static const green1  = Color(0xFF1B5E20);
  static const green2  = Color(0xFF2E7D32);
  static const green3  = Color(0xFF43A047);

  // Модуллар
  static const bread       = Color(0xFFE65100); // Нон
  static const marshrut    = Color(0xFF00695C); // Маршрут такси
  static const localTaxi   = Color(0xFF1565C0); // Маҳаллий такси
  static const intercity   = Color(0xFF6A1B9A); // Шаҳарлараро
  static const jobTop      = Color(0xFF0277BD); // ИШ ТОП

  // Статус
  static const success = Color(0xFF2E7D32);
  static const error   = Color(0xFFB71C1C);
  static const warning = Color(0xFFE65100);
  static const info    = Color(0xFF1565C0);

  // Фон
  static const background = Color(0xFFF5F7FF);
  static const surface    = Colors.white;
}

// ══════════════════════════════════════
// TEXT STYLES — тайёр стиллар
// ══════════════════════════════════════
class AppStyles {
  // Сарлавҳалар
  static const titleLarge = TextStyle(
      fontSize: AppText.titleLarge, fontWeight: FontWeight.bold);
  static const titleMedium = TextStyle(
      fontSize: AppText.titleMedium, fontWeight: FontWeight.bold);
  static const titleSmall = TextStyle(
      fontSize: AppText.titleSmall, fontWeight: FontWeight.w600);

  // Матн
  static const bodyLarge  = TextStyle(fontSize: AppText.bodyLarge);
  static const bodyMedium = TextStyle(fontSize: AppText.bodyMedium);
  static const bodySmall  = TextStyle(fontSize: AppText.bodySmall);

  // Ёрлиқлар
  static const labelLarge = TextStyle(
      fontSize: AppText.labelLarge, fontWeight: FontWeight.w600);
  static const labelSmall = TextStyle(
      fontSize: AppText.labelSmall, fontWeight: FontWeight.w600);
  static const labelTiny  = TextStyle(fontSize: AppText.labelTiny);

  // Тугма
  static const buttonText = TextStyle(
      fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold);

  // Иккинчи даражали
  static TextStyle hint(Color color) =>
      TextStyle(fontSize: AppText.bodySmall, color: color);
  static TextStyle caption(Color color) =>
      TextStyle(fontSize: AppText.labelTiny, color: color);
}

// ══════════════════════════════════════
// MODULE THEMES — ҳар модул учун ранг тизими
// ══════════════════════════════════════
class ModuleTheme {
  final Color primary;
  final Color secondary;
  final Color surface;    // Oч фон
  final Color onSurface;  // Матн ранги
  final Color appBar;

  const ModuleTheme({
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.onSurface,
    required this.appBar,
  });

  // ── НОН — Норинж ──
  static const bread = ModuleTheme(
    primary:   Color(0xFFE65100),
    secondary: Color(0xFFFF8F00),
    surface:   Color(0xFFFFF3E0),
    onSurface: Color(0xFF4E2600),
    appBar:    Color(0xFFE65100),
  );

  // ── МАРШРУТ ТАКСИ — Ҳаворанг ──
  static const marshrut = ModuleTheme(
    primary:   Color(0xFF0288D1),
    secondary: Color(0xFF039BE5),
    surface:   Color(0xFFE1F5FE),
    onSurface: Color(0xFF00344D),
    appBar:    Color(0xFF0277BD),
  );

  // ── МАҲАЛЛИЙ ТАКСИ — Сариқ ──
  static const localTaxi = ModuleTheme(
    primary:   Color(0xFFF57F17),
    secondary: Color(0xFFFF8F00),
    surface:   Color(0xFFFFF8E1),
    onSurface: Color(0xFF4E3000),
    appBar:    Color(0xFFF57F17),
  );

  // ── ШАҲАРЛАРАРО — Бинафша ──
  static const intercity = ModuleTheme(
    primary:   Color(0xFF7B1FA2),
    secondary: Color(0xFF9C27B0),
    surface:   Color(0xFFF3E5F5),
    onSurface: Color(0xFF2D0040),
    appBar:    Color(0xFF7B1FA2),
  );

  // ── ИШ ТОП — Жигарранг ──
  static const jobTop = ModuleTheme(
    primary:   Color(0xFF5D4037),
    secondary: Color(0xFF795548),
    surface:   Color(0xFFEFEBE9),
    onSurface: Color(0xFF1B0000),
    appBar:    Color(0xFF5D4037),
  );
}
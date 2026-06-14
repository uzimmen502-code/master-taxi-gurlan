import 'package:flutter/material.dart';

// ══════════════════════════════════════
// TYPOGRAPHY
// ══════════════════════════════════════
abstract final class AppText {
  static const double titleLarge = 18.0;
  static const double titleMedium = 16.0;
  static const double titleSmall = 14.0;
  static const double bodyLarge = 14.0;
  static const double bodyMedium = 13.0;
  static const double bodySmall = 12.0;
  static const double labelLarge = 12.0;
  static const double labelSmall = 11.0;
  static const double labelTiny = 10.0;
}

// ══════════════════════════════════════
// COLOURS — yagona brend palitra
// ══════════════════════════════════════
abstract final class AppColors {
  static const scaffold = Color(0xFFF7FAF4);
  static const scaffoldGradientEnd = Color(0xFFEEF7E8);

  static const primary = Color(0xFF0E7A38);
  static const primaryDark = Color(0xFF14532D);
  static const primaryMid = Color(0xFF2E9E57);
  static const primarySoft = Color(0xFF2C5A3D);

  static const cardGradientStart = Color(0xFFF4F9EF);
  static const cardGradientEnd = Color(0xFFE6F2DE);
  static const cardImageBg = Color(0xFFEDF7E8);
  static const tickerShell = Color(0xFFEEF7E8);
  static const bottomBarCapsule = Color(0xFFFFFFFF);
  static const arabicText = Color(0xFF0E7A38);

  /// Bosh ekran «500 СЎМ» festive (faqat home kartada).
  static const accentOrange = AppColors.primary;
  static const accentGold = Color(0xFFF9A825);

  static const background = scaffold;
  static const moduleBg = scaffold;
  static const surface = Colors.white;

  /// Tugmalar (AppBar `primary`дан тўқроқ).
  static const button = primaryDark;

  /// Semantik (xato / ogohlantirish — brenddan ajralgan).
  static const success = primaryMid;
  static const error = Color(0xFFB71C1C);
  static const warning = AppColors.primary;
  static const info = primary;
}

abstract final class AppStyles {
  static const titleLarge = TextStyle(
      fontSize: AppText.titleLarge, fontWeight: FontWeight.bold);
  static const titleMedium = TextStyle(
      fontSize: AppText.titleMedium, fontWeight: FontWeight.bold);
  static const titleSmall = TextStyle(
      fontSize: AppText.titleSmall, fontWeight: FontWeight.w600);
  static const bodyLarge = TextStyle(fontSize: AppText.bodyLarge);
  static const bodyMedium = TextStyle(fontSize: AppText.bodyMedium);
  static const bodySmall = TextStyle(fontSize: AppText.bodySmall);
  static const labelLarge = TextStyle(
      fontSize: AppText.labelLarge, fontWeight: FontWeight.w600);
  static const labelSmall = TextStyle(
      fontSize: AppText.labelSmall, fontWeight: FontWeight.w600);
  static const labelTiny = TextStyle(fontSize: AppText.labelTiny);
  static const buttonText = TextStyle(
      fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold);

  static TextStyle hint(Color color) =>
      TextStyle(fontSize: AppText.bodySmall, color: color);
  static TextStyle caption(Color color) =>
      TextStyle(fontSize: AppText.labelTiny, color: color);
}

/// Modul ekranlari — barchasi yashil tema.
class ModuleTheme {
  final Color primary;
  final Color secondary;
  final Color surface;
  final Color onSurface;
  final Color appBar;

  const ModuleTheme({
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.onSurface,
    required this.appBar,
  });

  static const bread = _all;
  static const marshrut = _all;
  static const localTaxi = _all;
  static const intercity = _all;
  static const jobTop = _all;

  static const _all = ModuleTheme(
    primary: AppColors.button,
    secondary: AppColors.primaryMid,
    surface: AppColors.moduleBg,
    onSurface: AppColors.primaryDark,
    appBar: AppColors.primary,
  );
}

abstract final class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.scaffold,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: AppColors.primaryDark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.bottomBarCapsule,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : const Color(0xFF9CA3AF),
          );
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.button,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.button,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.button,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.primary.withValues(alpha: 0.12),
      ),
    );
  }

  static ThemeData get adminWeb => light.copyWith(
        scaffoldBackgroundColor: AppColors.scaffold,
        appBarTheme: light.appBarTheme.copyWith(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
      );

  static BoxDecoration get cardGradient => homeModuleCardDecoration;

  /// Bosh ekran modul kartalari — ingichka yaltiroq yashil kontur.
  static BoxDecoration get homeModuleCardDecoration => BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.cardGradientStart,
            AppColors.cardGradientEnd,
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          width: 1.0,
          color: AppColors.primaryMid.withValues(alpha: 0.92),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140E7A38),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x335FD68A),
            blurRadius: 3,
            spreadRadius: 0,
          ),
        ],
      );
}

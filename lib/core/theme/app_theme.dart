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
// COLOURS — yagona brend palitra (neon lime)
// ══════════════════════════════════════
abstract final class AppColors {
  /// Асосий ёруғ — электрик лайм.
  static const lime = Color(0xFFB7FF1A);
  /// Энг ёруғ — неон сариқ-яшил.
  static const limeBright = Color(0xFFD9FF3F);
  /// Highlight — лимон оқ-яшил.
  static const limeHighlight = Color(0xFFF6FF8A);
  /// Ўрта тон — тоза лайм.
  static const limeMid = Color(0xFF9CFF00);
  /// Чет қисми — тўқ табиий яшил.
  static const limeEdge = Color(0xFF73C800);
  /// Энг қоронғи — чуқур яшил.
  static const limeDeep = Color(0xFF4E9F00);

  static const scaffold = lime;
  static const scaffoldGradientEnd = limeBright;

  static const primary = limeEdge;
  static const primaryDark = limeDeep;
  static const primaryMid = limeMid;
  static const primarySoft = limeEdge;

  static const cardGradientStart = limeHighlight;
  static const cardGradientEnd = limeBright;
  static const cardImageBg = limeHighlight;

  /// Home/courier kartalari uchun muted kontur / yorliq.
  static const cardBorderMuted = Color(0xFFB8E060);
  static const sectionMuted = Color(0xFF5A7A20);
  static const courierGreen = limeDeep;
  static const tickerShell = limeHighlight;
  static const bottomBarCapsule = Color(0xFFFFFFFF);
  static const arabicText = limeEdge;

  /// Bosh ekran «500 СЎМ» festive (faqat home kartada).
  static const accentOrange = limeEdge;
  static const accentGold = Color(0xFFF9A825);

  static const background = scaffold;
  static const moduleBg = scaffold;
  static const surface = Colors.white;

  /// Tugmalar — энг қоронғи лайм (оқ матн учун контраст).
  static const button = limeDeep;

  /// Semantik (xato / ogohlantirish — brenddan ajralgan).
  static const success = limeMid;
  static const error = Color(0xFFB71C1C);
  static const warning = limeEdge;
  static const info = limeEdge;
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
            color: Color(0x334E9F00),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x339CFF00),
            blurRadius: 3,
            spreadRadius: 0,
          ),
        ],
      );
}

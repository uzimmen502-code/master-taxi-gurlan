import 'package:flutter/material.dart';

import 'ava_tokens.dart';

export 'ava_tokens.dart';

// ══════════════════════════════════════
// TYPOGRAPHY
// ══════════════════════════════════════
// Ўлчамлар янги шкалага аллақачон мос (16 / 14 / 13 / 12 / 11), шунинг
// учун номлар ва қийматлар ўзгармади — 53 та файл тегилмайди.
// Янги семантик услублар: `AvaText` (ava_tokens.dart).
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
// COLOURS
// ══════════════════════════════════════

/// Эски ранг API'си — энди янги токенларга йўналтирилган.
///
/// Янги код `context.ava` (қаранг: [AvaColors]) ишлатсин. Бу синф фақат
/// мавжуд 189 та файл бузилмаслиги учун турибди ва модуллар бирма-бир
/// кўчирилгач олиб ташланади.
///
/// Эслатма: `lime*` номлари тарихий — қийматлари энди лайм эмас.
abstract final class AppColors {
  // ─── Тарихий «lime» номлари ───
  static const lime = AvaLight.bg;
  static const limeBright = AvaLight.surface2;
  static const limeHighlight = AvaLight.surface;
  static const limeMid = AvaLight.brand;
  static const limeEdge = AvaLight.brand;
  static const limeDeep = AvaLight.brand;

  // ─── Фон ───
  static const scaffold = AvaLight.bg;
  static const background = AvaLight.bg;
  static const moduleBg = AvaLight.bg;
  static const surface = AvaLight.surface;

  // ─── Бренд ───
  // Эски палитрада уччала «primary» тус иерархия учун эди; янги тизимда
  // битта бренд ранги бор, шунинг учун учаласи ҳам `brand`.
  static const primary = AvaLight.brand;
  static const primaryDark = AvaLight.brand;
  static const primaryMid = AvaLight.brand;
  static const primarySoft = AvaLight.brandSoft;
  static const button = AvaLight.brand;

  // ─── Усти ва контур ───
  static const cardImageBg = AvaLight.surface2;
  static const cardBorderMuted = AvaLight.line;
  static const tickerShell = AvaLight.surface;
  static const sectionMuted = AvaLight.ink2;

  // ─── Семантик ───
  static const success = AvaLight.ok;
  static const error = AvaLight.danger;
  static const warning = AvaLight.warn;
  static const info = AvaLight.brand;
  static const accentGold = AvaLight.warn;
}

// ══════════════════════════════════════
// THEME
// ══════════════════════════════════════

abstract final class AppTheme {
  static ThemeData get light => _build(
        brightness: Brightness.light,
        c: AvaColors.light,
      );

  /// Ёзилган, лекин ҳали `MaterialApp`га уланмаган (эга қарори).
  /// Ёқиш: `main.dart` да `darkTheme: AppTheme.dark` + `themeMode`.
  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        c: AvaColors.dark,
      );

  static ThemeData get adminWeb => light;

  static ThemeData _build({
    required Brightness brightness,
    required AvaColors c,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AvaFont.family,
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.brand,
        onPrimary: c.brandInk,
        primaryContainer: c.brandSoft,
        onPrimaryContainer: c.brand,
        secondary: c.brand,
        onSecondary: c.brandInk,
        surface: c.surface,
        onSurface: c.ink,
        surfaceContainerHighest: c.surface2,
        onSurfaceVariant: c.ink2,
        outline: c.line,
        outlineVariant: c.line,
        error: c.danger,
        onError: c.brandInk,
        errorContainer: c.dangerSoft,
        onErrorContainer: c.danger,
      ),
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.brand,
        foregroundColor: c.brandInk,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: c.brandInk),
        actionsIconTheme: IconThemeData(color: c.brandInk),
        titleTextStyle: TextStyle(
          fontFamily: AvaFont.family,
          fontSize: AppText.titleMedium,
          fontWeight: FontWeight.w800,
          color: c.brandInk,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AvaRadius.card),
          side: BorderSide(color: c.line),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.brandSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AvaText.navLabel.copyWith(
            fontFamily: AvaFont.family,
            color: selected ? c.brand : c.ink3,
          );
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.brandInk,
          elevation: 0,
          minimumSize: const Size(0, AvaTap.minSize),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AvaRadius.card),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.brandInk,
          minimumSize: const Size(0, AvaTap.minSize),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AvaRadius.card),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.brand,
          side: BorderSide(color: c.line),
          minimumSize: const Size(0, AvaTap.minSize),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AvaRadius.card),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.brand),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.brand,
        foregroundColor: c.brandInk,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.chip,
        side: BorderSide(color: c.line),
        labelStyle: AvaText.caption.copyWith(
          fontFamily: AvaFont.family,
          color: c.ink2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AvaRadius.chip),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: AvaText.body.copyWith(
          fontFamily: AvaFont.family,
          color: c.ink3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AvaRadius.search),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AvaRadius.search),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AvaRadius.search),
          borderSide: BorderSide(color: c.brand, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: AvaText.body.copyWith(
          fontFamily: AvaFont.family,
          color: c.bg,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AvaRadius.card),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AvaRadius.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AvaRadius.sheet),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.brand),
    );
  }
}

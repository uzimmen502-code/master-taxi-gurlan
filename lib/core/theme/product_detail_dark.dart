import 'package:flutter/material.dart';

/// Маҳсулот тафсилоти экранларининг ҚОРА дизайни.
///
/// Эга қарори (2026-10-17, қора намунани кўргач): қора мавзу ФАҚАТ
/// маҳсулот тафсилоти экранида — бутун иловага ёки бошқа экранларга
/// ТАЪСИР ҚИЛМАЙДИ. Бренд ранги (тўқ сариқ #FFA500) ўша, фақат фон ва
/// матн қоронғи. Шунинг учун бу алоҳида палитра: `AvaDark` (бутун илованинг
/// кўк-бренд қоронғи мавзуси) билан аралашмайди.
abstract final class PdDark {
  static const bg = Color(0xFF121212);
  static const surface = Color(0xFF1C1C1E);
  static const surface2 = Color(0xFF2A2A2D);
  static const line = Color(0xFF2E2E31);
  static const ink = Color(0xFFF2F2F2);
  static const muted = Color(0xFF9A9A9F);

  /// Бренд — AvaLight.brand билан бир хил (#FFA500).
  static const brand = Color(0xFFFFA500);
  static const brandInk = Color(0xFF1A1200);
  static const brandSoft = Color(0xFF2A2112);
  static const ok = Color(0xFF5FD08A);

  /// Экран ичидаги стандарт виджетлар (AppBar, SnackBar, тугмалар) қора
  /// чиқиши учун — фақат шу экран шахобчасига ўралади.
  static ThemeData theme(ThemeData base) {
    final scheme = ColorScheme.dark(
      primary: brand,
      onPrimary: brandInk,
      secondary: brand,
      surface: surface,
      onSurface: ink,
      error: const Color(0xFFFF8A80),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: line,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      iconTheme: const IconThemeData(color: ink),
    );
  }
}

/// [child] ни шу экранга хос қора мавзуга ўрайди.
class ProductDetailDark extends StatelessWidget {
  const ProductDetailDark({super.key, required this.child});

  final Widget child;

  /// Тизим шрифти катта (×1.3–1.5) бўлган қурилмада матн шу экранда ×1.15
  /// дан ошмайди: аввал нарх, поғоналар ва «ўхшашлар» экранга сиғмас эди
  /// (эга қурилмасида кўрилган, 2026-10-17; «Менинг бизнесим» варағидаги
  /// қоида билан бир хил).
  static const double maxTextScale = 1.15;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: maxTextScale,
        child: Theme(data: PdDark.theme(Theme.of(context)), child: child),
      );
}

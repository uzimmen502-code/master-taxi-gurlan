// AVA дизайн токенлари — рангларнинг ягона манбаи.
//
// Бу файл «нима» эканини (қиймат) сақлайди; «қандай кўринишини» (тема)
// `AppTheme` йиғади. Эски `AppColors` ҳам шу ердаги қийматларга
// йўналтирилган — иккита палитра йўқ.
//
// Қоронғи режим: `AvaColors.dark` тўлиқ ёзилган, лекин ҳозирча
// `MaterialApp`га уланмаган (эга қарори — аввал ёруғ режим чиқади).
// Ёқиш учун `main.dart`да `darkTheme: AppTheme.dark` + `themeMode` етарли.

import 'package:flutter/material.dart';

// ─── Хом қийматлар ──────────────────────────────────────────────────────────
// `const` бўлиши шарт: `AppColors` аъзолари 189 та файлда `const` ифодалар
// ичида ишлатилади (масалан `const Icon(color: AppColors.primary)`).

/// Ёруғ режим хом қийматлари.
abstract final class AvaLight {
  static const bg = Color(0xFFF3F5F8);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFEEF1F6);
  static const line = Color(0xFFDFE4EC);
  static const ink = Color(0xFF1A1A1A);
  static const ink2 = Color(0xFF6B6B6B);
  static const ink3 = Color(0xFF9E9E9E);
  static const brand = Color(0xFF1E4FD8);
  static const brandInk = Color(0xFFFFFFFF);
  static const brandSoft = Color(0xFFE8EEFF);
  static const ok = Color(0xFF177A4C);
  static const okSoft = Color(0xFFE4F5EC);
  static const warn = Color(0xFFB4590E);
  static const warnSoft = Color(0xFFFCEEE0);
  static const chip = Color(0xFFF4F6FA);

  /// ⚠️ Тавсиф жадвалида хатолик (danger) токени йўқ, лекин кодда
  /// `AppColors.error` 8 жойда ишлатилади ва уни йўқотиб бўлмайди.
  /// Қиймат палитрага мослаб танланди — эга тасдиқласа, ўзгармайди.
  static const danger = Color(0xFFC0332E);
  static const dangerSoft = Color(0xFFFDECEA);

  /// Лайм акцент — фақат «Барча хизматлар» катаги ва қидирув майдони
  /// учун (эга қарори). `brand`ни алмаштирмайди, унга қўшимча.
  static const accentLime = Color(0xFFCCD631);

  /// Лайм фон устидаги матн/иконка — контраст учун қора-яшил тон.
  static const accentLimeInk = Color(0xFF2B2E1A);

  /// Лайм фонсиз (оддий) ҳолатдаги хизмат-иконка ранги — тўқроқ стоп.
  static const accentLimeIcon = Color(0xFF8A9424);
}

/// Қоронғи режим хом қийматлари (ҳозирча уланмаган).
abstract final class AvaDark {
  static const bg = Color(0xFF12151C);
  static const surface = Color(0xFF1B1F29);
  static const surface2 = Color(0xFF232834);
  static const line = Color(0xFF333A48);
  static const ink = Color(0xFFEDEFF4);
  static const ink2 = Color(0xFFAEB5C4);
  static const ink3 = Color(0xFF7C8494);
  static const brand = Color(0xFF6E93FF);
  static const brandInk = Color(0xFF0B1020);
  static const brandSoft = Color(0xFF1E2A4C);
  static const ok = Color(0xFF6FD3A3);
  static const okSoft = Color(0xFF173327);
  static const warn = Color(0xFFF0A868);
  static const warnSoft = Color(0xFF3A2A18);
  static const chip = Color(0xFF232834);

  /// Қаранг: [AvaLight.danger].
  static const danger = Color(0xFFFF8A80);
  static const dangerSoft = Color(0xFF3A1D1B);

  /// Қаранг: [AvaLight.accentLime].
  static const accentLime = Color(0xFFCCD631);
  static const accentLimeInk = Color(0xFF2B2E1A);
  static const accentLimeIcon = Color(0xFFB9C93E);
}

// ─── Тема кенгайтмаси ───────────────────────────────────────────────────────

/// Виджетлар учун ранг токенлари: `context.ava.brand`.
///
/// `Theme.of(context)` орқали келади, шунинг учун қоронғи режим ёқилганда
/// виджетларни ўзгартириш керак эмас.
@immutable
class AvaColors extends ThemeExtension<AvaColors> {
  const AvaColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.brand,
    required this.brandInk,
    required this.brandSoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.chip,
    required this.danger,
    required this.dangerSoft,
    required this.accentLime,
    required this.accentLimeInk,
    required this.accentLimeIcon,
  });

  /// Экран фони.
  final Color bg;

  /// Карточка / варақа усти.
  final Color surface;

  /// Иккиламчи усти — расм ўрни, ажратилган блок.
  final Color surface2;

  /// Ажратувчи чизиқ ва контур.
  final Color line;

  /// Асосий матн.
  final Color ink;

  /// Иккиламчи матн.
  final Color ink2;

  /// Учламчи матн — изоҳ, хира ёрлиқ.
  final Color ink3;

  /// Бренд ранги — ягона акцент.
  final Color brand;

  /// Бренд устидаги матн/иконка.
  final Color brandInk;

  /// Бренднинг юмшоқ фони — чип, белги.
  final Color brandSoft;

  /// Муваффақият.
  final Color ok;
  final Color okSoft;

  /// Огоҳлантириш.
  final Color warn;
  final Color warnSoft;

  /// Чип фони.
  final Color chip;

  /// Хатолик — қаранг: [AvaLight.danger].
  final Color danger;
  final Color dangerSoft;

  /// Лайм акцент — қаранг: [AvaLight.accentLime].
  final Color accentLime;
  final Color accentLimeInk;
  final Color accentLimeIcon;

  static const light = AvaColors(
    bg: AvaLight.bg,
    surface: AvaLight.surface,
    surface2: AvaLight.surface2,
    line: AvaLight.line,
    ink: AvaLight.ink,
    ink2: AvaLight.ink2,
    ink3: AvaLight.ink3,
    brand: AvaLight.brand,
    brandInk: AvaLight.brandInk,
    brandSoft: AvaLight.brandSoft,
    ok: AvaLight.ok,
    okSoft: AvaLight.okSoft,
    warn: AvaLight.warn,
    warnSoft: AvaLight.warnSoft,
    chip: AvaLight.chip,
    danger: AvaLight.danger,
    dangerSoft: AvaLight.dangerSoft,
    accentLime: AvaLight.accentLime,
    accentLimeInk: AvaLight.accentLimeInk,
    accentLimeIcon: AvaLight.accentLimeIcon,
  );

  static const dark = AvaColors(
    bg: AvaDark.bg,
    surface: AvaDark.surface,
    surface2: AvaDark.surface2,
    line: AvaDark.line,
    ink: AvaDark.ink,
    ink2: AvaDark.ink2,
    ink3: AvaDark.ink3,
    brand: AvaDark.brand,
    brandInk: AvaDark.brandInk,
    brandSoft: AvaDark.brandSoft,
    ok: AvaDark.ok,
    okSoft: AvaDark.okSoft,
    warn: AvaDark.warn,
    warnSoft: AvaDark.warnSoft,
    chip: AvaDark.chip,
    danger: AvaDark.danger,
    dangerSoft: AvaDark.dangerSoft,
    accentLime: AvaDark.accentLime,
    accentLimeInk: AvaDark.accentLimeInk,
    accentLimeIcon: AvaDark.accentLimeIcon,
  );

  @override
  AvaColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? brand,
    Color? brandInk,
    Color? brandSoft,
    Color? ok,
    Color? okSoft,
    Color? warn,
    Color? warnSoft,
    Color? chip,
    Color? danger,
    Color? dangerSoft,
    Color? accentLime,
    Color? accentLimeInk,
    Color? accentLimeIcon,
  }) {
    return AvaColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      brand: brand ?? this.brand,
      brandInk: brandInk ?? this.brandInk,
      brandSoft: brandSoft ?? this.brandSoft,
      ok: ok ?? this.ok,
      okSoft: okSoft ?? this.okSoft,
      warn: warn ?? this.warn,
      warnSoft: warnSoft ?? this.warnSoft,
      chip: chip ?? this.chip,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      accentLime: accentLime ?? this.accentLime,
      accentLimeInk: accentLimeInk ?? this.accentLimeInk,
      accentLimeIcon: accentLimeIcon ?? this.accentLimeIcon,
    );
  }

  @override
  AvaColors lerp(ThemeExtension<AvaColors>? other, double t) {
    if (other is! AvaColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AvaColors(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      line: c(line, other.line),
      ink: c(ink, other.ink),
      ink2: c(ink2, other.ink2),
      ink3: c(ink3, other.ink3),
      brand: c(brand, other.brand),
      brandInk: c(brandInk, other.brandInk),
      brandSoft: c(brandSoft, other.brandSoft),
      ok: c(ok, other.ok),
      okSoft: c(okSoft, other.okSoft),
      warn: c(warn, other.warn),
      warnSoft: c(warnSoft, other.warnSoft),
      chip: c(chip, other.chip),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      accentLime: c(accentLime, other.accentLime),
      accentLimeInk: c(accentLimeInk, other.accentLimeInk),
      accentLimeIcon: c(accentLimeIcon, other.accentLimeIcon),
    );
  }
}

/// `context.ava.brand` — қисқа йўл.
extension AvaColorsX on BuildContext {
  AvaColors get ava =>
      Theme.of(this).extension<AvaColors>() ?? AvaColors.light;
}

// ─── Ўлчамлар ───────────────────────────────────────────────────────────────

/// Радиуслар.
abstract final class AvaRadius {
  /// Карточка.
  static const double card = 12;

  /// Қидирув майдони.
  static const double search = 14;

  /// Чип / белги — тўлиқ юмалоқ эмас, ихчам.
  static const double chip = 999;

  /// Пастдан чиқадиган варақа.
  static const double sheet = 20;
}

/// Оралиқлар.
abstract final class AvaSpace {
  /// Экран четидаги бўшлиқ.
  static const double screen = 16;

  /// Бўлимлар орасидаги минимал масофа (Avito услуби — зич feed).
  static const double sectionMin = 4;

  /// Бўлимлар орасидаги максимал масофа.
  static const double sectionMax = 6;

  /// Қатор ичидаги кичик оралиқ.
  static const double gap = 8;

  /// Бўлим сарлавҳаси ↔ мазмуни орасидаги масофа (Avito услуби).
  static const double sectionHeaderGap = 2;
}

/// Босиш майдонининг минимал ўлчами.
abstract final class AvaTap {
  static const double minSize = 44;
}

/// Матн услублари — тавсифдаги шкала.
///
/// Ранг берилмаган: уни чақирувчи `context.ava` дан олади, шунда
/// қоронғи режимда услубларни дублаш керак бўлмайди.
abstract final class AvaText {
  /// Бўлим сарлавҳаси — 16/600 (Avito услуби: фақат нарх «оғир»).
  static const sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  /// Маҳсулот номи — 13/400 (фото биринчи, матн иккинчи даражали).
  static const productName = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Нарх — 14/700 (ранги `brand`) — ягона «оғир нуқта».
  static const price = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  /// Асосий матн — 14/400.
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  /// Изоҳ — 12/400.
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Пастки меню ёрлиғи — 11/500.
  static const navLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
}

/// Илова шрифти.
///
/// Тавсифда Manrope сўралган эди, лекин Manrope'да ўзбек кириллига хос
/// `Қ` (U+049A), `Ғ` (U+0492), `Ҳ` (U+04B2) ҳарфлари ЙЎҚ — улар сўз
/// ўртасида тизим шрифтига тушиб кетарди. Тавсифдаги захира вариант
/// («Roboto ёки Inter») бўйича Inter танланди: у Қ/Ғ/Ҳ/Ў, `ʻ` ва `→`
/// белгиларини тўлиқ қоплайди (Roboto'да `→` йўқ).
abstract final class AvaFont {
  static const family = 'Inter';
}

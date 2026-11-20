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
///
/// «Енгил дизайн» (эга 2026-11-20): оч кулранг/оқ асос, ЯГОНА тўқ сариқ акцент
/// (фақат тугма, фаол ҳолат, асосий таклиф). Аввалги крем `FFF0D1` фон ва илиқ
/// нейтраллар (2026-10-07) шу қарор билан алмашди.
abstract final class AvaLight {
  /// Саҳифа фони (эга 2026-11-20). Аввал крем `FFF0D1`.
  static const bg = Color(0xFFF7F8FA);

  /// Карточка (эга 2026-11-20).
  static const surface = Color(0xFFFFFFFF);

  /// Иккиламчи усти — расм ўрни, ботиқ майдон. `ink2` устида ≥ 4.5 (AA).
  static const surface2 = Color(0xFFF2F4F7);

  /// Ингичка чегара (эга 2026-11-20).
  static const line = Color(0xFFE8EBEF);

  /// Асосий матн (эга 2026-11-20). Аввал `171717`.
  static const ink = Color(0xFF1F2328);
  static const inkRow = Color(0xFF344054);
  static const insetEdgeTop = Color(0xFFDDE1E7);
  static const insetEdgeBottom = Color(0xFFFFFFFF);

  /// Ботиқ майдоннинг ички сояси — совуқ кулранг, 45% тиниқлик.
  static const insetShadow = Color(0x73667085);

  /// Иккиламчи матн (эга 2026-11-20). Оқда 4.97, `bg` да 4.68.
  static const ink2 = Color(0xFF667085);
  /// Учламчи — соф нейтрал кулранг (ўзгармаган; EV харитаси нуқтаси шуни ишлатади).
  static const ink3 = Color(0xFF9E9E9E);

  // ─── Бренд (эга қарори, 2026-10-07): AVA Primary #FFA500 ───

  /// AVA Primary — тугма, фаол ҳолат, асосий таклиф ФОНИ (эга 2026-11-20: ягона акцент).
  /// ⚠️ Матн ранги сифатида ИШЛАТИЛМАСИН: оқ фонда контраст 1.97.
  static const brand = Color(0xFFFFA500);

  /// Бренд устидаги матн/иконка — тўқ. `FFA500` устида `171717` 9.08 беради.
  static const brandInk = Color(0xFF171717);

  /// Бренднинг юмшоқ фони — баннер, чип, белги (эга 2026-11-20: баннер фони `FFF3DF`).
  static const brandSoft = Color(0xFFFFF3DF);

  /// Primary dark — босилган ҳолат ва hover фони. Матнга ЯРАМАЙДИ.
  static const brandPressed = Color(0xFFE68A00);

  /// Оч фондаги бренд МАТНИ/иконкаси/ингичка чизиғи — нарх, ҳавола.
  /// Оқ `surface` да 5.63, `bg` да ≥ 5.
  static const brandText = Color(0xFFA84D08);

  static const ok = Color(0xFF177A4C);
  static const okSoft = Color(0xFFE4F5EC);
  static const warn = Color(0xFFB4590E);
  static const warnSoft = Color(0xFFFCEEE0);
  static const chip = Color(0xFFF2F4F7);

  static const danger = Color(0xFFC0332E);
  static const dangerSoft = Color(0xFFFDECEA);
}

/// Қоронғи режим хом қийматлари (ҳали `MaterialApp`га уланмаган).
///
/// Эга 2026-11-20 «енгил дизайн»га мос: нейтрал кулранг-қора асос ва ўша ЯГОНА
/// тўқ сариқ акцент (аввал вақтинча кўк `6E93FF` эди — қарор қилинмаган деб
/// белгиланган). Қоронғида акцент бир поғона ёруғроқ (`FFB020`) — тўқ фонда
/// тиниқ кўринади; босилгани — ёруғ режим бренди. Қийматлар PROPOSED.
abstract final class AvaDark {
  static const bg = Color(0xFF0F1115);
  static const surface = Color(0xFF181B20);
  static const surface2 = Color(0xFF22262D);
  static const line = Color(0xFF2C313A);
  static const ink = Color(0xFFE7E9EC);
  static const inkRow = Color(0xFFF2F4F7);
  static const insetEdgeTop = Color(0xFF0B0D10);
  static const insetEdgeBottom = Color(0xFF2C313A);

  /// Қоронғи мавзуда соя деярли қора ва кучлироқ.
  static const insetShadow = Color(0xB8000000);
  static const ink2 = Color(0xFFA3AAB6);
  static const ink3 = Color(0xFF757D8A);
  static const brand = Color(0xFFFFB020);
  static const brandInk = Color(0xFF171717);
  static const brandSoft = Color(0xFF2B2214);
  static const brandPressed = Color(0xFFFFA500);
  static const brandText = Color(0xFFFFB547);
  static const ok = Color(0xFF6FD3A3);
  static const okSoft = Color(0xFF173327);
  static const warn = Color(0xFFF0A868);
  static const warnSoft = Color(0xFF3A2A18);
  static const chip = Color(0xFF22262D);

  /// Қаранг: [AvaLight.danger].
  static const danger = Color(0xFFFF8A80);
  static const dangerSoft = Color(0xFF3A1D1B);
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
    required this.inkRow,
    required this.insetEdgeTop,
    required this.insetEdgeBottom,
    required this.insetShadow,
    required this.ink2,
    required this.ink3,
    required this.brand,
    required this.brandInk,
    required this.brandSoft,
    required this.brandPressed,
    required this.brandText,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.chip,
    required this.danger,
    required this.dangerSoft,
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

  /// Бош саҳифа бўлимидаги ЭЪЛОН ҚАТОРИ матни — асосий матндан САЛ очроқ
  /// (эга қарори, 2026-09-26). Атайлаб алоҳида токен: глобал [ink] га
  /// тегилмайди, яъни қолган экранлардаги матн ўз рангида қолади.
  final Color inkRow;

  /// Ботиқ майдоннинг ТЕПА чети — фондан тўқроқ.
  ///
  /// Flutter'да CSS'даги inset соя йўқ, шунинг учун «чуқурча» ҳисси
  /// икки четнинг фарқи билан ясалади: тепаси тўқ, пасти оч.
  final Color insetEdgeTop;

  /// Ботиқ майдоннинг ПАСТ чети — фондан очроқ.
  final Color insetEdgeBottom;

  /// Ботиқ майдоннинг ИЧКИ сояси (эга қарори, 2026-09-29 — «D» варианти).
  ///
  /// Тиниқлиги токеннинг ўзида: чақирувчи уни ўзгартирмайди, шунда
  /// иккала мавзуда ҳам соя бир хил кучда кўринади.
  /// Қаранг: `AvaInsetPanel`.
  final Color insetShadow;

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

  /// Босилган/hover ҳолатдаги бренд фони. Матнга ишлатилмайди.
  final Color brandPressed;

  /// Оч фондаги бренд матни, иконкаси ва ингичка чизиғи.
  /// [brand] ни матн ранги қилиб ишлатманг — шуни ишлатинг.
  final Color brandText;

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

  static const light = AvaColors(
    bg: AvaLight.bg,
    surface: AvaLight.surface,
    surface2: AvaLight.surface2,
    line: AvaLight.line,
    ink: AvaLight.ink,
    inkRow: AvaLight.inkRow,
    insetEdgeTop: AvaLight.insetEdgeTop,
    insetEdgeBottom: AvaLight.insetEdgeBottom,
    insetShadow: AvaLight.insetShadow,
    ink2: AvaLight.ink2,
    ink3: AvaLight.ink3,
    brand: AvaLight.brand,
    brandInk: AvaLight.brandInk,
    brandSoft: AvaLight.brandSoft,
    brandPressed: AvaLight.brandPressed,
    brandText: AvaLight.brandText,
    ok: AvaLight.ok,
    okSoft: AvaLight.okSoft,
    warn: AvaLight.warn,
    warnSoft: AvaLight.warnSoft,
    chip: AvaLight.chip,
    danger: AvaLight.danger,
    dangerSoft: AvaLight.dangerSoft,
  );

  static const dark = AvaColors(
    bg: AvaDark.bg,
    surface: AvaDark.surface,
    surface2: AvaDark.surface2,
    line: AvaDark.line,
    ink: AvaDark.ink,
    inkRow: AvaDark.inkRow,
    insetEdgeTop: AvaDark.insetEdgeTop,
    insetEdgeBottom: AvaDark.insetEdgeBottom,
    insetShadow: AvaDark.insetShadow,
    ink2: AvaDark.ink2,
    ink3: AvaDark.ink3,
    brand: AvaDark.brand,
    brandInk: AvaDark.brandInk,
    brandSoft: AvaDark.brandSoft,
    brandPressed: AvaDark.brandPressed,
    brandText: AvaDark.brandText,
    ok: AvaDark.ok,
    okSoft: AvaDark.okSoft,
    warn: AvaDark.warn,
    warnSoft: AvaDark.warnSoft,
    chip: AvaDark.chip,
    danger: AvaDark.danger,
    dangerSoft: AvaDark.dangerSoft,
  );

  @override
  AvaColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? ink,
    Color? inkRow,
    Color? insetEdgeTop,
    Color? insetEdgeBottom,
    Color? insetShadow,
    Color? ink2,
    Color? ink3,
    Color? brand,
    Color? brandInk,
    Color? brandSoft,
    Color? brandPressed,
    Color? brandText,
    Color? ok,
    Color? okSoft,
    Color? warn,
    Color? warnSoft,
    Color? chip,
    Color? danger,
    Color? dangerSoft,
  }) {
    return AvaColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      inkRow: inkRow ?? this.inkRow,
      insetEdgeTop: insetEdgeTop ?? this.insetEdgeTop,
      insetEdgeBottom: insetEdgeBottom ?? this.insetEdgeBottom,
      insetShadow: insetShadow ?? this.insetShadow,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      brand: brand ?? this.brand,
      brandInk: brandInk ?? this.brandInk,
      brandSoft: brandSoft ?? this.brandSoft,
      brandPressed: brandPressed ?? this.brandPressed,
      brandText: brandText ?? this.brandText,
      ok: ok ?? this.ok,
      okSoft: okSoft ?? this.okSoft,
      warn: warn ?? this.warn,
      warnSoft: warnSoft ?? this.warnSoft,
      chip: chip ?? this.chip,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
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
      inkRow: c(inkRow, other.inkRow),
      insetEdgeTop: c(insetEdgeTop, other.insetEdgeTop),
      insetEdgeBottom: c(insetEdgeBottom, other.insetEdgeBottom),
      insetShadow: c(insetShadow, other.insetShadow),
      ink2: c(ink2, other.ink2),
      ink3: c(ink3, other.ink3),
      brand: c(brand, other.brand),
      brandInk: c(brandInk, other.brandInk),
      brandSoft: c(brandSoft, other.brandSoft),
      brandPressed: c(brandPressed, other.brandPressed),
      brandText: c(brandText, other.brandText),
      ok: c(ok, other.ok),
      okSoft: c(okSoft, other.okSoft),
      warn: c(warn, other.warn),
      warnSoft: c(warnSoft, other.warnSoft),
      chip: c(chip, other.chip),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
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
  /// Карточка — 16 (эга 2026-11-20 «енгил дизайн»; аввал 12).
  static const double card = 16;

  /// Бош саҳифа баннери (эга 2026-11-20: 14–16).
  static const double banner = 16;

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

  /// Бош саҳифа катта карточкалари орасидаги масофа (эга 2026-11-20: 10–12).
  static const double cardGap = 10;

  /// Бош саҳифа бўлимлари орасидаги масофа (эга 2026-11-20 «енгил дизайн»).
  static const double homeSection = 20;

  /// Бўлим сарлавҳаси ↔ мазмуни орасидаги масофа (Avito услуби).
  ///
  /// 2 → 0 (эга қарори, 2026-09-27). Эслатма: кўзга ташланадиган
  /// масофанинг асосий қисми бу эмас эди — уни «Барчаси» тугмасининг
  /// босиш майдони ҳосил қиларди (қаранг: `_SeeAllButton.minHeight`).
  static const double sectionHeaderGap = 0;
}

/// Босиш майдонининг минимал ўлчами.
abstract final class AvaTap {
  static const double minSize = 44;
}

/// КБЖУ диаграммаси рангларининг ягона манбаи (2026-10-19, ega: «янги ранг
/// киритиш мумкин»; таом формаси, `DishFactsEditor`). Бренд тўқ сариғидан
/// ва ok/warn/danger маъноларидан онгли равишда ФАРҚЛИ: оқсил — кўк, ёғ —
/// олтин-жигарранг, углевод — зангори.
///
/// Контраст (WCAG, ҳисобланган): ёруғда оқ `surface` устида 5.30 / 3.64 /
/// 4.13, крем `bg` да 4.70 / 3.23 / 3.67 — номатн белгилар учун керакли 3:1
/// дан юқори. Қоронғида `surface` (`1B1F29`) да 7.35 / 8.22 / 8.31. Қўшни
/// сегментлар бир-бирига яқин (1.14…1.46), шунинг учун диаграммада улар
/// орасида бўшлиқ бор ва ҳар қиймат РАҚАМ билан ёзилади — ранг ягона
/// белги эмас.
@immutable
class AvaMacroColors {
  const AvaMacroColors({required this.protein, required this.fat, required this.carbs});

  /// Оқсил.
  final Color protein;

  /// Ёғ.
  final Color fat;

  /// Углевод.
  final Color carbs;

  static const light = AvaMacroColors(
    protein: Color(0xFF2E6DB4),
    fat: Color(0xFFB7791F),
    carbs: Color(0xFF1B8A8F),
  );

  static const dark = AvaMacroColors(
    protein: Color(0xFF7FB0F0),
    fat: Color(0xFFE0B04A),
    carbs: Color(0xFF5CC8CC),
  );
}

/// `context.avaMacro.protein` — мавзуга қараб.
extension AvaMacroColorsX on BuildContext {
  AvaMacroColors get avaMacro =>
      Theme.of(this).brightness == Brightness.dark ? AvaMacroColors.dark : AvaMacroColors.light;
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

  /// Бош экран бўлим сарлавҳалари («Бозорлар», «Янги эълонлар:» …) — 18/600
  /// (эга 2026-11-20 «енгил дизайн»; 2026-10-26 дан 14 эди). Бошқа экранлар [sectionTitle] да қолади.
  static const homeSectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  /// Бош саҳифа катта карточкаси сарлавҳаси — 16/600 (эга 2026-11-20).
  static const homeCardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  /// Бош саҳифа карточкаси изоҳи — 14/400 (эга 2026-11-20); ранги `ink2`.
  static const homeCardCaption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Маҳсулот номи — 13/400 (фото биринчи, матн иккинчи даражали).
  static const productName = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Нарх — 14/700 (ранги `brandText`) — ягона «оғир нуқта».
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

  /// Бош саҳифа бўлимидаги эълон/қатор матни — **12/400, қатор баландлиги
  /// АНИҚ 14 px** (эга қарори, 2026-09-26: аввал 14 px шрифт ва 18.9 px
  /// қатор эди — зич лентага баланд ва йирик эди).
  ///
  /// `height` — шрифт ўлчамига КЎПАЙТУВЧИ, шунинг учун каср кўринишида
  /// (14/12) ёзилган: шрифт ўзгарса, махражни ўзгартириш кифоя — қатор
  /// барибир 14 px бўлиб қолади. Бешала қатор бўлими (эълон, хизмат,
  /// шаҳарлараро, туман ичида юк, танишув) шу битта жойдан созланади.
  ///
  /// Ҳарфлар ораси [feedRowLetterSpacing] (эга сўрови, 2026-10-08:
  /// «ҳарфлар ораси кенгроқ бўлса соддароқ ва ўқишга осонроқ»). Ҳарф
  /// ораси қатор БАЛАНДЛИГИГА таъсир қилмайди — 14 px сақланади.
  static const feedRow = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 14 / 12,
    letterSpacing: feedRowLetterSpacing,
  );

  /// Қатор матнининг ҳарф ораси, px. Inter 12 px учун 0 = зич; 0.4 ≈ 3%
  /// — кўзга сезиларли, лекин сўзлар «сочилиб» кетмайди.
  static const double feedRowLetterSpacing = 0.4;

  /// Изоҳ — 12/400.
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Таом тагидаги иккинчи даража ёзув (тавсиф, масофа, миқдор чегирмаси, баҳо, КБЖУ ёрлиғи) — **12/400**,
  /// ҳарфлар ораси [feedRowLetterSpacing] (эга, 2026-10-23: «таом тагидаги ёзувлар ихчам майда, ҳарфлар ораси
  /// кенгроқ ва ўқиладиган бўлсин»). 12 px — қуйи чегара (ундан кичик ўқилмайди); қатор баландлиги [caption]
  /// билан бир хил (1.3), шунинг учун қатъий баландликдаги меню қаторларининг ҳисоби ўзгармайди. Ранг — `ink2`
  /// (контраст ≥ 4.5:1); `ink3` (≈2.7:1) маъноли матнга ярамайди.
  static const dishNote = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
    letterSpacing: feedRowLetterSpacing,
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

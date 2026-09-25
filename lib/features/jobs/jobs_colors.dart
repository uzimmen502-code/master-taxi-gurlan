import 'package:flutter/material.dart';

import '../../core/theme/ava_tokens.dart';
import '../../models/job_ad.dart';

/// ИШ ЭЪЛОН палитраси — [AvaColors] токенларининг шу модулдаги номлари.
///
/// Илгари бу ерда алоҳида кўк (#0277BD) ва юмшоқ яшил фон бор эди;
/// янги дизайн тизимида битта бренд ранги бўлгани учун улар токенларга
/// боғланди.
abstract final class JobsColors {
  /// Лента / экран фони.
  static const scaffold = AvaLight.bg;

  /// Битта бренд акценти.
  static const accentBlue = AvaLight.brand;

  /// AppBar, таблар, «+ Эълон қўшиш», «Таҳрирлаш» фон.
  static const bar = accentBlue;

  /// Матн бар/CTA устида.
  static const onBar = AvaLight.brandInk;

  /// Таб танланмаган — бренд усти матнининг хира кўриниши.
  static const tabUnselected = Color(0xCCFFFFFF);

  /// Асосий матн.
  static const ink = AvaLight.ink;

  /// Иккинчи даража матн.
  static const muted = AvaLight.ink2;

  /// Hint / бўш мета.
  static const hint = AvaLight.ink3;

  /// Карточка.
  static const surface = AvaLight.surface;

  /// Чегара.
  static const border = AvaLight.line;

  /// Қидирув fill.
  static const fieldFill = AvaLight.surface2;

  /// «Эълон» акценти.
  static const kindAd = accentBlue;

  /// «Хизмат таклифи» акценти.
  static const kindService = accentBlue;

  /// Legacy «Иш» (work) — бренддан ажралиб турсин, огоҳлантириш туси.
  static const kindWork = AvaLight.warn;

  /// Шошилинч.
  static const urgent = AvaLight.danger;
  static const urgentSoft = AvaLight.dangerSoft;

  /// Нарх chip.
  static const priceBg = AvaLight.brandSoft;
  static const priceText = accentBlue;

  static Color accentFor(AdKind kind) {
    switch (kind) {
      case AdKind.work:
        return kindWork;
      case AdKind.service:
        return kindService;
      case AdKind.ad:
        return kindAd;
    }
  }
}

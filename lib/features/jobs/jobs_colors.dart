import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/job_ad.dart';

/// ИШ ЭЪЛОН палитраси (бошқа модулларга таъсир қилмайди).
abstract final class JobsColors {
  /// Лента / экран фони — юмшоқ яшил (ёруғ lime эмас).
  static const scaffold = Color(0xFFF7FFEF);

  /// AppBar ва оқ матнли CTA фон — чуқур лайм.
  static const bar = AppColors.button; // #4E9F00

  /// Оқ матн бар/CTA устида.
  static const onBar = Colors.white;

  /// Таб танланмаган.
  static const tabUnselected = Color(0xCCFFFFFF);

  /// Асосий матн.
  static const ink = Color(0xFF1A1A1A);

  /// Иккинчи даража матн.
  static const muted = Color(0xFF5A6B4A);

  /// Hint / бўш мета.
  static const hint = Color(0xFF6B7B5A);

  /// Карточка.
  static const surface = Colors.white;

  /// Чегара.
  static const border = Color(0xFFE0E0E0);

  /// Қидирув fill.
  static const fieldFill = Color(0xFFF5F8F0);

  /// Эълон акцент.
  static const kindAd = AppColors.button;

  /// Хизмат акцент.
  static const kindService = Color(0xFF0277BD);

  /// Legacy «Иш» (work).
  static const kindWork = Color(0xFFD84315);

  /// Шошилинч.
  static const urgent = Color(0xFFC62828);
  static const urgentSoft = Color(0xFFFFEBEE);

  /// Нарх chip.
  static const priceBg = Color(0xFFEEF8E0);
  static const priceText = AppColors.button;

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

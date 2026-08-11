import 'package:flutter/material.dart';

import '../../models/job_ad.dart';

/// ИШ ЭЪЛОН палитраси (бошқа модулларга таъсир қилмайди).
abstract final class JobsColors {
  /// Лента / экран фони — юмшоқ яшил (ёруғ lime эмас).
  static const scaffold = Color(0xFFF7FFEF);

  /// Иш бор / Хизмат таклифи — битта кўк акцент.
  static const accentBlue = Color(0xFF0277BD);

  /// AppBar, таблар, «+ Эълон қўшиш», «Таҳрирлаш» фон.
  static const bar = accentBlue;

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

  /// «Иш бор» (ad) акцент — кўк.
  static const kindAd = accentBlue;

  /// «Хизмат таклифи» акцент — кўк.
  static const kindService = accentBlue;

  /// Legacy «Иш» (work).
  static const kindWork = Color(0xFFD84315);

  /// Шошилинч.
  static const urgent = Color(0xFFC62828);
  static const urgentSoft = Color(0xFFFFEBEE);

  /// Нарх chip.
  static const priceBg = Color(0xFFE3F2FD);
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

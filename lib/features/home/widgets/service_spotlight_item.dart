import 'package:flutter/material.dart';

/// Хизматлар блокидаги битта катак маълумоти (`ServiceCircleTile`,
/// «Барча хизматлар» экрани, `buildHomeServices`).
///
/// Аввал `services_spotlight_carousel.dart` ичида турарди; ўша карусель ва
/// 3D плитка бош саҳифадан олиб ташлангач (2026-09-26, OLX услуби) ва ҳеч
/// қаерда чақирилмагани учун ўчирилди — бу синф алоҳида файлга кўчди.
class ServiceSpotlightItem {
  const ServiceSpotlightItem({
    required this.moduleId,
    required this.label,
    required this.onTap,
    this.imagePath,
    this.svgPath,
    this.emoji,
    this.icon,
    this.iconColor,
    this.iconScale = 1.0,
    this.gateId,
  });

  /// Ранг ва расм калити (`olxTintFor`, `serviceImageFor`).
  final String moduleId;

  /// Админ дарвозаси калити (кўриниш / очилиш). Бўш бўлса — [moduleId].
  ///
  /// Битта модул бир неча плиткага бўлинганда керак: масалан «Эълонлар»
  /// ва «Хизматлар» — иккита плитка, ҳар бирининг ўз ранги, лекин админ
  /// панелда битта `jobs` калити билан ёқилади (эга қарори, 2026-10-06).
  final String? gateId;
  String get gate => gateId ?? moduleId;
  final String label;
  final VoidCallback onTap;
  final String? imagePath;

  /// Расмий бренд логотипи (vektor) — масалан тўлов провайдерлари учун.
  final String? svgPath;
  final String? emoji;
  final IconData? icon;
  final Color? iconColor;
  final double iconScale;
}

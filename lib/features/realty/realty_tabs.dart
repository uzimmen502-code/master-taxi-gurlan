import 'package:flutter/material.dart';

import '../../models/realty_listing.dart';

/// «Кўчмас мулк Кластери» — учта TAB ва уларнинг ранглари.
///
/// Ранглар концепциянинг 7-бўлимидан: ОДДИЙ яшил, РЕКЛАМА мандарин,
/// СРОЧНО қизил. Дизайнер эслатмаси бажарилган — учаласи ёрқинлиги
/// бўйича ҳам фарқланади (яшил очроқ → қизил тўқроқ), шунда ранг
/// кўрлиги бўлган фойдаланувчи ҳам пинларни қўшимча белгисиз ажратади.
abstract final class RealtyTabs {
  static const List<RealtyTier> order = [
    RealtyTier.plain,
    RealtyTier.promo,
    RealtyTier.urgent,
  ];

  static const int count = 3;

  static RealtyTier tierForIndex(int index) =>
      order[index.clamp(0, count - 1)];

  static int indexForTier(RealtyTier tier) => order.indexOf(tier);

  /// Матн калитлари — `assets/lang/*.json`.
  static String labelKey(RealtyTier tier) {
    switch (tier) {
      case RealtyTier.plain:
        return 'realty_tier_plain';
      case RealtyTier.promo:
        return 'realty_tier_promo';
      case RealtyTier.urgent:
        return 'realty_tier_urgent';
    }
  }

  static Color colorFor(RealtyTier tier) {
    switch (tier) {
      case RealtyTier.plain:
        return const Color(0xFF3FAE5A); // яшил — энг очи
      case RealtyTier.promo:
        return const Color(0xFFF28C28); // мандарин — ўртача
      case RealtyTier.urgent:
        return const Color(0xFFB3261E); // қизил — энг тўқи
    }
  }

  /// Google Maps пин ранги — [colorFor] билан мос.
  static double markerHueFor(RealtyTier tier) {
    switch (tier) {
      case RealtyTier.plain:
        return 120; // hueGreen
      case RealtyTier.promo:
        return 30; // hueOrange
      case RealtyTier.urgent:
        return 0; // hueRed
    }
  }
}

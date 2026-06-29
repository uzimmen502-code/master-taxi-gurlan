import 'package:flutter/material.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';

import '../../../../models/driver_client_stats.dart';

/// **В«Р”РѕРёРјРёР№ РјРёР¶РѕР·В»** badge вЂ” bron sheet'РЅРёРЅРі С‚РµРїР°СЃРёРіР° Р¶РѕР№Р»Р°С€Р°РґРё.
///
/// `stats == null` С‘РєРё `bookingCount == 0` Р±СћР»СЃР° hech РЅР°СЂСЃР° РєСћСЂСЃР°С‚РёР»РјР°Р№РґРё
/// (Р±РёСЂРёРЅС‡Рё РјР°СЂС‚Р° Р±СЂРѕРЅ Т›РёР»Р°С‘С‚РіР°РЅ РјРёР¶РѕР·).
class LoyalClientBadge extends StatelessWidget {
  const LoyalClientBadge({super.key, required this.stats, this.compact = false});

  final DriverClientStats? stats;

  /// `true` вЂ” РєРёС‡РєРёРЅР° (ride РєР°СЂС‚РѕС‡РєР°СЃРёРґР°).
  /// `false` вЂ” РєР°С‚С‚Р° (bron sheet'РґР° С‚РµРїР°РґР°).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    if (s == null || s.bookingCount == 0) return const SizedBox.shrink();

    final label = _loyaltyLabel(context, s);
    if (label.isEmpty) return const SizedBox.shrink();

    final palette = s.isVip
        ? _LoyaltyPalette.vip
        : s.isLoyal
            ? _LoyaltyPalette.loyal
            : _LoyaltyPalette.repeat;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: palette.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(palette.icon, size: 11, color: palette.fg),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: palette.fg)),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [palette.bg, palette.bgAlt]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(palette.icon, size: 18, color: palette.fg),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: palette.fg)),
            Text(
                '${context.tr('booking_count_label').replaceAll('{n}', '${s.bookingCount}')} В· ${_formatPrice(s.totalSpent)} ${context.tr('sum')}',
                style: TextStyle(
                    fontSize: 10, color: palette.fg.withValues(alpha: 0.8))),
          ],
        ),
      ]),
    );
  }

  static String _loyaltyLabel(BuildContext context, DriverClientStats s) {
    if (s.isVip) return context.tr('vip_client');
    if (s.isLoyal) return context.tr('loyal_client');
    if (s.bookingCount > 1) {
      return context
          .tr('trip_count_label')
          .replaceAll('{n}', '${s.bookingCount}');
    }
    return '';
  }

  static String _formatPrice(int p) {
    final s = p.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _LoyaltyPalette {
  const _LoyaltyPalette(
      {required this.bg,
      required this.bgAlt,
      required this.border,
      required this.fg,
      required this.icon});

  final Color bg;
  final Color bgAlt;
  final Color border;
  final Color fg;
  final IconData icon;

  static const repeat = _LoyaltyPalette(
    bg: Color(0xFFF3E5F5),
    bgAlt: Color(0xFFE1BEE7),
    border: Color(0xFF9C27B0),
    fg: AppColors.primary,
    icon: Icons.repeat,
  );

  static const loyal = _LoyaltyPalette(
    bg: Color(0xFFFFF8E1),
    bgAlt: Color(0xFFFFE0B2),
    border: Color(0xFFFFB300),
    fg: AppColors.primary,
    icon: Icons.workspace_premium,
  );

  static const vip = _LoyaltyPalette(
    bg: Color(0xFFE8F5E9),
    bgAlt: Color(0xFFC8E6C9),
    border: AppColors.primaryMid,
    fg: AppColors.primaryDark,
    icon: Icons.diamond,
  );
}

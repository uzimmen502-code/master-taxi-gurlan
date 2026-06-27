import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';

/// Marshrut panel pastki 2 qatorli segmented bar holatlari.
enum MarshrutPanelBarState {
  /// Smena yo'q.
  a,

  /// Smena bor, online.
  b,

  /// Smena bor, tanaffus.
  c,

  /// Smena tugagan (lokal UI holati).
  d,
}

MarshrutPanelBarState resolveMarshrutPanelBarState({
  required bool shiftEnded,
  required bool hasScheduleToday,
  required bool isOnline,
}) {
  if (shiftEnded) return MarshrutPanelBarState.d;
  if (!hasScheduleToday) return MarshrutPanelBarState.a;
  if (isOnline) return MarshrutPanelBarState.b;
  return MarshrutPanelBarState.c;
}

/// Pastki bar — soddalashtirilgan:
///   • Smena yo'q  → bitta to'liq kenglikdagi "Smenani boshlash" tugmasi.
///   • Smena faol  → faqat ONLINE | TANAFFUS qatori.
/// "Smena ma'lumoti" va "Smenani tugatish" AppBar'ga ko'chirildi.
class MarshrutPanelBottomBar extends StatelessWidget {
  const MarshrutPanelBottomBar({
    super.key,
    required this.barState,
    required this.onOnlineTap,
    required this.onTanaffusTap,
    required this.onSmenaStartedTap,
  });

  final MarshrutPanelBarState barState;
  final VoidCallback? onOnlineTap;
  final VoidCallback? onTanaffusTap;
  final VoidCallback? onSmenaStartedTap;

  static const Color _green = AppColors.primaryMid;
  static const Color _yellow = AppColors.accentGold;
  static const double _rowHeight = 52;
  static const double _segmentFontSize = AppText.titleMedium;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (barState) {
      case MarshrutPanelBarState.a:
        // Smena yo'q: bitta to'liq kenglikdagi yashil "Smenani boshlash".
        return _FullWidthButton(
          height: _rowHeight,
          fontSize: _segmentFontSize,
          label: context.tr('marshrut_seg_smena_start'),
          icon: Icons.play_circle_fill,
          color: _green,
          onTap: onSmenaStartedTap,
        );
      case MarshrutPanelBarState.b:
      case MarshrutPanelBarState.c:
        // Smena faol: faqat ONLINE | TANAFFUS.
        return _SegmentRow(
          height: _rowHeight,
          fontSize: _segmentFontSize,
          leftLabel: context.tr('marshrut_seg_online'),
          rightLabel: context.tr('marshrut_seg_tanaffus'),
          leftActive: barState == MarshrutPanelBarState.b,
          rightActive: barState == MarshrutPanelBarState.c,
          leftActiveColor: _green,
          rightActiveColor: _yellow,
          onLeftTap: onOnlineTap,
          onRightTap: onTanaffusTap,
        );
      case MarshrutPanelBarState.d:
        // Smena tugagan: passiv status.
        return _FullWidthButton(
          height: _rowHeight,
          fontSize: _segmentFontSize,
          label: context.tr('marshrut_seg_smena_ended_status'),
          icon: Icons.check_circle,
          color: Colors.grey.shade400,
          onTap: null,
        );
    }
  }
}

class _FullWidthButton extends StatelessWidget {
  const _FullWidthButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.height,
    required this.fontSize,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final double height;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? color : Colors.grey.shade300,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: height,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white, size: fontSize + 4),
              const SizedBox(width: 8),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.leftLabel,
    required this.rightLabel,
    required this.leftActive,
    required this.rightActive,
    required this.leftActiveColor,
    required this.rightActiveColor,
    required this.height,
    required this.fontSize,
    this.onLeftTap,
    this.onRightTap,
  });

  final String leftLabel;
  final String rightLabel;
  final bool leftActive;
  final bool rightActive;
  final Color leftActiveColor;
  final Color rightActiveColor;
  final double height;
  final double fontSize;
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SegmentHalf(
            label: leftLabel,
            active: leftActive,
            activeColor: leftActiveColor,
            height: height,
            fontSize: fontSize,
            onTap: onLeftTap,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(12),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _SegmentHalf(
            label: rightLabel,
            active: rightActive,
            activeColor: rightActiveColor,
            height: height,
            fontSize: fontSize,
            onTap: onRightTap,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentHalf extends StatelessWidget {
  const _SegmentHalf({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.borderRadius,
    required this.height,
    required this.fontSize,
    this.onTap,
  });

  final String label;
  final bool active;
  final Color activeColor;
  final BorderRadius borderRadius;
  final double height;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? activeColor : Colors.grey.shade200;
    final fg = active
        ? (activeColor == AppColors.accentGold ? Colors.black87 : Colors.white)
        : Colors.grey.shade600;
    final enabled = onTap != null;

    return Material(
      color: bg,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                height: 1.1,
                color: enabled || active ? fg : Colors.grey.shade500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

/// Pastki bar: ONLINE|TANAFFUS va Smena boshlandi|Smena tugadi.
class MarshrutPanelBottomBar extends StatelessWidget {
  const MarshrutPanelBottomBar({
    super.key,
    required this.barState,
    required this.onOnlineTap,
    required this.onTanaffusTap,
    required this.onSmenaStartedTap,
    required this.onSmenaEndedTap,
    required this.onSmenaInfoTap,
  });

  final MarshrutPanelBarState barState;
  final VoidCallback? onOnlineTap;
  final VoidCallback? onTanaffusTap;
  final VoidCallback? onSmenaStartedTap;
  final VoidCallback? onSmenaEndedTap;
  final VoidCallback? onSmenaInfoTap;

  static const Color _green = AppColors.primaryMid;
  static const Color _yellow = AppColors.accentGold;
  static const Color _red = AppColors.error;
  static const double _rowHeight = 50;
  static const double _segmentFontSize = AppText.titleMedium;

  @override
  Widget build(BuildContext context) {
    final onlineLeftActive = barState == MarshrutPanelBarState.b;
    final tanaffusRightActive = barState == MarshrutPanelBarState.c;
    final row1Enabled = barState == MarshrutPanelBarState.b ||
        barState == MarshrutPanelBarState.c;

    final smenaInfoEnabled = barState == MarshrutPanelBarState.b ||
        barState == MarshrutPanelBarState.c;

    final String smenaLeftLabel;
    final String smenaRightLabel;
    final bool smenaLeftActive;
    final bool smenaRightActive;
    final VoidCallback? smenaLeftTap;
    final VoidCallback? smenaRightTap;

    switch (barState) {
      case MarshrutPanelBarState.a:
        // Smena yo'q: boshlash (yashil) | smena yo'q (kulrang).
        smenaLeftLabel = context.tr('marshrut_seg_smena_start');
        smenaRightLabel = context.tr('marshrut_seg_smena_none');
        smenaLeftActive = true;
        smenaRightActive = false;
        smenaLeftTap = onSmenaStartedTap;
        smenaRightTap = null;
      case MarshrutPanelBarState.b:
      case MarshrutPanelBarState.c:
        // Smena faol: faol (yashil) | tugatish (qizil).
        smenaLeftLabel = context.tr('marshrut_seg_smena_active');
        smenaRightLabel = context.tr('marshrut_seg_smena_end_action');
        smenaLeftActive = true;
        smenaRightActive = true;
        smenaLeftTap = null;
        smenaRightTap = onSmenaEndedTap;
      case MarshrutPanelBarState.d:
        // Smena tugagan: ikkala tomonda status, faqat o'ng qizil.
        smenaLeftLabel = context.tr('marshrut_seg_smena_ended_status');
        smenaRightLabel = context.tr('marshrut_seg_smena_ended_status');
        smenaLeftActive = false;
        smenaRightActive = true;
        smenaLeftTap = null;
        smenaRightTap = null;
    }

    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SegmentRow(
                height: _rowHeight,
                fontSize: _segmentFontSize,
                leftLabel: context.tr('marshrut_seg_online'),
                rightLabel: context.tr('marshrut_seg_tanaffus'),
                leftActive: onlineLeftActive,
                rightActive: tanaffusRightActive,
                leftActiveColor: _green,
                rightActiveColor: _yellow,
                onLeftTap: row1Enabled ? onOnlineTap : null,
                onRightTap: row1Enabled ? onTanaffusTap : null,
              ),
              const SizedBox(height: 8),
              _SegmentRow(
                height: _rowHeight,
                fontSize: _segmentFontSize,
                leftLabel: smenaLeftLabel,
                rightLabel: smenaRightLabel,
                leftActive: smenaLeftActive,
                rightActive: smenaRightActive,
                leftActiveColor: _green,
                rightActiveColor: _red,
                onLeftTap: smenaLeftTap,
                onRightTap: smenaRightTap,
              ),
              const SizedBox(height: 8),
              _SmenaInfoButton(
                height: _rowHeight,
                fontSize: _segmentFontSize,
                label: context.tr('marshrut_smena_info_btn'),
                enabled: smenaInfoEnabled,
                onPressed: smenaInfoEnabled ? onSmenaInfoTap : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmenaInfoButton extends StatefulWidget {
  const _SmenaInfoButton({
    required this.label,
    required this.enabled,
    required this.height,
    required this.fontSize,
    this.onPressed,
  });

  final String label;
  final bool enabled;
  final double height;
  final double fontSize;
  final VoidCallback? onPressed;

  @override
  State<_SmenaInfoButton> createState() => _SmenaInfoButtonState();
}

class _SmenaInfoButtonState extends State<_SmenaInfoButton> {
  bool _pressed = false;

  Future<void> _handleTap() async {
    if (widget.onPressed == null) return;
    setState(() => _pressed = true);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() => _pressed = false);
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onPressed != null;
    final bg = _pressed
        ? AppColors.primaryMid
        : enabled
            ? Colors.white
            : Colors.grey.shade200;
    final fg = _pressed
        ? Colors.white
        : enabled
            ? AppColors.primaryDark
            : Colors.grey.shade500;
    final borderColor = _pressed
        ? AppColors.primaryMid
        : enabled
            ? AppColors.primaryDark.withValues(alpha: 0.35)
            : Colors.grey.shade300;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? _handleTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: widget.fontSize + 2, color: fg),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.bold,
                    color: fg,
                    height: 1.1,
                  ),
                ),
              ],
            ),
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

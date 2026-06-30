import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';

/// Bugungi marshrut karta'i — qaerdan-qayerga, to'xtash chiplari, o'rinlar
/// ko'rsatkichi ва йўналишни ўзгартириш тугмаси.
class RouteCard extends StatelessWidget {
  const RouteCard({
    super.key,
    required this.stops,
    required this.direction,
    required this.seatsLeft,
    required this.onSwitchDirection,
    required this.isOnline,
    this.color = AppColors.primaryDark,
    this.errorColor = const Color(0xFFB71C1C),
  });

  final List<String> stops;
  final String direction;
  final int seatsLeft;
  final VoidCallback onSwitchDirection;
  final bool isOnline;
  final Color color;
  final Color errorColor;

  @override
  Widget build(BuildContext context) {
    final from = stops.isNotEmpty ? stops.first : '';
    final to = stops.isNotEmpty ? stops.last : '';
    final routeText = direction == 'forward' ? '$from → $to' : '$to → $from';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _RouteHeadlineBanner(
          routeText: routeText,
          isOnline: isOnline,
          color: color,
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: stops
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(s,
                              style: TextStyle(
                                  fontSize: AppText.labelTiny, color: color)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      seatsLeft == 0
                          ? '🚫 Бўш жой йўқ'
                          : '💺 $seatsLeft та бўш жой',
                      style: TextStyle(
                          fontSize: AppText.bodyMedium,
                          fontWeight: FontWeight.bold,
                          color: seatsLeft == 0 ? errorColor : color),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onSwitchDirection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_horiz,
                              size: 16, color: Colors.black),
                          const SizedBox(width: 4),
                          Text(context.tr('switch_direction_short'),
                              style: const TextStyle(
                                  fontSize: AppText.labelSmall,
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _RouteHeadlineBanner extends StatefulWidget {
  const _RouteHeadlineBanner({
    required this.routeText,
    required this.isOnline,
    required this.color,
  });

  final String routeText;
  final bool isOnline;
  final Color color;

  @override
  State<_RouteHeadlineBanner> createState() => _RouteHeadlineBannerState();
}

class _RouteHeadlineBannerState extends State<_RouteHeadlineBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _RouteHeadlineBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isOnline != widget.isOnline) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.isOnline) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _equalizerBars(Color barColor) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(5, (i) {
            final phase = (_pulse.value + i * 0.18) * 2 * math.pi;
            final h = 4.0 + 10.0 * (0.35 + 0.65 * ((math.sin(phase) + 1) / 2));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                width: 3,
                height: h,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.isOnline;
    final wave = online ? (0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi)) : 0.0;

    final bg = online
        ? Color.lerp(
            const Color(0xFFE8F5E9),
            AppColors.primary.withValues(alpha: 0.35),
            wave,
          )!
        : Colors.grey.shade200;

    final textColor = online
        ? Color.lerp(widget.color, AppColors.primary, 0.35 + wave * 0.35)!
        : Colors.grey.shade600;

    final barColor =
        online ? AppColors.primaryMid : Colors.grey.shade400;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        boxShadow: online
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15 + wave * 0.2),
                  blurRadius: 10 + wave * 6,
                  spreadRadius: wave * 1.5,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.routeText,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppText.titleLarge,
                fontWeight: FontWeight.bold,
                color: textColor,
                height: 1.25,
              ),
            ),
          ),
          if (online) ...[
            const SizedBox(height: 8),
            _equalizerBars(barColor),
          ],
        ],
      ),
    );
  }
}

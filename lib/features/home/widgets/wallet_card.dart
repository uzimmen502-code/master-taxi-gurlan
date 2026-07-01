import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../painters/calligraphic_border_painter.dart';

/// Hamyon kartasi — yashil fon + oltin ramka + aylanuvchi binaфsha gradient chegara.
class WalletCard extends StatefulWidget {
  const WalletCard({
    super.key,
    required this.balance,
    required this.lastTxAmount,
    required this.displayName,
    required this.dateText,
    required this.locationText,
    this.lastTxIsCredit,
    this.onHistoryTap,
  });

  final String balance;
  final String lastTxAmount;
  final String displayName;
  final String dateText;
  final String locationText;

  /// `true` — kirim (oq), `false` — chiqim (qizil), `null` — tranzaksiya yo'q.
  final bool? lastTxIsCredit;
  final VoidCallback? onHistoryTap;

  @override
  State<WalletCard> createState() => _WalletCardState();
}

class _WalletCardState extends State<WalletCard>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF36A63A);
  static const _gold = Color(0xFFF5C518);
  static const _badgeText = Color(0xFF1A5E1C);
  static const _debitTint = Color(0xFFFFCDD2);
  static const _purple = Color(0xFF4A148C);
  static const _purpleBright = Color(0xFFE1BEE7);

  static const _goldLight = Color(0xFFFFF4C2);
  static const _goldDark = Color(0xFFC9A000);
  static const _outerRadius = 19.0;
  static const _innerRadius = 16.0;
  static const _borderWidth = 3.5;

  late final AnimationController _orbitCtrl;

  @override
  void initState() {
    super.initState();
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _orbitCtrl.dispose();
    super.dispose();
  }

  Color get _txAmountColor {
    if (widget.lastTxIsCredit == null) return Colors.white;
    return widget.lastTxIsCredit! ? Colors.white : _debitTint;
  }

  BoxDecoration _orbitShellDecoration(double turn) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(_outerRadius),
      gradient: SweepGradient(
        center: Alignment.center,
        transform: GradientRotation(turn * math.pi * 2),
        colors: const [
          Colors.transparent,
          Colors.transparent,
          _purple,
          _purpleBright,
          Colors.white,
          _purpleBright,
          _purple,
          Colors.transparent,
          Colors.transparent,
        ],
        stops: const [
          0.00,
          0.28,
          0.36,
          0.42,
          0.50,
          0.58,
          0.64,
          0.72,
          1.00,
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: _purple.withValues(alpha: 0.5),
          blurRadius: 12,
          spreadRadius: 0.5,
        ),
      ],
    );
  }

  Widget _cardBody() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_innerRadius),
      child: ColoredBox(
        color: _green,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: CalligraphicBorderPainter(isCompact: false),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 7,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          widget.dateText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _gold,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Faol',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _badgeText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          widget.balance,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [_goldLight, _gold, _goldDark],
                            stops: [0.0, 0.5, 1.0],
                          ).createShader(bounds),
                          child: Text(
                            widget.displayName.toUpperCase(),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 1,
                                  color: Color(0x66000000),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                            children: [
                              const TextSpan(text: 'Oxirgi: '),
                              TextSpan(
                                text: widget.lastTxAmount,
                                style: TextStyle(color: _txAmountColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFAC775),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  widget.locationText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.noScaling,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onHistoryTap,
          borderRadius: BorderRadius.circular(_outerRadius),
          child: AnimatedBuilder(
            animation: _orbitCtrl,
            builder: (context, child) {
              return DecoratedBox(
                decoration: _orbitShellDecoration(_orbitCtrl.value),
                child: Padding(
                  padding: const EdgeInsets.all(_borderWidth),
                  child: child,
                ),
              );
            },
            child: _cardBody(),
          ),
        ),
      ),
    );
  }
}

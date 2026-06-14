import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Нон картаси: «500 СЎМ» — bitta qator, qizil-oq animatsiya.
class FestivePriceText extends StatefulWidget {
  const FestivePriceText({
    super.key,
    required this.amountFontSize,
    this.currencyFontSize = 13,
    this.amount = '500',
    this.currency = 'СЎМ',
  });

  final double amountFontSize;
  final double currencyFontSize;
  final String amount;
  final String currency;

  String get _line => '$amount $currency';

  @override
  State<FestivePriceText> createState() => _FestivePriceTextState();
}

class _FestivePriceTextState extends State<FestivePriceText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  TextStyle _lineStyle(double size) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: Colors.white,
        height: 1.0,
        letterSpacing: size >= 14 ? 2.0 : 1.5,
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final t = _controller.value;
            return LinearGradient(
              colors: const [
                AppColors.error,
                Color(0xFFFFB300),
                AppColors.error,
                Color(0xFFFF5252),
              ],
              stops: const [0.0, 0.35, 0.65, 1.0],
              begin: Alignment(-1.2 + 2.4 * t, -0.2),
              end: Alignment(0.2 + 2.4 * t, 0.8),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: Text(
        widget._line,
        textAlign: TextAlign.right,
        style: _lineStyle(widget.amountFontSize),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/home_ticker_ad.dart';
import '../../../models/home_ticker_animation_style.dart';
import '../home_grid_layout.dart';

/// Matn uzunligi va ekran kengligiga qarab ticker rejasi.
class HomeTickerLayoutPlan {
  const HomeTickerLayoutPlan({
    required this.resolvedStyle,
    required this.maxLines,
    required this.barHeight,
    required this.useMarquee,
    required this.isAuto,
  });

  final String resolvedStyle;
  final int maxLines;
  final double barHeight;
  final bool useMarquee;
  final bool isAuto;

  static const double horizontalPadding = 12;
  static const double verticalPadding = 10;
  static const double lineHeightFactor = 1.2;

  static double get barHeightScale => HomeGridLayout.tickerBarHeightScale;

  static TextStyle textStyleFor(HomeTickerAd ad) => TextStyle(
        fontSize: ad.fontSize.toDouble(),
        fontWeight: FontWeight.w600,
        color: AppColors.primaryDark,
        height: lineHeightFactor,
        shadows: const [
          Shadow(
            color: Color(0x330E7A38),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      );

  static HomeTickerLayoutPlan compute({
    required HomeTickerAd ad,
    required double maxWidth,
  }) {
    final text = ad.text;
    final style = textStyleFor(ad);
    final contentWidth = (maxWidth - horizontalPadding * 2).clamp(200.0, maxWidth);
    final isAuto = HomeTickerAnimationStyle.isAuto(ad.animationStyle);

    if (text.isEmpty) {
      return HomeTickerLayoutPlan(
        resolvedStyle: HomeTickerAnimationStyle.fadeIn,
        maxLines: 1,
        barHeight: _barHeight(1, ad.fontSize),
        useMarquee: false,
        isAuto: isAuto,
      );
    }

    final measuredLines = _measureLineCount(text, style, contentWidth, 5);
    final targetByLength = _targetLinesFromCharCount(text.length);
    var lines = measuredLines;
    if (targetByLength > lines) lines = targetByLength;
    lines = lines.clamp(1, 5);

    final overflowsAt5 =
        _textExceedsLines(text, style, contentWidth, 5) || text.length > 150;

    String resolved;
    var useMarquee = false;

    if (isAuto) {
      if (overflowsAt5 || text.length > 150) {
        useMarquee = true;
        lines = 1;
        resolved = HomeTickerAnimationStyle.marquee;
      } else if (text.length <= 35 && lines <= 1) {
        resolved = HomeTickerAnimationStyle.typewriter;
        lines = 1;
      } else if (lines == 1 && text.length <= 45) {
        resolved = HomeTickerAnimationStyle.cascade;
        lines = 1;
      } else {
        resolved = HomeTickerAnimationStyle.fadeIn;
        lines = lines.clamp(2, 5);
      }
    } else {
      resolved = HomeTickerAnimationStyle.normalizeManual(ad.animationStyle);
      if (HomeTickerAnimationStyle.isFitOnScreen(resolved)) {
        useMarquee = false;
        lines = lines.clamp(1, 5);
      } else if (resolved == HomeTickerAnimationStyle.marquee) {
        useMarquee = true;
        lines = 1;
      } else if (overflowsAt5 &&
          resolved != HomeTickerAnimationStyle.typewriter &&
          resolved != HomeTickerAnimationStyle.cascade) {
        useMarquee = true;
        lines = 1;
        resolved = HomeTickerAnimationStyle.marquee;
      } else {
        lines = lines.clamp(1, 5);
        if (resolved == HomeTickerAnimationStyle.typewriter ||
            resolved == HomeTickerAnimationStyle.cascade) {
          lines = lines.clamp(1, 3);
        }
      }
    }

    return HomeTickerLayoutPlan(
      resolvedStyle: resolved,
      maxLines: lines,
      barHeight: _barHeight(lines, ad.fontSize),
      useMarquee: useMarquee,
      isAuto: isAuto,
    );
  }

  static int _targetLinesFromCharCount(int len) {
    if (len <= 35) return 1;
    if (len <= 70) return 2;
    if (len <= 110) return 3;
    if (len <= 150) return 4;
    return 5;
  }

  static int _measureLineCount(
    String text,
    TextStyle style,
    double maxWidth,
    int maxLines,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    return tp.computeLineMetrics().length.clamp(1, maxLines);
  }

  static bool _textExceedsLines(
    String text,
    TextStyle style,
    double maxWidth,
    int maxLines,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    return tp.didExceedMaxLines;
  }

  static double _barHeight(int lines, int fontSize) {
    final base =
        lines * fontSize * lineHeightFactor + verticalPadding * 2;
    final h = base * barHeightScale;
    return h.clamp(32.0 * barHeightScale, 120.0 * barHeightScale);
  }
}

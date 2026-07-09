import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../splash_taglines_holder.dart';

/// Qora fon: spiral kirish → 3 s pulsatsiya → ekrandan chiqish → UI fade-in.
class AppLaunchSplash extends StatefulWidget {
  const AppLaunchSplash({super.key, required this.child});

  final Widget child;

  static const Duration spiralDuration = Duration(milliseconds: 1500);
  static const Duration pulseDuration = Duration(milliseconds: 3000);
  static const Duration exitDuration = Duration(milliseconds: 900);

  static const int spiralTurns = 10;

  static Duration get totalDuration =>
      spiralDuration + pulseDuration + exitDuration;

  @override
  State<AppLaunchSplash> createState() => _AppLaunchSplashState();
}

class _AppLaunchSplashState extends State<AppLaunchSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const List<double> _pulseStart = [1.0, 1.06, 1.12];
  static const List<double> _pulsePeak = [1.12, 1.18, 1.24];
  static const List<double> _pulseEnd = [1.06, 1.12, 1.18];

  static const double _exitScaleStart = 1.18;
  static const Color _taglineColor = Color(0xFF4CD964);

  bool _overlayVisible = true;

  late final double _spiralFraction;
  late final double _pulseFraction;

  @override
  void initState() {
    super.initState();

    final totalMs = AppLaunchSplash.totalDuration.inMilliseconds.toDouble();
    _spiralFraction = AppLaunchSplash.spiralDuration.inMilliseconds / totalMs;
    _pulseFraction = AppLaunchSplash.pulseDuration.inMilliseconds / totalMs;

    _controller = AnimationController(
      vsync: this,
      duration: AppLaunchSplash.totalDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _overlayVisible = false);
        }
      });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _pulseScale(double t) {
    final segment = math.min((t * 3).floor(), 2);
    final localT = (t * 3) - segment;

    if (localT < 0.55) {
      final p = Curves.easeInOutCubic.transform(localT / 0.55);
      return _pulseStart[segment] +
          (_pulsePeak[segment] - _pulseStart[segment]) * p;
    }
    final p = Curves.easeInOutCubic.transform((localT - 0.55) / 0.45);
    return _pulsePeak[segment] +
        (_pulseEnd[segment] - _pulsePeak[segment]) * p;
  }

  ({String? text, double opacity}) _taglineForPulse(double pulseLocal) {
    if (!SplashTaglinesHolder.enabled) {
      return (text: null, opacity: 0);
    }

    final words = SplashTaglinesHolder.sessionWords;
    if (words.isEmpty) return (text: null, opacity: 0);

    String? text;
    double opacity = 0;

    for (var i = 0; i < 3 && i < words.length; i++) {
      final revealAt = (i + 0.72) / 3.0;
      if (pulseLocal < revealAt) break;
      text = words[i];
      final fadeWindow = 0.04;
      opacity = pulseLocal < revealAt + fadeWindow
          ? ((pulseLocal - revealAt) / fadeWindow).clamp(0.0, 1.0)
          : 1.0;
    }

    return (text: text, opacity: opacity);
  }

  _SplashFrame _frameFor(double t) {
    if (t < _spiralFraction) {
      final local = t / _spiralFraction;
      final scaleEased = Curves.easeOutCubic.transform(local);
      final spinEased = Curves.easeOutQuart.transform(local);
      return _SplashFrame(
        scale: 0.08 + 0.92 * scaleEased,
        rotation: AppLaunchSplash.spiralTurns * 2 * math.pi * spinEased,
        logoOpacity: Curves.easeIn.transform(local.clamp(0, 1)),
        contentOpacity: 0,
      );
    }

    final pulseEnd = _spiralFraction + _pulseFraction;
    if (t < pulseEnd) {
      final local = (t - _spiralFraction) / _pulseFraction;
      final tagline = _taglineForPulse(local);
      return _SplashFrame(
        scale: _pulseScale(local),
        rotation: 0,
        logoOpacity: 1,
        contentOpacity: 0,
        tagline: tagline.text,
        taglineOpacity: tagline.opacity,
      );
    }

    final local = (t - pulseEnd) / (1 - pulseEnd);
    final zoom = Curves.easeInOutCubic.transform(local);
    final logoFade = local < 0.4
        ? 1.0
        : 1 - Curves.easeIn.transform((local - 0.4) / 0.6);
    final lastTagline = SplashTaglinesHolder.enabled &&
            SplashTaglinesHolder.sessionWords.isNotEmpty
        ? SplashTaglinesHolder.sessionWords[
            math.min(2, SplashTaglinesHolder.sessionWords.length - 1)]
        : null;

    return _SplashFrame(
      scale: _exitScaleStart + 4.0 * zoom,
      rotation: 0,
      logoOpacity: logoFade,
      contentOpacity:
          local < 0.3 ? 0 : Curves.easeInOut.transform((local - 0.3) / 0.7),
      tagline: lastTagline,
      taglineOpacity: logoFade,
    );
  }

  @override
  Widget build(BuildContext context) {
    final logoWidth = MediaQuery.sizeOf(context).width * 0.52;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final frame = _frameFor(_controller.value);

          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: frame.contentOpacity.clamp(0, 1),
                child: widget.child,
              ),
              if (_overlayVisible)
                ColoredBox(
                  color: Colors.black,
                  child: IgnorePointer(
                    child: Center(
                      child: Opacity(
                        opacity: frame.logoOpacity.clamp(0, 1),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.rotate(
                              angle: frame.rotation,
                              child: Transform.scale(
                                scale: frame.scale,
                                child: Image.asset(
                                  'assets/images/splash_logo.png',
                                  width: logoWidth.clamp(160, 280),
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                            if (frame.tagline != null &&
                                frame.taglineOpacity > 0.01)
                              Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: Opacity(
                                  opacity:
                                      frame.taglineOpacity.clamp(0, 1),
                                  child: Text(
                                    frame.tagline!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _taglineColor.withValues(
                                        alpha: 0.95,
                                      ),
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2.4,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SplashFrame {
  const _SplashFrame({
    required this.scale,
    required this.rotation,
    required this.logoOpacity,
    required this.contentOpacity,
    this.tagline,
    this.taglineOpacity = 0,
  });

  final double scale;
  final double rotation;
  final double logoOpacity;
  final double contentOpacity;
  final String? tagline;
  final double taglineOpacity;
}

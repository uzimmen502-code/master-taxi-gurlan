import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../splash_taglines_holder.dart';

/// Qora fon: spiral kirish → 3.5 s pulsatsiya → ekrandan chiqish → UI fade-in.
class AppLaunchSplash extends StatefulWidget {
  const AppLaunchSplash({super.key, required this.child});

  final Widget child;

  static const Duration spiralDuration = Duration(milliseconds: 1500);
  static const Duration pulseDuration = Duration(milliseconds: 3500);
  static const Duration exitDuration = Duration(milliseconds: 900);

  // 15 turns in 1.5 seconds gives only ~6 frames per turn on a 60 Hz display
  // and looks like stutter even when no frames are dropped.
  static const int spiralTurns = 3;

  static Duration get totalDuration =>
      spiralDuration + pulseDuration + exitDuration;

  @override
  State<AppLaunchSplash> createState() => _AppLaunchSplashState();
}

class _AppLaunchSplashState extends State<AppLaunchSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const List<double> _pulseStart = [1.0, 1.10];
  static const List<double> _pulsePeak = [1.30, 1.45];
  static const List<double> _pulseEnd = [1.10, 1.25];

  static const double _thirdGrowthStart = 1.25;
  static const double _exitScaleEnd = 5.60;
  static const Color _taglineColor = Color(0xFF4CD964);
  static const AssetImage _logoAsset =
      AssetImage('assets/images/splash_logo.png');

  bool _overlayVisible = true;
  bool _logoPrepared = false;
  bool _warmingLogo = false;
  ImageProvider<Object> _logoImage = _logoAsset;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logoPrepared) return;
    _logoPrepared = true;

    final mediaQuery = MediaQuery.of(context);
    final logoWidth = (mediaQuery.size.width * 0.52).clamp(160.0, 280.0);
    final cacheWidth = (logoWidth * 1.60 * mediaQuery.devicePixelRatio).ceil();
    _logoImage = ResizeImage.resizeIfNeeded(cacheWidth, null, _logoAsset);
    _startAfterLogoDecode();
  }

  Future<void> _startAfterLogoDecode() async {
    try {
      await precacheImage(_logoImage, context);
    } catch (_) {
      // The Image widget still reports the asset error; never freeze splash.
    }
    if (mounted) {
      setState(() => _warmingLogo = true);
      await SchedulerBinding.instance.endOfFrame;
    }
    if (mounted) {
      _warmingLogo = false;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _pulseScale(double t) {
    final segment = math.min((t * 3).floor(), 2);
    final localT = (t * 3) - segment;

    // The third breath and exit use one curve, so there is no pause at 1.60.
    if (segment == 2) {
      return _thirdGrowthScale(localT * _thirdGrowthPulseFraction);
    }

    if (localT < 0.55) {
      final p = Curves.easeInOutSine.transform(localT / 0.55);
      return _pulseStart[segment] +
          (_pulsePeak[segment] - _pulseStart[segment]) * p;
    }
    final p = Curves.easeInOutSine.transform((localT - 0.55) / 0.45);
    return _pulsePeak[segment] + (_pulseEnd[segment] - _pulsePeak[segment]) * p;
  }

  double get _thirdGrowthPulseFraction {
    final thirdPulseMs = AppLaunchSplash.pulseDuration.inMilliseconds / 3;
    return thirdPulseMs /
        (thirdPulseMs + AppLaunchSplash.exitDuration.inMilliseconds);
  }

  double _thirdGrowthScale(double progress) {
    final eased = Curves.easeInCubic.transform(
      progress.clamp(0.0, 1.0).toDouble(),
    );
    return _thirdGrowthStart + (_exitScaleEnd - _thirdGrowthStart) * eased;
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
      final revealAt = (i + 0.55) / 3.0;
      if (pulseLocal < revealAt) break;
      text = words[i];
      opacity = 1;
    }

    return (text: text, opacity: opacity);
  }

  _SplashFrame _frameFor(double t) {
    if (t < _spiralFraction) {
      final local = t / _spiralFraction;
      final scaleEased = Curves.easeOutCubic.transform(local);
      final spinEased = Curves.easeInOutSine.transform(local);
      return _SplashFrame(
        scale: 0.08 + 0.92 * scaleEased,
        rotation: AppLaunchSplash.spiralTurns * 2 * math.pi * spinEased,
        logoOpacity: Curves.easeIn.transform(local.clamp(0, 1)),
        contentOpacity: 0,
        backgroundOpacity: 1,
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
        backgroundOpacity: 1,
        tagline: tagline.text,
        taglineOpacity: tagline.opacity,
      );
    }

    final local = (t - pulseEnd) / (1 - pulseEnd);
    final growthProgress =
        _thirdGrowthPulseFraction + (1 - _thirdGrowthPulseFraction) * local;
    final logoFade = local < 0.15
        ? 1.0
        : local >= 0.60
            ? 0.0
            : 1 -
                Curves.easeInOutSine.transform(
                  ((local - 0.15) / 0.45).clamp(0.0, 1.0),
                );
    // splash_logo.png has an opaque black background. Finish its fade before
    // revealing the route below, otherwise its square bounds become visible.
    final contentOpacity = local < 0.55
        ? 0.0
        : Curves.easeInOutSine.transform(
            ((local - 0.55) / 0.45).clamp(0.0, 1.0),
          );
    final lastTagline = SplashTaglinesHolder.enabled &&
            SplashTaglinesHolder.sessionWords.isNotEmpty
        ? SplashTaglinesHolder.sessionWords[
            math.min(2, SplashTaglinesHolder.sessionWords.length - 1)]
        : null;

    return _SplashFrame(
      scale: _thirdGrowthScale(growthProgress),
      rotation: 0,
      logoOpacity: logoFade,
      contentOpacity: contentOpacity,
      backgroundOpacity: 1 - contentOpacity,
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
        child: RepaintBoundary(
          child: Image(
            image: _logoImage,
            width: logoWidth.clamp(160, 280),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ),
        builder: (context, logoChild) {
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
                  color: Colors.black.withValues(
                    alpha: frame.backgroundOpacity.clamp(0, 1),
                  ),
                  child: IgnorePointer(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: Opacity(
                            opacity: math
                                .max(
                                  frame.logoOpacity,
                                  _warmingLogo ? 0.01 : 0.0,
                                )
                                .clamp(0.0, 1.0)
                                .toDouble(),
                            child: Transform.rotate(
                              angle: frame.rotation,
                              child: Transform.scale(
                                scale: frame.scale,
                                child: logoChild,
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              logoWidth.clamp(160, 280) *
                                      math.max(frame.scale, 1.60) /
                                      2 +
                                  18,
                            ),
                            child: Opacity(
                              opacity: frame.taglineOpacity.clamp(0, 1),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 280),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: frame.tagline == null
                                    ? const SizedBox.shrink(
                                        key: ValueKey('empty'),
                                      )
                                    : Text(
                                        frame.tagline!,
                                        key: ValueKey(frame.tagline),
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
                          ),
                        ),
                      ],
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
    required this.backgroundOpacity,
    this.tagline,
    this.taglineOpacity = 0,
  });

  final double scale;
  final double rotation;
  final double logoOpacity;
  final double contentOpacity;
  final double backgroundOpacity;
  final String? tagline;
  final double taglineOpacity;
}

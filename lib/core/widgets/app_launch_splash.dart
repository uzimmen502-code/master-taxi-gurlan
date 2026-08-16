import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../brand_labels.dart';

/// Қора фон: лого нуқтадан ўсиб 3 марта экранга урилади, сўнг UI.
///
/// Юқори: AVA + туман. Паст сўзлар йўқ. ~1.8 с.
class AppLaunchSplash extends StatefulWidget {
  const AppLaunchSplash({
    super.key,
    required this.child,
    this.onFinished,
  });

  final Widget child;

  /// Splash overlay yopilganda (bir marta) — FCM/notification shu paytda.
  final VoidCallback? onFinished;

  /// Урилишлар ораси.
  static const Duration hitInterval = Duration(milliseconds: 500);
  static const int hitCount = 3;
  static const Duration exitDuration = Duration(milliseconds: 280);

  static Duration get totalDuration => Duration(
        milliseconds: hitInterval.inMilliseconds * hitCount +
            exitDuration.inMilliseconds,
      );

  @override
  State<AppLaunchSplash> createState() => _AppLaunchSplashState();
}

class _AppLaunchSplashState extends State<AppLaunchSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double _startScale = 0.04;
  static const double _restScale = 1.0;
  /// ~экран кенглигига урилиш (лого ~0.52 * width).
  static const double _slamScale = 2.05;
  static const AssetImage _logoAsset =
      AssetImage('assets/images/splash_logo.png');

  bool _overlayVisible = true;
  bool _logoPrepared = false;
  bool _warmingLogo = false;
  ImageProvider<Object> _logoImage = _logoAsset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppLaunchSplash.totalDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _overlayVisible = false);
          widget.onFinished?.call();
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

  double _hitScale(int index, double local) {
    final from = index == 0 ? _startScale : _restScale;
    const slamAt = 0.58;
    if (local < slamAt) {
      final p = Curves.easeInCubic.transform(local / slamAt);
      return from + (_slamScale - from) * p;
    }
    final p = Curves.easeOutCubic.transform((local - slamAt) / (1 - slamAt));
    return _slamScale + (_restScale - _slamScale) * p;
  }

  _SplashFrame _frameFor(double t) {
    final totalMs = AppLaunchSplash.totalDuration.inMilliseconds.toDouble();
    final ms = t * totalMs;
    final hitMs =
        AppLaunchSplash.hitInterval.inMilliseconds * AppLaunchSplash.hitCount;
    final interval = AppLaunchSplash.hitInterval.inMilliseconds.toDouble();

    if (ms < hitMs) {
      final i = (ms / interval).floor().clamp(0, AppLaunchSplash.hitCount - 1);
      final local = ((ms - i * interval) / interval).clamp(0.0, 1.0);
      return _SplashFrame(
        scale: _hitScale(i, local),
        logoOpacity: 1,
        contentOpacity: 0,
        backgroundOpacity: 1,
        brandOpacity: 1,
      );
    }

    final local = ((ms - hitMs) /
            AppLaunchSplash.exitDuration.inMilliseconds)
        .clamp(0.0, 1.0);
    final logoFade = local < 0.55
        ? 1.0 - Curves.easeIn.transform(local / 0.55)
        : 0.0;
    final contentOpacity = local < 0.35
        ? 0.0
        : Curves.easeOut.transform(((local - 0.35) / 0.65).clamp(0.0, 1.0));

    return _SplashFrame(
      scale: _restScale,
      logoOpacity: logoFade,
      contentOpacity: contentOpacity,
      backgroundOpacity: 1 - contentOpacity,
      brandOpacity: logoFade,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final logoWidth = size.width * 0.52;

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
          final logoOp = _warmingLogo && frame.logoOpacity < 0.01
              ? 0.01
              : frame.logoOpacity;

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
                        Positioned(
                          top: padding.top + 36,
                          left: 28,
                          right: 28,
                          child: Opacity(
                            opacity: frame.brandOpacity.clamp(0, 1),
                            child: BrandTitleColumn(
                              listenToConfig: true,
                              spacing: 6,
                              brandStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2.0,
                                height: 1.05,
                              ),
                              districtStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: Opacity(
                            opacity: logoOp.clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: frame.scale,
                              child: logoChild,
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
    required this.logoOpacity,
    required this.contentOpacity,
    required this.backgroundOpacity,
    this.brandOpacity = 0,
  });

  final double scale;
  final double logoOpacity;
  final double contentOpacity;
  final double backgroundOpacity;
  final double brandOpacity;
}

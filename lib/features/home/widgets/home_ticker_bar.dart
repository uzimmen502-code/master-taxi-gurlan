import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/home_ticker_ad.dart';
import '../../../models/home_ticker_animation_style.dart';
import '../utils/home_ticker_layout.dart';

/// Duo ostida — matn to‘g‘ridan fon ustida (quti yo‘q).
class HomeTickerBar extends StatefulWidget {
  const HomeTickerBar({super.key, required this.ads});

  final List<HomeTickerAd> ads;

  @override
  State<HomeTickerBar> createState() => _HomeTickerBarState();
}

class _HomeTickerBarState extends State<HomeTickerBar> {
  int _adIndex = 0;

  void _nextAd() {
    if (!mounted || widget.ads.isEmpty) return;
    setState(() => _adIndex = (_adIndex + 1) % widget.ads.length);
  }

  @override
  void didUpdateWidget(covariant HomeTickerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ads != widget.ads) {
      _adIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) return const SizedBox.shrink();

    final ad = widget.ads[_adIndex % widget.ads.length];

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plan = HomeTickerLayoutPlan.compute(
            ad: ad,
            maxWidth: constraints.maxWidth,
          );

          return AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: double.infinity,
              height: plan.barHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HomeTickerLayoutPlan.horizontalPadding,
                  vertical: HomeTickerLayoutPlan.verticalPadding,
                ),
                child: _TickerAdPlayer(
                  key: ValueKey(
                    '${ad.id}_${ad.animationStyle}_${plan.resolvedStyle}_'
                    '${plan.maxLines}_$_adIndex',
                  ),
                  ad: ad,
                  plan: plan,
                  maxWidth: constraints.maxWidth -
                      HomeTickerLayoutPlan.horizontalPadding * 2,
                  onCycleComplete: _nextAd,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TickerAdPlayer extends StatefulWidget {
  const _TickerAdPlayer({
    super.key,
    required this.ad,
    required this.plan,
    required this.maxWidth,
    required this.onCycleComplete,
  });

  final HomeTickerAd ad;
  final HomeTickerLayoutPlan plan;
  final double maxWidth;
  final VoidCallback onCycleComplete;

  @override
  State<_TickerAdPlayer> createState() => _TickerAdPlayerState();
}

class _TickerAdPlayerState extends State<_TickerAdPlayer>
    with SingleTickerProviderStateMixin {
  Timer? _holdTimer;
  Timer? _adRotateTimer;
  AnimationController? _marqueeCtrl;
  int _visibleChars = 0;
  int _visibleLines = 0;
  int _visibleWords = 0;
  Offset _slideOffset = const Offset(1.15, 0);
  double _fadeOpacity = 0;
  double _fitFadeOpacity = 0;
  double _popScale = 0.82;
  double _pulseOpacity = 1;
  List<String> _chars = const [];
  List<String> _words = const [];

  HomeTickerLayoutPlan get plan => widget.plan;

  TextStyle get _textStyle => HomeTickerLayoutPlan.textStyleFor(widget.ad);

  int get _letterIntervalMs {
    final sp = widget.ad.scrollSpeed.clamp(15, 120);
    return (1000 / (sp * 0.75)).round().clamp(35, 220);
  }

  int get _stepIntervalMs {
    final sp = widget.ad.scrollSpeed.clamp(15, 120);
    return (900 - sp * 5).round().clamp(80, 450);
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _TickerAdPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ad.id != widget.ad.id ||
        oldWidget.ad.text != widget.ad.text ||
        oldWidget.plan.resolvedStyle != widget.plan.resolvedStyle ||
        oldWidget.plan.maxLines != widget.plan.maxLines) {
      _stop();
      _start();
    }
  }

  void _stop() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _adRotateTimer?.cancel();
    _adRotateTimer = null;
    _marqueeCtrl?.dispose();
    _marqueeCtrl = null;
  }

  bool get _loopsStyleAnimation =>
      HomeTickerAnimationStyle.isFitOnScreen(plan.resolvedStyle);

  void _armAdRotation() {
    _adRotateTimer?.cancel();
    final sec = widget.ad.durationSec.clamp(3, 120);
    _adRotateTimer = Timer(Duration(seconds: sec), () {
      if (!mounted) return;
      widget.onCycleComplete();
    });
  }

  void _resetFitAnimationState() {
    _visibleLines = 0;
    _visibleWords = 0;
    _fitFadeOpacity = 0;
    _popScale = 0.82;
    _pulseOpacity = 1;
  }

  /// Fit uslublar: animatsiya tugagach qisqa pauza, keyin yana boshlanadi.
  void _scheduleStyleLoop({Duration pause = const Duration(milliseconds: 450)}) {
    _holdTimer?.cancel();
    _holdTimer = Timer(pause, () {
      if (!mounted) return;
      _resetFitAnimationState();
      _startFitAnimationOnly();
    });
  }

  void _startFitAnimationOnly() {
    switch (plan.resolvedStyle) {
      case HomeTickerAnimationStyle.fitFade:
        _startFitFade(loop: true);
      case HomeTickerAnimationStyle.fitLines:
        _startFitLines(loop: true);
      case HomeTickerAnimationStyle.fitWords:
        _startFitWords(loop: true);
      case HomeTickerAnimationStyle.fitPulse:
        _startFitPulse(loop: true);
      case HomeTickerAnimationStyle.fitPop:
        _startFitPop(loop: true);
      default:
        break;
    }
  }

  void _start() {
    final text = widget.ad.text;
    _chars = text.characters.toList();
    _words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .toList();
    if (text.isEmpty) {
      _scheduleNext(const Duration(milliseconds: 300));
      return;
    }

    if (plan.useMarquee) {
      _startMarquee(text);
      return;
    }

    if (_loopsStyleAnimation) {
      _armAdRotation();
    }

    switch (plan.resolvedStyle) {
      case HomeTickerAnimationStyle.typewriter:
        _startTypewriter();
      case HomeTickerAnimationStyle.cascade:
        _startCascade();
      case HomeTickerAnimationStyle.fadeIn:
        _startFadeIn();
      case HomeTickerAnimationStyle.slideIn:
        _startSlideIn();
      case HomeTickerAnimationStyle.fitFade:
        _startFitFade(loop: true);
      case HomeTickerAnimationStyle.fitLines:
        _startFitLines(loop: true);
      case HomeTickerAnimationStyle.fitWords:
        _startFitWords(loop: true);
      case HomeTickerAnimationStyle.fitPulse:
        _startFitPulse(loop: true);
      case HomeTickerAnimationStyle.fitPop:
        _startFitPop(loop: true);
      default:
        _startFadeIn();
    }
  }

  void _scheduleNext(Duration delay) {
    _holdTimer?.cancel();
    _holdTimer = Timer(delay, () {
      if (!mounted) return;
      widget.onCycleComplete();
    });
  }

  void _startMarquee(String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final segmentWidth = tp.width + 80;
    final pxPerSec = widget.ad.scrollSpeed.clamp(15, 120).toDouble();
    final scrollSec = (segmentWidth / pxPerSec).clamp(6.0, 60.0);

    _marqueeCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (scrollSec * 1000).round()),
    )..repeat();

    _scheduleNext(Duration(seconds: widget.ad.durationSec));
    if (mounted) setState(() {});
  }

  void _startTypewriter() {
    _visibleChars = 0;
    void tick() {
      if (!mounted) return;
      if (_visibleChars >= _chars.length) {
        _scheduleNext(Duration(seconds: widget.ad.durationSec));
        return;
      }
      setState(() => _visibleChars++);
      _holdTimer = Timer(Duration(milliseconds: _letterIntervalMs), tick);
    }
    tick();
  }

  void _startCascade() {
    _visibleChars = 0;
    void tick() {
      if (!mounted) return;
      if (_visibleChars >= _chars.length) {
        _scheduleNext(Duration(seconds: widget.ad.durationSec));
        return;
      }
      setState(() => _visibleChars++);
      _holdTimer = Timer(Duration(milliseconds: _letterIntervalMs), tick);
    }
    tick();
  }

  void _startFadeIn() {
    final enterMs = (2200 - widget.ad.scrollSpeed * 12).clamp(600, 2000);
    setState(() => _fadeOpacity = 0);
    Future.microtask(() {
      if (!mounted) return;
      setState(() => _fadeOpacity = 1);
    });
    _scheduleNext(
      Duration(milliseconds: enterMs) +
          Duration(seconds: widget.ad.durationSec),
    );
  }

  void _startSlideIn() {
    final enterMs = (2400 - widget.ad.scrollSpeed * 14).clamp(500, 1800);
    setState(() => _slideOffset = const Offset(1.15, 0));
    Future.microtask(() {
      if (!mounted) return;
      setState(() => _slideOffset = Offset.zero);
    });
    _scheduleNext(
      Duration(milliseconds: enterMs) +
          Duration(seconds: widget.ad.durationSec),
    );
  }

  void _startFitFade({bool loop = false}) {
    final enterMs = (2200 - widget.ad.scrollSpeed * 12).clamp(600, 2000);
    final holdMs = (widget.ad.durationSec * 200).clamp(400, 1800);
    setState(() => _fitFadeOpacity = 0);
    Future.microtask(() {
      if (!mounted) return;
      setState(() => _fitFadeOpacity = 1);
    });
    if (!loop) {
      _scheduleNext(
        Duration(milliseconds: enterMs) +
            Duration(seconds: widget.ad.durationSec),
      );
      return;
    }
    _holdTimer = Timer(Duration(milliseconds: enterMs + holdMs), () {
      if (!mounted) return;
      setState(() => _fitFadeOpacity = 0);
      _holdTimer = Timer(Duration(milliseconds: enterMs), () {
        if (!mounted) return;
        _scheduleStyleLoop();
      });
    });
  }

  void _startFitLines({bool loop = false}) {
    _visibleLines = 0;
    final target = plan.maxLines.clamp(1, 5);
    final holdMs = (widget.ad.durationSec * 200).clamp(400, 1800);
    void tick() {
      if (!mounted) return;
      if (_visibleLines >= target) {
        if (!loop) {
          _scheduleNext(Duration(seconds: widget.ad.durationSec));
          return;
        }
        _holdTimer = Timer(Duration(milliseconds: holdMs), () {
          if (!mounted) return;
          _scheduleStyleLoop();
        });
        return;
      }
      setState(() => _visibleLines++);
      _holdTimer = Timer(Duration(milliseconds: _stepIntervalMs), tick);
    }
    tick();
  }

  void _startFitWords({bool loop = false}) {
    _visibleWords = 0;
    final holdMs = (widget.ad.durationSec * 200).clamp(400, 1800);
    void tick() {
      if (!mounted) return;
      if (_visibleWords >= _words.length) {
        if (!loop) {
          _scheduleNext(Duration(seconds: widget.ad.durationSec));
          return;
        }
        _holdTimer = Timer(Duration(milliseconds: holdMs), () {
          if (!mounted) return;
          _scheduleStyleLoop();
        });
        return;
      }
      setState(() => _visibleWords++);
      _holdTimer = Timer(Duration(milliseconds: _stepIntervalMs), tick);
    }
    tick();
  }

  void _startFitPulse({bool loop = false}) {
    _pulseOpacity = 1;
    var tickCount = 0;
    final pulsesPerCycle =
        (widget.ad.durationSec * 4).clamp(8, 48).round();
    void tick() {
      if (!mounted) return;
      tickCount++;
      final wave = (math.sin(tickCount * 0.22) + 1) / 2;
      setState(() => _pulseOpacity = 0.55 + 0.45 * wave);
      if (tickCount >= pulsesPerCycle) {
        if (!loop) {
          _scheduleNext(const Duration(milliseconds: 200));
          return;
        }
        _scheduleStyleLoop(pause: const Duration(milliseconds: 280));
        return;
      }
      _holdTimer = Timer(const Duration(milliseconds: 60), tick);
    }
    tick();
  }

  void _startFitPop({bool loop = false}) {
    final enterMs = (2400 - widget.ad.scrollSpeed * 14).clamp(500, 1800);
    final holdMs = (widget.ad.durationSec * 200).clamp(400, 1800);
    setState(() => _popScale = 0.82);
    Future.microtask(() {
      if (!mounted) return;
      setState(() => _popScale = 1);
    });
    if (!loop) {
      _scheduleNext(
        Duration(milliseconds: enterMs) +
            Duration(seconds: widget.ad.durationSec),
      );
      return;
    }
    _holdTimer = Timer(Duration(milliseconds: enterMs + holdMs), () {
      if (!mounted) return;
      setState(() => _popScale = 0.82);
      _holdTimer = Timer(Duration(milliseconds: enterMs), () {
        if (!mounted) return;
        _scheduleStyleLoop();
      });
    });
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Widget _multilineText(String text, {double opacity = 1, int? maxLines}) {
    return Opacity(
      opacity: opacity,
      child: Text(
        text,
        style: _textStyle,
        maxLines: maxLines ?? plan.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Matn ekran chegarasidan chiqmasin — kenglik/ balandlik bo'yicha sig'diradi.
  Widget _fitOnScreen(Widget child) {
    return ClipRect(
      child: Align(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.ad.text;
    if (text.isEmpty) return const SizedBox.shrink();

    if (plan.useMarquee) {
      return _buildMarquee(text);
    }

    return switch (plan.resolvedStyle) {
      HomeTickerAnimationStyle.typewriter => _buildTypewriter(text),
      HomeTickerAnimationStyle.cascade => _buildCascade(text),
      HomeTickerAnimationStyle.slideIn => _buildSlide(text),
      HomeTickerAnimationStyle.fitFade => _buildFitFade(text),
      HomeTickerAnimationStyle.fitLines => _buildFitLines(text),
      HomeTickerAnimationStyle.fitWords => _buildFitWords(text),
      HomeTickerAnimationStyle.fitPulse => _buildFitPulse(text),
      HomeTickerAnimationStyle.fitPop => _buildFitPop(text),
      _ => _buildFade(text),
    };
  }

  Widget _buildMarquee(String text) {
    if (_marqueeCtrl == null) return const SizedBox.shrink();

    final tp = TextPainter(
      text: TextSpan(text: text, style: _textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: widget.maxWidth);

    if (tp.width <= widget.maxWidth) {
      return Center(child: _multilineText(text));
    }

    final segmentWidth = tp.width + 80;
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _marqueeCtrl!,
        builder: (context, _) {
          final dx = -_marqueeCtrl!.value * segmentWidth;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text, style: _textStyle, maxLines: 1),
                const SizedBox(width: 80),
                Text(text, style: _textStyle, maxLines: 1),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTypewriter(String text) {
    final shown = _chars.take(_visibleChars.clamp(0, _chars.length)).join();
    return Center(
      child: Text(
        shown,
        style: _textStyle,
        maxLines: plan.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildCascade(String text) {
    if (plan.maxLines > 1) {
      final count = _visibleChars.clamp(0, _chars.length);
      final shown = _chars.take(count).join();
      return Center(child: _multilineText(shown));
    }

    final count = _visibleChars.clamp(0, _chars.length);
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(count, (i) {
            return TweenAnimationBuilder<double>(
              key: ValueKey('$count-$i-${_chars[i]}'),
              tween: Tween(begin: 28, end: 0),
              duration: Duration(milliseconds: _letterIntervalMs + 80),
              curve: Curves.easeOutCubic,
              builder: (context, dx, child) {
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: Opacity(
                    opacity: (1 - (dx / 28)).clamp(0.3, 1.0),
                    child: child,
                  ),
                );
              },
              child: Text(_chars[i], style: _textStyle),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildFade(String text) {
    final enterMs = (2200 - widget.ad.scrollSpeed * 12).clamp(600, 2000);
    return AnimatedOpacity(
      opacity: _fadeOpacity,
      duration: Duration(milliseconds: enterMs.round()),
      curve: Curves.easeInOut,
      child: Center(child: _multilineText(text)),
    );
  }

  Widget _buildSlide(String text) {
    final enterMs = (2400 - widget.ad.scrollSpeed * 14).clamp(500, 1800);
    return AnimatedSlide(
      offset: _slideOffset,
      duration: Duration(milliseconds: enterMs.round()),
      curve: Curves.easeOutCubic,
      child: Center(child: _multilineText(text)),
    );
  }

  Widget _buildFitFade(String text) {
    final enterMs = (2200 - widget.ad.scrollSpeed * 12).clamp(600, 2000);
    return _fitOnScreen(
      AnimatedOpacity(
        opacity: _fitFadeOpacity,
        duration: Duration(milliseconds: enterMs.round()),
        curve: Curves.easeInOut,
        child: _multilineText(text),
      ),
    );
  }

  Widget _buildFitLines(String text) {
    final lines = _visibleLines.clamp(0, plan.maxLines);
    return _fitOnScreen(
      _multilineText(text, maxLines: lines == 0 ? 1 : lines),
    );
  }

  Widget _buildFitWords(String text) {
    if (_words.isEmpty) {
      return _fitOnScreen(_multilineText(text));
    }
    final shown = _words.take(_visibleWords.clamp(0, _words.length)).join(' ');
    return _fitOnScreen(_multilineText(shown));
  }

  Widget _buildFitPulse(String text) {
    return _fitOnScreen(
      Opacity(
        opacity: _pulseOpacity,
        child: _multilineText(text),
      ),
    );
  }

  Widget _buildFitPop(String text) {
    final enterMs = (2400 - widget.ad.scrollSpeed * 14).clamp(500, 1800);
    return _fitOnScreen(
      AnimatedScale(
        scale: _popScale,
        duration: Duration(milliseconds: enterMs.round()),
        curve: Curves.easeOutBack,
        child: _multilineText(text),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Асосий экран «жонли» фони — енгил gradient + камёб shine.
///
/// Фақат шу қатлам қайта чизилади ([RepaintBoundary]); ListView/тагмалар
/// анимациядан қайта қурилмайди. `disableAnimations` → тинч лайм.
class HomeAliveBackground extends StatefulWidget {
  const HomeAliveBackground({super.key});

  @override
  State<HomeAliveBackground> createState() => _HomeAliveBackgroundState();
}

class _HomeAliveBackgroundState extends State<HomeAliveBackground>
    with TickerProviderStateMixin {
  /// Ранг «нафас» — тўлиқ цикл ~9 с.
  late final AnimationController _breathe;

  /// Shine такрори ~2.7 с; чизиқ ҳаракати ~0.85 с.
  late final AnimationController _shine;

  static const _breathePeriod = Duration(milliseconds: 9000);
  static const _shinePeriod = Duration(milliseconds: 2700);

  static const _stops = <Color>[
    AppColors.limeEdge, // #73C800
    AppColors.limeMid, // #9CFF00
    AppColors.lime, // #B7FF1A
    AppColors.limeBright, // #D9FF3F
    AppColors.limeHighlight, // #F6FF8A
    AppColors.limeBright,
    AppColors.lime,
    AppColors.limeMid,
    AppColors.limeEdge,
  ];

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(vsync: this, duration: _breathePeriod)
      ..repeat();
    _shine = AnimationController(vsync: this, duration: _shinePeriod)
      ..repeat();
  }

  @override
  void dispose() {
    _breathe.dispose();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const ColoredBox(color: AppColors.lime);
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_breathe, _shine]),
        builder: (context, _) {
          return CustomPaint(
            painter: _HomeAlivePainter(
              breathe: _breathe.value,
              shinePhase: _shine.value,
              stops: _stops,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _HomeAlivePainter extends CustomPainter {
  _HomeAlivePainter({
    required this.breathe,
    required this.shinePhase,
    required this.stops,
  });

  final double breathe;
  final double shinePhase;
  final List<Color> stops;

  /// Shine чизиғи давом этиши (shinePeriod нисбатида).
  static const _shineSpan = 0.32;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Марказ ёруғроқ, четда #73C800 — диагонал градиент.
    final shift = breathe;
    final c0 = _sample(shift);
    final c1 = _sample(shift + 0.18);
    final c2 = _sample(shift + 0.36);
    final c3 = _sample(shift + 0.55);
    final edge = AppColors.limeEdge;

    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment(-1.2 + shift * 0.4, -1.0),
        end: Alignment(1.0, 1.2 - shift * 0.35),
        colors: [
          Color.lerp(edge, c0, 0.55)!,
          c1,
          c2,
          Color.lerp(c3, AppColors.limeHighlight, 0.35)!,
          Color.lerp(c2, edge, 0.25)!,
          edge,
        ],
        stops: const [0.0, 0.22, 0.45, 0.62, 0.82, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    // Shine — 30° диагонал, чап→ўнг.
    if (shinePhase < _shineSpan) {
      final u = (shinePhase / _shineSpan).clamp(0.0, 1.0);
      final travel = Curves.easeInOut.transform(u);
      _paintShine(canvas, size, travel);
    }
  }

  void _paintShine(Canvas canvas, Size size, double travel) {
    final w = size.width;
    final h = size.height;
    // Диагонал йўл бўйлаб марказ.
    final cx = -w * 0.35 + (w * 1.7) * travel;
    final cy = h * 0.5;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(30 * math.pi / 180);

    final bandH = h * 1.6;
    final glowW = 56.0;
    final coreW = 10.0;

    final glowRect = Rect.fromCenter(
      center: Offset.zero,
      width: glowW,
      height: bandH,
    );
    final coreRect = Rect.fromCenter(
      center: Offset.zero,
      width: coreW,
      height: bandH,
    );

    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0x00FFFFB4),
          const Color(0x33FFFFB4), // ~0.20
          const Color(0x00FFFFB4),
        ],
      ).createShader(glowRect);
    canvas.drawRect(glowRect, glowPaint);

    final corePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0x00FFFFFF),
          const Color(0xBFFFFFFF), // ~0.75
          const Color(0x00FFFFFF),
        ],
      ).createShader(coreRect);
    canvas.drawRect(coreRect, corePaint);

    canvas.restore();
  }

  Color _sample(double t) {
    final n = stops.length;
    final x = ((t % 1.0) + 1.0) % 1.0;
    final f = x * (n - 1);
    final i = f.floor().clamp(0, n - 2);
    final local = f - i;
    return Color.lerp(stops[i], stops[i + 1], local)!;
  }

  @override
  bool shouldRepaint(covariant _HomeAlivePainter old) {
    return old.breathe != breathe || old.shinePhase != shinePhase;
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';

/// Кафе-ресторан / уй ошпази ОЧИЛДИ табриги (эга, 2026-10-31: «Б» — конфетти).
///
/// Икки пастки бурчакдан рангли конфетти отилади (~3 с), ўртада карта «Панелга ўтиш»
/// босилгунча туради. Пакетсиз — [CustomPainter] (APK ҳажми ошмайди). Тизимда
/// «анимацияни камайтириш» ёқилган бўлса — конфеттисиз, фақат карта.
Future<void> showOpenedCelebration(BuildContext context, {required bool homeCook}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, __) => _OpenedCelebration(homeCook: homeCook),
    transitionBuilder: (ctx, anim, _, child) {
      final a = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: child),
      );
    },
  );
}

class _OpenedCelebration extends StatefulWidget {
  const _OpenedCelebration({required this.homeCook});

  final bool homeCook;

  @override
  State<_OpenedCelebration> createState() => _OpenedCelebrationState();
}

class _OpenedCelebrationState extends State<_OpenedCelebration> with SingleTickerProviderStateMixin {
  // `initState` да (лениво эмас): «анимацияни камайтириш» ёқиқ бўлса контроллер ишлатилмайди ва
  // биринчи марта `dispose` да яратилиб, ўчирилган дарахтдан TickerMode қидирарди.
  late final AnimationController _ctrl;
  final _particles = ConfettiPainter.burst(math.Random(7));

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: ConfettiPainter.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduce && !_ctrl.isAnimating && _ctrl.value == 0) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Stack(
      children: [
        if (!reduce)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => CustomPaint(
                  key: const ValueKey('opened_confetti'),
                  painter: ConfettiPainter(_particles, _ctrl.value),
                ),
              ),
            ),
          ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Material(
              color: c.surface,
              borderRadius: BorderRadius.circular(20),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
                      child: Icon(
                        widget.homeCook ? Icons.soup_kitchen_rounded : Icons.restaurant_rounded,
                        size: 32,
                        color: c.brandInk,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      context.tr(widget.homeCook
                          ? 'restaurants_m_submitted_approved_home_cook'
                          : 'restaurants_m_submitted_approved'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: c.ink, height: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr('restaurants_m_opened_sub'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: c.ink2, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('opened_go_panel'),
                        style: FilledButton.styleFrom(
                          backgroundColor: c.brand,
                          foregroundColor: c.brandInk,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          context.tr('restaurants_m_opened_go_panel'),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
  }
}

/// Бир дона конфетти (нисбий бошланғич нуқта ва тезлик — экран ўлчамига боғлиқ эмас).
@immutable
class ConfettiParticle {
  const ConfettiParticle({
    required this.fromLeft,
    required this.vx,
    required this.vy,
    required this.spin,
    required this.phase,
    required this.w,
    required this.h,
    required this.color,
  });

  final bool fromLeft;
  final double vx, vy, spin, phase, w, h;
  final Color color;
}

/// Конфетти чизувчи — соф ҳисоб (вақт [t] 0..1 бўйича ҳолат; тест учун детерминистик).
class ConfettiPainter extends CustomPainter {
  ConfettiPainter(this.particles, this.t);

  final List<ConfettiParticle> particles;

  /// 0..1 — [duration] бўйича ўтган вақт.
  final double t;

  static const duration = Duration(milliseconds: 3200);
  static const _colors = [
    Color(0xFFFFA500), Color(0xFFFF5A5F), Color(0xFF3CB371), Color(0xFF3B82F6),
    Color(0xFFA855F7), Color(0xFFFFD400), Color(0xFFFF7AB6),
  ];

  /// Икки бурчакдан 70 тадан — превьюдаги «Б» вариант билан бир хил.
  static List<ConfettiParticle> burst(math.Random r, {int perSide = 70}) {
    double rnd(double a, double b) => a + r.nextDouble() * (b - a);
    final out = <ConfettiParticle>[];
    for (final left in const [true, false]) {
      for (var i = 0; i < perSide; i++) {
        final deg = left ? rnd(290, 340) : rnd(200, 250);
        final sp = rnd(5, 10);
        out.add(ConfettiParticle(
          fromLeft: left,
          vx: math.cos(deg * math.pi / 180) * sp,
          vy: math.sin(deg * math.pi / 180) * sp,
          spin: rnd(-0.3, 0.3),
          phase: rnd(0, 6),
          w: rnd(5, 9),
          h: rnd(8, 13),
          color: _colors[i % _colors.length],
        ));
      }
    }
    return out;
  }

  /// Кадр (60 fps) бўйича ҳолат: ҳаво қаршилиги 0.99/кадр, оғирлик 0.16/кадр².
  static Offset positionAt(ConfettiParticle p, double frames, Size size) {
    final x0 = p.fromLeft ? 10.0 : size.width - 10;
    final y0 = size.height - 20;
    final drag = (1 - math.pow(0.99, frames)) / 0.01;
    return Offset(x0 + p.vx * drag, y0 + p.vy * frames + 0.08 * frames * frames);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final frames = t * duration.inMilliseconds / 1000 * 60;
    // Охирги 15 % да аста-секин йўқолади.
    final fade = t > 0.85 ? (1 - t) / 0.15 : 1.0;
    final paint = Paint();
    for (final p in particles) {
      final pos = positionAt(p, frames, size);
      if (pos.dy > size.height + 20) continue;
      final rot = p.phase + p.spin * frames;
      final flip = math.cos(frames / 8 + p.phase).abs();
      paint.color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(rot);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h * flip), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.t != t || old.particles != particles;
}

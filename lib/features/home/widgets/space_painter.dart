import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Серверсиз — бош экран учун юлдузлар / комета / кичик система.
class ShootingStar {
  ShootingStar({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.life = 1.0,
  });

  double x;
  double y;
  final double vx;
  final double vy;
  double life;
}

class _Star {
  const _Star({
    required this.nx,
    required this.ny,
    required this.radius,
    required this.phase,
    required this.speed,
  });

  final double nx;
  final double ny;
  final double radius;
  final double phase;
  final double speed;
}

class SpacePainter extends CustomPainter {
  SpacePainter(this.t, this.shootingStars);

  /// Секундлар (0…60 цикл).
  final double t;
  final List<ShootingStar> shootingStars;

  static final math.Random _r42 = math.Random(42);
  static final List<_Star> _stars = _buildStars();

  static List<_Star> _buildStars() {
    final list = <_Star>[];
    for (var i = 0; i < 180; i++) {
      list.add(
        _Star(
          nx: _r42.nextDouble(),
          ny: _r42.nextDouble(),
          radius: 0.2 + _r42.nextDouble() * 1.3,
          phase: _r42.nextDouble() * 2 * math.pi,
          speed: 0.008 + _r42.nextDouble() * 0.02,
        ),
      );
    }
    return list;
  }

  @override
  bool shouldRepaint(covariant SpacePainter oldDelegate) => true;

  Color _hsl(double h, double s, double l) =>
      HSLColor.fromAHSL(1, h % 360, s.clamp(0, 1), l.clamp(0, 1)).toColor();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── STEP 2: animated gradient background ─────────────────────────
    final c1 = _hsl(185 + math.sin(t * 0.3) * 8, 0.82, 0.035);
    final c2 = _hsl(220 + math.sin(t * 0.25) * 10, 0.85, 0.045);
    final c3 = _hsl(195 + math.cos(t * 0.28) * 8, 0.78, 0.035);
    final bg = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, h),
        [c1, c2, c3],
        const [0.0, 0.48, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bg);

    // ── STEP 3: nebula orbs (MaskFilter only here) ───────────────────
    void drawNebula(Offset c, double radius, Color color) {
      final layer = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withAlpha(0)],
          stops: const [0.35, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: radius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
      canvas.drawCircle(c, radius, layer);
    }

    drawNebula(
      Offset(w * 0.15 + math.sin(t * 0.4) * 18, h * 0.12 + math.cos(t * 0.35) * 15),
      130,
      const Color(0x29009AAA),
    );
    drawNebula(
      Offset(w * 0.80 + math.cos(t * 0.38) * 20, h * 0.75 + math.sin(t * 0.42) * 18),
      140,
      const Color(0x2D0A28A0),
    );
    drawNebula(
      Offset(w * 0.50 + math.sin(t * 0.22) * 25, h * 0.50 + math.cos(t * 0.28) * 20),
      100,
      const Color(0x1A005078),
    );

    // ── STEP 4: galaxy spiral ──────────────────────────────────────────
    final galCenter = Offset(w * 0.5, h * 0.45);
    canvas.save();
    canvas.translate(galCenter.dx, galCenter.dy);
    canvas.rotate(t * 0.03);
    canvas.scale(1.0, 0.42);
    final galPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x248CD2FF),
          const Color(0x008CD2FF),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 100));
    canvas.drawCircle(Offset.zero, 100, galPaint);
    canvas.restore();

    // ── STEP 5: stars ────────────────────────────────────────────────
    for (final s in _stars) {
      final px = s.nx * w;
      final py = s.ny * h;
      final alpha = 0.35 + 0.65 * (math.sin(t * s.speed * 80 + s.phase)).abs();
      final col = Color.fromRGBO(200, 240, 255, alpha.clamp(0.0, 1.0));
      if (s.radius > 1.0) {
        final glow = Paint()
          ..color = Color.fromRGBO(160, 220, 255, (alpha * 0.12).clamp(0.0, 1.0))
          ..maskFilter = null;
        canvas.drawCircle(Offset(px, py), s.radius * 2.8, glow);
      }
      canvas.drawCircle(Offset(px, py), s.radius, Paint()..color = col);
    }

    // ── STEP 6: solar system ─────────────────────────────────────────
    final sunX = w * 0.38;
    final sunY = h * 0.22;
    const scaleY = 0.55;

    void drawOrbit(double r) {
      final path = Path()
        ..addOval(
          Rect.fromCenter(
            center: Offset(sunX, sunY),
            width: 2 * r,
            height: 2 * r * scaleY,
          ),
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = const Color.fromRGBO(100, 180, 220, 0.10),
      );
    }

    for (final r in [28.0, 42.0, 58.0, 74.0, 96.0, 120.0]) {
      drawOrbit(r);
    }

    Offset planetPos(double orbit, double startAngle, double speed) {
      final ang = startAngle + t * speed;
      return Offset(
        sunX + math.cos(ang) * orbit,
        sunY + math.sin(ang) * orbit * scaleY,
      );
    }

    // Planet renderers return center + draw callback order handled by caller
    void drawMercury(Offset p) {
      final g = RadialGradient(
        colors: const [Color(0xFFB0B0B0), Color(0xFF6E6E6E)],
      ).createShader(Rect.fromCircle(center: p, radius: 3));
      canvas.drawCircle(p, 3, Paint()..shader = g);
    }

    void drawVenus(Offset p) {
      final g = RadialGradient(
        colors: const [Color(0xFFFFF59D), Color(0xFFFFC107), Color(0xFFFF8F00)],
      ).createShader(Rect.fromCircle(center: p, radius: 4.5));
      canvas.drawCircle(p, 4.5, Paint()..shader = g);
    }

    void drawEarth(Offset p) {
      final r = 5.0;
      canvas.drawCircle(
        p,
        r + 1.2,
        Paint()..color = const Color.fromRGBO(100, 200, 255, 0.25),
      );
      final g = RadialGradient(
        colors: const [Color(0xFF4FC3F7), Color(0xFF2E7D32), Color(0xFF1565C0)],
      ).createShader(Rect.fromCircle(center: p, radius: r));
      canvas.drawCircle(p, r, Paint()..shader = g);
      final moonAng = t * 1.8 + 3.0;
      final md = r * 2.8;
      final moon = Offset(p.dx + math.cos(moonAng) * md, p.dy + math.sin(moonAng) * md);
      canvas.drawCircle(
        moon,
        1.8,
        Paint()..color = const Color(0xFFE0E0E0),
      );
    }

    void drawMars(Offset p) {
      final r = 4.0;
      final g = RadialGradient(
        colors: const [Color(0xFFFF7043), Color(0xFFD84315)],
      ).createShader(Rect.fromCircle(center: p, radius: r));
      canvas.drawCircle(p, r, Paint()..shader = g);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(p.dx, p.dy - r * 0.35), radius: r * 0.55),
        math.pi * 1.1,
        math.pi * 0.8,
        false,
        Paint()..color = Colors.white.withValues(alpha: 0.75),
      );
    }

    void drawJupiter(Offset p) {
      final r = 9.0;
      final rect = Rect.fromCircle(center: p, radius: r);
      final g = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFD7CCC8),
          const Color(0xFF8D6E63),
          const Color(0xFF5D4037),
          const Color(0xFFD7CCC8),
        ],
        stops: const [0.0, 0.35, 0.7, 1.0],
      ).createShader(rect);
      canvas.drawCircle(p, r, Paint()..shader = g);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(p.dx + 2, p.dy + 1), width: 5, height: 3.5),
        Paint()..color = const Color(0xFFB71C1C),
      );
    }

    void drawSaturn(Offset p) {
      final r = 7.5;
      void drawRingArc(double start, double sweep, bool behind) {
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.scale(1.0, 0.30);
        for (final m in [1.35, 1.50, 1.70]) {
          final op = behind ? 0.22 : 0.38;
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: r * m),
            start,
            sweep,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = behind ? 1.0 : 1.2
              ..color = Color.fromRGBO(255, 220, 160, op),
          );
        }
        canvas.restore();
      }

      drawRingArc(math.pi, math.pi, true);
      final body = RadialGradient(
        colors: const [Color(0xFFFFF8E1), Color(0xFFFFD54F), Color(0xFFFFA000)],
      ).createShader(Rect.fromCircle(center: p, radius: r));
      canvas.drawCircle(p, r, Paint()..shader = body);
      drawRingArc(0, math.pi, false);
    }

    final mercuryP = planetPos(28, 1.1, 0.90);
    final venusP = planetPos(42, 2.4, 0.60);
    final earthP = planetPos(58, 0.3, 0.45);
    final marsP = planetPos(74, 4.0, 0.32);
    final jupiterP = planetPos(96, 5.2, 0.18);
    final saturnP = planetPos(120, 0.8, 0.12);

    final behind = <VoidCallback>[];
    final front = <VoidCallback>[];

    void addLayer(Offset p, VoidCallback draw) {
      if (p.dy >= sunY) {
        behind.add(draw);
      } else {
        front.add(draw);
      }
    }

    addLayer(mercuryP, () => drawMercury(mercuryP));
    addLayer(venusP, () => drawVenus(venusP));
    addLayer(earthP, () => drawEarth(earthP));
    addLayer(marsP, () => drawMars(marsP));
    addLayer(jupiterP, () => drawJupiter(jupiterP));
    addLayer(saturnP, () => drawSaturn(saturnP));

    for (final d in behind) {
      d();
    }

    _drawSun(canvas, sunX, sunY, t);

    for (final d in front) {
      d();
    }

    // ── STEP 7: shooting stars (data from parent) ─────────────────────
    for (final s in shootingStars) {
      if (s.life <= 0) continue;
      final tailStart = Offset(s.x - s.vx * 16, s.y - s.vy * 16);
      final grad = Paint()
        ..shader = ui.Gradient.linear(
          tailStart,
          Offset(s.x, s.y),
          [
            Colors.transparent,
            Color.fromRGBO(180, 240, 255, s.life * 0.5),
            Colors.white.withValues(alpha: s.life),
          ],
          const [0.0, 0.55, 1.0],
        )
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(tailStart, Offset(s.x, s.y), grad);
      canvas.drawCircle(
        Offset(s.x, s.y),
        1.8,
        Paint()..color = Colors.white.withValues(alpha: s.life.clamp(0.0, 1.0)),
      );
    }
  }

  void _drawSun(Canvas canvas, double sunX, double sunY, double t) {
    final pulse = math.sin(t * 2) * 2;
    final sunCenter = Offset(sunX, sunY);
    final body = RadialGradient(
      colors: const [
        Color(0xFFFFF8D0),
        Color(0xFFFFE060),
        Color(0xFFFF9010),
        Color(0xFFCC5500),
      ],
      stops: const [0.0, 0.35, 0.72, 1.0],
    ).createShader(Rect.fromCircle(center: sunCenter, radius: 14));
    canvas.drawCircle(sunCenter, 10, Paint()..shader = body);

    for (var i = 0; i < 3; i++) {
      final rr = [16.0, 22.0, 28.0][i] + pulse;
      canvas.drawCircle(
        sunCenter,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Color.fromRGBO(255, 200, 80, 0.12 + i * 0.06),
      );
    }

    final flarePaint = Paint()
      ..color = const Color(0xFFFFDC50)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final base = t * 0.3;
    for (var i = 0; i < 6; i++) {
      final deg = i * math.pi / 3;
      final len = 13 + math.sin(t * 2 + deg) * 3;
      final x2 = sunX + math.cos(deg + base) * len;
      final y2 = sunY + math.sin(deg + base) * len;
      canvas.drawLine(sunCenter, Offset(x2, y2), flarePaint);
    }
  }
}

/// Биринчи кадрлар учун кометаларни инициализация қилиш.
List<ShootingStar> createInitialShootingStars(double w, double h) {
  final r = math.Random(99);
  final list = <ShootingStar>[];
  for (var i = 0; i < 2; i++) {
    list.add(
      ShootingStar(
        x: r.nextDouble() * w * 0.6,
        y: r.nextDouble() * h * 0.35,
        vx: 2.5 + r.nextDouble() * 3.0,
        vy: 1.2 + r.nextDouble() * 2.0,
        life: 0.4 + r.nextDouble() * 0.6,
      ),
    );
  }
  return list;
}

void updateShootingStars(
  List<ShootingStar> stars,
  double w,
  double h,
  math.Random rng,
) {
  for (final s in stars) {
    s.x += s.vx;
    s.y += s.vy;
    s.life -= 0.022;
  }
  stars.removeWhere(
    (s) => s.life <= 0 || s.x > w + 80 || s.y > h + 80 || s.x < -100,
  );
  var tries = 0;
  while (stars.length < 2 && tries < 12) {
    tries++;
    if (rng.nextDouble() < 0.7 || stars.isEmpty) {
      stars.add(
        ShootingStar(
          x: rng.nextDouble() * w * 0.6,
          y: rng.nextDouble() * h * 0.35,
          vx: 2.5 + rng.nextDouble() * 3.0,
          vy: 1.2 + rng.nextDouble() * 2.0,
          life: 1.0,
        ),
      );
    }
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Karta konturi bo'ylab qisqa oq-oltin yorug' chiziq(lar).
/// 4 ta soat yo'nalishi, 4 ta teskari — jami 8 segment.
class MetallicBorderHighlightPainter extends CustomPainter {
  MetallicBorderHighlightPainter({
    required this.progress,
    required this.borderRadius,
    this.strokeWidth = 2.4,
    this.highlightFraction = 0.13,
    this.segmentCountPerDirection = 4,
  });

  /// 0..1 — kontur bo'ylab aylanish.
  final double progress;
  final double borderRadius;
  final double strokeWidth;
  final double highlightFraction;

  /// Har bir yo'nalishdagi nur chiziqlari soni (jami 2 × segmentCountPerDirection).
  final int segmentCountPerDirection;

  static const _goldWarm = Color(0xFFFFF0A0);
  static const _goldSoft = Color(0xFFFFF8E0);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final inset = strokeWidth / 2 + 0.5;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
      Radius.circular(borderRadius - inset),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final total = metric.length;
    final segLen = total * highlightFraction;
    final travelCw = progress * total;
    final travelCcw = total - travelCw;
    final step = total / segmentCountPerDirection;

    for (var i = 0; i < segmentCountPerDirection; i++) {
      final offset = step * i;
      _drawHighlight(canvas, metric, (travelCw + offset) % total, segLen);
      _drawHighlight(canvas, metric, (travelCcw + offset) % total, segLen);
    }
  }

  void _drawHighlight(
    Canvas canvas,
    ui.PathMetric metric,
    double start,
    double length,
  ) {
    final segment = _extractSegment(metric, start, length);
    if (segment.computeMetrics().isEmpty) return;

    final mid = (start + length / 2) % metric.length;
    final tangent = metric.getTangentForOffset(mid);
    if (tangent == null) return;

    final dir = tangent.vector;
    final norm = dir.distance == 0 ? const Offset(1, 0) : dir / dir.distance;
    final gradStart = tangent.position - norm * (length * 0.35);
    final gradEnd = tangent.position + norm * (length * 0.35);

    final glowExtra = strokeWidth * (3 / 2.4);
    final blurSigma = strokeWidth * (2.5 / 2.4);

    canvas.drawPath(
      segment,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + glowExtra
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
    );

    canvas.drawPath(
      segment,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          gradStart,
          gradEnd,
          [
            _goldSoft.withValues(alpha: 0),
            _goldWarm.withValues(alpha: 0.85),
            Colors.white,
            _goldWarm.withValues(alpha: 0.85),
            _goldSoft.withValues(alpha: 0),
          ],
          const [0.0, 0.28, 0.5, 0.72, 1.0],
        ),
    );
  }

  Path _extractSegment(ui.PathMetric metric, double start, double length) {
    final total = metric.length;
    final end = start + length;
    if (end <= total) {
      return metric.extractPath(start, end);
    }
    return Path()
      ..addPath(metric.extractPath(start, total), Offset.zero)
      ..addPath(metric.extractPath(0, end - total), Offset.zero);
  }

  @override
  bool shouldRepaint(covariant MetallicBorderHighlightPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.highlightFraction != highlightFraction ||
        oldDelegate.segmentCountPerDirection != segmentCountPerDirection;
  }
}

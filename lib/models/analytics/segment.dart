import 'package:flutter/material.dart';

/// Сегментация (pie/donut/bar) учун битта улуш.
class Segment {
  const Segment({
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });

  final String label;
  final num value;
  final Color? color;
  final String? icon;
}

/// Тўлиқ сегментация — улушлар + жами.
class SegmentBreakdown {
  const SegmentBreakdown({required this.title, required this.segments});

  final String title;
  final List<Segment> segments;

  num get total => segments.fold<num>(0, (a, s) => a + s.value);

  double percentOf(Segment s) {
    final t = total;
    if (t == 0) return 0;
    return s.value.toDouble() / t.toDouble() * 100.0;
  }
}

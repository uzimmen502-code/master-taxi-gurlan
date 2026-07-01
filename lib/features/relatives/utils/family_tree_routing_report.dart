import 'package:flutter/material.dart';

import 'family_tree_line_router.dart';

/// Widget testlari uchun daraht chiziq holati.
@immutable
class FamilyTreeRoutingReport {
  const FamilyTreeRoutingReport({
    required this.routingSucceeded,
    required this.segments,
    required this.cardRects,
    required this.outerFrames,
    required this.layoutRowGap,
    required this.layoutSiblingGap,
    this.linePad = 8,
    this.lineWidth = 3.2,
  });

  final bool routingSucceeded;
  final List<({Offset a, Offset b})> segments;
  final List<Rect> cardRects;
  final List<Rect> outerFrames;
  final double layoutRowGap;
  final double layoutSiblingGap;
  final double linePad;
  final double lineWidth;

  List<Rect> get frameObstacles => [...cardRects, ...outerFrames];

  /// Chiziq ramka ICHIDAN (ochiq interior) o'tmasligi kerak.
  bool get allSegmentsClearOfFrames {
    for (final s in segments) {
      for (final r in frameObstacles) {
        if (_segPassesInterior(s.a, s.b, r)) return false;
      }
    }
    return true;
  }

  int get violations {
    var n = 0;
    for (final s in segments) {
      for (final r in frameObstacles) {
        if (_segPassesInterior(s.a, s.b, r)) n++;
      }
    }
    return n;
  }
}

bool _segPassesInterior(Offset a, Offset b, Rect r) {
  const eps = 0.5;
  final inner = r.deflate(eps);
  if (inner.width <= 0 || inner.height <= 0) return false;
  return FamilyTreeLineRouter.segHitsRect(a, b, inner);
}

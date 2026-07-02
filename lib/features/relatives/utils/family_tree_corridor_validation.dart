import 'package:flutter/material.dart';

import 'family_tree_line_router.dart';

/// Odam karta ramkasi ichidan chiziq o'tmasligi (qat'iy qoida).
class FamilyTreeCorridorValidation {
  FamilyTreeCorridorValidation._();

  static bool segmentsClear({
    required Iterable<({Offset a, Offset b})> segments,
    required List<Rect> personCards,
    double innerEps = 0.5,
  }) {
    return findViolations(
      segments: segments,
      personCards: personCards,
      innerEps: innerEps,
    ).isEmpty;
  }

  static List<({Offset a, Offset b, Rect frame})> findViolations({
    required Iterable<({Offset a, Offset b})> segments,
    required List<Rect> personCards,
    double innerEps = 0.5,
  }) {
    final out = <({Offset a, Offset b, Rect frame})>[];
    for (final s in segments) {
      for (final r in personCards) {
        final inner = r.deflate(innerEps);
        if (inner.width <= 0 || inner.height <= 0) continue;
        if (FamilyTreeLineRouter.segHitsRect(s.a, s.b, inner)) {
          out.add((a: s.a, b: s.b, frame: r));
        }
      }
    }
    return out;
  }
}

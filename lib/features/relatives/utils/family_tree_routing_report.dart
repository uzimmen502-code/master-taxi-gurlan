import 'package:flutter/material.dart';

import 'family_tree_corridor_validation.dart';

/// Widget testlari uchun daraht chiziq holati.
@immutable
class FamilyTreeRoutingReport {
  const FamilyTreeRoutingReport({
    required this.routingSucceeded,
    required this.segments,
    required this.cardRects,
    required this.cardRectsById,
    required this.parentLinks,
    required this.outerFrames,
    required this.layoutRowGap,
    required this.layoutSiblingGap,
    this.linePad = 8,
    this.lineWidth = 3.2,
  });

  final bool routingSucceeded;
  final List<({Offset a, Offset b})> segments;
  final List<Rect> cardRects;
  final Map<String, Rect> cardRectsById;
  /// childId -> parentId (ota yoki ona)
  final List<({String childId, String parentId})> parentLinks;
  final List<Rect> outerFrames;
  final double layoutRowGap;
  final double layoutSiblingGap;
  final double linePad;
  final double lineWidth;

  /// Farzand kartasi har doim ota-onadan pastda (istisno yo'q).
  bool get childrenBelowParents {
    for (final link in parentLinks) {
      final child = cardRectsById[link.childId];
      final parent = cardRectsById[link.parentId];
      if (child == null || parent == null) continue;
      if (child.top <= parent.top) return false;
    }
    return parentLinks.isNotEmpty || cardRectsById.isNotEmpty;
  }

  /// Faqat odam kartalari — nikoh ramkasi to'siq emas.
  bool get allSegmentsClearOfFrames => FamilyTreeCorridorValidation.segmentsClear(
        segments: segments,
        personCards: cardRects,
      );

  int get violations => violationDetails.length;

  List<({Offset a, Offset b, Rect frame})> get violationDetails =>
      FamilyTreeCorridorValidation.findViolations(
        segments: segments,
        personCards: cardRects,
      );
}

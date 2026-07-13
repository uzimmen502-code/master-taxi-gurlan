import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Orthogonal nasab marshrut: oila bus/stem + band segment penalty.
class FamilyTreeLineRouter {
  FamilyTreeLineRouter({
    required this.obstacles,
    required this.laneStep,
    required this.linePad,
    this.preferShortestDirect = true,
  });

  final List<Rect> obstacles;
  final double laneStep;
  final double linePad;
  /// `false` bo'lsa, to'g'ri qisqa segment ishlatilmaydi — faqat BFS yo'laklari.
  final bool preferShortestDirect;

  /// Horizontal bus Y — laneId bo'yicha (rang emas).
  final Map<int, double> _busLanes = {};
  final Map<int, int> _busCorridorOf = {};

  /// Vertikal o'zak X — laneId bo'yicha.
  final Map<int, double> _stemLanes = {};
  final Map<int, (double, double)> _stemYRangeOf = {};
  

  /// Band qilingan segmentlar (penalty / kesishish tekshiruvi).
  final List<(Offset, Offset)> _occupied = [];

  static const int maxPathPoints = 20;
  static const int maxBfsIterations = 400;
  static const double laneStepMin = 16.0;
  static const double laneStepMax = 28.0;
  static const double laneOverlapFactor = 0.9;
  static const double occupiedPenalty = 120.0;

  /// Koridor balandligi va yo'laklar soniga qarab bus qadami.
  static double laneStepFor({
    required double corridorHeight,
    required int laneCount,
    required double linePad,
    double min = laneStepMin,
    double max = laneStepMax,
  }) {
    final usable = corridorHeight - 2 * linePad;
    if (usable <= 0) return min;
    if (laneCount <= 1) return usable.clamp(min, max);
    return (usable / laneCount).clamp(min, max);
  }

  static bool segHitsRect(Offset a, Offset b, Rect r) {
    if ((a.dx - b.dx).abs() < 0.5) {
      final x = a.dx;
      if (x < r.left || x > r.right) return false;
      final y1 = math.min(a.dy, b.dy);
      final y2 = math.max(a.dy, b.dy);
      return y2 > r.top && y1 < r.bottom;
    }
    if ((a.dy - b.dy).abs() < 0.5) {
      final y = a.dy;
      if (y < r.top || y > r.bottom) return false;
      final x1 = math.min(a.dx, b.dx);
      final x2 = math.max(a.dx, b.dx);
      return x2 > r.left && x1 < r.right;
    }
    return false;
  }

  bool segmentClear(Offset a, Offset b, {List<Rect>? obstacles}) {
    final obs = obstacles ?? this.obstacles;
    for (final r in obs) {
      if (segHitsRect(a, b, r)) return false;
    }
    return true;
  }

  bool pathClear(List<Offset> path, List<Rect> obs) {
    for (var i = 0; i < path.length - 1; i++) {
      if (!segmentClear(path[i], path[i + 1], obstacles: obs)) return false;
    }
    return true;
  }

  static String ptKey(Offset p) =>
      '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}';

  static bool axisAligned(Offset a, Offset b) =>
      (a.dx - b.dx).abs() < 0.5 || (a.dy - b.dy).abs() < 0.5;

  /// Ikki orthogonal segment kesishadi yoki ustma-ust yotadi.
  static bool segmentsConflict(Offset a1, Offset b1, Offset a2, Offset b2) {
    final v1 = (a1.dx - b1.dx).abs() < 0.5;
    final v2 = (a2.dx - b2.dx).abs() < 0.5;
    final h1 = (a1.dy - b1.dy).abs() < 0.5;
    final h2 = (a2.dy - b2.dy).abs() < 0.5;
    if (!((v1 || h1) && (v2 || h2))) return false;

    if (v1 && v2) {
      if ((a1.dx - a2.dx).abs() >= 0.5) return false;
      final y1a = math.min(a1.dy, b1.dy);
      final y1b = math.max(a1.dy, b1.dy);
      final y2a = math.min(a2.dy, b2.dy);
      final y2b = math.max(a2.dy, b2.dy);
      return y1a < y2b - 0.5 && y2a < y1b - 0.5;
    }
    if (h1 && h2) {
      if ((a1.dy - a2.dy).abs() >= 0.5) return false;
      final x1a = math.min(a1.dx, b1.dx);
      final x1b = math.max(a1.dx, b1.dx);
      final x2a = math.min(a2.dx, b2.dx);
      final x2b = math.max(a2.dx, b2.dx);
      return x1a < x2b - 0.5 && x2a < x1b - 0.5;
    }
    // Orthogonal cross.
    final vx = v1 ? a1.dx : a2.dx;
    final hy = h1 ? a1.dy : a2.dy;
    final vMin = v1
        ? math.min(a1.dy, b1.dy)
        : math.min(a2.dy, b2.dy);
    final vMax = v1
        ? math.max(a1.dy, b1.dy)
        : math.max(a2.dy, b2.dy);
    final hMin = h1
        ? math.min(a1.dx, b1.dx)
        : math.min(a2.dx, b2.dx);
    final hMax = h1
        ? math.max(a1.dx, b1.dx)
        : math.max(a2.dx, b2.dx);
    final crosses = vx >= hMin - 0.5 &&
        vx <= hMax + 0.5 &&
        hy >= vMin - 0.5 &&
        hy <= vMax + 0.5;
    if (!crosses) return false;
    // T-tutashuv (kesishish nuqtasi bir segmentning uchi) — ruxsat.
    final cross = Offset(vx, hy);
    bool atEnd(Offset p, Offset s, Offset e) =>
        (p.dx - s.dx).abs() < 0.5 && (p.dy - s.dy).abs() < 0.5 ||
        (p.dx - e.dx).abs() < 0.5 && (p.dy - e.dy).abs() < 0.5;
    if (atEnd(cross, a1, b1) || atEnd(cross, a2, b2)) return false;
    return true;
  }

  bool clearOfOccupied(Offset a, Offset b) {
    for (final (oa, ob) in _occupied) {
      if (segmentsConflict(a, b, oa, ob)) return false;
    }
    return true;
  }

  double segmentPenalty(Offset a, Offset b) {
    var p = 0.0;
    for (final (oa, ob) in _occupied) {
      if (segmentsConflict(a, b, oa, ob)) p += occupiedPenalty;
    }
    return p;
  }

  void registerSegment(Offset a, Offset b) {
    if ((a.dx - b.dx).abs() < 0.5 && (a.dy - b.dy).abs() < 0.5) return;
    _occupied.add((a, b));
  }

  void registerPath(List<Offset> path) {
    for (var i = 0; i < path.length - 1; i++) {
      registerSegment(path[i], path[i + 1]);
    }
  }

  List<Offset> collectCandidates(Offset a, Offset b, List<Rect> obs) {
    final out = <Offset>[a, b];
    final seen = <String>{ptKey(a), ptKey(b)};

    void add(Offset p) {
      final k = ptKey(p);
      if (seen.add(k)) out.add(p);
    }

    final minX = math.min(a.dx, b.dx);
    final maxX = math.max(a.dx, b.dx);
    final minY = math.min(a.dy, b.dy);
    final maxY = math.max(a.dy, b.dy);

    for (final r in obs) {
      final l = r.left - linePad;
      final rt = r.right + linePad;
      final t = r.top - linePad;
      final bt = r.bottom + linePad;
      add(Offset(l, t));
      add(Offset(rt, t));
      add(Offset(l, bt));
      add(Offset(rt, bt));
      add(Offset(r.center.dx, t));
      add(Offset(r.center.dx, bt));
      add(Offset(l, r.center.dy));
      add(Offset(rt, r.center.dy));
    }

    for (final p in [a, b]) {
      for (final r in obs) {
        add(Offset(p.dx, r.top - linePad));
        add(Offset(p.dx, r.bottom + linePad));
        add(Offset(r.left - linePad, p.dy));
        add(Offset(r.right + linePad, p.dy));
      }
    }

    for (var y = minY; y <= maxY + 0.5; y += laneStep) {
      add(Offset(a.dx, y));
      add(Offset(b.dx, y));
    }
    for (var x = minX; x <= maxX + 0.5; x += laneStep) {
      add(Offset(x, a.dy));
      add(Offset(x, b.dy));
    }

    // Band segment / to'siqdan aylanib o'tish uchun qo'shimcha yo'laklar.
    for (final d in [-1.0, 1.0]) {
      final dy = d * laneStep;
      final dx = d * laneStep;
      add(Offset(a.dx, a.dy + dy));
      add(Offset(b.dx, b.dy + dy));
      add(Offset(a.dx + dx, a.dy));
      add(Offset(b.dx + dx, b.dy));
    }

    return out;
  }

  /// Orthogonal yo'l; band segmentlardan qochadi (penalty / hard skip).
  List<Offset>? route(
    Offset a,
    Offset b, {
    List<Rect>? obstacles,
  }) {
    final obs = obstacles ?? this.obstacles;
    if (preferShortestDirect &&
        segmentClear(a, b, obstacles: obs) &&
        clearOfOccupied(a, b)) {
      return [a, b];
    }

    final candidates = collectCandidates(a, b, obs);
    final visited = <String>{ptKey(a)};
    // Parent-pointer BFS — har bir node faqat 1 marta saqlanadi.
    final parent = <String, String?>{ptKey(a): null};
    final nodeAt = <String, Offset>{ptKey(a): a};
    final queue = <String>[ptKey(a)];
    var head = 0;
    var iterations = 0;
    String? goalKey;

    while (head < queue.length && iterations < maxBfsIterations) {
      iterations++;
      final curKey = queue[head++];
      final cur = nodeAt[curKey]!;
      if ((cur.dx - b.dx).abs() < 0.5 && (cur.dy - b.dy).abs() < 0.5) {
        goalKey = curKey;
        break;
      }
      // Depth limit
      var depth = 0;
      var pk = curKey as String?;
      while (pk != null && depth < maxPathPoints) {
        pk = parent[pk];
        depth++;
      }
      if (depth >= maxPathPoints) continue;

      for (final next in candidates) {
        if (!axisAligned(cur, next)) continue;
        final nk = ptKey(next);
        if (visited.contains(nk)) continue;
        if (!segmentClear(cur, next, obstacles: obs)) continue;
        if (!clearOfOccupied(cur, next)) continue;
        visited.add(nk);
        parent[nk] = curKey;
        nodeAt[nk] = next;
        queue.add(nk);
      }
    }

    if (goalKey == null) return null;
    // Reconstruct path
    final path = <Offset>[];
    var k = goalKey as String?;
    while (k != null) {
      path.add(nodeAt[k]!);
      k = parent[k];
    }
    final result = path.reversed.toList();
    if (pathClear(result, obs)) return result;
    return null;
  }

  /// Oila uchun alohida horizontal bus Y.
  double? allocateBusY({
    required Object laneId,
    required Object corridorId,
    required double preferred,
    required double minY,
    required double maxY,
    required double minX,
    required double maxX,
    List<Rect>? obstacles,
    double? laneStep,
  }) {
    if (maxY < minY) return null;
    final step = laneStep ?? this.laneStep;
    final obs = obstacles ?? this.obstacles;
    final corridorKey = corridorId.hashCode;
    final laneKey = Object.hash(identityHashCode(laneId), corridorKey);

    final existing = _busLanes[laneKey];
    if (existing != null) return existing;

    final candidates = <double>[];
    for (var y = minY; y <= maxY + 0.5; y += step) {
      candidates.add(y);
    }
    if (preferred >= minY && preferred <= maxY) {
      candidates.add(preferred);
    }
    candidates.sort(
      (a, b) => (a - preferred).abs().compareTo((b - preferred).abs()),
    );

    for (final y in candidates) {
      final laneFree = !_busLanes.entries.any(
        (e) =>
            e.key != laneKey &&
            _busCorridorOf[e.key] == corridorKey &&
            (e.value - y).abs() < step * laneOverlapFactor,
      );
      final a = Offset(minX, y);
      final b = Offset(maxX, y);
      final horizClear = segmentClear(a, b, obstacles: obs);
      // Lane ajratish asosiy; occupied — faqat route() fallbackda.
      if (laneFree && horizClear) {
        _busLanes[laneKey] = y;
        _busCorridorOf[laneKey] = corridorKey;
        return y;
      }
    }
    return null;
  }

  /// Oila uchun alohida vertikal o'zak X.
  double? allocateStemX({
    required Object laneId,
    required Object corridorId,
    required double preferred,
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    List<Rect>? obstacles,
    double? laneStep,
  }) {
    if (maxX < minX || maxY < minY) return null;
    final step = laneStep ?? this.laneStep;
    final obs = obstacles ?? this.obstacles;
    final corridorKey = corridorId.hashCode;
    final laneKey = Object.hash(identityHashCode(laneId), corridorKey);

    final existing = _stemLanes[laneKey];
    if (existing != null) return existing;

    final candidates = <double>[preferred];
    for (var x = minX; x <= maxX + 0.5; x += step) {
      candidates.add(x);
    }
    // preferred atrofida zichroq qidiruv
    for (var i = 1; i <= 8; i++) {
      candidates.add(preferred + i * step);
      candidates.add(preferred - i * step);
    }
    final uniq = <double>{};
    final ordered = <double>[];
    for (final x in candidates) {
      if (x < minX - 0.5 || x > maxX + 0.5) continue;
      if (uniq.add(x)) ordered.add(x);
    }
    ordered.sort(
      (a, b) => (a - preferred).abs().compareTo((b - preferred).abs()),
    );

    for (final x in ordered) {
      final laneFree = !_stemLanes.entries.any((e) {
        if (e.key == laneKey) return false;
        if ((e.value - x).abs() >= step * laneOverlapFactor) return false;
        final range = _stemYRangeOf[e.key];
        if (range == null) return false;
        // Y oralig'i ustma-ust bo'lsa bir xil X taqiqlanadi.
        return minY < range.$2 - 0.5 && range.$1 < maxY - 0.5;
      });
      final a = Offset(x, minY);
      final b = Offset(x, maxY);
      final vertClear = segmentClear(a, b, obstacles: obs);
      if (laneFree && vertClear) {
        _stemLanes[laneKey] = x;
        _stemYRangeOf[laneKey] = (minY, maxY);
        return x;
      }
    }
    return null;
  }
}

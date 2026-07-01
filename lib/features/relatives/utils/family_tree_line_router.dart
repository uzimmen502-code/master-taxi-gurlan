import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ramka ichidan o'tmaydigan orthogonal marshrut — visibility graph + BFS.
class FamilyTreeLineRouter {
  FamilyTreeLineRouter({
    required this.obstacles,
    required this.laneStep,
    required this.linePad,
  });

  final List<Rect> obstacles;
  final double laneStep;
  final double linePad;
  final Map<int, double> _colorLanes = {};
  final Map<int, int> _laneCorridorOf = {};

  static const int maxPathPoints = 21;

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

    return out;
  }

  List<Offset>? route(
    Offset a,
    Offset b, {
    List<Rect>? obstacles,
  }) {
    final obs = obstacles ?? this.obstacles;
    if (segmentClear(a, b, obstacles: obs)) return [a, b];

    final candidates = collectCandidates(a, b, obs);
    final visited = <String>{ptKey(a)};
    final queue = <List<Offset>>[
      [a],
    ];

    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      final cur = path.last;
      if ((cur.dx - b.dx).abs() < 0.5 && (cur.dy - b.dy).abs() < 0.5) {
        if (pathClear(path, obs)) return path;
        continue;
      }
      if (path.length >= maxPathPoints) continue;

      for (final next in candidates) {
        if (!axisAligned(cur, next)) continue;
        if (!segmentClear(cur, next, obstacles: obs)) continue;
        final k = ptKey(next);
        if (visited.contains(k)) continue;
        visited.add(k);
        queue.add([...path, next]);
      }
    }

    for (final start in candidates) {
      if ((start.dx - b.dx).abs() > 0.5 && (start.dy - b.dy).abs() > 0.5) {
        continue;
      }
      if (!segmentClear(start, b, obstacles: obs)) continue;
      final subVisited = <String>{ptKey(a)};
      final subQueue = <List<Offset>>[
        [a],
      ];
      while (subQueue.isNotEmpty) {
        final path = subQueue.removeAt(0);
        final cur = path.last;
        if ((cur.dx - start.dx).abs() < 0.5 &&
            (cur.dy - start.dy).abs() < 0.5) {
          final full = [...path, b];
          if (pathClear(full, obs)) return full;
          continue;
        }
        if (path.length >= maxPathPoints - 1) continue;
        for (final next in candidates) {
          if (!axisAligned(cur, next)) continue;
          if (!segmentClear(cur, next, obstacles: obs)) continue;
          final k = ptKey(next);
          if (subVisited.contains(k)) continue;
          subVisited.add(k);
          subQueue.add([...path, next]);
        }
      }
    }

    return null;
  }

  double? allocateBusY({
    required Color color,
    required double preferred,
    required double minY,
    required double maxY,
    required double minX,
    required double maxX,
    List<Rect>? obstacles,
  }) {
    if (maxY < minY) return null;
    final obs = obstacles ?? this.obstacles;
    // Bir xil koridorda turli ranglar alohida y; boshqa koridorlarda qayta ishlatiladi.
    final corridorKey = Object.hash(
      minY.round(),
      maxY.round(),
    );
    final laneKey = Object.hash(color.toARGB32(), corridorKey);
    var y = minY;
    while (y <= maxY + 0.5) {
      final laneFree = !_colorLanes.entries.any(
        (e) =>
            e.key != laneKey &&
            _laneCorridorOf[e.key] == corridorKey &&
            (e.value - y).abs() < laneStep * 0.9,
      );
      final horizClear = segmentClear(
        Offset(minX, y),
        Offset(maxX, y),
        obstacles: obs,
      );
      if (laneFree && horizClear) {
        _colorLanes[laneKey] = y;
        _laneCorridorOf[laneKey] = corridorKey;
        return y;
      }
      y += laneStep;
    }
    return null;
  }
}

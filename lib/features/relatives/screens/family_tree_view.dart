import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/relative_person.dart';
import '../utils/family_tree_line_router.dart';
import '../utils/family_tree_routing_report.dart';

/// 🌳 Nasab daraxti — yangi qoidalar (2025).
/// Er/xotin har doim yonma-yon; chiziqlar ramka atrofidan; turli rang bir qatorda emas.
class FamilyTreeView extends StatefulWidget {
  const FamilyTreeView({
    super.key,
    required this.people,
    this.onTap,
    this.immersive = false,
    this.onExitImmersive,
  });

  /// Widget testlari uchun oxirgi muvaffaqiyatli layout hisoboti.
  @visibleForTesting
  static FamilyTreeRoutingReport? debugRoutingReport;

  final List<RelativePerson> people;
  final void Function(RelativePerson person)? onTap;
  final bool immersive;
  final VoidCallback? onExitImmersive;

  @override
  State<FamilyTreeView> createState() => _FamilyTreeViewState();
}

class _FamilyTreeViewState extends State<FamilyTreeView>
    with TickerProviderStateMixin {
  static const _accent = Color(0xFF6A4C93);
  static const _minScale = 0.1;
  static const _maxScale = 4.0;

  static const int _familyPaletteCount = 10;
  static const _familyPalette = <Color>[
    Color(0xFF1565C0),
    Color(0xFFC62828),
    Color(0xFF2E7D32),
    Color(0xFFEF6C00),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFAD1457),
    Color(0xFF558B2F),
    Color(0xFF4527A0),
    Color(0xFF00695C),
  ];

  static const _lineWidth = 3.2;
  static const _outerFrameWidth = 2.4;
  static const _lineageTiers = 5;
  /// Ramka atrofidan xavfsiz masofa (chiziq markazi emas — chetidan).
  static const _linePad = 8.0;
  /// Turli ranglar uchun parallel gorizontal yo'lak qadami.
  static const _busLaneStep = 22.0;
  static const _sulolaMandarin = Color(0xFFFF9800);

  static const double _cardW = 120;
  static const double _cardH = 100;
  static const double _spouseGap = 0;
  static const double _siblingGap = 40;
  static const _rootGap = 64.0;
  /// Avlodlar orasidagi chiziq koridori (ko'p yo'lak sig'adi).
  static const _rowGap = 112.0;
  static const _maxLayoutAttempts = 30;
  static const _expandVerticalStep = 26.0;
  static const _expandHorizontalStep = 20.0;
  static const _expandRootStep = 28.0;
  static const double _familyPadTop = 8;
  static const double _familyPadSide = 8;
  static const double _familyPadBottom = 10;
  static const double _pad = 48;

  late Map<String, RelativePerson> _byId;
  late Map<String, int> _addOrder;
  final List<_FamilyNode> _families = [];
  final Map<String, _FamilyNode> _familyOf = {};
  final Map<String, Rect> _cardRect = {};
  final List<_LineSeg> _segments = [];
  final List<_OuterFrame> _outerFrames = [];
  final Map<String, Color> _inheritedColor = {};
  final Map<String, Color?> _ownFamilyColor = {};
  final Map<String, bool> _splitBorder = {};
  final Set<String> _sulolaHighlight = {};

  Size _contentSize = Size.zero;
  int _placed = 0;
  String _sig = '';
  int _colorSeq = 0;
  final Map<int, double> _gapBelowGen = {};
  final Map<int, double> _siblingGapAtGen = {};
  double _layoutRootGap = _rootGap;

  final _transform = TransformationController();
  late final AnimationController _fitAnim;
  late final AnimationController _pulseAnim;
  Animation<Matrix4>? _matrixAnim;

  Size _viewport = Size.zero;
  bool _didInitialFit = false;
  bool _isScaleGesture = false;

  @override
  void initState() {
    super.initState();
    _fitAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _transform.addListener(_onTransformChanged);
    _build();
    if (widget.immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit(padFactor: 0.88);
      });
    }
  }

  void _onTransformChanged() {
    if (_isScaleGesture) return;
    if (_fitAnim.isAnimating) _fitAnim.stop();
  }

  @override
  void didUpdateWidget(covariant FamilyTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newSig = _signatureOf(widget.people);
    if (newSig != _sig) {
      _build();
      _didInitialFit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
  }

  @override
  void dispose() {
    if (widget.immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _transform.removeListener(_onTransformChanged);
    _fitAnim.dispose();
    _pulseAnim.dispose();
    _transform.dispose();
    super.dispose();
  }

  String _signatureOf(List<RelativePerson> ps) {
    final b = StringBuffer();
    for (final p in ps) {
      b
        ..write(p.id)
        ..write('|')
        ..write(p.fatherId ?? '')
        ..write(',')
        ..write(p.motherId ?? '')
        ..write(',')
        ..write(p.spouseId ?? '')
        ..write(',')
        ..write(p.gender)
        ..write(',')
        ..write(p.fullName)
        ..write(',')
        ..write(p.birthDate?.millisecondsSinceEpoch ?? '')
        ..write(',')
        ..write(p.photoUrl)
        ..write(';');
    }
    return b.toString();
  }

  bool _has(String? id) => id != null && _byId.containsKey(id);

  bool _hasDirectParentLink(RelativePerson child, _FamilyNode parent) {
    return parent.members.any(
      (p) => p.id == child.fatherId || p.id == child.motherId,
    );
  }

  _FamilyNode? _resolveParentFamily(RelativePerson m) {
    if (_has(m.fatherId)) {
      final f = _familyOf[m.fatherId!];
      if (f != null) return f;
    }
    if (_has(m.motherId)) {
      return _familyOf[m.motherId!];
    }
    return null;
  }

  bool _hasParentInTree(RelativePerson p) {
    if (_has(p.fatherId) && _familyOf.containsKey(p.fatherId)) return true;
    if (_has(p.motherId) && _familyOf.containsKey(p.motherId)) return true;
    return false;
  }

  bool _hasLinkedChildren(_FamilyNode f) {
    for (final c in _byId.values) {
      if (_hasDirectParentLink(c, f)) return true;
    }
    return false;
  }

  List<RelativePerson> _directChildrenOf(_FamilyNode f) {
    final out = <RelativePerson>[];
    final seen = <String>{};
    for (final c in _byId.values) {
      if (!_hasDirectParentLink(c, f)) continue;
      if (seen.add(c.id)) out.add(c);
    }
    out.sort(_comparePeople);
    return out;
  }

  Color _nextFamilyColor() =>
      _familyPalette[_colorSeq++ % _familyPaletteCount];

  Color _inheritedFromParents(RelativePerson m) {
    if (_has(m.fatherId)) {
      final f = _familyOf[m.fatherId!];
      if (f?.familyColor != null) return f!.familyColor!;
    }
    if (_has(m.motherId)) {
      final f = _familyOf[m.motherId!];
      if (f?.familyColor != null) return f!.familyColor!;
    }
    return _accent;
  }

  int _birthOrder(RelativePerson? p) {
    if (p == null || p.birthDate == null) return 1 << 30;
    final d = p.birthDate!;
    return d.year * 10000 + d.month * 100 + d.day;
  }

  int _comparePeople(RelativePerson? a, RelativePerson? b) {
    final o = _birthOrder(a).compareTo(_birthOrder(b));
    if (o != 0) return o;
    return (_addOrder[a!.id] ?? 0).compareTo(_addOrder[b!.id] ?? 0);
  }

  static int _genderRank(String g) =>
      g == 'male' ? 0 : (g == 'female' ? 1 : 2);

  double _familyWidth(_FamilyNode f) =>
      f.isCouple ? _cardW * 2 + _spouseGap : _cardW;

  double _gapBelow(int gen) => _gapBelowGen.putIfAbsent(gen, () => _rowGap);

  double _siblingGapAt(int gen) =>
      _siblingGapAtGen.putIfAbsent(gen, () => _siblingGap);

  void _resetLayoutGaps() {
    _gapBelowGen.clear();
    _siblingGapAtGen.clear();
    _layoutRootGap = _rootGap;
  }

  void _expandVertical(int gen, {double? amount}) {
    _gapBelowGen[gen] = _gapBelow(gen) + (amount ?? _expandVerticalStep);
  }

  void _expandHorizontal(int gen, {double? amount}) {
    _siblingGapAtGen[gen] = _siblingGapAt(gen) + (amount ?? _expandHorizontalStep);
  }

  void _expandRoots({double? amount}) {
    _layoutRootGap += amount ?? _expandRootStep;
  }

  void _expandForHint(_ExpandHint hint) {
    if (hint.expandAll) {
      final gens = <int>{
        ..._gapBelowGen.keys,
        if (hint.verticalGen != null) hint.verticalGen!,
      };
      for (final g in gens) {
        _expandVertical(g, amount: _busLaneStep + 10);
      }
      final hGens = <int>{
        ..._siblingGapAtGen.keys,
        if (hint.horizontalGen != null) hint.horizontalGen!,
      };
      for (final g in hGens) {
        _expandHorizontal(g);
      }
      _expandRoots();
      return;
    }
    if (hint.verticalGen != null) _expandVertical(hint.verticalGen!);
    if (hint.horizontalGen != null) _expandHorizontal(hint.horizontalGen!);
  }

  void _resetFamilyLayout() {
    _cardRect.clear();
    _segments.clear();
    _outerFrames.clear();
    for (final f in _families) {
      f.centerX = 0;
      f.gen = 0;
      f.outerRect = null;
    }
  }

  /// Ramkalar ustma-ust tushsa, qaysi avlodda zich ekanini qaytaradi.
  int? _detectOverlapGen() {
    final entries = _cardRect.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final a = entries[i].value.deflate(2);
        final b = entries[j].value.deflate(2);
        if (a.width <= 0 || b.width <= 0) continue;
        if (!a.overlaps(b)) continue;
        final fa = _familyOf[entries[i].key];
        final fb = _familyOf[entries[j].key];
        if (fa != null && fb != null) {
          return math.max(fa.gen, fb.gen);
        }
      }
    }
    return null;
  }

  bool _segmentsClearInterior(Iterable<_LineSeg> segs) {
    final frames = <Rect>[
      ..._cardRect.values,
      for (final f in _families)
        if (f.outerRect != null) f.outerRect!,
    ];
    for (final s in segs) {
      for (final r in frames) {
        final inner = r.deflate(0.5);
        if (inner.width <= 0 || inner.height <= 0) continue;
        if (FamilyTreeLineRouter.segHitsRect(s.a, s.b, inner)) return false;
      }
    }
    return true;
  }

  double _rowHeightFor(_FamilyNode f) {
    final gap = _gapBelow(f.gen);
    if (f.isCouple) {
      return _cardH + _familyPadTop + _familyPadBottom + gap;
    }
    return _cardH + gap;
  }

  void _build() {
    _sig = _signatureOf(widget.people);
    _byId = {for (final p in widget.people) p.id: p};
    _addOrder = {
      for (var i = 0; i < widget.people.length; i++) widget.people[i].id: i,
    };
    _families.clear();
    _familyOf.clear();
    _cardRect.clear();
    _segments.clear();
    _outerFrames.clear();
    _inheritedColor.clear();
    _ownFamilyColor.clear();
    _splitBorder.clear();
    _colorSeq = 0;
    _contentSize = Size.zero;
    _placed = 0;

    final referenced = <String>{};
    for (final p in widget.people) {
      if (_has(p.fatherId)) referenced.add(p.fatherId!);
      if (_has(p.motherId)) referenced.add(p.motherId!);
      if (_has(p.spouseId)) referenced.add(p.spouseId!);
    }

    final relevant = <RelativePerson>[];
    for (final p in widget.people) {
      final linked =
          _has(p.fatherId) || _has(p.motherId) || _has(p.spouseId);
      if (linked || referenced.contains(p.id)) relevant.add(p);
    }
    if (relevant.isEmpty) return;

    final partner = <String, String>{};
    void pair(String a, String b) {
      if (a == b) return;
      if (partner.containsKey(a) || partner.containsKey(b)) return;
      partner[a] = b;
      partner[b] = a;
    }

    for (final p in relevant) {
      if (_has(p.spouseId)) pair(p.id, p.spouseId!);
    }
    for (final c in relevant) {
      if (_has(c.fatherId) && _has(c.motherId)) {
        pair(c.fatherId!, c.motherId!);
      }
    }

    final seen = <String>{};
    for (final p in relevant) {
      if (seen.contains(p.id)) continue;
      final pr = partner[p.id];
      final members = <RelativePerson>[p];
      seen.add(p.id);
      if (pr != null && !seen.contains(pr) && _byId.containsKey(pr)) {
        members.add(_byId[pr]!);
        seen.add(pr);
      }
      members.sort((a, b) => _genderRank(a.gender) - _genderRank(b.gender));
      final f = _FamilyNode(members);
      _families.add(f);
      for (final m in members) {
        _familyOf[m.id] = f;
      }
    }

    int parentScore(RelativePerson m) =>
        (_has(m.fatherId) ? 1 : 0) + (_has(m.motherId) ? 1 : 0);

    for (final f in _families) {
      RelativePerson? best;
      _FamilyNode? bestPf;
      var bestScore = -1;
      for (final m in f.members) {
        final pf = _resolveParentFamily(m);
        if (pf == null || identical(pf, f)) continue;
        if (!_hasDirectParentLink(m, pf)) continue;
        final sc = parentScore(m);
        if (sc > bestScore) {
          best = m;
          bestPf = pf;
          bestScore = sc;
        }
      }
      if (best != null && bestPf != null) {
        f.parent = bestPf;
        f.anchorId = best.id;
        bestPf.children.add(f);
      }
    }

    for (final f in _families) {
      f.children.sort((a, b) {
        final ap = _byId[a.anchorId ?? a.members.first.id];
        final bp = _byId[b.anchorId ?? b.members.first.id];
        return _comparePeople(ap, bp);
      });
    }

    _resetLayoutGaps();
    _assignColors();

    var routingOk = false;
    _ExpandHint? lastHint;
    for (var attempt = 0; attempt < _maxLayoutAttempts && !routingOk; attempt++) {
      _resetFamilyLayout();

    final placed = <_FamilyNode>{};
    final rowHeights = <int, double>{};

    void contour(_FamilyNode f, bool left, Map<int, double> out) {
      final half = _familyWidth(f) / 2;
      final edge = left ? f.centerX - half : f.centerX + half;
      final d = f.gen;
      final cur = out[d];
      if (cur == null) {
        out[d] = edge;
      } else {
        out[d] = left ? math.min(cur, edge) : math.max(cur, edge);
      }
      for (final c in f.children) {
        contour(c, left, out);
      }
    }

    void shift(_FamilyNode f, double dx) {
      f.centerX += dx;
      for (final c in f.children) {
        shift(c, dx);
      }
    }

    void layoutSub(_FamilyNode f, int depth) {
      if (!placed.add(f)) return;
      f.gen = depth;
      rowHeights[depth] = math.max(rowHeights[depth] ?? 0, _rowHeightFor(f));

      if (f.children.isEmpty) {
        f.centerX = _familyWidth(f) / 2;
        return;
      }
      final right = <int, double>{};
      for (final c in f.children) {
        layoutSub(c, depth + 1);
        final lc = <int, double>{};
        contour(c, true, lc);
        var need = 0.0;
        lc.forEach((d, leftEdge) {
          final rc = right[d];
          if (rc != null) {
            final s = rc + _siblingGapAt(d) - leftEdge;
            if (s > need) need = s;
          }
        });
        if (need > 0) shift(c, need);
        final rcm = <int, double>{};
        contour(c, false, rcm);
        rcm.forEach((d, e) {
          final cur = right[d];
          right[d] = (cur == null) ? e : math.max(cur, e);
        });
      }
      f.centerX =
          (f.children.first.centerX + f.children.last.centerX) / 2;
    }

    final roots = _families.where((f) => f.parent == null).toList()
      ..sort((a, b) => _comparePeople(a.members.first, b.members.first));

    final rootBlock = <int, double>{};
    for (final r in roots) {
      layoutSub(r, 0);
      final lc = <int, double>{};
      contour(r, true, lc);
      var need = 0.0;
      lc.forEach((d, leftEdge) {
        final rc = rootBlock[d];
        if (rc != null) {
          final s = rc + _layoutRootGap - leftEdge;
          if (s > need) need = s;
        }
      });
      if (need > 0) shift(r, need);
      final rcm = <int, double>{};
      contour(r, false, rcm);
      rcm.forEach((d, e) {
        final cur = rootBlock[d];
        rootBlock[d] = (cur == null) ? e : math.max(cur, e);
      });
    }
    for (final f in _families) {
      if (placed.contains(f)) continue;
      layoutSub(f, 0);
    }

    double yForGen(int gen) {
      var y = 0.0;
      for (var g = 0; g < gen; g++) {
        y += rowHeights[g] ?? (_cardH + _gapBelow(g));
      }
      return y;
    }

    var minLeft = double.infinity;
    var maxRight = -double.infinity;
    var maxBottom = -double.infinity;

    for (final f in _families) {
      final topY = yForGen(f.gen);
      final cardTop = f.isCouple ? topY + _familyPadTop : topY;
      final positions = _memberLefts(f);

      for (var i = 0; i < f.members.length; i++) {
        final left = positions[i];
        final r = Rect.fromLTWH(left, cardTop, _cardW, _cardH);
        _cardRect[f.members[i].id] = r;
        minLeft = math.min(minLeft, r.left);
        maxRight = math.max(maxRight, r.right);
        maxBottom = math.max(maxBottom, r.bottom);
      }

      if (f.isCouple) {
        final left = _cardRect[f.members[0].id]!;
        final right = _cardRect[f.members[1].id]!;
        final outer = Rect.fromLTRB(
          left.left - _familyPadSide,
          topY,
          right.right + _familyPadSide,
          left.bottom + _familyPadBottom,
        );
        f.outerRect = outer;
        minLeft = math.min(minLeft, outer.left);
        maxRight = math.max(maxRight, outer.right);
        maxBottom = math.max(maxBottom, outer.bottom);
      }
    }

    if (!minLeft.isFinite) return;

    final overlapGen = _detectOverlapGen();
    if (overlapGen != null) {
      _expandHorizontal(overlapGen);
      lastHint = _ExpandHint(horizontalGen: overlapGen);
      continue;
    }

    const offY = _pad;
    final offX = _pad - minLeft;
    for (final id in _cardRect.keys.toList()) {
      _cardRect[id] = _cardRect[id]!.translate(offX, offY);
    }
    for (final f in _families) {
      f.centerX += offX;
      if (f.outerRect != null) {
        f.outerRect = f.outerRect!.translate(offX, offY);
      }
    }

    _contentSize = Size(
      maxRight - minLeft + 2 * _pad,
      maxBottom + 2 * _pad,
    );
    _placed = _cardRect.length;

    final lineResult = _buildLines();
    routingOk = lineResult.ok;
    lastHint = lineResult.hint ?? lastHint;
    if (routingOk || attempt == _maxLayoutAttempts - 1) {
      FamilyTreeView.debugRoutingReport = FamilyTreeRoutingReport(
        routingSucceeded: routingOk,
        segments: [
          for (final s in _segments) (a: s.a, b: s.b),
        ],
        cardRects: _cardRect.values.toList(),
        outerFrames: [
          for (final f in _families)
            if (f.outerRect != null) f.outerRect!,
        ],
        layoutRowGap: _gapBelowGen.values.fold(
          _rowGap,
          (a, b) => math.max(a, b),
        ),
        layoutSiblingGap: _siblingGapAtGen.values.fold(
          _siblingGap,
          (a, b) => math.max(a, b),
        ),
        linePad: _linePad,
        lineWidth: _lineWidth,
      );
    }
    if (!routingOk) {
      _expandForHint(lastHint ?? const _ExpandHint(expandAll: true));
    }
    } // layout retry
  }

  List<double> _memberLefts(_FamilyNode f) {
    if (f.isCouple) {
      final leftLeft = f.centerX - _cardW - _spouseGap / 2;
      final rightLeft = f.centerX + _spouseGap / 2;
      return [leftLeft, rightLeft];
    }
    return [f.centerX - _cardW / 2];
  }

  void _assignColors() {
    final ordered = [..._families]
      ..sort((a, b) {
        final g = a.gen.compareTo(b.gen);
        if (g != 0) return g;
        return a.centerX.compareTo(b.centerX);
      });

    for (final f in ordered) {
      if (!_hasLinkedChildren(f)) continue;
      f.familyColor = _nextFamilyColor();
      final own = f.familyColor!;

      for (final m in f.members) {
        final isRoot = !_hasParentInTree(m);
        if (isRoot) {
          _inheritedColor[m.id] = own;
          _ownFamilyColor[m.id] = null;
          _splitBorder[m.id] = false;
        } else {
          _inheritedColor[m.id] = _inheritedFromParents(m);
          _ownFamilyColor[m.id] = own;
          _splitBorder[m.id] = true;
        }
      }
    }

    for (final f in ordered) {
      if (f.familyColor != null) continue;
      if (!f.isCouple) continue;
      if (!f.members.any((m) => !_hasParentInTree(m))) {
        f.familyColor = _nextFamilyColor();
        final c = f.familyColor!;
        for (final m in f.members) {
          _inheritedColor[m.id] = c;
          _ownFamilyColor[m.id] = null;
          _splitBorder[m.id] = false;
        }
      }
    }

    for (final f in ordered) {
      if (f.familyColor != null) continue;
      for (final m in f.members) {
        _inheritedColor.putIfAbsent(m.id, () => _inheritedFromParents(m));
        _ownFamilyColor.putIfAbsent(m.id, () => null);
        _splitBorder.putIfAbsent(m.id, () => false);
      }
    }
  }

  _LineBuildResult _buildLines() {
    final usedKeys = <String>{};
    final allObstacles = _lineObstacles();
    final router = FamilyTreeLineRouter(
      obstacles: allObstacles,
      laneStep: _busLaneStep,
      linePad: _linePad,
    );
    var ok = true;
    _ExpandHint? hint;

    void markFail(_ExpandHint h) {
      ok = false;
      hint ??= h;
    }

    void addSeg(Offset a, Offset b, Color color, double width) {
      final key =
          '${a.dx.toStringAsFixed(1)},${a.dy.toStringAsFixed(1)}-'
          '${b.dx.toStringAsFixed(1)},${b.dy.toStringAsFixed(1)}';
      if (usedKeys.contains(key)) return;
      usedKeys.add(key);
      _segments.add(_LineSeg(a, b, color, width));
    }

    bool drawRouted(
      Offset a,
      Offset b,
      Color color,
      List<Rect> obstacles,
      int parentGen,
    ) {
      final path = router.route(a, b, obstacles: obstacles);
      if (path == null) {
        markFail(_ExpandHint(
          verticalGen: parentGen,
          horizontalGen: parentGen + 1,
        ));
        return false;
      }
      for (var i = 0; i < path.length - 1; i++) {
        if (!router.segmentClear(path[i], path[i + 1], obstacles: obstacles)) {
          markFail(_ExpandHint(
            verticalGen: parentGen,
            horizontalGen: parentGen + 1,
          ));
          return false;
        }
        addSeg(path[i], path[i + 1], color, _lineWidth);
      }
      return true;
    }

    bool drawTopConnector(
      double cx,
      double top,
      Color color, {
      Set<String> excludePersonIds = const {},
    }) {
      final side = math.min(_cardW * 0.2, 12.0);
      final left = Offset(cx - side, top);
      final right = Offset(cx + side, top);
      final obs = _lineObstacles(excludePersonIds: excludePersonIds);
      if (!router.segmentClear(left, right, obstacles: obs)) {
        markFail(_ExpandHint(horizontalGen: _familyGenForPerson(excludePersonIds)));
        return false;
      }
      addSeg(left, right, color, _lineWidth);
      return true;
    }

    bool drawChildBus(
      double exitX,
      double exitY,
      List<({Rect bounds, Offset topCenter, _FamilyNode fam})> targets,
      Color color,
      Set<String> excludePersonIds,
      int parentGen,
    ) {
      if (targets.isEmpty) return true;

      final parentObs = _lineObstacles(excludePersonIds: excludePersonIds);
      final busObs = parentObs;
      final ceiling = _childConnectorCeiling(targets.map((t) => t.bounds));
      final floor = exitY + _linePad;

      var minX = exitX;
      var maxX = exitX;
      for (final t in targets) {
        minX = math.min(minX, t.topCenter.dx);
        maxX = math.max(maxX, t.topCenter.dx);
      }

      if (ceiling <= floor + _busLaneStep) {
        markFail(_ExpandHint(verticalGen: parentGen));
        return false;
      }

      final preferredBusY = exitY + (ceiling - exitY) * 0.42;
      final busY = router.allocateBusY(
        color: color,
        preferred: preferredBusY,
        minY: floor,
        maxY: ceiling - _linePad,
        minX: minX,
        maxX: maxX,
        obstacles: busObs,
      );
      if (busY == null) {
        markFail(_ExpandHint(
          verticalGen: parentGen,
          horizontalGen: parentGen + 1,
        ));
        return false;
      }

      if (!drawRouted(
        Offset(exitX, exitY),
        Offset(exitX, busY),
        color,
        parentObs,
        parentGen,
      )) {
        return false;
      }

      if ((maxX - minX).abs() > 0.5) {
        if (!drawRouted(
          Offset(minX, busY),
          Offset(maxX, busY),
          color,
          busObs,
          parentGen,
        )) {
          return false;
        }
      }

      for (final t in targets) {
        final childExclude = {
          ...excludePersonIds,
          ...t.fam.members.map((m) => m.id),
        };
        final childObs = _lineObstacles(excludePersonIds: childExclude);

        if (!drawRouted(
          Offset(t.topCenter.dx, busY),
          t.topCenter,
          color,
          childObs,
          parentGen,
        )) {
          return false;
        }
        if (!drawTopConnector(
          t.topCenter.dx,
          t.topCenter.dy,
          color,
          excludePersonIds: childExclude,
        )) {
          markFail(_ExpandHint(horizontalGen: t.fam.gen));
          return false;
        }
      }
      return true;
    }

    final pendingFrames = <_OuterFrame>[];

    for (final f in _families) {
      final color = f.familyColor ?? _accent;

      if (f.isCouple && f.outerRect != null) {
        pendingFrames.add(_OuterFrame(f.outerRect!, color));
      }

      if (!_hasLinkedChildren(f)) continue;

      final linked = _directChildrenOf(f);
      if (linked.isEmpty) continue;

      final parentIds = {for (final m in f.members) m.id};

      if (f.isCouple) {
        RelativePerson? father;
        RelativePerson? mother;
        for (final m in f.members) {
          if (m.gender == 'male') {
            father = m;
          } else if (m.gender == 'female') {
            mother = m;
          }
        }
        father ??= f.members[0];
        mother ??= f.members.length > 1 ? f.members[1] : null;

        final bothLinked = <RelativePerson>[];
        final fatherOnlyLinked = <RelativePerson>[];
        final motherOnlyLinked = <RelativePerson>[];

        for (final m in linked) {
          final hasF = m.fatherId == father.id;
          final hasM = mother != null && m.motherId == mother.id;
          if (hasF && hasM) {
            bothLinked.add(m);
          } else if (hasF) {
            fatherOnlyLinked.add(m);
          } else if (hasM) {
            motherOnlyLinked.add(m);
          }
        }

        if (bothLinked.isNotEmpty && f.outerRect != null) {
          if (!drawChildBus(
            f.outerRect!.center.dx,
            f.outerRect!.bottom,
            _childConnectorTargets(bothLinked),
            color,
            parentIds,
            f.gen,
          )) {
            _segments.clear();
            return _LineBuildResult(ok: false, hint: hint);
          }
        }
        if (fatherOnlyLinked.isNotEmpty) {
          final card = _cardRect[father.id]!;
          if (!drawChildBus(
            card.center.dx,
            card.bottom,
            _childConnectorTargets(fatherOnlyLinked),
            color,
            parentIds,
            f.gen,
          )) {
            _segments.clear();
            return _LineBuildResult(ok: false, hint: hint);
          }
        }
        if (mother != null && motherOnlyLinked.isNotEmpty) {
          final card = _cardRect[mother.id]!;
          if (!drawChildBus(
            card.center.dx,
            card.bottom,
            _childConnectorTargets(motherOnlyLinked),
            color,
            parentIds,
            f.gen,
          )) {
            _segments.clear();
            return _LineBuildResult(ok: false, hint: hint);
          }
        }
      } else {
        final card = _cardRect[f.members.first.id]!;
        if (!drawChildBus(
          card.center.dx,
          card.bottom,
          _childConnectorTargets(linked),
          color,
          parentIds,
          f.gen,
        )) {
          _segments.clear();
          return _LineBuildResult(ok: false, hint: hint);
        }
      }
    }

    _outerFrames.addAll(pendingFrames);
    if (ok && !_segmentsClearInterior(_segments)) {
      _segments.clear();
      return const _LineBuildResult(
        ok: false,
        hint: _ExpandHint(expandAll: true),
      );
    }
    return _LineBuildResult(ok: ok, hint: hint);
  }

  int? _familyGenForPerson(Set<String> personIds) {
    for (final id in personIds) {
      final fam = _familyOf[id];
      if (fam != null) return fam.gen;
    }
    return null;
  }

  double _childConnectorCeiling(Iterable<Rect> childBounds) {
    var ceiling = double.infinity;
    for (final r in childBounds) {
      ceiling = math.min(ceiling, r.top - _linePad - _lineWidth / 2);
    }
    return ceiling;
  }

  /// Har bir farzand oilasi uchun bitta ulagich (juftlik = tashqi ramka markazi).
  List<({Rect bounds, Offset topCenter, _FamilyNode fam})>
      _childConnectorTargets(
    List<RelativePerson> linked,
  ) {
    final seen = <_FamilyNode>{};
    final out = <({Rect bounds, Offset topCenter, _FamilyNode fam})>[];
    for (final m in linked) {
      final fam = _familyOf[m.id];
      if (fam == null || !seen.add(fam)) continue;
      if (fam.isCouple) {
        final outer = fam.outerRect;
        if (outer == null) continue;
        out.add((
          bounds: outer,
          topCenter: Offset(outer.center.dx, outer.top),
          fam: fam,
        ));
      } else {
        final r = _cardRect[m.id];
        if (r == null) continue;
        out.add((
          bounds: r,
          topCenter: Offset(r.center.dx, r.top),
          fam: fam,
        ));
      }
    }
    return out;
  }

  List<Rect> _lineObstacles({Set<String> excludePersonIds = const {}}) {
    final pad = _lineWidth / 2 + _linePad;
    final out = <Rect>[];
    for (final e in _cardRect.entries) {
      if (excludePersonIds.contains(e.key)) continue;
      out.add(e.value.inflate(pad));
    }
    for (final f in _families) {
      final outer = f.outerRect;
      if (outer == null) continue;
      if (f.members.every((m) => excludePersonIds.contains(m.id))) continue;
      out.add(outer.inflate(pad));
    }
    return out;
  }

  Set<String> _collectLineage(String anchorId) {
    final result = <String>{anchorId};
    final fam = _familyOf[anchorId];
    if (fam != null) {
      result.addAll(fam.members.map((m) => m.id));
    }

    var up = <String>{anchorId};
    for (var tier = 0; tier < _lineageTiers && up.isNotEmpty; tier++) {
      final next = <String>{};
      for (final id in up) {
        final p = _byId[id];
        if (p == null) continue;
        for (final pid in [p.fatherId, p.motherId]) {
          if (!_has(pid) || !result.add(pid!)) continue;
          next.add(pid);
        }
      }
      up = next;
    }

    var down = <String>{anchorId};
    for (var tier = 0; tier < _lineageTiers && down.isNotEmpty; tier++) {
      final next = <String>{};
      for (final id in down) {
        for (final child in _byId.values) {
          if (child.fatherId != id && child.motherId != id) continue;
          if (!result.add(child.id)) continue;
          next.add(child.id);
          final cf = _familyOf[child.id];
          if (cf != null) {
            result.addAll(cf.members.map((m) => m.id));
          }
        }
      }
      down = next;
    }

    return result;
  }

  void _highlightLineage(RelativePerson p) {
    final ids = _collectLineage(p.id);
    setState(() => _sulolaHighlight
      ..clear()
      ..addAll(ids));
    _pulseAnim
      ..stop()
      ..reset()
      ..repeat();
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      _pulseAnim.stop();
      setState(() => _sulolaHighlight.clear());
    });
  }

  double _pulseOpacity() {
    if (!_pulseAnim.isAnimating) return 0;
    final t = _pulseAnim.value * 2 * math.pi;
    return 0.14 + 0.30 * (0.5 + 0.5 * math.sin(t));
  }

  void _animateTo(Matrix4 target) {
    _matrixAnim = Matrix4Tween(begin: _transform.value, end: target)
        .animate(CurvedAnimation(parent: _fitAnim, curve: Curves.easeOutCubic));
    void tick() {
      _transform.value = _matrixAnim!.value;
      if (!_fitAnim.isAnimating) _matrixAnim?.removeListener(tick);
    }

    _matrixAnim!.addListener(tick);
    _fitAnim
      ..reset()
      ..forward();
  }

  double get _scale => _transform.value.getMaxScaleOnAxis();

  void _zoomAround(Offset focal, double targetScale) {
    final clamped = targetScale.clamp(_minScale, _maxScale);
    final scenePt = _transform.toScene(focal);
    final tx = focal.dx - scenePt.dx * clamped;
    final ty = focal.dy - scenePt.dy * clamped;
    final m = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(clamped, clamped, 1, 1);
    _animateTo(m);
  }

  void _onBackgroundDoubleTap() {
    if (widget.immersive) {
      widget.onExitImmersive?.call();
      return;
    }
    _openImmersive();
  }

  void _openImmersive() {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, _, __) => FamilyTreeView(
          people: widget.people,
          onTap: widget.onTap,
          immersive: true,
          onExitImmersive: () => Navigator.of(ctx).pop(),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _fit({double padFactor = 0.9}) {
    if (_viewport.isEmpty || _contentSize.isEmpty) return;
    final scale = (math.min(
              _viewport.width / _contentSize.width,
              _viewport.height / _contentSize.height,
            ) *
            padFactor)
        .clamp(_minScale, _maxScale);
    final tx = (_viewport.width - _contentSize.width * scale) / 2;
    final ty = (_viewport.height - _contentSize.height * scale) / 2;
    final m = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    _didInitialFit = true;
    _animateTo(m);
  }

  Widget _buildCanvas() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => child!,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final delta = event.scrollDelta.dy;
            if (delta == 0) return;
            _zoomAround(event.localPosition, _scale * math.exp(-delta * 0.002));
          }
        },
        child: InteractiveViewer(
          transformationController: _transform,
          clipBehavior: Clip.none,
          constrained: false,
          panEnabled: true,
          scaleEnabled: true,
          minScale: _minScale,
          maxScale: _maxScale,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          interactionEndFrictionCoefficient: 0.000009,
          scaleFactor: 240,
          onInteractionStart: (_) => _isScaleGesture = true,
          onInteractionEnd: (_) => _isScaleGesture = false,
          child: RepaintBoundary(
            child: SizedBox(
              width: _contentSize.width,
              height: _contentSize.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: _onBackgroundDoubleTap,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TreeLinesPainter(
                        _segments,
                        _outerFrames,
                        _sig.hashCode,
                      ),
                    ),
                  ),
                  for (final f in _families)
                    if (f.isCouple) ..._heartsFor(f),
                  for (final entry in _cardRect.entries)
                    Positioned(
                      left: entry.value.left,
                      top: entry.value.top,
                      width: _cardW,
                      height: _cardH,
                      child: _personCard(_byId[entry.key]!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _heartsFor(_FamilyNode f) {
    if (f.members.length != 2) return const [];
    final left = _cardRect[f.members[0].id];
    final right = _cardRect[f.members[1].id];
    if (left == null || right == null) return const [];
    const heartW = 30.0;
    final seam = (left.right + right.left) / 2;
    return [
      Positioned(
        left: seam - heartW / 2,
        top: left.top + _cardH / 2 - 11,
        width: heartW,
        height: 22,
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('❤', style: TextStyle(fontSize: 15, color: Colors.red)),
              SizedBox(width: 2),
              Text('❤', style: TextStyle(fontSize: 15, color: Colors.red)),
            ],
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_placed == 0) {
      return _hint();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = widget.immersive
            ? MediaQuery.sizeOf(context)
            : Size(constraints.maxWidth, constraints.maxHeight);
        if (!_didInitialFit && !widget.immersive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_didInitialFit) _fit();
          });
        }
        final canvas = _buildCanvas();
        if (widget.immersive) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F4F8),
            body: SafeArea(child: canvas),
          );
        }
        return Container(
          color: const Color(0xFFF5F4F8),
          child: canvas,
        );
      },
    );
  }

  Widget _personCard(RelativePerson p) {
    final inherited = _inheritedColor[p.id] ?? _accent;
    final own = _ownFamilyColor[p.id];
    final split = _splitBorder[p.id] == true && own != null;
    final bottom = split ? own : inherited;
    final highlight = _sulolaHighlight.contains(p.id);
    final pulse = highlight ? _pulseOpacity() : 0.0;
    const borderW = 2.0;
    const radius = 12.0;

    return GestureDetector(
      onTap: widget.onTap == null ? null : () => widget.onTap!(p),
      onDoubleTap: () => _highlightLineage(p),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _CardBorderPainter(
              inheritedColor: inherited.withValues(alpha: 0.9),
              bottomColor: bottom.withValues(alpha: 0.9),
              splitBottom: split,
              radius: radius,
              strokeWidth: borderW,
            ),
          ),
          if (pulse > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: ColoredBox(
                  color: _sulolaMandarin.withValues(alpha: pulse)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: inherited.withValues(alpha: 0.12),
                  backgroundImage:
                      p.photoUrl.isNotEmpty ? NetworkImage(p.photoUrl) : null,
                  child: p.photoUrl.isEmpty
                      ? Text(
                          p.fullName.isNotEmpty
                              ? p.fullName.characters.first.toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: inherited,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    p.fullName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                ),
                if (p.relationDegree.isNotEmpty)
                  Text(
                    p.relationDegree,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 9, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌳', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'Дарахт бўш.\nҚариндошни таҳрирлаб «Отаси» ёки «Онаси»ни '
              'белгиланг.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyNode {
  _FamilyNode(this.members);

  final List<RelativePerson> members;
  final List<_FamilyNode> children = [];
  _FamilyNode? parent;
  String? anchorId;
  int gen = 0;
  double centerX = 0;
  Color? familyColor;
  Rect? outerRect;

  bool get isCouple => members.length == 2;
}

/// Layout kengaytirish yo'nalishi (routing/layout muvaffaqiyatsiz bo'lsa).
class _ExpandHint {
  const _ExpandHint({
    this.verticalGen,
    this.horizontalGen,
    this.expandAll = false,
  });

  final int? verticalGen;
  final int? horizontalGen;
  final bool expandAll;
}

class _LineBuildResult {
  const _LineBuildResult({required this.ok, this.hint});

  final bool ok;
  final _ExpandHint? hint;
}

class _LineSeg {
  const _LineSeg(this.a, this.b, this.color, this.width);
  final Offset a;
  final Offset b;
  final Color color;
  final double width;
}

class _OuterFrame {
  const _OuterFrame(this.rect, this.color);
  final Rect rect;
  final Color color;
}

class _TreeLinesPainter extends CustomPainter {
  _TreeLinesPainter(this.segments, this.frames, this.revision);

  final List<_LineSeg> segments;
  final List<_OuterFrame> frames;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    // Chiziqlar avval — boshqa oila ramkalari ustidan ko'rinmasin.
    for (final s in segments) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(s.a, s.b, paint);
    }
    for (final f in frames) {
      final paint = Paint()
        ..color = f.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _FamilyTreeViewState._outerFrameWidth;
      canvas.drawRRect(
        RRect.fromRectAndRadius(f.rect, const Radius.circular(14)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TreeLinesPainter old) =>
      old.revision != revision;
}

class _CardBorderPainter extends CustomPainter {
  _CardBorderPainter({
    required this.inheritedColor,
    required this.bottomColor,
    required this.splitBottom,
    required this.radius,
    required this.strokeWidth,
  });

  final Color inheritedColor;
  final Color bottomColor;
  final bool splitBottom;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final half = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      half,
      half,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    if (!splitBottom) {
      final paint = Paint()
        ..color = inheritedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
      return;
    }

    final topPaint = Paint()
      ..color = inheritedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final bottomPaint = Paint()
      ..color = bottomColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final tl = Offset(rect.left + radius, rect.top);
    final tr = Offset(rect.right - radius, rect.top);

    canvas.drawLine(tl, tr, topPaint);
    canvas.drawLine(Offset(rect.left, rect.top + radius),
        Offset(rect.left, rect.bottom - radius), topPaint);
    canvas.drawLine(Offset(rect.right, rect.top + radius),
        Offset(rect.right, rect.bottom - radius), topPaint);
    canvas.drawLine(
      Offset(rect.left + radius, rect.bottom),
      Offset(rect.right - radius, rect.bottom),
      bottomPaint,
    );

    canvas.drawArc(
      Rect.fromLTWH(rect.left, rect.top, radius * 2, radius * 2),
      math.pi,
      math.pi / 2,
      false,
      topPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(rect.right - radius * 2, rect.top, radius * 2, radius * 2),
      -math.pi / 2,
      math.pi / 2,
      false,
      topPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
          rect.right - radius * 2, rect.bottom - radius * 2, radius * 2, radius * 2),
      0,
      math.pi / 2,
      false,
      bottomPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
          rect.left, rect.bottom - radius * 2, radius * 2, radius * 2),
      math.pi / 2,
      math.pi / 2,
      false,
      bottomPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CardBorderPainter old) =>
      old.inheritedColor != inheritedColor ||
      old.bottomColor != bottomColor ||
      old.splitBottom != splitBottom;
}

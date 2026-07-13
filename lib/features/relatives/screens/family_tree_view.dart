import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/relative_person.dart';
import '../utils/family_tree_corridor_validation.dart';
import '../utils/family_tree_line_router.dart';
import '../utils/family_tree_routing_report.dart';

/// 🌳 Nasab daraxti — koridor qatlami + slot layout.
/// Qoidalar: farzand doim pastda; nikoh ramkasi belgisi; chiziq odam kartasi ichidan o'tmaydi (BFS).
class FamilyTreeView extends StatefulWidget {
  const FamilyTreeView({
    super.key,
    required this.people,
    this.onTap,
    this.immersive = false,
    this.onExitImmersive,
    this.exportCaptureKey,
  });

  /// Widget testlari uchun oxirgi muvaffaqiyatli layout hisoboti.
  @visibleForTesting
  static FamilyTreeRoutingReport? debugRoutingReport;

  final List<RelativePerson> people;
  final void Function(RelativePerson person)? onTap;
  final bool immersive;
  final VoidCallback? onExitImmersive;

  /// PNG/PDF export uchun daraxt kanvasi.
  final GlobalKey? exportCaptureKey;

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
  static const _lineageTiers = 5;
  /// Koridor yo'lak qadami (har bolali oila = 1 lane).
  static const _laneStep = 22.0;
  static const _corridorBasePad = 16.0;
  static const _sulolaMandarin = Color(0xFFFF9800);

  /// Ramka atrofidan xavfsiz masofa — chiziq qalinligidan kelib chiqadi.
  double get _linePad => _lineWidth / 2 + 6;

  static const double _cardW = 120;
  static const double _cardH = 100;
  static const double _spouseGap = 0;
  static const double _siblingGap = 40;
  static const _rootGap = 64.0;
  /// Эр/хотин ташқи рамкаси олиб ташланган — пад энди 0.
  static const double _familyPadTop = 0;
  static const double _familyPadSide = 0;
  static const double _familyPadBottom = 0;
  static const double _pad = 48;

  late Map<String, RelativePerson> _byId;
  late Map<String, int> _addOrder;
  final List<_FamilyNode> _families = [];
  final Map<String, _FamilyNode> _familyOf = {};
  final Map<String, Rect> _cardRect = {};
  final List<_LineSeg> _segments = [];
  final Map<String, Color> _inheritedColor = {};
  final Map<String, Color?> _ownFamilyColor = {};
  final Map<String, bool> _splitBorder = {};
  final Set<String> _sulolaHighlight = {};

  Size _contentSize = Size.zero;
  int _placed = 0;
  bool _routingIncomplete = false;
  String _sig = '';
  int _colorSeq = 0;
  final Map<int, double> _siblingGapAtGen = {};
  final Map<int, double> _corridorExtraAtGen = {};
  double _layoutRootGap = _rootGap;
  int _maxGen = 0;

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

  double _siblingGapAt(int gen) =>
      _siblingGapAtGen.putIfAbsent(gen, () => _siblingGap);

  double _cardRowHeight(_FamilyNode f) {
    if (f.isCouple) {
      return _cardH + _familyPadTop + _familyPadBottom;
    }
    return _cardH;
  }

  double _maxCardRowHeightAtGen(int gen) {
    var h = 0.0;
    for (final f in _families) {
      if (f.gen == gen) h = math.max(h, _cardRowHeight(f));
    }
    return h;
  }

  int _laneCountAtGen(int gen) {
    var count = 0;
    for (final f in _families) {
      if (f.gen == gen && _hasLinkedChildren(f)) count++;
    }
    return count;
  }

  /// Koridor balandligi: L(g) × laneStep + padding (karta qatoridan keyin).
  double _corridorHeightAtGen(int gen) {
    final lanes = _laneCountAtGen(gen);
    if (lanes == 0) return 0;
    return lanes * _laneStep +
        2 * _linePad +
        _corridorBasePad +
        (_corridorExtraAtGen[gen] ?? 0);
  }

  double _yForCardRow(int gen) {
    var y = 0.0;
    for (var g = 0; g < gen; g++) {
      final h = _maxCardRowHeightAtGen(g);
      if (h == 0) continue;
      y += h + _corridorHeightAtGen(g);
    }
    return y;
  }

  void _resetLayoutGaps() {
    _siblingGapAtGen.clear();
    _corridorExtraAtGen.clear();
    _layoutRootGap = _rootGap;
  }

  void _expandCorridor(int gen, {double? amount}) {
    _corridorExtraAtGen[gen] =
        (_corridorExtraAtGen[gen] ?? 0) + (amount ?? _laneStep);
  }

  void _expandHorizontal(int gen, {double? amount}) {
    _siblingGapAtGen[gen] =
        _siblingGapAt(gen) + (amount ?? _siblingGapAt(gen) * 0.5);
  }

  void _resetFamilyLayout() {
    _cardRect.clear();
    _segments.clear();
    for (final f in _families) {
      f.centerX = 0;
      f.outerRect = null;
    }
  }

  /// Har bir odam uchun gen: ota/ona bo'lsa gen = max(ota.gen)+1.
  /// Aylana bog'lanish (A.fatherId=B, B.fatherId=A) DFS bilan aniqlanib,
  /// tsikl qirralari o'tkazib yuboriladi.
  void _assignGenerationsFromPersonLinks() {
    final g = <String, int>{for (final id in _byId.keys) id: 0};
    _maxGen = 0;

    // Aylana bog'lanishlarni aniqlash: child→parent grafda DFS rang usuli.
    final cycleEdges = <String, Set<String>>{};
    const white = 0, gray = 1, black = 2;
    final color = <String, int>{for (final id in _byId.keys) id: white};

    void dfs(String id) {
      color[id] = gray;
      final p = _byId[id]!;
      for (final parentId in [p.fatherId, p.motherId]) {
        if (parentId == null || !_byId.containsKey(parentId)) continue;
        if (color[parentId] == gray) {
          cycleEdges.putIfAbsent(id, () => <String>{}).add(parentId);
        } else if (color[parentId] == white) {
          dfs(parentId);
        }
      }
      color[id] = black;
    }

    for (final id in _byId.keys) {
      if (color[id] == white) dfs(id);
    }

    var changed = true;
    for (var pass = 0; pass < _byId.length + 2 && changed; pass++) {
      changed = false;
      for (final p in _byId.values) {
        var need = g[p.id]!;
        final skip = cycleEdges[p.id];
        if (_has(p.fatherId) && !(skip?.contains(p.fatherId!) ?? false)) {
          need = math.max(need, g[p.fatherId!]! + 1);
        }
        if (_has(p.motherId) && !(skip?.contains(p.motherId!) ?? false)) {
          need = math.max(need, g[p.motherId!]! + 1);
        }
        if (need > g[p.id]!) {
          g[p.id] = need;
          changed = true;
        }
      }
    }
    for (final f in _families) {
      f.gen = f.members.map((m) => g[m.id]!).fold(0, math.max);
      _maxGen = math.max(_maxGen, f.gen);
    }
    _compactGenerations();
  }

  /// Avlodlar orasidagi bo'sh joylarni olib tashlab, zich diapazon qiladi.
  void _compactGenerations() {
    final usedGens = <int>{};
    for (final f in _families) {
      usedGens.add(f.gen);
    }
    if (usedGens.isEmpty) return;
    final sorted = usedGens.toList()..sort();
    final remap = <int, int>{};
    for (var i = 0; i < sorted.length; i++) {
      remap[sorted[i]] = i;
    }
    for (final f in _families) {
      f.gen = remap[f.gen]!;
    }
    _maxGen = sorted.length - 1;
  }

  /// Oilalar daraxtini shaxsiy ota-ona bog'lanishidan qayta qurish.
  ///
  /// Intentional: each family is linked to a single parent family (the
  /// highest-gen parent found). When both parents belong to different
  /// families, only one link is created — this keeps the simplified tree
  /// layout single-rooted per subtree and avoids diamond routing.
  void _rebuildFamilyTreeFromPersonGens() {
    for (final f in _families) {
      f.children.clear();
      f.parent = null;
      f.anchorId = null;
    }
    for (final f in _families) {
      _FamilyNode? bestPf;
      var bestPg = -1;
      RelativePerson? anchor;
      for (final m in f.members) {
        for (final pid in [m.fatherId, m.motherId]) {
          if (!_has(pid)) continue;
          final pf = _familyOf[pid!]!;
          if (identical(pf, f)) continue;
          if (pf.gen >= f.gen) continue;
          if (pf.gen > bestPg) {
            bestPg = pf.gen;
            bestPf = pf;
            anchor = m;
          }
        }
      }
      if (bestPf == null) continue;
      f.parent = bestPf;
      f.anchorId = anchor!.id;
      if (!bestPf.children.contains(f)) bestPf.children.add(f);
    }
  }

  _FamilyNode _rootOf(_FamilyNode f) {
    var cur = f;
    while (cur.parent != null) {
      cur = cur.parent!;
    }
    return cur;
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
    return FamilyTreeCorridorValidation.segmentsClear(
      segments: [for (final s in segs) (a: s.a, b: s.b)],
      personCards: _cardRect.values.toList(),
    );
  }

  bool _segmentClearOfPersons(Offset a, Offset b) {
    for (final r in _cardRect.values) {
      final inner = r.deflate(0.5);
      if (FamilyTreeLineRouter.segHitsRect(a, b, inner)) return false;
    }
    return true;
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
    _inheritedColor.clear();
    _ownFamilyColor.clear();
    _splitBorder.clear();
    _colorSeq = 0;
    _contentSize = Size.zero;
    _placed = 0;
    _routingIncomplete = false;

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
      if (partner.containsKey(a) || partner.containsKey(b)) {
        debugPrint('Tree: spouse conflict $a already paired');
        return;
      }
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

    _assignGenerationsFromPersonLinks();
    _rebuildFamilyTreeFromPersonGens();

    for (final f in _families) {
      f.children.sort((a, b) {
        final ap = _byId[a.anchorId ?? a.members.first.id];
        final bp = _byId[b.anchorId ?? b.members.first.id];
        return _comparePeople(ap, bp);
      });
    }

    _resetLayoutGaps();
    _assignColors();

    const maxLayoutAttempts = 12;
    for (var attempt = 0; attempt < maxLayoutAttempts; attempt++) {
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

    void layoutSub(_FamilyNode f) {
      if (!placed.add(f)) return;
      rowHeights[f.gen] =
          math.max(rowHeights[f.gen] ?? 0, _cardRowHeight(f));

      if (f.children.isEmpty) {
        f.centerX = _familyWidth(f) / 2;
        return;
      }
      final right = <int, double>{};
      for (final c in f.children) {
        layoutSub(c);
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
      layoutSub(r);
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
      if (f.parent != null) {
        layoutSub(_rootOf(f));
      } else {
        layoutSub(f);
      }
    }

    double yForGen(int gen) => _yForCardRow(gen);

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

    maxBottom = math.max(
      maxBottom,
      _yForCardRow(_maxGen) + _maxCardRowHeightAtGen(_maxGen),
    );

    final overlapGen = _detectOverlapGen();
    if (overlapGen != null) {
      _expandHorizontal(overlapGen);
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

    _segments.clear();
    final linesOk = _buildRoutedLines();

    final needsLines = _families.any(_hasLinkedChildren);
    final routingOk = !needsLines ||
        (linesOk &&
            _segments.isNotEmpty &&
            _segmentsClearInterior(_segments));
    _routingIncomplete = !routingOk;
    if (!routingOk && needsLines && attempt < maxLayoutAttempts - 1) {
      var expandGen = 0;
      for (final f in _families) {
        if (_hasLinkedChildren(f)) {
          expandGen = math.max(expandGen, f.gen);
        }
      }
      _expandCorridor(expandGen);
      if (attempt.isOdd) _expandHorizontal(expandGen);
      continue;
    }
    FamilyTreeView.debugRoutingReport = FamilyTreeRoutingReport(
      routingSucceeded: routingOk,
      segments: [
        for (final s in _segments) (a: s.a, b: s.b),
      ],
      cardRects: _cardRect.values.toList(),
      cardRectsById: Map<String, Rect>.from(_cardRect),
      parentLinks: [
        for (final p in _byId.values) ...[
          if (_has(p.fatherId))
            (childId: p.id, parentId: p.fatherId!),
          if (_has(p.motherId))
            (childId: p.id, parentId: p.motherId!),
        ],
      ],
      outerFrames: const [],
      layoutRowGap: List.generate(_maxGen + 1, _corridorHeightAtGen)
          .fold(0.0, math.max),
      layoutSiblingGap: _siblingGapAtGen.values.fold(
        _siblingGap,
        (a, b) => math.max(a, b),
      ),
      linePad: _linePad,
      lineWidth: _lineWidth,
    );
    break;
    } // overlap retry
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

  /// Har oila: vertikal o'zak + horizontal bus + bolalarga tushish.
  /// Tutashuv: karta tashqi chekkasi (past/yuqori markaz).
  bool _buildRoutedLines() {
    final usedKeys = <String>{};
    var allOk = true;

    void addSeg(Offset a, Offset b, Color color, double width) {
      final key =
          '${a.dx.toStringAsFixed(1)},${a.dy.toStringAsFixed(1)}-'
          '${b.dx.toStringAsFixed(1)},${b.dy.toStringAsFixed(1)}';
      if (usedKeys.contains(key)) return;
      usedKeys.add(key);
      _segments.add(_LineSeg(a, b, color, width));
    }

    bool addValidatedSeg(Offset a, Offset b, Color color) {
      if ((a.dx - b.dx).abs() < 0.5 && (a.dy - b.dy).abs() < 0.5) {
        return true;
      }
      if (!_segmentClearOfPersons(a, b)) {
        allOk = false;
        return false;
      }
      addSeg(a, b, color, _lineWidth);
      return true;
    }

    void drawTopConnector(double cx, double landY, Color color) {
      final side = math.min(_cardW * 0.2, 12.0);
      addValidatedSeg(
        Offset(cx - side, landY),
        Offset(cx + side, landY),
        color,
      );
    }

    // Chekkaga yopishish: to'siq = karta o'zi (inflate yo'q).
    final obstacles = _cardRect.values.toList();
    final router = FamilyTreeLineRouter(
      obstacles: obstacles,
      laneStep: _laneStep,
      linePad: _linePad,
      preferShortestDirect: false,
    );

    // Avlod bo'yicha dinamik laneStep.
    final stepAtGen = <int, double>{};
    for (var g = 0; g <= _maxGen; g++) {
      final lanes = _laneCountAtGen(g);
      if (lanes == 0) continue;
      stepAtGen[g] = FamilyTreeLineRouter.laneStepFor(
        corridorHeight: _corridorHeightAtGen(g),
        laneCount: lanes,
        linePad: _linePad,
      );
    }

    /// Ota/ona kartasi past markaz (tashqi chekka).
    Offset belowSingleCard(_FamilyNode parent) {
      final card = _cardRect[parent.members.first.id]!;
      return Offset(card.center.dx, card.bottom);
    }

    Offset belowCoupleCards(_FamilyNode parent) {
      final left = _cardRect[parent.members[0].id]!;
      final right = _cardRect[parent.members[1].id]!;
      return Offset(
        (left.center.dx + right.center.dx) / 2,
        math.max(left.bottom, right.bottom),
      );
    }

    /// Bola kartasi yuqori markaz (tashqi chekka).
    Offset childCardTarget(RelativePerson child) {
      final r = _cardRect[child.id]!;
      return Offset(r.center.dx, r.top);
    }

    bool drawPathPoints(List<Offset> pts, Color color, {double? endCx}) {
      if (pts.length < 2) {
        allOk = false;
        return false;
      }
      for (var i = 0; i < pts.length - 1; i++) {
        if (!addValidatedSeg(pts[i], pts[i + 1], color)) return false;
      }
      router.registerPath(pts);
      if (endCx != null) {
        drawTopConnector(endCx, pts.last.dy, color);
      }
      return true;
    }

    final ordered = [..._families]
      ..sort((a, b) {
        final g = a.gen.compareTo(b.gen);
        if (g != 0) return g;
        return a.centerX.compareTo(b.centerX);
      });

    for (final f in ordered) {
      final color = f.familyColor ?? _accent;
      if (!_hasLinkedChildren(f)) continue;

      final linked = _directChildrenOf(f);
      if (linked.isEmpty) continue;

      final targets = _childConnectorTargets(linked)
        ..sort((a, b) {
          final ax = _cardRect[a.child.id]?.center.dx ?? 0;
          final bx = _cardRect[b.child.id]?.center.dx ?? 0;
          return ax.compareTo(bx);
        });
      if (targets.isEmpty) continue;

      final routeStart = f.isCouple && f.members.length == 2
          ? belowCoupleCards(f)
          : belowSingleCard(f);

      final ends = <Offset>[
        for (final t in targets) childCardTarget(t.child),
      ];
      final minChildX = ends.map((e) => e.dx).reduce(math.min);
      final maxChildX = ends.map((e) => e.dx).reduce(math.max);
      final minChildTop = ends.map((e) => e.dy).reduce(math.min);

      final step = stepAtGen[f.gen] ?? _laneStep;
      // Faqat karta koordinatalari (layout +_pad tarjimasi bilan mos).
      final minBusY = routeStart.dy + math.max(step * 0.35, _linePad);
      final maxBusY = minChildTop - math.max(step * 0.35, _linePad);
      final preferredBusY = (minBusY + maxBusY) / 2;

      final busSpanMinX = math.min(routeStart.dx, minChildX);
      final busSpanMaxX = math.max(routeStart.dx, maxChildX);

      final busY = router.allocateBusY(
        laneId: f,
        corridorId: f.gen,
        preferred: preferredBusY,
        minY: minBusY,
        maxY: maxBusY,
        minX: busSpanMinX,
        maxX: busSpanMaxX,
        obstacles: obstacles,
        laneStep: step,
      );

      final resolvedBusY = busY;
      if (resolvedBusY == null) {
        for (var i = 0; i < targets.length; i++) {
          final end = ends[i];
          final path = router.route(routeStart, end, obstacles: obstacles);
          if (path == null ||
              !drawPathPoints(path, color, endCx: end.dx)) {
            allOk = false;
          }
        }
        continue;
      }

      final stemX = router.allocateStemX(
            laneId: f,
            corridorId: f.gen,
            preferred: routeStart.dx,
            minX: busSpanMinX - step * 2,
            maxX: busSpanMaxX + step * 2,
            minY: routeStart.dy,
            maxY: resolvedBusY,
            obstacles: obstacles,
            laneStep: step,
          ) ??
          routeStart.dx;

      // 1) Ota-onadan o'zakka (kerak bo'lsa) + vertikal o'zak.
      final stemPath = <Offset>[routeStart];
      if ((stemX - routeStart.dx).abs() >= 0.5) {
        stemPath.add(Offset(stemX, routeStart.dy));
      }
      stemPath.add(Offset(stemX, resolvedBusY));
      if (!drawPathPoints(stemPath, color)) {
        allOk = false;
        continue;
      }

      // 2) Horizontal bus (o'zak + bolalar oralig'i).
      final busLeft = math.min(stemX, minChildX);
      final busRight = math.max(stemX, maxChildX);
      if ((busRight - busLeft).abs() >= 0.5) {
        if (!drawPathPoints(
          [Offset(busLeft, resolvedBusY), Offset(busRight, resolvedBusY)],
          color,
        )) {
          allOk = false;
          continue;
        }
      }

      // 3) Har bolaga vertikal tushish + yuqori tutashuv.
      for (var i = 0; i < ends.length; i++) {
        final end = ends[i];
        final drop = [Offset(end.dx, resolvedBusY), end];
        if (!drawPathPoints(drop, color, endCx: end.dx)) {
          allOk = false;
        }
      }
    }

    return allOk;
  }

  /// Har bir farzand uchun alohida ulagich — aynan shu odam kartasi.
  List<({RelativePerson child, _FamilyNode fam})> _childConnectorTargets(
    List<RelativePerson> linked,
  ) {
    final seen = <String>{};
    final out = <({RelativePerson child, _FamilyNode fam})>[];
    for (final m in linked) {
      if (!seen.add(m.id)) continue;
      final fam = _familyOf[m.id];
      if (fam == null) continue;
      if (_cardRect[m.id] == null) continue;
      out.add((child: m, fam: fam));
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
            key: widget.exportCaptureKey,
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
            body: SafeArea(
              child: Stack(
                children: [
                  canvas,
                  if (_routingIncomplete) _layoutWarning(),
                ],
              ),
            ),
          );
        }
        return Container(
          color: const Color(0xFFF5F4F8),
          child: Stack(
            children: [
              canvas,
              if (_routingIncomplete) _layoutWarning(),
            ],
          ),
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

  Widget _layoutWarning() {
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: Colors.orange.shade700),
              const SizedBox(width: 4),
              Text(
                context.tr('rel_tree_layout_incomplete'),
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ],
          ),
        ),
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
              context.tr('rel_tree_empty_hint'),
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

/// Segment — global koordinatalarda (koridor + karta qatorlari orasida).
class _LineSeg {
  const _LineSeg(this.a, this.b, this.color, this.width);
  final Offset a;
  final Offset b;
  final Color color;
  final double width;
}

class _TreeLinesPainter extends CustomPainter {
  _TreeLinesPainter(this.segments, this.revision);

  final List<_LineSeg> segments;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in segments) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(s.a, s.b, paint);
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

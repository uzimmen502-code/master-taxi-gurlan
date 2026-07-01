import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/relative_person.dart';

/// 🌳 Nasab daraxti — avlod qatlamlari bo'yicha maxsus joylashuv.
/// Er-xotin yonma-yon, ular orasida to'q yashil bog'lovchi; ota-ona ↔ bola
/// bog'lanishlari faqat vertikal/gorizontal (90°) chiziqlar bilan.
/// To'liq boshqariladigan pan/zoom: erkin surish, silliq zoom, double-tap, auto-fit.
class FamilyTreeView extends StatefulWidget {
  const FamilyTreeView({
    super.key,
    required this.people,
    this.onTap,
    this.immersive = false,
    this.onExitImmersive,
  });

  final List<RelativePerson> people;
  final void Function(RelativePerson person)? onTap;

  /// To'liq ekran rejimi — AppBar/tablar ustidan ochiladi.
  final bool immersive;

  /// Immersive rejimda bo'sh joyga ikki marta bosilganda chaqiriladi.
  final VoidCallback? onExitImmersive;

  @override
  State<FamilyTreeView> createState() => _FamilyTreeViewState();
}

class _FamilyTreeViewState extends State<FamilyTreeView>
    with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFF6A4C93);
  static const _spouseColor = Color(0xFF1B5E20); // to'q yashil
  static const double _minScale = 0.1;
  static const double _maxScale = 4.0;

  // Joylashuv o'lchamlari (piksel).
  static const double _cardW = 128;
  static const double _cardH = 104;
  static const double _spouseGap = 22;
  static const double _siblingGap = 26;
  static const double _rootGap = 56;
  static const double _rowGap = 64;
  static const double _rowHeight = _cardH + _rowGap;
  static const double _pad = 48;

  late Map<String, RelativePerson> _byId;
  final List<_Unit> _units = [];
  final Map<String, _Unit> _unitOf = {};
  final Map<String, Rect> _rectOf = {};
  final List<_LineSeg> _segments = [];

  Size _contentSize = Size.zero;
  int _placed = 0;
  String _sig = '';

  final _transform = TransformationController();
  late final AnimationController _anim;
  Animation<Matrix4>? _matrixAnim;

  Size _viewport = Size.zero;
  bool _didInitialFit = false;
  bool _isScaleGesture = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
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
    // Foydalanuvchi qo'lda surganida animatsiya to'xtatiladi.
    if (_anim.isAnimating) {
      _anim.stop();
    }
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
    _anim.dispose();
    _transform.dispose();
    super.dispose();
  }

  // ---- Daraxt qurish ----

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
        ..write(p.photoUrl)
        ..write(';');
    }
    return b.toString();
  }

  void _build() {
    _sig = _signatureOf(widget.people);
    _byId = {for (final p in widget.people) p.id: p};
    _units.clear();
    _unitOf.clear();
    _rectOf.clear();
    _segments.clear();
    _contentSize = Size.zero;
    _placed = 0;

    bool has(String? id) => id != null && _byId.containsKey(id);

    // Faqat bog'langan kishilar (ota/ona/turmush o'rtog'i mavjud yoki kimningdir
    // ota/ona/turmush o'rtog'i sifatida tilga olingan) ko'rsatiladi.
    final referenced = <String>{};
    for (final p in widget.people) {
      if (has(p.fatherId)) referenced.add(p.fatherId!);
      if (has(p.motherId)) referenced.add(p.motherId!);
      if (has(p.spouseId)) referenced.add(p.spouseId!);
    }
    final relevant = <RelativePerson>[];
    for (final p in widget.people) {
      final linked = has(p.fatherId) || has(p.motherId) || has(p.spouseId);
      if (linked || referenced.contains(p.id)) relevant.add(p);
    }
    if (relevant.isEmpty) return;

    // ---- Er-xotin juftlarini aniqlash (oshkor spouseId + umumiy farzanddan) ----
    final partner = <String, String>{};
    void pair(String a, String b) {
      if (a == b) return;
      if (partner.containsKey(a) || partner.containsKey(b)) return;
      partner[a] = b;
      partner[b] = a;
    }

    for (final p in relevant) {
      if (has(p.spouseId)) pair(p.id, p.spouseId!);
    }
    for (final c in relevant) {
      if (has(c.fatherId) && has(c.motherId)) pair(c.fatherId!, c.motherId!);
    }

    // ---- Birliklar (single / couple) ----
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
      // Erkak chapda, ayol o'ngda (aniq bo'lsa).
      members.sort((a, b) => _genderRank(a.gender) - _genderRank(b.gender));
      final unit = _Unit(members);
      _units.add(unit);
      for (final m in members) {
        _unitOf[m.id] = unit;
      }
    }

    // ---- Ota-ona birligi va ankor (qon-qarindosh bola) ----
    String? primaryParentId(RelativePerson m) {
      if (has(m.fatherId)) return m.fatherId;
      if (has(m.motherId)) return m.motherId;
      return null;
    }

    // Birlik qaysi ota-onaga ulanishini tanlash: HAR IKKALA ota-onasi daraxtda
    // bo'lgan a'zo ustun (qon-farzand o'z ota-onasi yonida tursin, uylanib
    // kelgan tomonga emas).
    int parentScore(RelativePerson m) =>
        (has(m.fatherId) ? 1 : 0) + (has(m.motherId) ? 1 : 0);

    for (final unit in _units) {
      RelativePerson? best;
      _Unit? bestPu;
      var bestScore = -1;
      for (final m in unit.members) {
        final pid = primaryParentId(m);
        if (pid == null) continue;
        final pu = _unitOf[pid];
        if (pu == null || identical(pu, unit)) continue;
        final sc = parentScore(m);
        if (sc > bestScore) {
          best = m;
          bestPu = pu;
          bestScore = sc;
        }
      }
      if (best != null) {
        unit.parent = bestPu;
        unit.anchorId = best.id;
        bestPu!.children.add(unit);
      }
    }

    // Chizish uchun: HAR bola HAM otasi, HAM onasi bilan ulanadi (turli birlikda
    // bo'lsa ham). Ota va ona bitta er-xotin birligida bo'lsa — bitta bog'.
    for (final e in _unitOf.entries) {
      final p = _byId[e.key]!;
      final self = e.value;
      final fu = has(p.fatherId) ? _unitOf[p.fatherId] : null;
      final mu = has(p.motherId) ? _unitOf[p.motherId] : null;
      if (fu != null && !identical(fu, self)) fu.edgeChildren.add(p);
      if (mu != null && !identical(mu, self) && !identical(mu, fu)) {
        mu.edgeChildren.add(p);
      }
    }

    // Bolalarni barqaror tartibda joylash.
    for (final u in _units) {
      u.children.sort((a, b) {
        final an = _byId[a.anchorId]?.fullName ?? '';
        final bn = _byId[b.anchorId]?.fullName ?? '';
        final c = an.compareTo(bn);
        return c != 0 ? c : a.members.first.id.compareTo(b.members.first.id);
      });
    }

    // ---- Tidy-tree joylashuv (kontur asosida — ustma-ustlik bo'lmaydi) ----
    // Har bir shoxobchaning chap/o'ng kontu`ri (avlod bo'yicha chekka qirralar)
    // kuzatilib, qo'shni shoxobcha bilan to'qnashsa butun shoxobcha o'ngga
    // suriladi. Bu ixtiyoriy daraxt uchun ustma-ustlikni butunlay bartaraf etadi.
    final placed = <_Unit>{};

    void contour(_Unit u, bool left, Map<int, double> out) {
      final half = _unitWidth(u) / 2;
      final edge = left ? u.centerX - half : u.centerX + half;
      final d = u.gen;
      final cur = out[d];
      if (cur == null) {
        out[d] = edge;
      } else {
        out[d] = left ? math.min(cur, edge) : math.max(cur, edge);
      }
      for (final c in u.children) {
        contour(c, left, out);
      }
    }

    void shift(_Unit u, double dx) {
      u.centerX += dx;
      for (final c in u.children) {
        shift(c, dx);
      }
    }

    // `block` — allaqachon joylashtirilgan shoxobchalar(ning) o'ng konturi.
    double packInto(_Unit u, Map<int, double> block, double gap) {
      final lc = <int, double>{};
      contour(u, true, lc);
      var need = 0.0;
      lc.forEach((d, leftEdge) {
        final rc = block[d];
        if (rc != null) {
          final s = rc + gap - leftEdge;
          if (s > need) need = s;
        }
      });
      if (need > 0) shift(u, need);
      final rcm = <int, double>{};
      contour(u, false, rcm);
      rcm.forEach((d, e) {
        final cur = block[d];
        block[d] = (cur == null) ? e : math.max(cur, e);
      });
      return need;
    }

    void layoutSub(_Unit u, int depth) {
      if (!placed.add(u)) return; // sikldan himoya
      u.gen = depth;
      if (u.children.isEmpty) {
        u.centerX = _unitWidth(u) / 2;
        return;
      }
      final right = <int, double>{};
      for (final c in u.children) {
        layoutSub(c, depth + 1);
        packInto(c, right, _siblingGap);
      }
      u.centerX = (u.children.first.centerX + u.children.last.centerX) / 2;
    }

    final roots = _units.where((u) => u.parent == null).toList()
      ..sort((a, b) {
        final c = a.members.first.fullName.compareTo(b.members.first.fullName);
        return c != 0 ? c : a.members.first.id.compareTo(b.members.first.id);
      });

    final rootBlock = <int, double>{};
    for (final r in roots) {
      layoutSub(r, 0);
      packInto(r, rootBlock, _rootGap);
    }
    // Sikl tufayli joylashmay qolganlar (kam ehtimol) — o'ng tomonga qo'shamiz.
    for (final u in _units) {
      if (placed.contains(u)) continue;
      layoutSub(u, 0);
      packInto(u, rootBlock, _rootGap);
    }

    // ---- Kartochka to'rtburchaklarini hisoblash + normalizatsiya ----
    var minLeft = double.infinity;
    var maxRight = -double.infinity;
    var maxBottom = -double.infinity;
    for (final u in _units) {
      final topY = u.gen * _rowHeight;
      final positions = _memberLefts(u);
      for (var i = 0; i < u.members.length; i++) {
        final left = positions[i];
        final r = Rect.fromLTWH(left, topY, _cardW, _cardH);
        _rectOf[u.members[i].id] = r;
        minLeft = math.min(minLeft, r.left);
        maxRight = math.max(maxRight, r.right);
        maxBottom = math.max(maxBottom, r.bottom);
      }
    }
    if (!minLeft.isFinite) return;

    final offX = _pad - minLeft;
    const offY = _pad;
    for (final id in _rectOf.keys.toList()) {
      _rectOf[id] = _rectOf[id]!.translate(offX, offY);
    }
    for (final u in _units) {
      u.centerX += offX;
    }

    _contentSize = Size(
      maxRight - minLeft + 2 * _pad,
      maxBottom + 2 * _pad,
    );
    _placed = _rectOf.length;

    _buildSegments(offY);
  }

  void _buildSegments(double offY) {
    for (final u in _units) {
      final topY = u.gen * _rowHeight + offY;

      // Er-xotin chizig'i (to'q yashil, gorizontal).
      if (u.members.length == 2) {
        final left = _rectOf[u.members[0].id]!;
        final right = _rectOf[u.members[1].id]!;
        final y = topY + _cardH / 2;
        _segments.add(_LineSeg(
          Offset(left.right, y),
          Offset(right.left, y),
          _spouseColor,
          2.6,
        ));
      }

      if (u.edgeChildren.isEmpty) continue;

      // Ota-ona ulanish nuqtasi.
      final double parentX = u.centerX;
      final double parentY = u.members.length == 2
          ? topY + _cardH / 2 // nikoh chizig'idan
          : topY + _cardH; // yakka ota/ona — kartochka pastidan
      final busY = topY + _cardH + (_rowGap / 2);

      // Har bir bola SHAXSining kartochkasi (turli birlikda/avlodda bo'lishi mumkin).
      final childRects = <Rect>[];
      for (final ch in u.edgeChildren) {
        final r = _rectOf[ch.id];
        if (r != null) childRects.add(r);
      }
      if (childRects.isEmpty) continue;

      // Pastga tushish (ota-onadan shinaga).
      _segments.add(_LineSeg(
        Offset(parentX, parentY),
        Offset(parentX, busY),
        _accentLine,
        1.8,
      ));
      // Gorizontal shina (ota-ona + barcha bolalar markazlari oralig'ida).
      var minX = parentX;
      var maxX = parentX;
      for (final r in childRects) {
        minX = math.min(minX, r.center.dx);
        maxX = math.max(maxX, r.center.dx);
      }
      _segments.add(_LineSeg(
        Offset(minX, busY),
        Offset(maxX, busY),
        _accentLine,
        1.8,
      ));
      // Har bolaga vertikal tushish — bola kartochkasining tepa-markazigacha.
      for (final r in childRects) {
        _segments.add(_LineSeg(
          Offset(r.center.dx, busY),
          Offset(r.center.dx, r.top),
          _accentLine,
          1.8,
        ));
      }
    }
  }

  static const _accentLine = Color(0x8C6A4C93); // accent, ~55% alpha

  static int _genderRank(String g) =>
      g == 'male' ? 0 : (g == 'female' ? 1 : 2);

  double _unitWidth(_Unit u) =>
      u.members.length == 2 ? _cardW * 2 + _spouseGap : _cardW;

  /// Birlik a'zolarining chap koordinatasi (normalizatsiyadan oldin).
  List<double> _memberLefts(_Unit u) {
    if (u.members.length == 2) {
      final leftLeft = u.centerX - _cardW - _spouseGap / 2;
      final rightLeft = u.centerX + _spouseGap / 2;
      return [leftLeft, rightLeft];
    }
    return [u.centerX - _cardW / 2];
  }

  // ---- Pan / Zoom boshqaruvi ----

  void _animateTo(Matrix4 target) {
    _matrixAnim = Matrix4Tween(begin: _transform.value, end: target)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    void tick() {
      _transform.value = _matrixAnim!.value;
      if (!_anim.isAnimating) {
        _matrixAnim?.removeListener(tick);
      }
    }

    _matrixAnim!.addListener(tick);
    _anim
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
    final nav = Navigator.of(context, rootNavigator: true);
    nav.push(
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
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final delta = event.scrollDelta.dy;
          if (delta == 0) return;
          final factor = math.exp(-delta * 0.002);
          _zoomAround(event.localPosition, _scale * factor);
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
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: _onBackgroundDoubleTap,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _EdgePainter(_segments, _sig.hashCode),
                    ),
                  ),
                ),
                for (final entry in _rectOf.entries)
                  Positioned(
                    left: entry.value.left,
                    top: entry.value.top,
                    width: _cardW,
                    height: _cardH,
                    child: _card(_byId[entry.key]!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- UI ----

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

  Widget _card(RelativePerson p) {
    return GestureDetector(
      onTap: widget.onTap == null ? null : () => widget.onTap!(p),
      child: Container(
        width: _cardW,
        height: _cardH,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withValues(alpha: 0.3)),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _accent.withValues(alpha: 0.15),
              backgroundImage:
                  p.photoUrl.isNotEmpty ? NetworkImage(p.photoUrl) : null,
              child: p.photoUrl.isEmpty
                  ? Text(
                      p.fullName.isNotEmpty
                          ? p.fullName.characters.first.toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: _accent, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(height: 5),
            Flexible(
              child: Text(
                p.fullName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
            if (p.relationDegree.isNotEmpty)
              Text(
                p.relationDegree,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
          ],
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
              'Дарахт ҳали бўш.\nҚариндошни таҳрирлаб, унинг «Отаси» ёки '
              '«Онаси»ни белгиланг — улар автоматик боғланади.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bir qator birligi: yakka shaxs yoki er-xotin (≤2 a'zo).
class _Unit {
  _Unit(this.members);

  final List<RelativePerson> members;
  final List<_Unit> children = []; // FAQAT joylashuv (tidy-tree) uchun
  final List<RelativePerson> edgeChildren = []; // chizish uchun: barcha ota/ona bog'lari
  _Unit? parent;
  String? anchorId; // joylashuvda ulanadigan qon-qarindosh bola
  int gen = 0;
  double centerX = 0;
}

class _LineSeg {
  const _LineSeg(this.a, this.b, this.color, this.width);
  final Offset a;
  final Offset b;
  final Color color;
  final double width;
}

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.segments, this.revision);

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
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.revision != revision || old.segments.length != segments.length;
}

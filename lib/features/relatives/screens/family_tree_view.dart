import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  });

  final List<RelativePerson> people;
  final void Function(RelativePerson person)? onTap;

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
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Animation<Matrix4>? _matrixAnim;

  Size _viewport = Size.zero;
  Offset _doubleTapPos = Offset.zero;
  bool _didInitialFit = false;

  @override
  void initState() {
    super.initState();
    _build();
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

    for (final unit in _units) {
      for (final m in unit.members) {
        final pid = primaryParentId(m);
        if (pid == null) continue;
        final pu = _unitOf[pid];
        if (pu == null || identical(pu, unit)) continue;
        unit.parent = pu;
        unit.anchorId = m.id;
        pu.children.add(unit);
        break;
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

    final roots = _units.where((u) => u.parent == null).toList();

    // ---- Tidy-tree joylashuv (x), avlod (gen) chuqurlikdan ----
    final visited = <_Unit>{};
    double cursor = 0;

    double layout(_Unit u, int depth) {
      if (!visited.add(u)) return u.centerX; // sikldan himoya
      u.gen = depth;
      if (u.children.isEmpty) {
        final w = _unitWidth(u);
        u.centerX = cursor + w / 2;
        cursor += w + _siblingGap;
      } else {
        var minC = double.infinity;
        var maxC = -double.infinity;
        for (final c in u.children) {
          final cx = layout(c, depth + 1);
          minC = math.min(minC, cx);
          maxC = math.max(maxC, cx);
        }
        u.centerX = (minC + maxC) / 2;
        final half = _unitWidth(u) / 2;
        cursor = math.max(cursor, u.centerX + half + _siblingGap);
      }
      return u.centerX;
    }

    for (final r in roots) {
      layout(r, 0);
      cursor += _rootGap;
    }
    // Sikl tufayli joylashmay qolganlar (kam ehtimol) — alohida ildiz sifatida.
    for (final u in _units) {
      if (!visited.contains(u)) layout(u, 0);
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
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut));
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

  void _zoomBy(double factor) {
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    _zoomAround(center, _scale * factor);
  }

  void _handleDoubleTap() {
    if (_scale < 1.4) {
      _zoomAround(_doubleTapPos, 2.0);
    } else {
      _fit();
    }
  }

  void _fit() {
    if (_viewport.isEmpty || _contentSize.isEmpty) return;
    const padFactor = 0.9;
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

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    if (_placed == 0) {
      return _hint();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (!_didInitialFit) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_didInitialFit) _fit();
          });
        }
        return Container(
          color: const Color(0xFFF5F4F8),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
                  onDoubleTap: _handleDoubleTap,
                  child: InteractiveViewer(
                    transformationController: _transform,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(1200),
                    minScale: _minScale,
                    maxScale: _maxScale,
                    child: SizedBox(
                      width: _contentSize.width,
                      height: _contentSize.height,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _EdgePainter(_segments, _sig.hashCode),
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
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: _ZoomControls(
                  onZoomIn: () => _zoomBy(1.3),
                  onZoomOut: () => _zoomBy(1 / 1.3),
                  onFit: _fit,
                ),
              ),
              Positioned(
                left: 12,
                bottom: 12,
                child: IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '☝ Сурилади · 🤏 Кенгайтиринг · 👆👆 Якинлаштириш',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ),
                ),
              ),
            ],
          ),
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

/// Daraxt uchun ekran boshqaruvi: kattalashtirish/kichraytirish, moslash.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  static const _accent = Color(0xFF6A4C93);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(Icons.add, 'Катталаштириш', onZoomIn),
        const SizedBox(height: 8),
        _btn(Icons.remove, 'Кичрайтириш', onZoomOut),
        const SizedBox(height: 8),
        _btn(Icons.fit_screen_outlined, 'Экранга мослаш', onFit),
      ],
    );
  }

  Widget _btn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: _accent, size: 22),
          ),
        ),
      ),
    );
  }
}

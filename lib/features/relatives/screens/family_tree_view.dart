import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

import '../../../models/relative_person.dart';

/// 🌳 Nasab daraxti — ota/ona bog'lanishlari asosida graf vizualizatsiyasi.
/// To'liq boshqariladigan pan/zoom: erkin surish (har tomonga), silliq
/// animatsiyali kattalashtirish/kichraytirish, double-tap zoom, auto-fit.
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
  static const double _minScale = 0.1;
  static const double _maxScale = 4.0;

  late Graph _graph;
  late SugiyamaConfiguration _config;
  late Map<String, RelativePerson> _byId;
  int _connected = 0;
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
      // Tuzilma o'zgardi — qayta moslab ko'rsatamiz.
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

  // ---- Graf qurish ----

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
    _graph = Graph();
    final nodes = <String, Node>{};
    Node nodeFor(String id) => nodes.putIfAbsent(id, () => Node.Id(id));

    for (final p in widget.people) {
      final f = p.fatherId;
      final m = p.motherId;
      if (f != null && f != p.id && _byId.containsKey(f)) {
        _graph.addEdge(nodeFor(f), nodeFor(p.id));
      }
      if (m != null && m != p.id && _byId.containsKey(m)) {
        _graph.addEdge(nodeFor(m), nodeFor(p.id));
      }
    }
    _connected = nodes.length;

    _config = SugiyamaConfiguration()
      ..nodeSeparation = 24
      ..levelSeparation = 64
      ..orientation = SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM;
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
    // Kichik bo'lsa — yaqinlashtir; katta bo'lsa — moslab qaytar.
    if (_scale < 1.4) {
      _zoomAround(_doubleTapPos, 2.0);
    } else {
      _fit();
    }
  }

  void _fit() {
    if (_viewport.isEmpty || _connected == 0) return;
    final bounds = _graph.calculateGraphBounds();
    if (!bounds.width.isFinite ||
        !bounds.height.isFinite ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return;
    }
    const pad = 0.86;
    final scale = (math.min(
      _viewport.width / bounds.width,
      _viewport.height / bounds.height,
    ) *
            pad)
        .clamp(_minScale, _maxScale);
    final tx = (_viewport.width - bounds.width * scale) / 2 - bounds.left * scale;
    final ty =
        (_viewport.height - bounds.height * scale) / 2 - bounds.top * scale;
    final m = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    _didInitialFit = true;
    _animateTo(m);
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    if (_connected == 0) {
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
                    child: GraphView(
                      graph: _graph,
                      algorithm: SugiyamaAlgorithm(_config),
                      animated: false,
                      paint: Paint()
                        ..color = _accent.withValues(alpha: 0.55)
                        ..strokeWidth = 1.6
                        ..style = PaintingStyle.stroke,
                      builder: (Node node) {
                        final id = node.key?.value as String?;
                        final p = id == null ? null : _byId[id];
                        if (p == null) return const SizedBox.shrink();
                        return _card(p);
                      },
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
                  onReset: _fit,
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
    final spouse = p.spouseId == null ? null : _byId[p.spouseId];
    return GestureDetector(
      onTap: widget.onTap == null ? null : () => widget.onTap!(p),
      child: Container(
        width: 136,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withValues(alpha: 0.3)),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 22,
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
            const SizedBox(height: 6),
            Text(
              p.fullName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            if (p.relationDegree.isNotEmpty)
              Text(
                p.relationDegree,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            if (spouse != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '⚭ ${spouse.fullName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: _accent),
                ),
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

/// Daraxt uchun ekran boshqaruvi: kattalashtirish/kichraytirish, moslash.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback onReset;

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

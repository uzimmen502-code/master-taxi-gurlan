import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

import '../../../models/relative_person.dart';

/// 🌳 Nasab daraxti — ota/ona bog'lanishlari asosida graf vizualizatsiyasi
/// (Sugiyama layered layout — bir nechta ota-onali DAG'ni qo'llab-quvvatlaydi).
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

class _FamilyTreeViewState extends State<FamilyTreeView> {
  static const _accent = Color(0xFF6A4C93);

  late Graph _graph;
  late SugiyamaConfiguration _config;
  late Map<String, RelativePerson> _byId;
  int _connected = 0;

  final _transform = TransformationController();
  late final GraphViewController _gvController =
      GraphViewController(transformationController: _transform);

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(covariant FamilyTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prev = _connected;
    _build();
    // Yangi qarindosh qo'shilsa — qayta moslab ko'rsatamiz.
    if (_connected != prev && _connected > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _gvController.zoomToFit();
      });
    }
  }

  @override
  void dispose() {
    // _transform GraphView tomonidan dispose qilinadi (controller orqali).
    super.dispose();
  }

  void _zoomBy(double factor) {
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size ?? const Size(320, 480);
    final center = Offset(size.width / 2, size.height / 2);
    final current = _transform.value.clone();
    final newScale = current.getMaxScaleOnAxis() * factor;
    if (newScale < 0.08 || newScale > 8) return;
    final zoom = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(factor, factor, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    _transform.value = zoom.multiplied(current);
  }

  void _build() {
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

  @override
  Widget build(BuildContext context) {
    if (_connected == 0) {
      return _hint();
    }
    return Container(
      color: const Color(0xFFF5F4F8),
      child: Stack(
        children: [
          Positioned.fill(
            child: GraphView.builder(
              graph: _graph,
              algorithm: SugiyamaAlgorithm(_config),
              controller: _gvController,
              autoZoomToFit: true,
              centerGraph: true,
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
          Positioned(
            right: 12,
            bottom: 12,
            child: _ZoomControls(
              onZoomIn: () => _zoomBy(1.25),
              onZoomOut: () => _zoomBy(0.8),
              onFit: () => _gvController.zoomToFit(),
              onReset: () => _gvController.resetView(),
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
                  '☝ Сурилади · 🤏 Кенгайтиринг',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
            ),
          ),
        ],
      ),
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

/// Daraxt uchun ekran boshqaruvi: kattalashtirish/kichraytirish, moslash, reset.
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
        const SizedBox(height: 8),
        _btn(Icons.center_focus_strong_outlined, 'Бошланғич ҳолат', onReset),
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

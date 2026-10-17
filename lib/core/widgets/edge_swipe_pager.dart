import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Саҳифа (маҳсулот) контенти ТУГАГАНДАН кейин сурилганда кейинги/олдинги
/// саҳифага ўтадиган вертикал пейджер.
///
/// Эга қарори (2026-10-17): тасодифий свайп халақит беради, шунинг учун
/// свайп ФАҚАТ маълумот охирига етгандагина ишлайди:
///   • контент охирида юқорига суринг → КЕЙИНГИ маҳсулот;
///   • контент тепасида пастга суринг → ОЛДИНГИ маҳсулот
/// (одатий «Reels» тартиби, `reverse: false`).
///
/// Ишлаш усули: [itemBuilder] қайтарган саҳифа ичидаги вертикал скролл
/// чегарадан ЧИҚИБ кетганда (overscroll) шу ерда ушланади. Саҳифа скроллида
/// [kEdgeSwipePhysics] бўлиши шарт — контент қисқа бўлса ҳам overscroll
/// хабари келиши учун.
///
/// Тасодифий ўтишдан сақлайди:
///  • фақат БАРМОҚ билан судралганда (`dragDetails != null`) — узун
///    контентни тез айлантириб охирига "урилиш" (fling) ўтказмайди;
///  • ишора чегарада БОШЛАНГАН бўлиши керак — контентни охиригача
///    судраб, давом эттирилган бармоқ ҳисобланмайди;
///  • [threshold] пикселдан кам суриш ҳисобланмайди.
const ScrollPhysics kEdgeSwipePhysics =
    AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics());

class EdgeSwipePager extends StatefulWidget {
  const EdgeSwipePager({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.initialIndex = 0,
    this.onPageChanged,
    this.threshold = 56,
  });

  final int itemCount;
  final int initialIndex;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int>? onPageChanged;

  /// Ўтиш учун чегарадан ортиқча сурилиши керак бўлган масофа (px).
  final double threshold;

  @override
  State<EdgeSwipePager> createState() => _EdgeSwipePagerState();
}

class _EdgeSwipePagerState extends State<EdgeSwipePager> {
  late final PageController _ctrl;
  late int _index;

  double _accum = 0;
  bool _handled = false;
  bool _startedAtBottom = false;
  bool _startedAtTop = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.itemCount - 1);
    _ctrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.itemCount) return;
    _handled = true;
    HapticFeedback.lightImpact();
    _ctrl.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  bool _onScroll(ScrollNotification n) {
    // Расм карусели ва горизонтал ленталарнинг хабарлари керак эмас.
    if (n.metrics.axis != Axis.vertical) return false;

    if (n is ScrollStartNotification) {
      _accum = 0;
      _handled = false;
      _startedAtBottom = n.metrics.extentAfter <= 0.5;
      _startedAtTop = n.metrics.extentBefore <= 0.5;
    } else if (n is OverscrollNotification) {
      if (n.dragDetails == null || _handled) return false;
      // overscroll > 0: охиридан ўтиб юқорига судралди; < 0: тепадан ўтиб пастга.
      if (n.overscroll > 0 && _startedAtBottom) {
        _accum = _accum < 0 ? n.overscroll : _accum + n.overscroll;
      } else if (n.overscroll < 0 && _startedAtTop) {
        _accum = _accum > 0 ? n.overscroll : _accum + n.overscroll;
      } else {
        return false;
      }
      if (_accum >= widget.threshold) {
        _go(1);
      } else if (_accum <= -widget.threshold) {
        _go(-1);
      }
    } else if (n is ScrollEndNotification) {
      _accum = 0;
      _handled = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _ctrl,
      scrollDirection: Axis.vertical,
      // Ўтиш фақат юқоридаги overscroll мантиғидан: пейджернинг ўз
      // бармоқ ишораси йўқ (саҳифа ичидаги скролл билан тўқнашмасин).
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.itemCount,
      onPageChanged: (i) {
        setState(() => _index = i);
        widget.onPageChanged?.call(i);
      },
      itemBuilder: (context, i) => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.itemBuilder(context, i),
      ),
    );
  }
}

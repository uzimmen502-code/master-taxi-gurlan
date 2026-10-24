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
    this.controller,
  });

  /// Ташқаридан бошқариш (тугма билан ўтиш — свайпга муқобил). Берилса,
  /// пейджер уни ЎЗИ ёпмайди; `initialPage` ташқарида белгиланади.
  final PageController? controller;

  final int itemCount;
  final int initialIndex;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int>? onPageChanged;

  /// Ўтиш учун чегарадан ортиқча сурилиши керак бўлган масофа (px).
  final double threshold;

  @override
  State<EdgeSwipePager> createState() => _EdgeSwipePagerState();
}

class _EdgeSwipePagerState extends State<EdgeSwipePager>
    with SingleTickerProviderStateMixin {
  /// Судраш пайтида саҳифа бармоқ орқасидан шунча (px) гача сурилади.
  /// Android 12+ нинг «чўзилиш» эффекти ўрнига: чўзилмайди, фақат сал
  /// сурилади ва қўйиб юборилса юмшоқ қайтади.
  static const double _maxPull = 40;

  late final PageController _ctrl;
  late int _index;

  /// Саҳифанинг вертикал сурилиши (манфий = юқорига).
  final ValueNotifier<double> _pull = ValueNotifier<double>(0);
  late final AnimationController _back;
  double _backFrom = 0;

  double _accum = 0;
  bool _handled = false;
  bool _startedAtBottom = false;
  bool _startedAtTop = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.itemCount - 1);
    _ctrl = widget.controller ?? PageController(initialPage: _index);
    // `initState`да яратилади: `late` лазй бўлса, dispose'да биринчи марта
    // яратилиб, «ўчирилган виджет аждоди» хатосини берарди.
    _back = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    )..addListener(() {
        _pull.value = _backFrom * (1 - Curves.easeOut.transform(_back.value));
      });
  }

  @override
  void dispose() {
    _back.dispose();
    _pull.dispose();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  void _setPull() {
    _back.stop();
    _pull.value = (-_accum * 0.5).clamp(-_maxPull, _maxPull);
  }

  void _releasePull() {
    if (_pull.value == 0) return;
    _backFrom = _pull.value;
    _back.forward(from: 0);
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.itemCount) return;
    _handled = true;
    // Саҳифа алмашади — сурилиш шу заҳоти йўқолади (янги саҳифа жойидан).
    _back.stop();
    _pull.value = 0;
    HapticFeedback.lightImpact();
    // Ҳаракатни камайтириш (reduced motion) ёқилган бўлса — анимациясиз.
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.jumpToPage(target);
      return;
    }
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
      } else {
        _setPull();
      }
    } else if (n is ScrollUpdateNotification && _accum != 0 && !_handled) {
      // Бармоқ чегарадан ичкарига қайтди — тўпланган масофа камаяди.
      final back = (n.scrollDelta ?? 0).abs();
      if (back > 0) {
        final sign = _accum > 0 ? 1 : -1;
        final next = _accum.abs() - back;
        _accum = next <= 0 ? 0 : sign * next;
        _setPull();
      }
    } else if (n is ScrollEndNotification) {
      _accum = 0;
      _handled = false;
      _releasePull();
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
        // Material 3 нинг «чўзилиш» (stretch) эффекти ўчирилади: саҳифа
        // чўзилиб, кейин сакраб ўтарди. Ўрнига — сал сурилиш ([_pull]).
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: ValueListenableBuilder<double>(
            valueListenable: _pull,
            child: widget.itemBuilder(context, i),
            builder: (context, dy, page) =>
                Transform.translate(offset: Offset(0, dy), child: page),
          ),
        ),
      ),
    );
  }
}

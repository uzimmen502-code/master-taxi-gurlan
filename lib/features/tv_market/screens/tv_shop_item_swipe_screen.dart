import 'package:flutter/material.dart';

import '../../../core/widgets/edge_swipe_pager.dart';
import '../../ads/screens/ad_swipe_screen.dart' show AdSwipeNav;
import '../models/tv_shop.dart';
import 'tv_shop_item_detail_screen.dart';

/// Аҳоли бозоридаги дўкон маҳсулотлари — СУРИБ кўриш (эга, 2026-10-31:
/// эълонлардагидек маҳсулотдан маҳсулотга свайп).
///
/// [AdSwipeScreen] билан БИР ХИЛ қоида: маълумот ТУГАГАНДАН кейин юқорига
/// суринг = кейинги, тепада пастга суринг = олдинги ([EdgeSwipePager]); у
/// Android 12+ нинг «чўзилиш» эффектини ҳам ўчиради. Тафсилот экрани
/// ўзгармаган — ҳар саҳифа ўз `Scaffold`и билан.
class TvShopItemSwipeScreen extends StatefulWidget {
  const TvShopItemSwipeScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    this.similarPool = const [],
    this.showShopButton = false,
    this.source = 'other',
    this.loadLatest,
  });

  /// Лентадаги маҳсулотлар (экрандаги тартибда) — сурилиш шулар орасида.
  final List<TvShopItem> items;
  final int initialIndex;
  final Iterable<TvShopItem> similarPool;
  final bool showShopButton;
  final String source;

  /// Тест учун: [TvShopItemDetailScreen.loadLatest] га узатилади.
  final Future<TvShopItem?> Function(String itemId)? loadLatest;

  @override
  State<TvShopItemSwipeScreen> createState() => _TvShopItemSwipeScreenState();
}

class _TvShopItemSwipeScreenState extends State<TvShopItemSwipeScreen> {
  late int _index;
  late final PageController _pager;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pager = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// Свайпга муқобил тугма (WCAG 2.5.7).
  void _step(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.items.length) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pager.jumpToPage(target);
      return;
    }
    _pager.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  TvShopItemDetailScreen _page(TvShopItem item) => TvShopItemDetailScreen(
        // Калит бўлмаса бир маҳсулотнинг ҳолати бошқасида қолиб кетарди.
        key: ValueKey(item.id),
        item: item,
        showShopButton: widget.showShopButton,
        similarPool: widget.similarPool,
        source: widget.source,
        loadLatest: widget.loadLatest,
      );

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.length <= 1) return _page(items.first);
    // Фон саҳифа ранги билан бир хил: судраганда саҳифа сал сурилади.
    return ColoredBox(
      color: kTvShopItemDetailBg,
      child: Stack(
        children: [
          EdgeSwipePager(
            itemCount: items.length,
            initialIndex: _index,
            controller: _pager,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _page(items[i]),
          ),
          // AppBar ОСТИДА, расм устида ўртада: AppBar'да сарлавҳа ва
          // иконкалар бор, расмнинг ўнг юқорисида «Видео» тугмаси.
          Positioned(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 20,
            left: 0,
            right: 0,
            child: Center(
              child: AdSwipeNav(
                index: _index,
                count: items.length,
                onStep: _step,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

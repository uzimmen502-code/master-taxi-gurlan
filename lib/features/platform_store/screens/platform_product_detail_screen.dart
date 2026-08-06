import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import '../ava_store_colors.dart';
import '../controllers/platform_store_controller.dart';
import '../widgets/platform_cart_sheet.dart';
import '../widgets/platform_image_stack.dart';

/// AVA дўкони маҳсулот детал: вертикал свайп = кейинги, пастда ўхшаш қатор.
class PlatformProductDetailScreen extends StatefulWidget {
  const PlatformProductDetailScreen({
    super.key,
    required this.product,
    this.catalog = const [],
  });

  final PlatformProduct product;
  final List<PlatformProduct> catalog;

  @override
  State<PlatformProductDetailScreen> createState() =>
      _PlatformProductDetailScreenState();
}

class _PlatformProductDetailScreenState
    extends State<PlatformProductDetailScreen> {
  late final PageController _pageCtrl;
  late List<PlatformProduct> _catalog;
  late int _index;

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog.isNotEmpty
        ? List.of(widget.catalog)
        : [widget.product];
    _index = _catalog.indexWhere((p) => p.id == widget.product.id);
    if (_index < 0) {
      _catalog = [
        widget.product,
        ..._catalog.where((p) => p.id != widget.product.id),
      ];
      _index = 0;
    }
    _pageCtrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goToProduct(PlatformProduct p) {
    final i = _catalog.indexWhere((x) => x.id == p.id);
    if (i < 0 || i == _index) return;
    HapticFeedback.selectionClick();
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openCart() async {
    final c = context.read<PlatformStoreController>();
    if (c.cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('platform_store_cart_empty')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AvaStoreColors.deep,
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider<PlatformStoreController>.value(
        value: c,
        child: const PlatformCartSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlatformStoreController>();

    return Scaffold(
      backgroundColor: AvaStoreColors.scaffold,
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            style: const TextStyle(
              color: AvaStoreColors.onBrand,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: 0.15,
            ),
            children: [
              const TextSpan(text: BrandLabels.brand),
              TextSpan(text: ' ${context.tr('platform_store_title_suffix')}'),
            ],
          ),
        ),
        backgroundColor: AvaStoreColors.brand,
        foregroundColor: AvaStoreColors.onBrand,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              onPressed: _openCart,
              icon: Badge(
                isLabelVisible: c.cartItemCount > 0,
                backgroundColor: AvaStoreColors.onBrand,
                label: Text(
                  '${c.cartItemCount}',
                  style: const TextStyle(
                    color: AvaStoreColors.brand,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
                child: const Icon(Icons.shopping_cart_rounded, size: 26),
              ),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        scrollDirection: Axis.vertical,
        reverse: true,
        itemCount: _catalog.length,
        onPageChanged: (i) {
          HapticFeedback.lightImpact();
          setState(() => _index = i);
        },
        itemBuilder: (context, i) {
          final raw = _catalog[i];
          final live = c.productOf(raw.id) ?? raw;
          return _ProductPage(
            product: live,
            catalog: _catalog,
            pageIndex: i,
            pageCount: _catalog.length,
            onOpenSimilar: _goToProduct,
            onOpenCart: _openCart,
          );
        },
      ),
    );
  }
}

class _ProductPage extends StatelessWidget {
  const _ProductPage({
    required this.product,
    required this.catalog,
    required this.pageIndex,
    required this.pageCount,
    required this.onOpenSimilar,
    required this.onOpenCart,
  });

  final PlatformProduct product;
  final List<PlatformProduct> catalog;
  final int pageIndex;
  final int pageCount;
  final ValueChanged<PlatformProduct> onOpenSimilar;
  final VoidCallback onOpenCart;

  List<PlatformProduct> _similar() {
    final others =
        catalog.where((p) => p.id != product.id).toList(growable: false);
    if (others.isEmpty) return const [];

    int score(PlatformProduct o) {
      var s = 0;
      final priceDiff = (o.price - product.price).abs();
      if (product.price > 0) {
        final ratio = priceDiff / product.price;
        if (ratio <= 0.25) {
          s += 40;
        } else if (ratio <= 0.5) {
          s += 25;
        } else if (ratio <= 1.0) {
          s += 10;
        }
      }
      if (o.unit.trim().toLowerCase() == product.unit.trim().toLowerCase()) {
        s += 20;
      }
      final a = product.name.toLowerCase();
      final b = o.name.toLowerCase();
      for (final t in a.split(RegExp(r'\s+'))) {
        if (t.length >= 3 && b.contains(t)) s += 8;
      }
      s -= (o.sortOrder - product.sortOrder).abs().clamp(0, 30);
      return s;
    }

    final ranked = List<PlatformProduct>.of(others)
      ..sort((a, b) => score(b).compareTo(score(a)));
    return ranked.take(16).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlatformStoreController>();
    final out = c.isOutOfStock(product);
    final qty = c.qtyOf(product.id);
    final priceText = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(product.price),
        );
    final similar = _similar();
    final hasNext = pageIndex < pageCount - 1;
    final h = MediaQuery.sizeOf(context).height;

    return Column(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: (h * 0.34).clamp(200.0, 280.0),
                child: ColoredBox(
                  color: AvaStoreColors.soft,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PlatformImageStack(
                        urls: product.displayImages,
                        memCacheWidth: 900,
                        borderRadius: 14,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      ),
                      if (out)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.38),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                context.tr('platform_store_out_of_stock'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AvaStoreColors.ink,
                          height: 1.18,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              priceText,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AvaStoreColors.deep,
                                height: 1,
                              ),
                            ),
                          ),
                          if (product.unit.trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AvaStoreColors.soft,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AvaStoreColors.border),
                              ),
                              child: Text(
                                product.unit,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AvaStoreColors.deep,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (!out && !product.isUnlimitedStock) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${context.tr('platform_store_stock_left')}: '
                          '${product.remaining} ${product.unit}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AvaStoreColors.muted,
                          ),
                        ),
                      ],
                      if (product.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          product.description.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: Color(0xFF3A4A4A),
                          ),
                        ),
                      ],
                      if (similar.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Expanded(
                          child: _SimilarStrip(
                            items: similar,
                            onTap: onOpenSimilar,
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (hasNext)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, top: 4),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AvaStoreColors.soft,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.keyboard_double_arrow_down_rounded,
                                    color: AvaStoreColors.deep
                                        .withValues(alpha: 0.8),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    context.tr('platform_store_swipe_next'),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AvaStoreColors.deep
                                          .withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _BottomActionBar(
          product: product,
          out: out,
          qty: qty,
          onOpenCart: onOpenCart,
        ),
      ],
    );
  }
}

/// Пастки CTA: Саватга | миқдор ± | Саватга ўтиш.
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.product,
    required this.out,
    required this.qty,
    required this.onOpenCart,
  });

  final PlatformProduct product;
  final bool out;
  final int qty;
  final VoidCallback onOpenCart;

  @override
  Widget build(BuildContext context) {
    final c = context.read<PlatformStoreController>();
    return Material(
      color: AvaStoreColors.surface,
      elevation: 12,
      shadowColor: AvaStoreColors.deep.withValues(alpha: 0.18),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: out
              ? SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: null,
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
                      disabledForegroundColor: AvaStoreColors.muted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      context.tr('platform_store_out_of_stock'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                )
              : qty == 0
                  ? SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          c.addToCart(product);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AvaStoreColors.brand,
                          foregroundColor: AvaStoreColors.onBrand,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: Text(
                          context.tr('platform_store_add'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: AvaStoreColors.soft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AvaStoreColors.brand,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              _QtyBtn(
                                icon: Icons.remove_rounded,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  c.decrease(product.id);
                                },
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  '$qty',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    color: AvaStoreColors.ink,
                                  ),
                                ),
                              ),
                              _QtyBtn(
                                icon: Icons.add_rounded,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  c.increase(product.id);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: onOpenCart,
                              style: FilledButton.styleFrom(
                                backgroundColor: AvaStoreColors.brand,
                                foregroundColor: AvaStoreColors.onBrand,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                context.tr('platform_store_go_cart'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvaStoreColors.brand,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 52,
          child: Icon(icon, color: AvaStoreColors.onBrand, size: 24),
        ),
      ),
    );
  }
}

class _SimilarStrip extends StatefulWidget {
  const _SimilarStrip({required this.items, required this.onTap});

  final List<PlatformProduct> items;
  final ValueChanged<PlatformProduct> onTap;

  @override
  State<_SimilarStrip> createState() => _SimilarStripState();
}

class _SimilarStripState extends State<_SimilarStrip> {
  final _scroll = ScrollController();
  bool _canScrollMore = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final more = _scroll.position.pixels < _scroll.position.maxScrollExtent - 8;
    if (more != _canScrollMore) setState(() => _canScrollMore = more);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _nudgeRight() {
    if (!_scroll.hasClients) return;
    final next = (_scroll.offset + 148).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('platform_store_similar'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AvaStoreColors.ink,
                ),
              ),
            ),
            if (_canScrollMore)
              Material(
                color: AvaStoreColors.brand,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: _nudgeRight,
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: AvaStoreColors.onBrand,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Stack(
            children: [
              ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 28, bottom: 2),
                itemCount: widget.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final p = widget.items[i];
                  return _SimilarCard(product: p, onTap: () => widget.onTap(p));
                },
              ),
              if (_canScrollMore)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 2,
                  child: IgnorePointer(
                    child: Container(
                      width: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            AvaStoreColors.scaffold.withValues(alpha: 0),
                            AvaStoreColors.scaffold,
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: AvaStoreColors.deep.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.product, required this.onTap});

  final PlatformProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final priceText = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(product.price),
        );
    return Material(
      color: AvaStoreColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          width: 112,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AvaStoreColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: ColoredBox(
                  color: AvaStoreColors.soft,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: _Thumb(url: product.coverImageUrl),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                            color: AvaStoreColors.ink,
                          ),
                        ),
                      ),
                      Text(
                        priceText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AvaStoreColors.deep,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    if (u.startsWith('assets/')) {
      return Image.asset(u, fit: BoxFit.contain);
    }
    if (u.isNotEmpty && isHttpImageUrl(u)) {
      return CachedNetworkImage(
        imageUrl: u,
        fit: BoxFit.contain,
        memCacheWidth: 280,
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AvaStoreColors.deep,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => const Icon(
          Icons.shopping_bag_outlined,
          size: 22,
          color: AvaStoreColors.muted,
        ),
      );
    }
    if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) return Image.memory(bytes, fit: BoxFit.contain);
    }
    return const Icon(
      Icons.shopping_bag_outlined,
      size: 22,
      color: AvaStoreColors.muted,
    );
  }
}

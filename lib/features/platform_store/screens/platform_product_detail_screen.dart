import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/edge_swipe_pager.dart';
import '../../../models/platform_product.dart';
import '../controllers/platform_store_controller.dart';
import '../widgets/platform_cart_sheet.dart';
import '../widgets/platform_image_gallery.dart';
import '../widgets/platform_image_stack.dart';

/// Шу экраннинг қора ранглари (эга қарори, 2026-10-17: қора мавзу ФАҚАТ
/// маҳсулот тафсилотида). Номлар аввалги `AvaStoreColors` билан бир хил —
/// фақат қиймати қора палитрадан ([PdDark]). Саватча варағи (ёруғ) ва
/// бошқа виджетлар `AvaStoreColors`да қолади.
abstract final class _S {
  static const brand = PdDark.brand;
  static const onBrand = PdDark.brandInk;
  static const soft = PdDark.surface;
  static const deep = PdDark.brand;
  static const scaffold = PdDark.bg;
  static const ink = PdDark.ink;
  static const muted = PdDark.muted;
  static const surface = PdDark.surface;
  static const border = PdDark.line;

  /// Акцент матн/белги (аввал `AppColors.primaryText` — ёруғ фондаги қўнғир).
  static const accent = PdDark.brand;
}

/// AVA маҳсулоти тафсилоти (Улгуржи бозор): қора дизайн; маълумот
/// ТУГАГАНДАН кейин юқорига суринг = кейинги, тепада пастга = олдинги.
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
  late List<PlatformProduct> _catalog;
  late int _index;

  /// Ўхшаш картадан ўтилганда ном пульси учун.
  String? _pulseProductId;
  int _pulseEpoch = 0;

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
  }

  /// Ўхшаш танланса — оралиқ саҳифаларсиз жорий ўринда алмаштириш (crossfade).
  void _goToProduct(PlatformProduct p) {
    final i = _catalog.indexWhere((x) => x.id == p.id);
    if (i < 0 || i == _index) return;
    HapticFeedback.mediumImpact();
    setState(() {
      final current = _catalog[_index];
      _catalog[i] = current;
      _catalog[_index] = p;
      _pulseProductId = p.id;
      _pulseEpoch++;
    });
  }

  Future<void> _openCart() async {
    final c = context.read<PlatformStoreController>();
    if (c.cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('platform_store_cart_empty'),
            style: const TextStyle(color: AppColors.onPrimary),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _S.deep,
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

    return ProductDetailDark(
      child: Scaffold(
        backgroundColor: _S.scaffold,
        appBar: AppBar(
          // «AVA дўкони» эмас — AVA товари Улгуржи бозорнинг бир қисми
          // (эга қарори 2026-10-07).
          title: Text(
            context.tr('wholesale_title'),
            style: const TextStyle(
              color: _S.ink,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: 0.15,
            ),
          ),
          backgroundColor: _S.scaffold,
          foregroundColor: _S.ink,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                onPressed: _openCart,
                icon: Badge(
                  isLabelVisible: c.cartItemCount > 0,
                  backgroundColor: _S.brand,
                  label: Text(
                    '${c.cartItemCount}',
                    style: const TextStyle(
                      color: _S.onBrand,
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
        body: EdgeSwipePager(
          itemCount: _catalog.length,
          initialIndex: _index,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) {
            final raw = _catalog[i];
            final live = c.productOf(raw.id) ?? raw;
            return _ProductPage(
              product: live,
              catalog: _catalog,
              pageIndex: i,
              pageCount: _catalog.length,
              pulseEpoch: live.id == _pulseProductId ? _pulseEpoch : 0,
              onOpenSimilar: _goToProduct,
              onOpenCart: _openCart,
            );
          },
        ),
      ),
    );
  }
}

class _ProductPage extends StatefulWidget {
  const _ProductPage({
    required this.product,
    required this.catalog,
    required this.pageIndex,
    required this.pageCount,
    required this.pulseEpoch,
    required this.onOpenSimilar,
    required this.onOpenCart,
  });

  final PlatformProduct product;
  final List<PlatformProduct> catalog;
  final int pageIndex;
  final int pageCount;

  /// Ўхшашдан ўтилганда >0 — ном бир марта пульс қилади.
  final int pulseEpoch;
  final ValueChanged<PlatformProduct> onOpenSimilar;
  final VoidCallback onOpenCart;

  @override
  State<_ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<_ProductPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.035), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.035, end: 1), weight: 60),
    ]).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOutCubic));
    if (widget.pulseEpoch > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runPulse());
    }
  }

  @override
  void didUpdateWidget(covariant _ProductPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulseEpoch > 0 && widget.pulseEpoch != oldWidget.pulseEpoch) {
      _runPulse();
    }
  }

  void _runPulse() {
    _pulseCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  List<PlatformProduct> _similar() {
    final product = widget.product;
    final others =
        widget.catalog.where((p) => p.id != product.id).toList(growable: false);
    if (others.isEmpty) return const [];

    Set<String> tokensOf(String name) => name
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3)
        .toSet();

    final mine = tokensOf(product.name);
    final byName = <PlatformProduct>[];
    for (final o in others) {
      if (mine.isEmpty) break;
      final theirs = tokensOf(o.name);
      if (theirs.any(mine.contains)) byName.add(o);
    }

    final pool = byName.isNotEmpty ? byName : List<PlatformProduct>.of(others);
    pool.sort((a, b) {
      final byPrice = a.price.compareTo(b.price);
      if (byPrice != 0) return byPrice;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return pool.take(16).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final c = context.watch<PlatformStoreController>();
    final out = c.isOutOfStock(product);
    final qty = c.qtyOf(product.id);
    final priceText = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(product.displayPrice),
        );
    final similar = _similar();
    final hasNext = widget.pageIndex < widget.pageCount - 1;
    final h = MediaQuery.sizeOf(context).height;

    void openGallery(int index) {
      openPlatformImageGallery(
        context,
        urls: product.displayImages,
        initialIndex: index,
      );
    }

    final body = Column(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: (h * 0.34).clamp(200.0, 280.0),
                child: ColoredBox(
                  color: _S.soft,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PlatformImageStack(
                        urls: product.displayImages,
                        memCacheWidth: 900,
                        borderRadius: 14,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        onTap: openGallery,
                        onDoubleTap: openGallery,
                      ),
                      if (out)
                        IgnorePointer(
                          child: ColoredBox(
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
                      ScaleTransition(
                        scale: _pulseScale,
                        alignment: Alignment.centerLeft,
                        child: AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (context, child) {
                            final t = Curves.easeOut.transform(
                              (1 - (_pulseCtrl.value - 0.5).abs() * 2)
                                  .clamp(0.0, 1.0),
                            );
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                color: _S.brand
                                    .withValues(alpha: 0.12 * t),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: child,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: _S.ink,
                                height: 1.18,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        priceText,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _S.accent,
                          height: 1,
                        ),
                      ),
                      // Улгуржи поғоналари (2026-09-29) — жорий миқдорга
                      // мос поғона ажратиб кўрсатилади.
                      if (product.effectiveTiers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _PriceTiers(product: product, qty: qty),
                      ],
                      if (!out && !product.isUnlimitedStock) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${context.tr('platform_store_stock_left')}: '
                          '${product.remaining}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _S.muted,
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
                            color: PdDark.ink,
                          ),
                        ),
                      ],
                      if (similar.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Expanded(
                          child: _SimilarStrip(
                            // Key — маҳсулот алмашganda қатор бошга қайтади.
                            key: ValueKey('similar_${product.id}'),
                            items: similar,
                            onTap: widget.onOpenSimilar,
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
                                color: _S.soft,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.keyboard_double_arrow_up_rounded,
                                    color: _S.accent
                                        .withValues(alpha: 0.8),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    context.tr('product_swipe_next_up'),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: _S.accent
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
          onOpenCart: widget.onOpenCart,
        ),
      ],
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final offset = Tween<Offset>(
          begin: const Offset(0.03, 0),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(product.id),
        // Саҳифа скролл қилинмайди, лекин юқорига/пастга суриш ([EdgeSwipePager])
        // сезилиши учун скролл ичида ва кўринма баландликда.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: kEdgeSwipePhysics,
            child: SizedBox(height: constraints.maxHeight, child: body),
          ),
        ),
      ),
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
      color: _S.surface,
      elevation: 12,
      shadowColor: _S.deep.withValues(alpha: 0.18),
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
                      disabledBackgroundColor: PdDark.surface2,
                      disabledForegroundColor: _S.muted,
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
                          backgroundColor: _S.brand,
                          foregroundColor: _S.onBrand,
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
                            color: _S.soft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _S.accent,
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
                                    color: _S.ink,
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
                                backgroundColor: _S.brand,
                                foregroundColor: _S.onBrand,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              // Миқдор ўзгарса сумма шу ернинг ўзида ўзгаради:
                              // поғона нархи × миқдор (кўрсатиш учун; ҳақиқий
                              // нархни буюртмада сервер ҳисоблайди).
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    context.tr('platform_store_go_cart'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    context.tr('price_sum_short').replaceAll(
                                          '{price}',
                                          formatPrice(
                                            product.priceForQty(qty) * qty,
                                          ),
                                        ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
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
      color: _S.brand,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 52,
          child: Icon(icon, color: _S.onBrand, size: 24),
        ),
      ),
    );
  }
}

class _SimilarStrip extends StatefulWidget {
  const _SimilarStrip({
    super.key,
    required this.items,
    required this.onTap,
  });

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
                  color: _S.ink,
                ),
              ),
            ),
            if (_canScrollMore)
              Material(
                color: _S.brand,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: _nudgeRight,
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: _S.onBrand,
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
                  return _SimilarCard(
                    product: p,
                    onTap: () => widget.onTap(p),
                  );
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
                            _S.scaffold.withValues(alpha: 0),
                            _S.scaffold,
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: _S.accent.withValues(alpha: 0.85),
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
  const _SimilarCard({
    required this.product,
    required this.onTap,
  });

  final PlatformProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final priceText = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(product.displayPrice),
        );
    return Material(
      color: _S.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          width: 112,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _S.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: ColoredBox(
                  color: _S.soft,
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
                            color: _S.ink,
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
                          color: _S.accent,
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
              color: _S.accent,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => const Icon(
          Icons.shopping_bag_outlined,
          size: 22,
          color: _S.muted,
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
      color: _S.muted,
    );
  }
}


/// Улгуржи нарх поғоналари — харидор қанчадан бошлаб арзонлашишини
/// кўриб турсин (эга қарори, 2026-09-29).
class _PriceTiers extends StatelessWidget {
  const _PriceTiers({required this.product, required this.qty});

  final PlatformProduct product;

  /// Саватдаги жорий миқдор — қайси поғона амалдалигини белгилайди.
  final int qty;

  @override
  Widget build(BuildContext context) {
    // Амалдаги поғоналар: админ қўймаган бўлса — базадаги нархдан
    // ҳисобланган (2026-10-06).
    final tiers = product.effectiveTiers;
    if (tiers.isEmpty) return const SizedBox.shrink();
    // Амалдаги поғона — ИНДЕКС бўйича (`priceForQty` қоидаси: qty >= minQty
    // бўлган охирги поғона). Нарх бўйича солиштирилса, икки поғона нархи
    // бир хил бўлганда иккаласи ҳам «танланган» кўринар эди.
    final effectiveQty = qty <= 0 ? product.minQty : qty;
    var activeIndex = tiers.lastIndexWhere((t) => effectiveQty >= t.minQty);
    if (activeIndex < 0) activeIndex = 0;
    final c = context.read<PlatformStoreController>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _S.soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('wholesale_price_tiers'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _S.accent.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 6),
          for (final (i, t) in tiers.indexed)
            // Босилса — миқдор шу поғона бошланишига ўтади. Қолдиқ етмаган
            // поғона хира ва босилмайди.
            Builder(builder: (context) {
              final active = i == activeIndex;
              final reachable =
                  PlatformStoreController.qtyForTier(product, t.minQty) != null;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: reachable
                    ? () {
                        HapticFeedback.selectionClick();
                        c.selectTier(product, t.minQty);
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Opacity(
                    opacity: reachable ? 1 : 0.4,
                    child: Row(
                      children: [
                        Icon(
                          active
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 16,
                          color: active
                              ? _S.accent
                              : _S.accent.withValues(alpha: 0.35),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${product.tierRangeLabel(i)} ${product.unit}: '
                            '${formatPrice(t.price)} $kCurrencySum',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight:
                                  active ? FontWeight.w800 : FontWeight.w500,
                              color: _S.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

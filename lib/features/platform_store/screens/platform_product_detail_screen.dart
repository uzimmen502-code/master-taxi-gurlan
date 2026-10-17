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
import '../../../models/price_tier.dart';
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
    _catalog =
        widget.catalog.isNotEmpty ? List.of(widget.catalog) : [widget.product];
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
          formatPrice(product.priceForQty(qty > 0 ? qty : product.minQty)),
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

    // Саҳифа БИТТА экранга сиғади (қурилмада шрифт ×1.3 да ҳам, эга талаби
    // 2026-10-17): расм кичикроқ, матнлар ихчам, «ўхшашлар» шу ернинг ўзида.
    // Жуда кичик экран учун захира — скролл ва чегарада свайп.
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);
    final body = Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: kEdgeSwipePhysics,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: (h * 0.28).clamp(150.0, 240.0),
                  child: ColoredBox(
                    color: _S.soft,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PlatformImageStack(
                          urls: product.displayImages,
                          memCacheWidth: 900,
                          borderRadius: 14,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
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
                                    horizontal: 14,
                                    vertical: 6,
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
                                      fontSize: 13,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
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
                                color: _S.brand.withValues(alpha: 0.12 * t),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: child,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 1,
                            ),
                            child: Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: _S.ink,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Нарх ТАНЛАНГАН миқдор/поғонага мос ўзгаради (аввал
                      // доим энг кам миқдордаги нарх кўринарди).
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            priceText,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: _S.accent,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '/ ${product.unit}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _S.muted,
                            ),
                          ),
                          const Spacer(),
                          if (!out && !product.isUnlimitedStock)
                            Text(
                              '${context.tr('platform_store_stock_left')}: '
                              '${product.remaining}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _S.muted,
                              ),
                            ),
                        ],
                      ),
                      // Улгуржи поғоналари — босиб танланади.
                      if (product.effectiveTiers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _PriceTiers(product: product, qty: qty),
                      ],
                      if (product.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          product.description.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: _S.ink.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                      if (similar.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 104 + 26 * textScale,
                          child: _SimilarStrip(
                            // Key — маҳсулот алмашганда қатор бошга қайтади.
                            key: ValueKey('similar_${product.id}'),
                            items: similar,
                            onTap: widget.onOpenSimilar,
                          ),
                        ),
                      ],
                      if (hasNext)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.keyboard_double_arrow_up_rounded,
                                color: _S.muted,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  context.tr('product_swipe_next_up'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _S.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
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
        child: body,
      ),
    );
  }
}

/// Пастки панел (ихчам): сават бўшда — нарх + «Саватга»; сават тўлганда —
/// миқдор ± ва «Саватга ўтиш» (жами сумма билан).
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

  static const double _h = 42;

  ButtonStyle get _btn => FilledButton.styleFrom(
        backgroundColor: _S.brand,
        foregroundColor: _S.onBrand,
        minimumSize: const Size(0, _h),
        // Материал 48 пиксел босиш майдонини қўшмасин — тугма аниқ 42.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.read<PlatformStoreController>();
    final unitPrice = product.priceForQty(qty > 0 ? qty : product.minQty);
    String sum(int v) =>
        context.tr('price_sum_short').replaceAll('{price}', formatPrice(v));

    Widget content;
    if (out) {
      content = SizedBox(
        width: double.infinity,
        height: _h,
        child: FilledButton(
          onPressed: null,
          style: FilledButton.styleFrom(
            disabledBackgroundColor: PdDark.surface2,
            disabledForegroundColor: _S.muted,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            context.tr('platform_store_out_of_stock'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      );
    } else if (qty == 0) {
      content = Row(
        children: [
          // Бир қаторда («11 025 сўм / дона») — катта шрифтда ҳам тошмайди.
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: sum(unitPrice),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _S.ink,
                    ),
                  ),
                  TextSpan(
                    text: ' / ${product.unit}',
                    style: const TextStyle(fontSize: 11, color: _S.muted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () {
              HapticFeedback.mediumImpact();
              c.addToCart(product);
            },
            style: _btn,
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
            label: Text(
              context.tr('platform_store_add'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
      );
    } else {
      content = Row(
        children: [
          Container(
            height: _h,
            decoration: BoxDecoration(
              color: _S.soft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _S.accent, width: 1.2),
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
                  width: 40,
                  child: Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
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
            child: FilledButton(
              onPressed: onOpenCart,
              style: _btn.copyWith(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              // Миқдор ўзгарса сумма шу ернинг ўзида ўзгаради: поғона нархи ×
              // миқдор (кўрсатиш учун; ҳақиқий нархни буюртмада сервер ҳисоблайди).
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr('platform_store_go_cart'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    sum(unitPrice * qty),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Material(
      color: _S.surface,
      elevation: 8,
      shadowColor: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: content,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 38,
        height: _BottomActionBar._h,
        child: Icon(icon, color: _S.accent, size: 20),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('platform_store_similar'),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _S.ink,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Stack(
            children: [
              ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 24),
                itemCount: widget.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 24,
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
                        size: 20,
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
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          width: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
                    padding: const EdgeInsets.all(5),
                    child: _Thumb(url: product.coverImageUrl),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(7, 4, 7, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
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
                          fontSize: 10.5,
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

/// Улгуржи нарх поғоналари — ихчам «чип»лар: босилса миқдор шу поғона
/// бошланишига ўтади, нарх ва сумма шу ернинг ўзида мос ўзгаради. Қолдиқ
/// етмаган поғона хира ва босилмайди.
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
    final activeIndex = activeTierIndex(tiers, qty <= 0 ? product.minQty : qty);
    final c = context.read<PlatformStoreController>();
    const gap = 6.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('wholesale_price_tiers'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _S.muted,
          ),
        ),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (context, cons) {
            final n = tiers.length;
            final w = ((cons.maxWidth - gap * (n - 1)) / n)
                .clamp(84.0, cons.maxWidth);
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (i, t) in tiers.indexed)
                  SizedBox(
                    width: w,
                    child: _TierChip(
                      label: '${tierRangeText(tiers, i)} ${product.unit}',
                      price: '${formatPrice(t.price)} $kCurrencySum',
                      active: i == activeIndex,
                      reachable: PlatformStoreController.qtyForTier(
                              product, t.minQty) !=
                          null,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        c.selectTier(product, t.minQty);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({
    required this.label,
    required this.price,
    required this.active,
    required this.reachable,
    required this.onTap,
  });

  final String label;
  final String price;
  final bool active;
  final bool reachable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: reachable ? 1 : 0.4,
      child: Material(
        color: active ? PdDark.brandSoft : _S.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: reachable ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _S.accent : _S.border,
                width: active ? 1.4 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: _S.ink.withValues(alpha: active ? 1 : 0.75),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: active ? _S.accent : _S.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

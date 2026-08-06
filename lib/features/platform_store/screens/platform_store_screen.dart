import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import '../ava_store_colors.dart';
import '../controllers/platform_store_controller.dart';
import '../widgets/platform_cart_sheet.dart';
import '../widgets/platform_product_card.dart';

/// AVA дўкони — каталог + қидирув + сават + миқдор.
class PlatformStoreScreen extends StatelessWidget {
  const PlatformStoreScreen({super.key, this.highlightProductId});

  final String? highlightProductId;

  static const brand = AvaStoreColors.brand;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final c = PlatformStoreController();
        unawaited(c.init());
        return c;
      },
      child: _PlatformStoreView(highlightProductId: highlightProductId),
    );
  }
}

class _PlatformStoreView extends StatefulWidget {
  const _PlatformStoreView({this.highlightProductId});

  final String? highlightProductId;

  @override
  State<_PlatformStoreView> createState() => _PlatformStoreViewState();
}

class _PlatformStoreViewState extends State<_PlatformStoreView> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  /// '' | food | non_food
  String _kindFilter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCart(BuildContext context) async {
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

  List<PlatformProduct> _filtered(List<PlatformProduct> all) {
    final q = _query;
    var list = all.where((p) {
      if (_kindFilter == PlatformProduct.kindFood && !p.isFood) return false;
      if (_kindFilter == PlatformProduct.kindNonFood && !p.isNonFood) {
        return false;
      }
      return CatalogSearch.matchesProduct(p, q);
    }).toList();
    if (CatalogSearch.normalize(q).isNotEmpty) {
      list.sort((a, b) {
        final byScore = CatalogSearch.scoreProduct(b, q)
            .compareTo(CatalogSearch.scoreProduct(a, q));
        if (byScore != 0) return byScore;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    } else {
      final highlightId = widget.highlightProductId;
      if (highlightId != null) {
        final idx = list.indexWhere((p) => p.id == highlightId);
        if (idx > 0) {
          final item = list.removeAt(idx);
          list.insert(0, item);
        }
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlatformStoreController>();
    final bottomPad = c.cartItemCount > 0 ? 88.0 : 24.0;

    return Scaffold(
      backgroundColor: AvaStoreColors.scaffold,
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            style: const TextStyle(
              color: AvaStoreColors.onBrand,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 0.2,
            ),
            children: [
              const TextSpan(text: BrandLabels.brand),
              TextSpan(
                text: ' ${context.tr('platform_store_title_suffix')}',
              ),
            ],
          ),
        ),
        backgroundColor: AvaStoreColors.brand,
        foregroundColor: AvaStoreColors.onBrand,
        elevation: 0,
        actions: [
          _PulsingCartButton(
            count: c.cartItemCount,
            onPressed: () => _openCart(context),
          ),
        ],
      ),
      body: c.loading
          ? const Center(
              child: CircularProgressIndicator(color: AvaStoreColors.deep),
            )
          : c.products.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: 48,
                          color: AvaStoreColors.deep.withValues(alpha: 0.55),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr('platform_store_empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AvaStoreColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _query = v),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AvaStoreColors.ink,
                        ),
                        decoration: InputDecoration(
                          hintText: context.tr('platform_store_search_hint'),
                          hintStyle: const TextStyle(
                            color: AvaStoreColors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: AvaStoreColors.deep,
                          ),
                          suffixIcon: _query.trim().isEmpty
                              ? null
                              : IconButton(
                                  tooltip: context
                                      .tr('platform_store_search_clear'),
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    color: AvaStoreColors.muted,
                                  ),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          filled: true,
                          fillColor: AvaStoreColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AvaStoreColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AvaStoreColors.deep,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _KindChip(
                              label: context.tr('platform_store_kind_all'),
                              selected: _kindFilter.isEmpty,
                              onTap: () => setState(() => _kindFilter = ''),
                            ),
                            const SizedBox(width: 8),
                            _KindChip(
                              label: context.tr('platform_store_kind_food'),
                              selected:
                                  _kindFilter == PlatformProduct.kindFood,
                              onTap: () => setState(
                                () => _kindFilter = PlatformProduct.kindFood,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _KindChip(
                              label:
                                  context.tr('platform_store_kind_non_food'),
                              selected: _kindFilter ==
                                  PlatformProduct.kindNonFood,
                              onTap: () => setState(
                                () => _kindFilter =
                                    PlatformProduct.kindNonFood,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final items = _filtered(c.products);
                          if (items.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Text(
                                  context
                                      .tr('platform_store_search_none')
                                      .replaceAll('{query}', _query.trim()),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AvaStoreColors.muted,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(18, 10, 18, 2),
                                child: Text(
                                  CatalogSearch.normalize(_query).isEmpty
                                      ? context
                                          .tr('platform_store_search_total')
                                          .replaceAll(
                                            '{count}',
                                            '${c.products.length}',
                                          )
                                      : context
                                          .tr('platform_store_search_found')
                                          .replaceAll(
                                            '{found}',
                                            '${items.length}',
                                          )
                                          .replaceAll(
                                            '{total}',
                                            '${c.products.length}',
                                          ),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AvaStoreColors.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: RefreshIndicator(
                                  color: AvaStoreColors.deep,
                                  onRefresh: c.refresh,
                                  child: GridView.builder(
                                    padding: EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      bottomPad,
                                    ),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 0.62,
                                    ),
                                    itemCount: items.length,
                                    itemBuilder: (context, i) =>
                                        PlatformProductCard(
                                      product: items[i],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: c.cartItemCount == 0
          ? null
          : _CartCheckoutBar(
              itemCount: c.cartItemCount,
              totalLabel: context.tr('price_sum_short').replaceAll(
                    '{price}',
                    formatPrice(c.grandTotal),
                  ),
              onPressed: () => _openCart(context),
            ),
    );
  }
}

class _CartCheckoutBar extends StatelessWidget {
  const _CartCheckoutBar({
    required this.itemCount,
    required this.totalLabel,
    required this.onPressed,
  });

  final int itemCount;
  final String totalLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvaStoreColors.surface,
      elevation: 14,
      shadowColor: AvaStoreColors.deep.withValues(alpha: 0.2),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AvaStoreColors.brand,
                foregroundColor: AvaStoreColors.onBrand,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AvaStoreColors.onBrand.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$itemCount',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('platform_store_go_cart'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    totalLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AvaStoreColors.brand : AvaStoreColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AvaStoreColors.deep : AvaStoreColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: selected ? AvaStoreColors.onBrand : AvaStoreColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingCartButton extends StatefulWidget {
  const _PulsingCartButton({
    required this.count,
    required this.onPressed,
  });

  final int count;
  final VoidCallback onPressed;

  @override
  State<_PulsingCartButton> createState() => _PulsingCartButtonState();
}

class _PulsingCartButtonState extends State<_PulsingCartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: widget.onPressed,
      icon: ScaleTransition(
        scale: _scale,
        child: Badge(
          isLabelVisible: widget.count > 0,
          backgroundColor: AvaStoreColors.onBrand,
          label: Text(
            '${widget.count}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: AvaStoreColors.brand,
            ),
          ),
          child: const Icon(
            Icons.shopping_cart_rounded,
            color: AvaStoreColors.onBrand,
            size: 28,
          ),
        ),
      ),
    );
  }
}

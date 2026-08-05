import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import '../controllers/platform_store_controller.dart';
import '../widgets/platform_cart_sheet.dart';
import '../widgets/platform_product_card.dart';

/// Платформа дўкони — каталог + қидирув + сават + миқдор.
class PlatformStoreScreen extends StatelessWidget {
  const PlatformStoreScreen({super.key, this.highlightProductId});

  /// Очилганда шу id'ли маҳсулот рўйхат бошида кўринади (қидирувсиз ҳолатда).
  final String? highlightProductId;

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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCart(BuildContext context) async {
    final c = context.read<PlatformStoreController>();
    if (c.cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('platform_store_cart_empty'))),
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
    var list = all.where((p) => CatalogSearch.matchesProduct(p, q)).toList();
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

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F7),
      appBar: AppBar(
        title: Text(context.tr('platform_store_title')),
        backgroundColor: AppColors.button,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _openCart(context),
            icon: Badge(
              isLabelVisible: c.cartItemCount > 0,
              label: Text('${c.cartItemCount}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
        ],
      ),
      floatingActionButton: c.cartItemCount == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openCart(context),
              backgroundColor: AppColors.button,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.shopping_bag_outlined),
              label: Text(
                context.tr('price_sum_short').replaceAll(
                      '{price}',
                      formatPrice(c.cartTotal),
                    ),
              ),
            ),
      body: c.loading
          ? const Center(child: CircularProgressIndicator())
          : c.products.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.tr('platform_store_empty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: context.tr('platform_store_search_hint'),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.trim().isEmpty
                              ? null
                              : IconButton(
                                  tooltip: context.tr('platform_store_search_clear'),
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
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
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  context
                                      .tr('platform_store_search_none')
                                      .replaceAll('{query}', _query.trim()),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                                          .replaceAll('{found}', '${items.length}')
                                          .replaceAll(
                                            '{total}',
                                            '${c.products.length}',
                                          ),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: RefreshIndicator(
                                  onRefresh: c.refresh,
                                  child: GridView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      88,
                                    ),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                      childAspectRatio: 0.68,
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
    );
  }
}

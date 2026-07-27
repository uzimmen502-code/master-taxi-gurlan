import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../controllers/platform_store_controller.dart';
import '../widgets/platform_cart_sheet.dart';
import '../widgets/platform_product_card.dart';

/// Платформа дўкони — каталог + сават + миқдор.
class PlatformStoreScreen extends StatelessWidget {
  const PlatformStoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final c = PlatformStoreController();
        unawaited(c.init());
        return c;
      },
      child: const _PlatformStoreView(),
    );
  }
}

class _PlatformStoreView extends StatelessWidget {
  const _PlatformStoreView();

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
              : RefreshIndicator(
                  onRefresh: c.refresh,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.68,
                    ),
                    itemCount: c.products.length,
                    itemBuilder: (context, i) => PlatformProductCard(
                      product: c.products[i],
                    ),
                  ),
                ),
    );
  }
}

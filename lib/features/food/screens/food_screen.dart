import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../controllers/food_controller.dart';
import '../widgets/food_cart_sheet.dart';
import '../widgets/product_card.dart';

class FoodScreen extends StatelessWidget {
  const FoodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final c = FoodController(
          ordersRepo: ctx.read<OrdersRepository>(),
          inventoryRepo: ctx.read<InventoryRepository>(),
        );
        unawaited(c.init());
        return c;
      },
      child: const _FoodView(),
    );
  }
}

class _FoodView extends StatefulWidget {
  const _FoodView();

  @override
  State<_FoodView> createState() => _FoodViewState();
}

class _FoodViewState extends State<_FoodView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<FoodController>();
      if (c.hasInternet && c.pendingCount > 0) {
        c.flushPendingOrders();
      }
    });
  }

  static String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Future<void> _showCart(BuildContext context) async {
    final c = context.read<FoodController>();
    final loc = AppLocalizations.of(context)!;
    if (c.cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(loc.translate('cart_empty')),
          duration: const Duration(seconds: 1)));
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider<FoodController>.value(
        value: c,
        child: const FoodCartSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<FoodController>();

    final localizedCategories = <String, String>{
      'Барчаси': loc.translate('all_categories'),
      'Асосий': loc.translate('main_dishes'),
      'Товуқ': loc.translate('chicken'),
      'Балиқ': loc.translate('fish'),
      'Шўрва': loc.translate('soups'),
      'Ичимликлар': loc.translate('drinks'),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.translate('food_order')),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (c.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    loc
                        .translate('bread_pending_count')
                        .replaceAll('{n}', c.pendingCount.toString()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: c.categoryKeys.map((cat) {
                  final isSelected = c.selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => c.selectCategory(cat),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.green : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? Colors.green : Colors.grey[300]!,
                        ),
                      ),
                      child: Text(
                        localizedCategories[cat] ?? cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final products = c.filteredProducts;
                if (constraints.maxWidth >= 700) {
                  final horizontalPad =
                      (constraints.maxWidth * 0.05).clamp(18.0, 56.0);
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                        horizontalPad, 16, horizontalPad, 96),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 330,
                      mainAxisExtent: 340,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: products.length,
                    itemBuilder: (_, index) => ProductCard(
                      product: products[index],
                      controller: c,
                      grid: true,
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                  itemCount: products.length,
                  itemBuilder: (_, index) => ProductCard(
                    product: products[index],
                    controller: c,
                  ),
                );
              },
            ),
          ),
        ],
      ),
          if (!c.hasInternet)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          loc.translate('bread_offline_banner'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (c.pendingCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            loc
                                .translate('bread_pending_count')
                                .replaceAll('{n}', c.pendingCount.toString()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: c.cartItemCount > 0
          ? FloatingActionButton.extended(
              onPressed: () => _showCart(context),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.shopping_basket),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text('${c.cartItemCount}',
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
              label: Text(
                '${_formatPrice(c.cartTotal)} ${loc.translate("sum")}',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

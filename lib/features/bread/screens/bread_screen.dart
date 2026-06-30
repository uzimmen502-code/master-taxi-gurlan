import 'package:flutter/material.dart';

import 'package:provider/provider.dart';



import '../../../l10n/app_localizations.dart';

import '../../../repositories/bread_repository.dart';

import '../../../repositories/inventory_repository.dart';

import '../../../repositories/orders_repository.dart';

import '../../../core/theme/app_theme.dart';

import '../controllers/bread_controller.dart';

import '../widgets/bread_cart_sheet.dart';

import '../widgets/bread_extra_product_card.dart';

import '../widgets/bread_product_card.dart';



/// Нон буюртма экрани — `Provider` орқали [BreadController].

class BreadScreen extends StatelessWidget {

  const BreadScreen({super.key});



  @override

  Widget build(BuildContext context) {

    return ChangeNotifierProvider(

      create: (ctx) => BreadController(

        breadRepo: ctx.read<BreadRepository>(),

        ordersRepo: ctx.read<OrdersRepository>(),

        inventoryRepo: ctx.read<InventoryRepository>(),

      ),

      child: const _BreadView(),

    );

  }

}



class _BreadView extends StatefulWidget {

  const _BreadView();



  @override

  State<_BreadView> createState() => _BreadViewState();

}



class _BreadViewState extends State<_BreadView> {

  @override

  void initState() {

    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {

      if (!mounted) return;

      final c = context.read<BreadController>();

      if (c.hasInternet && c.pendingCount > 0) {

        c.flushPendingOrders();

      }

    });

  }



  static const _primary = AppColors.primary;

  static const _orange = AppColors.primary;



  void _showCart(BuildContext context) {

    final loc = AppLocalizations.of(context)!;

    final c = context.read<BreadController>();

    if (!c.hasCartItems) {

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(

        content: Text(loc.translate('bread_snack_cart_empty')),

        backgroundColor: AppColors.button,

        behavior: SnackBarBehavior.floating,

        shape:

            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),

      ));

      return;

    }

    showModalBottomSheet(

      context: context,

      isScrollControlled: true,

      backgroundColor: Colors.transparent,

      builder: (_) => ChangeNotifierProvider<BreadController>.value(

        value: c,

        child: const BreadCartSheet(),

      ),

    );

  }



  String _cartSummary(BreadController c) {

    final parts = <String>[];

    c.cart.forEach((id, count) {

      try {

        final p = c.allProducts.firstWhere((p) => p.id == id);

        parts.add('${p.name} × $count');

      } catch (_) {}

    });

    for (final p in c.extraProducts) {

      final q = c.extraProductsCart[p.id] ?? 0;

      if (q > 1e-9) parts.add('${p.name} × ${p.qtyCaptionNum(q)}');

    }

    return parts.join(', ');

  }



  @override

  Widget build(BuildContext context) {

    final loc = AppLocalizations.of(context)!;

    final c = context.watch<BreadController>();

    return Scaffold(

      backgroundColor: AppColors.moduleBg,

      body: Stack(children: [

        c.isLoading

            ? const Center(child: CircularProgressIndicator(color: _primary))

            : CustomScrollView(slivers: [

                SliverAppBar(

                  pinned: true,

                  expandedHeight: 56,

                  backgroundColor: AppColors.primary,

                  foregroundColor: Colors.white,

                  flexibleSpace: FlexibleSpaceBar(

                    title: Text(

                      loc.translate('bread_title'),

                      style: const TextStyle(

                        fontSize: AppText.titleMedium,

                        fontWeight: FontWeight.bold,

                        color: Colors.white,

                        shadows: [

                          Shadow(color: Colors.black54, blurRadius: 4),

                        ],

                      ),

                    ),

                    background: Container(

                      decoration: const BoxDecoration(

                        gradient: LinearGradient(

                          colors: [AppColors.primaryMid, AppColors.primary],

                          begin: Alignment.topLeft,

                          end: Alignment.bottomRight,

                        ),

                      ),

                    ),

                  ),

                ),

                _sectionHeader(loc.translate('bread_section_yopish')),

                _productGrid(c.yopishProducts, c),

                _sectionHeader(loc.translate('bread_section_ready')),

                _productGrid(c.readyProducts, c),

                _sectionHeader(loc.translate('bread_section_wedding')),

                _productGrid(c.toyProducts, c),

                _sectionHeader(loc.translate('bread_section_extras')),

                SliverPadding(

                  padding: const EdgeInsets.symmetric(horizontal: 12),

                  sliver: SliverList(

                    delegate: SliverChildBuilderDelegate(

                      (_, i) {

                        final p = c.extraProducts[i];

                        final count = c.extraProductsCart[p.id] ?? 0.0;

                        return BreadExtraProductCard(

                          product: p,

                          count: count,

                          onAdd: () => c.bumpExtraQty(p.id, 1),

                          onOpenCart: () => _showCart(context),

                        );

                      },

                      childCount: c.extraProducts.length,

                    ),

                  ),

                ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),

              ]),

        if (!c.hasInternet)

          Positioned(

            top: 0,

            left: 0,

            right: 0,

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

                        blurRadius: 8),

                  ],

                ),

                child: Row(children: [

                  const Icon(Icons.wifi_off, color: Colors.white, size: 18),

                  const SizedBox(width: 10),

                  Expanded(

                    child: Text(

                      loc.translate('bread_offline_banner'),

                      style: const TextStyle(

                          color: Colors.white,

                          fontSize: 12,

                          fontWeight: FontWeight.w500),

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

                              fontWeight: FontWeight.bold)),

                    ),

                ]),

              ),

            ),

          ),

        if (c.cartCount > 0)

          Positioned(

            bottom: 16,

            left: 16,

            right: 16,

            child: SafeArea(

              child: GestureDetector(

                onTap: () => _showCart(context),

                child: Container(

                  padding: const EdgeInsets.symmetric(

                      horizontal: 20, vertical: 14),

                  decoration: BoxDecoration(

                    gradient: const LinearGradient(

                        colors: [AppColors.primaryMid, AppColors.button]),

                    borderRadius: BorderRadius.circular(16),

                    boxShadow: [

                      BoxShadow(

                          color: _primary.withValues(alpha: 0.4),

                          blurRadius: 10,

                          offset: const Offset(0, 4)),

                    ],

                  ),

                  child: Row(children: [

                    Expanded(

                      child: Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            Text(_cartSummary(c),

                                style: const TextStyle(

                                    fontSize: AppText.bodyMedium,

                                    color: Colors.white70),

                                maxLines: 1,

                                overflow: TextOverflow.ellipsis),

                            Text(loc.translate('bread_view_cart'),

                                style: const TextStyle(

                                    fontSize: AppText.bodySmall,

                                    color: Colors.white60)),

                          ]),

                    ),

                    Container(

                      padding: const EdgeInsets.symmetric(

                          horizontal: 12, vertical: 6),

                      decoration: BoxDecoration(

                          color: Colors.white.withValues(alpha: 0.2),

                          borderRadius: BorderRadius.circular(10)),

                      child: Text(

                          loc

                              .translate('bread_cart_items_count')

                              .replaceAll('{n}', c.cartCount.toString()),

                          style: const TextStyle(

                              fontSize: AppText.titleMedium,

                              fontWeight: FontWeight.bold,

                              color: Colors.white)),

                    ),

                  ]),

                ),

              ),

            ),

          ),

      ]),

    );

  }



  SliverToBoxAdapter _sectionHeader(String title) => SliverToBoxAdapter(

        child: Padding(

          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),

          child: Row(children: [

            Container(

                width: 4,

                height: 18,

                decoration: BoxDecoration(

                    color: _orange,

                    borderRadius: BorderRadius.circular(2))),

            const SizedBox(width: 8),

            Text(title,

                style: const TextStyle(

                    fontSize: AppText.titleSmall,

                    fontWeight: FontWeight.bold)),

          ]),

        ),

      );



  SliverPadding _productGrid(List items, BreadController c) => SliverPadding(

        padding: const EdgeInsets.symmetric(horizontal: 12),

        sliver: SliverGrid(

          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(

            crossAxisCount: 2,

            mainAxisSpacing: 10,

            crossAxisSpacing: 10,

            childAspectRatio: 0.72,

          ),

          delegate: SliverChildBuilderDelegate(

            (_, i) {

              final p = items[i];

              final count = c.cart[p.id] ?? 0;

              return BreadProductCard(

                product: p,

                count: count,

                price: c.productPrice(p),

                onAdd: () => c.addProductToCart(p.id),

                onIncrement: () => c.incrementProduct(p.id),

                onDecrement: () => c.decrementProduct(p.id),

              );

            },

            childCount: items.length,

          ),

        ),

      );

}



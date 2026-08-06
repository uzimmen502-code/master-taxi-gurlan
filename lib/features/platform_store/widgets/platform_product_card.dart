import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import '../ava_store_colors.dart';
import '../controllers/platform_store_controller.dart';
import '../screens/platform_product_detail_screen.dart';
import 'platform_image_stack.dart';

class PlatformProductCard extends StatelessWidget {
  const PlatformProductCard({super.key, required this.product});

  final PlatformProduct product;

  void _openDetail(BuildContext context) {
    final catalog = context.read<PlatformStoreController>().products;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => ChangeNotifierProvider.value(
          value: context.read<PlatformStoreController>(),
          child: PlatformProductDetailScreen(
            product: product,
            catalog: catalog,
          ),
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 280),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlatformStoreController>();
    final qty = c.qtyOf(product.id);
    final out = c.isOutOfStock(product);
    final priceText = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(product.price),
        );

    return Material(
      color: AvaStoreColors.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AvaStoreColors.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: AvaStoreColors.deep.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 58,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AvaStoreColors.soft),
                    PlatformImageStack(
                      urls: product.displayImages,
                      memCacheWidth: 600,
                      borderRadius: 10,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    ),
                    if (out)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: 0.42),
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              context.tr('platform_store_out_of_stock'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 42,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: AvaStoreColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        priceText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AvaStoreColors.deep,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (out)
                        const SizedBox(height: 34)
                      else if (qty == 0)
                        SizedBox(
                          width: double.infinity,
                          height: 34,
                          child: FilledButton(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              c.addToCart(product);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AvaStoreColors.brand,
                              foregroundColor: AvaStoreColors.onBrand,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              context.tr('platform_store_add'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        )
                      else
                        _MiniStepper(
                          qty: qty,
                          onMinus: () {
                            HapticFeedback.selectionClick();
                            c.decrease(product.id);
                          },
                          onPlus: () {
                            HapticFeedback.selectionClick();
                            c.increase(product.id);
                          },
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

class _MiniStepper extends StatelessWidget {
  const _MiniStepper({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
  });

  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: AvaStoreColors.soft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AvaStoreColors.brand, width: 1.2),
      ),
      child: Row(
        children: [
          _StepIcon(icon: Icons.remove_rounded, onTap: onMinus),
          Expanded(
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: AvaStoreColors.ink,
              ),
            ),
          ),
          _StepIcon(icon: Icons.add_rounded, onTap: onPlus),
        ],
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvaStoreColors.brand,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: AvaStoreColors.onBrand),
        ),
      ),
    );
  }
}


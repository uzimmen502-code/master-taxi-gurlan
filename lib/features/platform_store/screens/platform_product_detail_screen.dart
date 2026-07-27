import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import '../../ads/widgets/ad_image_slider.dart';
import '../controllers/platform_store_controller.dart';

/// Онлайн бозор детал экранига ўхшаш: катта расм + тўлиқ маълумот.
class PlatformProductDetailScreen extends StatelessWidget {
  const PlatformProductDetailScreen({super.key, required this.product});

  final PlatformProduct product;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlatformStoreController>();
    final live = c.productOf(product.id) ?? product;
    final out = c.isOutOfStock(live);
    final qty = c.qtyOf(live.id);
    final priceText = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(live.price),
        );

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF1A3A20),
            flexibleSpace: FlexibleSpaceBar(
              background: AdImageSlider(
                imageUrls: live.displayImages,
                height: 300,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    live.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3A20),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    priceText,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E5C1E),
                    ),
                  ),
                  if (live.unit.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Бирлик: ${live.unit}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                  if (out) ...[
                    const SizedBox(height: 10),
                    Text(
                      context.tr('platform_store_out_of_stock'),
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else if (!live.isUnlimitedStock) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Қолдиқ: ${live.remaining} ${live.unit}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                  if (live.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Тавсиф',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      live.description.trim(),
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.45,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: out
              ? FilledButton(
                  onPressed: null,
                  child: Text(context.tr('platform_store_out_of_stock')),
                )
              : qty == 0
                  ? FilledButton.icon(
                      onPressed: () => c.addToCart(live),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.button,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('platform_store_add')),
                    )
                  : Row(
                      children: [
                        _RoundQty(
                          icon: Icons.remove,
                          onTap: () => c.decrease(live.id),
                        ),
                        Expanded(
                          child: Text(
                            '$qty ${live.unit}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        _RoundQty(
                          icon: Icons.add,
                          onTap: () => c.increase(live.id),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _RoundQty extends StatelessWidget {
  const _RoundQty({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE8F5E9),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: AppColors.button),
        ),
      ),
    );
  }
}

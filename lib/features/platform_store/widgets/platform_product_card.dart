import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import '../controllers/platform_store_controller.dart';

class PlatformProductCard extends StatelessWidget {
  const PlatformProductCard({super.key, required this.product});

  final PlatformProduct product;

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
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.cardBorderMuted, width: 0.5),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Image(url: product.imageUrl),
                    if (out)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: Center(
                          child: Text(
                            context.tr('platform_store_out_of_stock'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A3A20),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              priceText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2E5C1E),
              ),
            ),
            const SizedBox(height: 6),
            if (out)
              Text(
                context.tr('platform_store_out_of_stock'),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (qty == 0)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => c.addToCart(product),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.button,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: const Size(0, 34),
                  ),
                  child: Text(
                    context.tr('platform_store_add'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
            else
              Row(
                children: [
                  _QtyBtn(
                    icon: Icons.remove,
                    onTap: () => c.decrease(product.id),
                  ),
                  Expanded(
                    child: Text(
                      '$qty',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  _QtyBtn(
                    icon: Icons.add,
                    onTap: () => c.increase(product.id),
                  ),
                ],
              ),
          ],
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
    return SizedBox(
      width: 34,
      height: 34,
      child: Material(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Icon(icon, size: 18, color: AppColors.button),
        ),
      ),
    );
  }
}

class _Image extends StatelessWidget {
  const _Image({required this.url});

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
        fit: BoxFit.cover,
        placeholder: (_, __) => const ColoredBox(
          color: Color(0xFFE8F5E9),
          child: Center(child: Text('🛒', style: TextStyle(fontSize: 28))),
        ),
        errorWidget: (_, __, ___) => const ColoredBox(
          color: Color(0xFFE8F5E9),
          child: Center(child: Text('🛒', style: TextStyle(fontSize: 28))),
        ),
      );
    }
    if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.cover);
      }
    }
    return const ColoredBox(
      color: Color(0xFFE8F5E9),
      child: Center(child: Text('🛒', style: TextStyle(fontSize: 28))),
    );
  }
}

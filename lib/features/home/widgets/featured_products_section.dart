import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/utils/formatters.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../services/featured_products_service.dart';

/// «Улгуржи нарҳларда тавсия этамиз» — Платформа дўконидан 2×3 та маҳсулот.
class FeaturedProductsSection extends StatefulWidget {
  const FeaturedProductsSection({super.key, required this.onProductTap});

  /// Босилган маҳсулот id'сини қайтаради (Платформа дўкони шу id билан очилади).
  final void Function(String productId) onProductTap;

  @override
  State<FeaturedProductsSection> createState() =>
      _FeaturedProductsSectionState();
}

class _FeaturedProductsSectionState extends State<FeaturedProductsSection> {
  static const _titleDark = AppColors.limeDeep;
  static const _sectionMuted = AppColors.sectionMuted;

  final _service = FeaturedProductsService();
  late final Future<List<FeaturedProduct>> _future =
      _service.getFeaturedProducts();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FeaturedProduct>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }

        final items = snap.data ?? const <FeaturedProduct>[];
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              context.tr('home_featured_empty'),
              style: TextStyle(
                fontSize: 12,
                color: _sectionMuted.withValues(alpha: 0.9),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('home_featured_title'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _titleDark,
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                // Платформа дўкони (0.68) билан яқин — баннер расм тўлиқ сиғсин.
                childAspectRatio: 0.78,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _FeaturedProductCard(
                product: items[index],
                onTap: () => widget.onProductTap(items[index].id),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FeaturedProductCard extends StatelessWidget {
  const _FeaturedProductCard({
    required this.product,
    required this.onTap,
  });

  final FeaturedProduct product;
  final VoidCallback onTap;

  static const _titleDark = AppColors.limeDeep;
  static const _priceGreen = AppColors.limeEdge;
  static const _cardBorder = AppColors.cardBorderMuted;
  static const _fallbackEmoji = '🛒';
  static const _fallbackTint = Color(0xFFE8F5E9);

  @override
  Widget build(BuildContext context) {
    final priceText = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(product.price),
        );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _cardBorder, width: 0.5),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.hardEdge,
                  child: ColoredBox(
                    color: _fallbackTint,
                    child: _ProductImage(
                      imageUrl: product.imageUrl,
                      fallbackEmoji: _fallbackEmoji,
                      fallbackTint: _fallbackTint,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _titleDark,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                priceText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _priceGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({
    required this.imageUrl,
    required this.fallbackEmoji,
    required this.fallbackTint,
  });

  final String imageUrl;
  final String fallbackEmoji;
  final Color fallbackTint;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();

    // Дизайн баннерлари тўлиқ кўринсин — cover кесиб юборарди.
    if (url.startsWith('assets/')) {
      return SizedBox.expand(
        child: Image.asset(
          url,
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ),
      );
    }

    if (url.isNotEmpty && isHttpImageUrl(url)) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: 600,
        placeholder: (_, __) => Center(
          child: Text(fallbackEmoji, style: const TextStyle(fontSize: 28)),
        ),
        errorWidget: (_, __, ___) => _FallbackBox(
          emoji: fallbackEmoji,
          tint: fallbackTint,
        ),
      );
    }

    if (url.isNotEmpty && isDataImageUrl(url)) {
      final bytes = decodeDataUrlImageBytes(url);
      if (bytes != null) {
        return SizedBox.expand(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        );
      }
    }

    return _FallbackBox(emoji: fallbackEmoji, tint: fallbackTint);
  }
}

class _FallbackBox extends StatelessWidget {
  const _FallbackBox({required this.emoji, required this.tint});

  final String emoji;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: tint,
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 34)),
      ),
    );
  }
}

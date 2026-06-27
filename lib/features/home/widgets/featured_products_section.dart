import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../services/featured_products_service.dart';

/// «Tavsiya etamiz» — non, taom, bozor dan 2×3 ta mahsulot.
class FeaturedProductsSection extends StatefulWidget {
  const FeaturedProductsSection({super.key, required this.onProductTap});

  final void Function(String source) onProductTap;

  @override
  State<FeaturedProductsSection> createState() =>
      _FeaturedProductsSectionState();
}

class _FeaturedProductsSectionState extends State<FeaturedProductsSection> {
  static const _titleDark = Color(0xFF1A3A20);
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

        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Hozircha tavsiyalar yo‘q',
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
            const Text(
              'Tavsiya etamiz',
              style: TextStyle(
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
                childAspectRatio: 1.0,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _FeaturedProductCard(
                product: items[index],
                onTap: () => widget.onProductTap(items[index].source),
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

  static const _titleDark = Color(0xFF1A3A20);
  static const _priceGreen = Color(0xFF2E5C1E);
  static const _cardBorder = AppColors.cardBorderMuted;

  String get _fallbackEmoji {
    switch (product.source) {
      case 'bread':
        return '🍞';
      case 'food':
        return '🍽️';
      case 'market':
        return '🛒';
      default:
        return '📦';
    }
  }

  Color get _fallbackTint {
    switch (product.source) {
      case 'bread':
        return const Color(0xFFFFF3E0);
      case 'food':
        return const Color(0xFFFFEBEE);
      case 'market':
        return const Color(0xFFE3F2FD);
      default:
        return const Color(0xFFF5F5F5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final priceText =
        '${NumberFormat('#,###').format(product.price)} so\'m';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _cardBorder, width: 0.5),
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 88,
                  width: double.infinity,
                  child: _ProductImage(
                    imageUrl: product.imageUrl,
                    fallbackEmoji: _fallbackEmoji,
                    fallbackTint: _fallbackTint,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _titleDark,
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

    if (url.startsWith('assets/')) {
      return Image.asset(url, fit: BoxFit.contain);
    }

    if (url.isNotEmpty && isHttpImageUrl(url)) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        placeholder: (_, __) => ColoredBox(
          color: fallbackTint,
          child: Center(
            child: Text(fallbackEmoji, style: const TextStyle(fontSize: 32)),
          ),
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
        return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity);
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

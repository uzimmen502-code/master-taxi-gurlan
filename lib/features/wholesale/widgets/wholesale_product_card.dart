import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/wholesale_product.dart';

class WholesaleProductCard extends StatelessWidget {
  const WholesaleProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  final WholesaleProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.imageUrls.isEmpty
                      ? Container(
                          color: Colors.grey.shade200,
                          child:
                              const Icon(Icons.inventory_2_outlined, size: 40),
                        )
                      : Image.network(
                          product.imageUrls.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade200,
                            child:
                                const Icon(Icons.image_not_supported_outlined),
                          ),
                        ),
                  if (product.videoClipIds.isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.play_circle_fill,
                            color: Colors.white, size: 16),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: AppText.bodyMedium, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.priceLine,
                    style: const TextStyle(
                        fontSize: AppText.labelSmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'МОҚ: ${product.moq} ${product.unit}',
                    style: TextStyle(
                        fontSize: AppText.labelTiny, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.sellerCompanyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppText.labelTiny, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

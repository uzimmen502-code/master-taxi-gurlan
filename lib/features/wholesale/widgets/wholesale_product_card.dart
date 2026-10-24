import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../ads/widgets/market_grid.dart';
import '../models/wholesale_product.dart';
import '../utils/wholesale_labels.dart';

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
    final moq = context
        .tr('wholesale_moq_short')
        .replaceAll('{qty}', '${product.moq}')
        .replaceAll('{unit}', wholesaleUnitLabel(context, product.unit));
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: MarketGridMetrics.imageAspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.imageUrls.isEmpty
                      ? Container(
                          color: Colors.grey.shade200,
                          child:
                              const Icon(Icons.inventory_2_outlined, size: 40),
                        )
                      : ColoredBox(
                          color: Colors.grey.shade200,
                          child: Image.network(
                            product.imageUrls.first,
                            // contain: расм четлари қирқилмайди (ега 2026-10-19).
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(
                                  Icons.image_not_supported_outlined),
                            ),
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
            // Изоҳ — битта қатор: «МОҚ · сотувчи» (катак баландлиги шу қатор
            // сонига мослаб ҳисобланган, MarketGridMetrics).
            MarketCardText(
              title: product.title,
              price: wholesalePriceLine(context, product),
              caption: product.sellerCompanyName.isEmpty
                  ? moq
                  : '$moq · ${product.sellerCompanyName}',
            ),
          ],
        ),
      ),
    );
  }
}

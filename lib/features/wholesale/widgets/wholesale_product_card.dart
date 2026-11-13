import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../ads/widgets/market_corner_badge.dart';
import '../../ads/widgets/market_grid.dart';
import '../models/wholesale_product.dart';
import '../utils/wholesale_labels.dart';

class WholesaleProductCard extends StatelessWidget {
  const WholesaleProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onSellerTap,
    this.cornerBadge,
  });

  /// Тепа ўнгдаги бозор белгиси (Аралаш бозорда «Хитой», эга 2026-11-13).
  final String? cornerBadge;

  final WholesaleProduct product;
  final VoidCallback onTap;

  /// Сотувчи номи (карточка пастки қатори) босилса — унинг магазини
  /// (эга, 2026-11-13). `null` — номи оддий матн (магазиннинг ўзида).
  final VoidCallback? onSellerTap;

  /// Пастки «сотувчи» қаторининг босиладиган баландлиги.
  static const double sellerTapHeight = 28;

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    final tap = onSellerTap;
    if (tap == null || product.sellerCompanyName.trim().isEmpty) return card;
    return Stack(
      children: [
        card,
        Positioned(
          left: 4,
          right: 4,
          bottom: 4,
          height: sellerTapHeight,
          child: Semantics(
            button: true,
            label: product.sellerCompanyName,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: ValueKey('wholesale-card-seller-${product.id}'),
                borderRadius: BorderRadius.circular(8),
                onTap: tap,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context) {
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
                          // Кэш + кичрайтирилган декодлаш (memCacheWidth): гридда
                          // тўлиқ ҳажмли расмлар декодланмасин (лента шиддати).
                          child: CachedNetworkImage(
                            imageUrl: product.imageUrls.first,
                            // contain: расм четлари қирқилмайди (ега 2026-10-19).
                            fit: BoxFit.contain,
                            memCacheWidth: 400,
                            placeholder: (_, __) =>
                                ColoredBox(color: Colors.grey.shade200),
                            errorWidget: (_, __, ___) => Container(
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
                  if (cornerBadge != null && cornerBadge!.trim().isNotEmpty)
                    MarketCornerBadge(text: cornerBadge!),
                ],
              ),
            ),
            // Изоҳ — битта қатор: «МОҚ · сотувчи» (катак баландлиги шу қатор
            // сонига мослаб ҳисобланган, MarketGridMetrics).
            MarketCardText(
              title: product.title,
              price: wholesalePriceLine(context, product),
              // «МОҚ» олиб ташланди (эга, 2026-11-01) — фақат сотувчи.
              // Босиладиган бўлса «›» — магазинга ўтиш белгиси.
              caption: onSellerTap != null && product.sellerCompanyName.trim().isNotEmpty
                  ? '${product.sellerCompanyName} ›'
                  : product.sellerCompanyName,
            ),
          ],
        ),
      ),
    );
  }
}

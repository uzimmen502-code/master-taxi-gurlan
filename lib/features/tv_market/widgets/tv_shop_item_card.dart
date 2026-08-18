import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_shop.dart';
import 'tv_shop_photo_gallery.dart';

/// Vitrina mahsulot kartasi — roʻyxat va ochiq doʻkonda.
class TvShopItemCard extends StatelessWidget {
  const TvShopItemCard({
    super.key,
    required this.item,
    this.highlight = false,
    this.onVideo,
  });

  final TvShopItem item;
  final bool highlight;
  final VoidCallback? onVideo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: highlight ? 4 : 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlight
                ? const Color(0xFF00E676)
                : Colors.grey.shade200,
            width: highlight ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TvShopPhotoCarousel(
              urls: item.displayPhotos,
              height: 200,
              hasVideo: item.hasVideo,
              onVideo: onVideo,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (highlight)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.tr('tv_channel_from_reel'),
                          style: const TextStyle(
                            color: Color(0xFF007A3D),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (item.hasPrice) ...[
                    Text(
                      formatMoney(item.price),
                      style: const TextStyle(
                        color: Color(0xFF00A853),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    item.districtLabel,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_shop.dart';
import 'tv_shop_photo_gallery.dart';

/// Vitrina mahsulot kartasi — rasmlar, tanlash, zoom, tavsif.
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
    final kindKey = item.kind == 'service'
        ? 'tv_publish_service'
        : 'tv_publish_product';
    final desc = item.description.trim();
    return Material(
      color: Colors.white,
      elevation: highlight ? 3 : 0,
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
              height: 280,
              hasVideo: item.hasVideo,
              onVideo: onVideo,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (highlight)
                        _Chip(
                          label: context.tr('tv_channel_from_reel'),
                          fill: const Color(0xFF00E676).withValues(alpha: 0.14),
                          text: const Color(0xFF007A3D),
                        ),
                      _Chip(
                        label: context.tr(kindKey),
                        fill: Colors.grey.shade100,
                        text: Colors.grey.shade800,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      height: 1.25,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (item.hasPrice) ...[
                    Text(
                      formatMoney(item.price),
                      style: const TextStyle(
                        color: Color(0xFF00A853),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (item.districtLabel.trim().isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            item.districtLabel,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.fill,
    required this.text,
  });

  final String label;
  final Color fill;
  final Color text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

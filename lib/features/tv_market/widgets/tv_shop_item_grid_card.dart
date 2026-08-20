import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_shop.dart';
import 'tv_shop_photo_gallery.dart';

/// Очиқ дўкон / Аҳоли бозори — 2 устунли товар плиткаси.
class TvShopItemGridCard extends StatelessWidget {
  const TvShopItemGridCard({
    super.key,
    required this.item,
    this.highlight = false,
    this.showShopBadge = false,
    required this.onTap,
  });

  final TvShopItem item;
  final bool highlight;
  final bool showShopBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = item.coverPhotoUrl;
    final photos = item.displayPhotos.length;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight
                  ? const Color(0xFF00E676)
                  : const Color(0xFFE6E8EE),
              width: highlight ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    cover.isEmpty
                        ? ColoredBox(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image_outlined, size: 36),
                          )
                        : TvShopNetworkImage(url: cover, fit: BoxFit.cover),
                    if (showShopBadge)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: _Pill(
                          text: context.tr('tv_shop_mine'),
                          color: const Color(0xFF00E676),
                          fg: Colors.black,
                        ),
                      ),
                    if (photos > 1)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: _Pill(
                          text: '$photos',
                          color: Colors.black54,
                          fg: Colors.white,
                        ),
                      ),
                    if (item.hasVideo)
                      const Align(
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                      const Spacer(),
                      if (item.hasPrice)
                        Text(
                          formatMoney(item.price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF00A853),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
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

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.color,
    required this.fg,
  });

  final String text;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

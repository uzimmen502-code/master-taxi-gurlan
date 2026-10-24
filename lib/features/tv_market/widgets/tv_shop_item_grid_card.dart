import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_shop.dart';
import 'tv_shop_photo_gallery.dart';
import '../../../core/theme/app_theme.dart';
import '../../ads/widgets/market_grid.dart';

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
    // Карта кўриниши Аҳоли бозоридаги бошқа карталар (AdCard,
    // PlatformMarketCard) билан бир хил: Card, соя 2, радиус 12, расм
    // `contain` (четлари қирқилмайди, эга 2026-10-19). Ажратиб турадиган
    // ягона жой — `highlight` рамкаси.
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlight
            ? const BorderSide(color: AvaLight.ok, width: 1.6)
            : BorderSide.none,
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
                    cover.isEmpty
                        ? const ColoredBox(
                            color: AppColors.cardImageBg,
                            child: Icon(Icons.image_outlined, size: 36),
                          )
                        : ColoredBox(
                            color: AppColors.cardImageBg,
                            child: TvShopNetworkImage(
                              url: cover,
                              fit: BoxFit.contain,
                            ),
                          ),
                    if (showShopBadge)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: _Pill(
                          text: context.tr('tv_shop_mine'),
                          color: AvaLight.ok,
                          // Оқ матн яшил фонда ≈5.3:1 (қора ≈3.9:1 эди).
                          fg: Colors.white,
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
              MarketCardText(
                title: item.title,
                titleLines: 2,
                price: item.hasPrice ? formatMoney(item.price) : null,
                // Нарх ранги бошқа карталардагидек (AdCard — primaryText).
              ),
            ],
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
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

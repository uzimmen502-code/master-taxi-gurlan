import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../favorites/domain/favorite_ref.dart';
import '../../favorites/widgets/favorite_heart.dart';
import '../../ads/widgets/market_grid.dart' show DiscountPriceLine;
import '../../product_badges/product_badge.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/widgets/tv_shop_photo_gallery.dart';
import '../domain/market_taxonomy.dart';

/// Бозор рўйхати карточкаси: расм · сарлавҳа · нарх бирлиги билан («85 000 сўм / кг») · нисбий жой ·
/// битта қисқа майдонлар қатори. Расмнинг ўнг юқорисида ❤ (Танланганлар, STAGE 10).
class MarketListingCard extends StatelessWidget {
  const MarketListingCard({
    super.key,
    required this.item,
    required this.market,
    required this.locationLabel,
    required this.onTap,
  });

  final TvShopItem item;

  /// Таксономиядаги бозор (майдон номлари учун); `null` — майдонлар қатори йўқ.
  final MarketDef? market;
  final String locationLabel;
  final VoidCallback onTap;

  static const double photoSize = 112;

  @override
  Widget build(BuildContext context) {
    final lang = context.contentLang;
    final price = item.priceLabel(context.tr);
    final m = market;
    final attrsLine = m == null ? '' : marketAttrsLine(m, m.autoCategory ?? item.category, item.attrs, lang);
    final cover = item.coverPhotoUrl;
    return Card(
      key: ValueKey('market_card_${item.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: photoSize,
              height: photoSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: AppColors.cardImageBg,
                    child: cover.isEmpty
                        ? const Icon(Icons.image_outlined, size: 32)
                        : TvShopNetworkImage(url: cover, fit: BoxFit.cover),
                  ),
                  // Белги (эга 2026-11-19): тепа чап, битта.
                  ProductBadgeOverlay(data: item.badge, top: 4, left: 4),
                  // ❤ Танланганлар (STAGE 10, эга 2026-11-15) — олдиндан ажратилган жойда.
                  Positioned(
                    top: 4,
                    right: 4,
                    child: SizedBox(
                      key: ValueKey('market_card_fav_slot_${item.id}'),
                      width: 32,
                      height: 32,
                      child: FavoriteHeart(favorite: FavoriteRef.fromShopItem(item)),
                    ),
                  ),
                  if (item.imported == true)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                        child: Text(context.tr('market_imported'),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    if (price.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      if (item.badge.strikePrice(DateTime.now()) case final old?)
                        DiscountPriceLine(price: price, oldPrice: old, fontSize: 15)
                      else
                        Text(price,
                            key: ValueKey('market_card_price_${item.id}'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryText)),
                    ],
                    if (attrsLine.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(attrsLine,
                          key: ValueKey('market_card_attrs_${item.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    ],
                    if (locationLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.place_outlined, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(locationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

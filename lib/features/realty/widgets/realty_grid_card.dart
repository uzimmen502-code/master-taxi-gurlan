import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../ads/widgets/market_corner_badge.dart';
import '../../ads/widgets/market_grid.dart';
import '../../favorites/domain/favorite_ref.dart';
import '../../favorites/widgets/favorite_heart.dart';
import 'realty_field_labels.dart';

/// Нарх қатори битим тури билан: «450 000 000 сўм · сотиш» / «3 000 000 · ижара» (8-босқич, эга 2026-11-15).
/// Нарх матни бўш бўлса — фақат битим тури.
String realtyPriceWithDeal(String Function(String key) tr, RealtyListing r) {
  final deal = tr(r.deal == RealtyDeal.rent ? 'realty_deal_rent' : 'realty_deal_sale').toLowerCase();
  final price = r.priceText.trim();
  return price.isEmpty ? deal : '$price · $deal';
}

/// Аралаш бозор тўридаги Уй-жой эълони (8-босқич): тепа ўнгда «Уй-жой» белгиси, пастки чапда НИСБИЙ жой
/// (фақат туман/вилоят — аниқ манзил кўрсатилмайди, у пуллик ахборот).
class RealtyGridCard extends StatelessWidget {
  const RealtyGridCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.locationLabel = '',
  });

  final RealtyListing listing;
  final VoidCallback onTap;
  final String locationLabel;

  @override
  Widget build(BuildContext context) {
    final cover = listing.imageUrls.isEmpty ? '' : listing.imageUrls.first;
    return Card(
      key: ValueKey('aralash_realty_${listing.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          child: Icon(Icons.apartment_outlined, size: 36),
                        )
                      : ColoredBox(
                          color: AppColors.cardImageBg,
                          child: CachedNetworkImage(
                            imageUrl: cover,
                            fit: BoxFit.contain,
                            memCacheWidth: 400,
                            errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported_outlined),
                          ),
                        ),
                  MarketCornerBadge(text: context.tr('aralash_badge_realty')),
                  MarketLocationPill(text: locationLabel),
                  FavoriteHeartOverlay(favorite: FavoriteRef.fromRealty(listing)),
                ],
              ),
            ),
            MarketCardText(
              title: listing.titleOrText,
              price: realtyPriceWithDeal(context.tr, listing),
              caption: realtyCardSpecs(context.tr, listing),
            ),
          ],
        ),
      ),
    );
  }
}

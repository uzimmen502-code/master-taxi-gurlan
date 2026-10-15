import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/utils/formatters.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/ad_model.dart';
import '../screens/ad_details_screen.dart';
import '../screens/ad_swipe_screen.dart';
import 'market_grid.dart';

/// Grid tile for cheap product listing.
class AdCard extends StatelessWidget {
  const AdCard({super.key, required this.ad, this.catalog = const []});

  final AdModel ad;

  /// Лентадаги қолган эълонлар — тафсилотда суриб ўтиш учун
  /// (АВА дўконидаги андоза, эга қарори 2026-09-29). Бўш бўлса
  /// одатдагидек биттагина эълон очилади.
  final List<AdModel> catalog;

  void _open(BuildContext context) {
    final i = catalog.indexWhere((e) => e.id == ad.id);
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => i < 0
            ? AdDetailsScreen(ad: ad)
            : AdSwipeScreen(ads: catalog, initialIndex: i),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = ad.imageUrls.isNotEmpty ? ad.imageUrls.first : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: GestureDetector(
        onTap: () => _open(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: MarketGridMetrics.imageAspect,
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => const ColoredBox(
                        color: AppColors.cardImageBg,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => const ColoredBox(
                        color: AppColors.cardImageBg,
                        child: Icon(Icons.broken_image),
                      ),
                    )
                  : const ColoredBox(
                      color: AppColors.cardImageBg,
                      child: Center(child: Icon(Icons.image, size: 40)),
                    ),
            ),
            MarketCardText(
              title: ad.title,
              price: formatMoney(ad.price),
              caption: ad.description,
            ),
          ],
        ),
      ),
    );
  }
}

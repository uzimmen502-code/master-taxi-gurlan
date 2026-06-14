import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/ad_model.dart';
import '../screens/ad_details_screen.dart';

/// Grid tile for cheap product listing.
class AdCard extends StatelessWidget {
  const AdCard({super.key, required this.ad});

  final AdModel ad;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ad.imageUrls.isNotEmpty ? ad.imageUrls.first : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdDetailsScreen(ad: ad),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
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
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppText.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${ad.price} so\'m',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppText.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ad.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
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

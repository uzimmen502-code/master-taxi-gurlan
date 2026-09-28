import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../realty_tabs.dart';

/// Лентадаги битта объект картаси.
///
/// Чап четдаги тасма — TAB ранги, шунда лентада ҳам, харитада ҳам
/// объектнинг даражаси бир хил ранг билан ўқилади.
class RealtyCard extends StatelessWidget {
  const RealtyCard({super.key, required this.listing, required this.onTap});

  final RealtyListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final tierColor = RealtyTabs.colorFor(listing.tier);
    final specs = listing.specsLabel;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: tierColor),
              if (listing.imageUrls.isNotEmpty)
                SizedBox(
                  width: 96,
                  child: Image.network(
                    listing.imageUrls.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: c.surface2),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        listing.titleOrText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppText.bodyLarge,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      if (specs.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          specs,
                          style: TextStyle(
                            fontSize: AppText.bodySmall,
                            color: c.ink2,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (listing.priceText.isNotEmpty)
                            Expanded(
                              child: Text(
                                listing.priceText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppText.bodyMedium,
                                  fontWeight: FontWeight.w700,
                                  color: tierColor,
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          if (listing.hasVideo)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.play_circle_outline,
                                size: 18,
                                color: c.ink3,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              context.tr(
                                listing.deal == RealtyDeal.sale
                                    ? 'realty_deal_sale'
                                    : 'realty_deal_rent',
                              ),
                              style: TextStyle(
                                fontSize: AppText.labelSmall,
                                fontWeight: FontWeight.w600,
                                color: c.ink3,
                              ),
                            ),
                          ),
                        ],
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

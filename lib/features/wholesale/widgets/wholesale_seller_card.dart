import 'package:flutter/material.dart';

import '../../../core/geo/geo_name_text.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../models/wholesale_product.dart';
import '../screens/wholesale_seller_products_screen.dart';

/// Улгуржи / Хитой тафсилотидаги сотувчи карточкаси (қора дизайн):
/// сотувчи номи, ҳудуд ва «Сотувчининг барча маҳсулотлари →» тугмаси.
///
/// Тугма сотувчи ҳужжат идентификатори (`sellerId`) бўлгандагина чиқади;
/// сотувчи шу маҳсулот бозоридаги ([WholesaleProduct.market]) товарлари
/// билан очилади.
class WholesaleSellerCard extends StatelessWidget {
  const WholesaleSellerCard({super.key, required this.product});

  final WholesaleProduct product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final name = p.sellerCompanyName.trim().isEmpty
        ? context.tr('wholesale_seller_label')
        : p.sellerCompanyName.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: PdDark.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.storefront_outlined,
                size: 18, color: PdDark.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: PdDark.ink,
                ),
              ),
            ),
          ]),
          if (p.districtId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Row(children: [
                const Icon(Icons.place_outlined,
                    size: 14, color: PdDark.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: GeoDistrictText(
                    p.districtId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: PdDark.muted),
                  ),
                ),
              ]),
            ),
          ],
          if (p.sellerId.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey('wholesale_go_seller'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: PdDark.brand,
                  side: const BorderSide(color: PdDark.brand),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WholesaleSellerProductsScreen(
                      sellerId: p.sellerId,
                      sellerName: p.sellerCompanyName,
                      market: p.isChina
                          ? WholesaleProduct.marketChina
                          : WholesaleProduct.marketWholesale,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        context.tr('shop_item_seller_all'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

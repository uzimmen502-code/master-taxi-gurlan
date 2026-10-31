import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../models/wholesale_product.dart';
import '../screens/wholesale_seller_products_screen.dart';

/// Улгуржи / Хитой тафсилотида «Сотувчининг барча маҳсулотлари →» тугмаси.
/// Сотувчи ҳужжат идентификатори (`sellerId`) бўлгандагина чиқади.
class WholesaleSellerCard extends StatelessWidget {
  const WholesaleSellerCard({super.key, required this.product});

  final WholesaleProduct product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    // Сотувчи номи ва ҳудуди бу ерда кўрсатилмайди (эга, 2026-11-01): ном нарх
    // устида бор, ҳудуд товар Ўзбекистонда тургандек туюлдирарди.
    if (p.sellerId.isEmpty) return const SizedBox.shrink();
    return SizedBox(
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
    );
  }
}

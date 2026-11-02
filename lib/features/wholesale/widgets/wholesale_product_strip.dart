import 'package:flutter/material.dart';

import '../../../core/theme/product_detail_dark.dart';
import '../../../shared/widgets/product_mini_tile.dart';
import '../models/wholesale_product.dart';
import '../utils/wholesale_labels.dart';

/// Тафсилот экрани пастидаги горизонтал лента («Ўхшаш маҳсулотлар»,
/// «Сотувчининг бошқа маҳсулотлари»). Карточкада НАРХ, ўлчов ва МИНИМАЛ
/// буюртма доим кўринади: нарх «1 кг дан» билан «500 кг дан»ни бир хил
/// шартда солиштириб бўлмайди — харидор иккисини ёнма-ён кўрсин.
class WholesaleProductStrip extends StatelessWidget {
  const WholesaleProductStrip({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
  });

  final String title;
  final List<WholesaleProduct> items;
  final ValueChanged<WholesaleProduct> onTap;

  // Ўлчамлар (эга, 2026-10-31: 136 → 108 px, 226 → 178 px) — [ProductMiniTile]да;
  // Аралаш бозор тафсилотлари ҳам шу картани ишлатади (эга, 2026-11-03).

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: PdDark.ink,
            ),
          ),
        ),
        SizedBox(
          height: ProductMiniTile.stripHeight(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final p = items[i];
              return ProductMiniTile(
                palette: ProductMiniPalette.dark,
                imageUrl: p.imageUrls.isEmpty ? '' : p.imageUrls.first,
                title: p.title,
                price: wholesalePriceLine(context, p),
                // Ўхшашлар — бошқа сотувчилардан: ким сотаётгани кўринсин (эга, 2026-11-01).
                subtitle: p.sellerCompanyName,
                onTap: () => onTap(p),
              );
            },
          ),
        ),
      ],
    );
  }
}

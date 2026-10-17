import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/geo/geo_names.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../models/wholesale_product.dart';

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

  static const double _tileWidth = 136;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PdDark.ink,
            ),
          ),
        ),
        SizedBox(
          height: 226,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _Tile(
              product: items[i],
              onTap: () => onTap(items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.product, required this.onTap});

  final WholesaleProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final moq = context
        .tr('wholesale_moq_short')
        .replaceAll('{qty}', '${product.moq}')
        .replaceAll('{unit}', product.unit);
    // Сотувчи қайси ҳудудда — харидорга яқини муҳим. Эски ҳужжатда
    // `districtId` бўш: сатр умуман кўринмайди.
    final district = product.districtId.isEmpty
        ? ''
        : GeoNames.district(product.districtId, context.contentLang);
    return SizedBox(
      width: WholesaleProductStrip._tileWidth,
      child: Material(
        color: PdDark.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: product.imageUrls.isEmpty
                    ? const ColoredBox(
                        color: PdDark.surface2,
                        child: Icon(Icons.inventory_2_outlined,
                            color: PdDark.muted),
                      )
                    : CachedNetworkImage(
                        imageUrl: product.imageUrls.first,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: PdDark.surface2,
                          child: Icon(Icons.broken_image,
                              color: PdDark.muted),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PdDark.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.priceLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PdDark.brand,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      moq,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: PdDark.muted),
                    ),
                    if (district.isNotEmpty)
                      Text(
                        district,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: PdDark.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

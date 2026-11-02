import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/ava_tokens.dart';
import '../../core/theme/product_detail_dark.dart';

/// Тафсилот экранлари пастидаги «Ўхшаш маҳсулотлар» картаси — ЯГОНА манба
/// (эга, 2026-11-03: «Аралаш бозордаги ўхшашлар карта таги бўш — Улгуржидагидек
/// бўлсин»). Ўлчам ва тузилиш Улгуржиники (2026-10-31): эни 108, тўртбурчак расм,
/// остида ном · нарх · сотувчи/туман, ортиқча бўш жой йўқ. Ранглар экран мавзусидан.
class ProductMiniPalette {
  const ProductMiniPalette({
    required this.surface,
    required this.imageBg,
    required this.ink,
    required this.price,
    required this.muted,
  });

  final Color surface;
  final Color imageBg;
  final Color ink;
  final Color price;
  final Color muted;

  /// Улгуржи/Хитой тафсилоти (қора).
  static const dark = ProductMiniPalette(
    surface: PdDark.surface,
    imageBg: PdDark.surface2,
    ink: PdDark.ink,
    price: PdDark.brand,
    muted: PdDark.muted,
  );

  /// Аралаш бозор тафсилотлари (ёруғ). Нарх — `brandText` (оқда 5.6:1; `brand` матнга ярамайди).
  static const light = ProductMiniPalette(
    surface: AvaLight.surface,
    imageBg: AvaLight.surface2,
    ink: AvaLight.ink,
    price: AvaLight.brandText,
    muted: AvaLight.ink2,
  );
}

class ProductMiniTile extends StatelessWidget {
  const ProductMiniTile({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onTap,
    this.price,
    this.subtitle = '',
    this.palette = ProductMiniPalette.light,
    this.border = false,
  });

  /// Ўлчамлар (Улгуржи, эга 2026-10-31: 136 → 108 px, лента 226 → 178 px).
  static const double width = 108;

  /// Расм остидаги матн блоки (3 қатор), шрифт 1.0 да.
  static const double _textBlock = 70;

  /// Лента баландлиги: расм (эни билан тенг) + матн. Тизим шрифти катталашса
  /// матн блоки ҳам ўсади (1.6 гача) — ном/нарх қирқилмайди.
  static double stripHeight(BuildContext context) {
    final k = (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(1.0, 1.6);
    return width + _textBlock * k;
  }

  final String imageUrl;
  final String title;
  final String? price;
  final String subtitle;
  final VoidCallback onTap;
  final ProductMiniPalette palette;

  /// Ёруғ фонда карта четини ажратиш (оқ карта крем фонда).
  final bool border;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SizedBox(
      width: width,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: border ? const BorderSide(color: AvaLight.line) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ColoredBox(
                  color: p.imageBg,
                  child: imageUrl.isEmpty
                      ? Icon(Icons.inventory_2_outlined, color: p.muted)
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          // contain: расм четлари қирқилмайди (эга 2026-10-19).
                          fit: BoxFit.contain,
                          memCacheWidth: 300,
                          errorWidget: (_, __, ___) => Icon(Icons.broken_image, color: p.muted),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.15, fontWeight: FontWeight.w600, color: p.ink),
                    ),
                    if (price != null && price!.isNotEmpty)
                      Text(
                        price!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, height: 1.15, fontWeight: FontWeight.w600, color: p.price),
                      ),
                    if (subtitle.trim().isNotEmpty)
                      Text(
                        subtitle.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, height: 1.15, color: p.muted),
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

// Ресторан қатори — бош экран бўлими ва «Барчаси» рўйхати учун БИТТА
// кўриниш (§12.2): логотип · номи · ошхона тури · масофа · вақт · чиплар.
// Чегирма тэглари атайлаб ЙЎҚ (Meituan 2024 сабоғи) — фақат сифат ва
// хизмат сигналлари.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../home/widgets/ava_chip.dart';
import '../../home/widgets/ava_list_row.dart';
import '../domain/restaurant_models.dart';

/// Масофа ёрлиғи: `1.2 км` (1 км дан кам бўлса `800 м`).
String formatDistanceLabel(BuildContext context, double km) {
  if (km < 1) {
    return context
        .tr('restaurants_distance_m')
        .replaceAll('{m}', (km * 1000).round().toString());
  }
  final s = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
  return context.tr('restaurants_distance_km').replaceAll('{km}', s);
}

/// Тахминий етиб келиш: тайёрлаш + йўл (~3 дақ/км, PROPOSED). Масофа
/// номаълум бўлса фақат тайёрлаш вақти.
int estimatedMinutes(Restaurant r, double? km) =>
    r.prepTimeMin + (km == null ? 0 : (km * 3).round());

class RestaurantLogo extends StatelessWidget {
  const RestaurantLogo({super.key, required this.restaurant, this.size = 40});

  final Restaurant restaurant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final url = restaurant.logoUrl.trim();
    final initial = restaurant.name.trim().isEmpty
        ? '?'
        : restaurant.name.trim().characters.first.toUpperCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: SizedBox(
        width: size,
        height: size,
        child: url.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _Initial(initial, c),
              )
            : _Initial(initial, c),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial(this.text, this.c);

  final String text;
  final AvaColors c;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: c.brandSoft,
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: c.brandText,
            ),
          ),
        ),
      );
}

class RestaurantRow extends StatelessWidget {
  const RestaurantRow({
    super.key,
    required this.restaurant,
    this.distanceKm,
    this.onTap,
  });

  final Restaurant restaurant;
  final double? distanceKm;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final open = r.isOpenNow;
    final parts = <String>[
      if (r.cuisineTags.isNotEmpty) r.cuisineTags.take(2).join(', '),
      if (distanceKm != null) formatDistanceLabel(context, distanceKm!),
      context
          .tr('restaurants_eta')
          .replaceAll('{min}', estimatedMinutes(r, distanceKm).toString()),
    ];
    final chips = <Widget>[
      if (!open)
        AvaChip(label: context.tr('restaurants_closed'), tone: AvaChipTone.warn),
      if (r.delivery.isAvaCourier)
        AvaChip(label: context.tr('restaurants_chip_delivery'), tone: AvaChipTone.brand),
      if (r.delivery.isOwnCourier)
        AvaChip(label: context.tr('restaurants_chip_own_courier'), tone: AvaChipTone.brand),
      if (r.delivery.pickup) AvaChip(label: context.tr('restaurants_chip_pickup')),
      if (r.minOrderAmount > 0)
        AvaChip(
          label: context
              .tr('restaurants_chip_min')
              .replaceAll('{amount}', formatPrice(r.minOrderAmount)),
        ),
      if (r.isHomeCook) AvaChip(label: context.tr('restaurants_chip_home_cook')),
    ];
    return AvaListRow(
      title: r.name,
      subtitle: parts.join(' · '),
      meta: chips.take(3).toList(growable: false),
      leading: RestaurantLogo(restaurant: r),
      onTap: onTap,
    );
  }
}

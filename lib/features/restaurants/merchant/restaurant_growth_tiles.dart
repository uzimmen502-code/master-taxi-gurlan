// Ресторан панели: онлайн дўкон воситалари кафе-ресторанга (2026-10-25).
//  • «Дўкон» табида — доимий ҳавола ва QR ([RestaurantLinkTile]): дўконнинг ўша варағи (`ShopLinkSheet`),
//    ўша `getMyShopLink` (restaurantId билан), ўша `/s/<id>` саҳифаси.
//  • «Ҳисобот» табида — кўришлар статистикаси ([RestaurantViewsTile]): дўконнинг ўша экрани (`ShopStatsScreen`),
//    маълумот `restaurants/{rid}/view_stats` дан.
// Ҳар иккаласи фақат ресторан панелида (а'золар) кўринади; ҳуқуқни сервер ва rules текширади.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../business_map/data/business_repository.dart';
import '../../my_shop/screens/shop_stats_screen.dart';
import '../../my_shop/shop_stats.dart';
import '../../my_shop/widgets/shop_link_sheet.dart';
import '../data/restaurant_view_stats.dart';
import '../data/restaurants_repository.dart';
import '../domain/restaurant_models.dart';

class _PanelTile extends StatelessWidget {
  const _PanelTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AvaRadius.card),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: tileKey,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: onTap == null ? c.ink3 : c.brandText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: c.ink2)),
                    ],
                  ),
                ),
                if (onTap != null) Icon(Icons.chevron_right_rounded, color: c.ink3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Доимий ҳавола ва QR. Тасдиқланмаган (ёки тўхтатилган) ресторанда тугма ўчиқ ва сабаби ёзилади —
/// сервер ҳам бундай ресторанга ҳавола бермайди (`RESTAURANT_NOT_APPROVED`).
class RestaurantLinkTile extends StatelessWidget {
  const RestaurantLinkTile({super.key, required this.restaurant, this.loadLink});

  final Restaurant restaurant;

  /// Тест учун; бўлмаса `getMyShopLink(restaurantId)`.
  final Future<String> Function()? loadLink;

  @override
  Widget build(BuildContext context) {
    final approved = restaurant.isApproved;
    return _PanelTile(
      tileKey: const ValueKey('restaurant_link_tile'),
      icon: Icons.qr_code_2_rounded,
      title: context.tr('restaurant_link_title'),
      subtitle: context.tr(approved ? 'restaurant_link_tile_sub' : 'restaurant_link_not_approved'),
      onTap: approved
          ? () => showShopLinkSheet(
                context,
                title: restaurant.name,
                headingKey: 'restaurant_link_title',
                hintKey: 'restaurant_link_hint',
                loadLink: ({String businessId = ''}) =>
                    (loadLink ?? () => BusinessRepository().getMyShopLink(restaurantId: restaurant.id))(),
              )
          : null,
    );
  }
}

/// Кўришлар статистикаси (ресторан ва таом кўришлари, манбалар, энг кўп кўрилган таомлар).
class RestaurantViewsTile extends StatelessWidget {
  const RestaurantViewsTile({super.key, required this.restaurant, this.loadSummary, this.loadTitles});

  final Restaurant restaurant;

  /// Тест учун алмаштирилади.
  final Future<ShopStatsSummary> Function(int days)? loadSummary;
  final Future<Map<String, String>> Function()? loadTitles;

  Future<Map<String, String>> _titles() async {
    final menu = await RestaurantsRepository().watchMenu(restaurant.id).first;
    return {for (final m in menu) m.id: m.name};
  }

  @override
  Widget build(BuildContext context) {
    return _PanelTile(
      tileKey: const ValueKey('restaurant_views_tile'),
      icon: Icons.insights_rounded,
      title: context.tr('restaurant_views_title'),
      subtitle: context.tr('restaurant_views_sub'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShopStatsScreen(
            phone: '',
            labels: ShopStatsLabels.restaurant,
            loadSummary: loadSummary ?? (d) => RestaurantViewStatsRepository().fetch(restaurant.id, days: d),
            loadTitles: loadTitles ?? _titles,
          ),
        ),
      ),
    );
  }
}

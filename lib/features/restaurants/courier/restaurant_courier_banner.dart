// Курьер панелидаги «🍽 Ресторан буюртмалари» баннери (Б3) — бошқа
// баннерлар (гилам, сут) каби кириш нуқтаси. Кўриниш дарвозаси — бош
// экран бўлими билан БИР манба (`resolveRestaurantsAccess`): модул очиқ →
// ҳамма; «Тез кунда» → фақат синовчи; яширин → йўқ.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../data/restaurants_repository.dart';
import '../domain/restaurants_access.dart';
import 'restaurant_nearby_orders_screen.dart';

class RestaurantCourierBanner extends StatefulWidget {
  const RestaurantCourierBanner({
    super.key,
    required this.courierUid,
    required this.onClaimed,
    this.repository,
    this.accessCheck,
  });

  final String courierUid;

  /// Курьер буюртма олди — маршрутни қайта юклаш.
  final VoidCallback onClaimed;
  final RestaurantsRepository? repository;
  final Future<bool> Function()? accessCheck;

  @override
  State<RestaurantCourierBanner> createState() => _RestaurantCourierBannerState();
}

class _RestaurantCourierBannerState extends State<RestaurantCourierBanner> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    ServiceConfigHolder.revision.addListener(_resolve);
    _resolve();
  }

  @override
  void dispose() {
    ServiceConfigHolder.revision.removeListener(_resolve);
    super.dispose();
  }

  Future<void> _resolve() async {
    final ok = await resolveRestaurantsAccess(accessCheck: widget.accessCheck ?? _repo.hasAccess);
    if (mounted && ok != _allowed) setState(() => _allowed = ok);
  }

  Future<void> _open() async {
    final claimed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RestaurantNearbyOrdersScreen(courierUid: widget.courierUid, repository: _repo),
      ),
    );
    if (claimed == true) widget.onClaimed();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) return const SizedBox.shrink();
    return Material(
      color: AvaLight.brandSoft,
      child: InkWell(
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AvaLight.line))),
          child: Row(children: [
            const Text('🍽', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('restaurants_courier_banner'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AvaLight.brandText),
              ),
            ),
            const Icon(Icons.chevron_right, color: AvaLight.brandText),
          ]),
        ),
      ),
    );
  }
}

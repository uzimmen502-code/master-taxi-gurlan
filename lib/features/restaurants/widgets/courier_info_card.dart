// Курьер маълумоти карточкаси (S6): буюртмани олган курьернинг исми, қўнғироқ ва «Харитада кузатиш».
// Мижознинг буюртма экранида ва ресторан эгасининг буюртма карточкасида ишлатилади (битта виджет, 7-қоида).
// Фақат [CourierTracking.canTrack] бўлганда кўрсатилади — чақирувчи шуни текширади.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/order_model.dart';
import '../data/restaurants_repository.dart';
import '../screens/courier_tracking_screen.dart';

class CourierInfoCard extends StatelessWidget {
  const CourierInfoCard({super.key, required this.order, required this.repository, this.compact = false});

  final OrderModel order;
  final RestaurantsRepository repository;

  /// Ресторан панелида — ихчам (чегарасиз, паддинг кам).
  final bool compact;

  void _track(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CourierTrackingScreen(orderId: order.id, repository: repository, initial: order),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final name = order.courierName.trim().isEmpty ? context.tr('restaurants_courier_default_name') : order.courierName.trim();
    return Container(
      key: const ValueKey('courier-info'),
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: compact ? c.surface2 : c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: compact ? null : Border.all(color: c.line),
      ),
      // Икки қатор: исм + қўнғироқ; пастда тўлиқ кенгликдаги «Харитада кузатиш» (тор экран ва катта шрифтда ҳам сиғади).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.delivery_dining_rounded, color: c.brandText),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('restaurants_courier_title'), style: TextStyle(fontSize: 12, color: c.ink2)),
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('courier-call'),
                tooltip: context.tr('restaurants_track_call'),
                icon: const Icon(Icons.call_rounded),
                onPressed: (order.courierId ?? '').isEmpty ? null : () => callPhone(order.courierId!),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            key: const ValueKey('courier-track'),
            onPressed: () => _track(context),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(context.tr('restaurants_track_open')),
          ),
        ],
      ),
    );
  }
}

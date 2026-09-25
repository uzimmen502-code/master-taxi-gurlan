import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../controllers/active_orders_controller.dart';

/// Бош саҳифадаги фаол буюртма карточкаси.
///
/// Тавсиф талаби: «Фақат фаол буюртма бўлганда кўринади, акс ҳолда
/// бутунлай йўқолади» — шунинг учун [order] `null` бўлса
/// [SizedBox.shrink] қайтарилади, жой ҳам эгалланмайди.
class ActiveOrderCard extends StatelessWidget {
  const ActiveOrderCard({
    super.key,
    required this.order,
    required this.extraCount,
    required this.onTap,
  });

  final HomeActiveOrder? order;

  /// Бошқа фаол буюртмалар сони — «+1» белгиси учун.
  final int extraCount;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = order;
    if (o == null) return const SizedBox.shrink();

    final c = context.ava;
    final (icon, label, tone) = switch (o.stage) {
      ActiveOrderStage.searching => (
          Icons.search_rounded,
          context.tr('home_active_order_searching'),
          c.warn,
        ),
      ActiveOrderStage.onWay => (
          Icons.directions_car_rounded,
          context.tr('home_active_order_on_way'),
          c.brand,
        ),
      ActiveOrderStage.arrived => (
          Icons.where_to_vote_rounded,
          context.tr('home_active_order_arrived'),
          c.ok,
        ),
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        child: Container(
          constraints: const BoxConstraints(minHeight: AvaTap.minSize),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AvaRadius.card),
            border: Border.all(color: tone, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AvaRadius.card - 2),
                ),
                child: Icon(icon, size: 20, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AvaText.productName.copyWith(color: tone),
                          ),
                        ),
                        if (extraCount > 0) ...[
                          const SizedBox(width: 6),
                          _ExtraBadge(count: extraCount),
                        ],
                      ],
                    ),
                    if (o.title.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        o.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AvaText.caption.copyWith(color: c.ink2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// «+1» — яна нечта фаол буюртма борлиги.
class _ExtraBadge extends StatelessWidget {
  const _ExtraBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: BorderRadius.circular(AvaRadius.chip),
      ),
      child: Text(
        '+$count',
        style: AvaText.caption.copyWith(color: c.brand),
      ),
    );
  }
}

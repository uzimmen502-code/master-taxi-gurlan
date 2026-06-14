import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final isFood = order.type == 'food';
    final emoji = isFood ? '🍽️' : '🫓';
    final title = isFood ? 'Овқат буюртма' : 'Нон буюртма';
    final color = isFood ? AppColors.primary : AppColors.primary;

    final dt = order.createdAt;
    final dateStr =
        dt != null ? '${dt.day}-${monthNameUz(dt.month)}' : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (dateStr.isNotEmpty)
            Text(dateStr,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          const SizedBox(width: 8),
          _StatusChip(status: order.status),
        ]),
        const SizedBox(height: 8),
        ...order.items.take(3).map((it) {
          final qtyStr =
              it.qty != null ? '${it.qty.toString()} ${it.unit}' : '× ${it.count}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('• ${it.name}  $qtyStr',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          );
        }),
        if (order.items.length > 3)
          Text('... ва яна ${order.items.length - 3} та',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        const SizedBox(height: 8),
        if (order.deliveryTime.isNotEmpty)
          _BadgeBox(
            text: '🕐 Тахминий вақт: ${order.deliveryTime}',
            color: AppColors.primary,
          ),
        if (order.rejectReason.isNotEmpty)
          _BadgeBox(
            text: '❌ ${order.rejectReason}',
            color: Colors.red,
          ),
        Row(children: [
          Text(formatPrice(order.total),
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          Text(' сўм',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  static const _map = <String, ({String label, Color color})>{
    'new': (label: '🔵 Янги', color: AppColors.primary),
    'accepted': (label: '🟡 Қабул', color: AppColors.primaryMid),
    'ready': (label: '🟠 Тайёр', color: AppColors.warning),
    'delivered': (label: '🟢 Етказилди', color: AppColors.primary),
  };

  @override
  Widget build(BuildContext context) {
    final info = _map[status];
    final label = info?.label ?? status;
    final color = info?.color ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

class _BadgeBox extends StatelessWidget {
  const _BadgeBox({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

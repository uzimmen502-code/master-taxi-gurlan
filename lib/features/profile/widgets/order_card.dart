import 'package:flutter/material.dart';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    this.onCancel,
    this.cancelling = false,
  });

  final OrderModel order;
  final VoidCallback? onCancel;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final isFood = order.type == 'food';
    final isPlatform = order.type == 'platform';
    final emoji = isPlatform ? '🛒' : (isFood ? '🍽️' : '🫓');
    final title = isPlatform
        ? '${BrandLabels.brand} ${context.tr('platform_store_title_suffix')}'
        : (isFood ? 'Овқат буюртма' : 'Нон буюртма');
    final color = AppColors.primary;

    final dt = order.createdAt;
    final dateStr =
        dt != null ? '${dt.day}-${monthNameUz(dt.month)}' : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
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
          _StatusChip(
            status: order.status,
            fulfillment: order.effectiveFulfillment,
          ),
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
        if (order.balanceApplied > 0) ...[
          const SizedBox(height: 4),
          Text(
            '${context.tr('bread_wallet_will_apply').replaceAll('{amount}', formatPrice(order.balanceApplied))}'
            '${order.collectibleDue > 0 ? ' · ${context.tr('bread_wallet_cash_due').replaceAll('{amount}', formatPrice(order.collectibleDue))}' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
        Row(children: [
          Text(formatPrice(order.total),
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          Text(' сўм',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]),
        if (onCancel != null && order.canCustomerCancel) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: cancelling ? null : onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade200),
              ),
              child: cancelling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.tr('order_cancel')),
            ),
          ),
        ],
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.fulfillment = ''});
  final String status;
  final String fulfillment;

  static const _map = <String, ({String label, Color color})>{
    'new': (label: '🔵 Янги', color: AppColors.primary),
    'accepted': (label: '🟡 Қабул', color: AppColors.primaryMid),
    'ready': (label: '🟠 Тайёр', color: AppColors.warning),
    'delivered': (label: '🟢 Етказилди', color: AppColors.primary),
    'cancelled': (label: 'Бекор', color: Colors.red),
    'rejected': (label: 'Бекор', color: Colors.red),
  };

  @override
  Widget build(BuildContext context) {
    final key = (status == 'cancelled' ||
            status == 'rejected' ||
            fulfillment == 'cancelled')
        ? 'cancelled'
        : status;
    final info = _map[key];
    final label = info?.label ??
        (key == 'cancelled' ? context.tr('order_status_cancelled') : status);
    final color = info?.color ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

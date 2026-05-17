import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';

/// Тарих рўйхатидаги битта буюртма картаси.
class BreadHistoryCard extends StatelessWidget {
  const BreadHistoryCard({super.key, required this.order});

  final OrderModel order;

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted':
        return const Color(0xFFFF8F00);
      case 'ready':
        return Colors.deepOrange;
      case 'delivered':
        return const Color(0xFF2E7D32);
      case 'rejected':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'new':
        return '🔵 Янги';
      case 'accepted':
        return '🟡 Қабул';
      case 'ready':
        return '🟠 Тайёр';
      case 'delivered':
        return '🟢 Етказилди';
      case 'rejected':
        return '🔴 Рад';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(
            left: BorderSide(color: _statusColor(order.status), width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🫓', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              order.items
                  .take(2)
                  .map((i) => '${i.name} × ${i.count}')
                  .join(', '),
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor(order.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_statusLabel(order.status),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(order.status))),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.location_on_outlined,
              size: 13, color: Colors.grey.shade400),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              order.address,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${formatPrice(order.total)} сўм',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE65100)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          formatDateShort(order.createdAt),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
      ]),
    );
  }
}

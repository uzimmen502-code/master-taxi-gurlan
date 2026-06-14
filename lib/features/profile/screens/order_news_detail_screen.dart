import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/news_item.dart';
import '../../../models/order_news_group.dart';
import '../../../models/order_model.dart';
import '../../../repositories/orders_repository.dart';
import '../../../shared/widgets/order_receipt_view.dart';
import '../../../core/theme/app_theme.dart';

/// Битта буюртма: чек + барча статус хабарлари.
class OrderNewsDetailScreen extends StatelessWidget {
  const OrderNewsDetailScreen({super.key, required this.group});

  final OrderNewsGroup group;

  static const _green = AppColors.primaryDark;

  String _statusLabel(String s) {
    switch (s) {
      case 'new':
        return '🔵 Юборилди';
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

  Color _statusColor(String s) {
    switch (s) {
      case 'new':
        return Colors.blue;
      case 'accepted':
        return AppColors.primary;
      case 'ready':
        return Colors.deepOrange;
      case 'delivered':
        return _green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersRepo = context.read<OrdersRepository>();

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(group.moduleLabel),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<OrderModel?>(
        future: ordersRepo.getById(group.orderId),
        builder: (context, orderSnap) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (orderSnap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (orderSnap.data != null)
                OrderReceiptView(order: orderSnap.data!)
              else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    group.messages.isNotEmpty
                        ? group.messages.first.body
                        : 'Чек маълумоти топилмади',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Хабарлар тарихи',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              ...group.messages.map(_messageTile),
            ],
          );
        },
      ),
    );
  }

  Widget _messageTile(NewsItem n) {
    final color = _statusColor(n.orderStatus);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _statusLabel(n.orderStatus),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  _dateTime(n.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              n.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            if (n.body.isNotEmpty &&
                n.source != 'order_placed' &&
                !n.body.contains('Жами:')) ...[
              const SizedBox(height: 6),
              Text(
                n.body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _dateTime(DateTime t) {
    return '${t.day.toString().padLeft(2, '0')}.'
        '${t.month.toString().padLeft(2, '0')}.${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/courier_order.dart';
import '../../../repositories/courier_orders_repository.dart';

/// Admin — kuryer buyurtmalari monitoring (faqat o'qish).
class CourierOrdersAdminScreen extends StatefulWidget {
  const CourierOrdersAdminScreen({super.key});

  @override
  State<CourierOrdersAdminScreen> createState() =>
      _CourierOrdersAdminScreenState();
}

class _CourierOrdersAdminScreenState extends State<CourierOrdersAdminScreen> {
  static final _dateFmt = DateFormat('dd.MM.yyyy HH:mm');
  final _repo = CourierOrdersRepository();
  int _filterIndex = 0;

  static const _filters = ['Hammasi', 'Kutilmoqda', 'Faol', 'Yetkazildi'];

  bool _matchesFilter(CourierOrder order) {
    return switch (_filterIndex) {
      1 => order.status == CourierOrderStatus.pending,
      2 =>
        order.status == CourierOrderStatus.accepted ||
            order.status == CourierOrderStatus.pickedUp,
      3 => order.status == CourierOrderStatus.delivered,
      _ => true,
    };
  }

  int _displayTotal(CourierOrder order) {
    if (order.totalPrice > 0) return order.totalPrice;
    return order.estimatedPrice + order.deliveryFee;
  }

  (Color bg, Color fg) _statusColors(CourierOrderStatus status) {
    return switch (status) {
      CourierOrderStatus.pending => (Colors.orange.shade100, Colors.orange.shade900),
      CourierOrderStatus.accepted => (Colors.blue.shade100, Colors.blue.shade900),
      CourierOrderStatus.pickedUp => (Colors.purple.shade100, Colors.purple.shade900),
      CourierOrderStatus.delivered => (Colors.green.shade100, Colors.green.shade900),
      CourierOrderStatus.cancelled => (Colors.grey.shade200, Colors.grey.shade800),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            '🛵 Kuryer buyurtmalari',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            segments: List.generate(
              _filters.length,
              (i) => ButtonSegment(value: i, label: Text(_filters[i])),
            ),
            selected: {_filterIndex},
            onSelectionChanged: (s) => setState(() => _filterIndex = s.first),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<List<CourierOrder>>(
            stream: _repo.watchAll(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Xato: ${snap.error}'),
                  ),
                );
              }
              final all = snap.data ?? const [];
              final orders = all.where(_matchesFilter).toList(growable: false);
              if (orders.isEmpty) {
                return const Center(child: Text('Buyurtmalar yo\'q'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _OrderRow(
                  order: orders[i],
                  displayTotal: _displayTotal(orders[i]),
                  dateFmt: _dateFmt,
                  statusColors: _statusColors(orders[i].status),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.displayTotal,
    required this.dateFmt,
    required this.statusColors,
  });

  final CourierOrder order;
  final int displayTotal;
  final DateFormat dateFmt;
  final (Color bg, Color fg) statusColors;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = statusColors;
    final created = order.createdAt != null
        ? dateFmt.format(order.createdAt!.toLocal())
        : '—';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName.isNotEmpty
                            ? order.customerName
                            : 'Mijoz',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        order.customerPhone,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              order.description,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 6),
            Text(
              order.deliveryAddress,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  'Yetkazish: ${formatPrice(order.deliveryFee)} so\'m',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Jami: ${formatPrice(displayTotal)} so\'m',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Vaqt: $created',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (order.courierName.isNotEmpty)
                  Text(
                    'Kuryer: ${order.courierName}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

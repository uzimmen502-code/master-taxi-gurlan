import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/agro_pickup_order.dart';
import '../../../repositories/agro_pickup_orders_repository.dart';

const _accent = Color(0xFF4A6FA5);

/// Mijozning sut qabul buyurtmalari.
class MilkPickupOrdersScreen extends StatefulWidget {
  const MilkPickupOrdersScreen({super.key});

  @override
  State<MilkPickupOrdersScreen> createState() => _MilkPickupOrdersScreenState();
}

class _MilkPickupOrdersScreenState extends State<MilkPickupOrdersScreen> {
  static final _dateFmt = DateFormat('dd.MM.yyyy HH:mm');
  String? _phone;

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = phoneDigits(prefs.getString('user_phone') ?? '');
    if (mounted) setState(() => _phone = phone);
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF5),
      appBar: AppBar(
        title: Text(context.tr('milk_my_orders')),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
      ),
      body: phone == null || phone.length < 9
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<AgroPickupOrder>>(
              stream: context
                  .read<AgroPickupOrdersRepository>()
                  .watchForCustomer(phone),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final orders = (snap.data ?? const [])
                    .where((o) => o.productType == AgroPickupOrder.productMilk)
                    .toList();
                if (orders.isEmpty) {
                  return Center(
                    child: Text(
                      context.tr('milk_no_orders'),
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _OrderCard(
                    order: orders[i],
                    dateFmt: _dateFmt,
                  ),
                );
              },
            ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.dateFmt,
  });

  final AgroPickupOrder order;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    final liters = order.literCount == order.literCount.roundToDouble()
        ? '${order.literCount.toInt()}'
        : order.literCount.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$liters ${context.tr('milk_liter_suffix')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  context.tr(order.statusLabelKey()),
                  style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.pickupAddress,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          if (order.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              order.note,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
          if (order.finalPrice > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${formatPrice(order.finalPrice)} so\'m',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
          ],
          if (order.createdAt != null) ...[
            const SizedBox(height: 8),
            Text(
              dateFmt.format(order.createdAt!),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

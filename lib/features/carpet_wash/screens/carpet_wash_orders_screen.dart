import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/carpet_wash_order.dart';
import '../../../repositories/carpet_wash_orders_repository.dart';

const _accent = Color(0xFF6D4C41);

/// Mijozning gilam yuvish buyurtmalari ro'yxati.
class CarpetWashOrdersScreen extends StatefulWidget {
  const CarpetWashOrdersScreen({super.key});

  @override
  State<CarpetWashOrdersScreen> createState() => _CarpetWashOrdersScreenState();
}

class _CarpetWashOrdersScreenState extends State<CarpetWashOrdersScreen> {
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
      backgroundColor: const Color(0xFFF6FAF2),
      appBar: AppBar(
        title: Text(context.tr('carpet_my_orders')),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
      ),
      body: phone == null || phone.length < 9
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<CarpetWashOrder>>(
              stream: context
                  .read<CarpetWashOrdersRepository>()
                  .watchForCustomer(phone),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final orders = snap.data ?? const [];
                if (orders.isEmpty) {
                  return Center(
                    child: Text(
                      context.tr('carpet_no_orders'),
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

  final CarpetWashOrder order;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
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
                  '${order.carpetCount} ${context.tr('carpet_count_suffix')}',
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

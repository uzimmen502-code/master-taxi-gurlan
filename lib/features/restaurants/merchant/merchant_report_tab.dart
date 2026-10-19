// Ресторан панели — «Ҳисобот» (§12.8): бугун — буюртмалар, етказилди,
// тушум (таом), AVA ҳақи (2 %), жараёндагилар; ҳамён баланси.
// Ҳисоб — клиентда, бор буюртмалар оқимидан (100 та охиргиси).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';
import '../../../repositories/user_repository.dart';
import '../../profile/screens/wallet_screen.dart';
import '../data/restaurants_repository.dart';
import '../domain/restaurant_models.dart';
import 'merchant_order_actions.dart';

/// Бугунги кўрсаткичлар (соф, тестланади).
class MerchantDailyStats {
  const MerchantDailyStats({
    required this.orders,
    required this.delivered,
    required this.revenue,
    required this.avaFee,
    required this.active,
  });

  final int orders;
  final int delivered;
  final int revenue;
  final int avaFee;
  final int active;

  static MerchantDailyStats compute(List<OrderModel> all, DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    var orders = 0;
    var delivered = 0;
    var revenue = 0;
    var fee = 0;
    var active = 0;
    for (final o in all) {
      if (merchantBucketFor(o) != MerchantOrderBucket.history) active += 1;
      final t = o.createdAt;
      if (t == null || t.isBefore(start)) continue;
      orders += 1;
      if (o.restaurantStatus == RestaurantOrderStatus.delivered) {
        delivered += 1;
        revenue += o.foodAmount;
      }
      if (o.avaFeeCharged && !o.avaFeeRefunded) fee += o.avaFeeAmount;
    }
    return MerchantDailyStats(orders: orders, delivered: delivered, revenue: revenue, avaFee: fee, active: active);
  }
}

class MerchantReportTab extends StatefulWidget {
  const MerchantReportTab({super.key, required this.restaurant, required this.repository});

  final Restaurant restaurant;
  final RestaurantsRepository repository;

  @override
  State<MerchantReportTab> createState() => _MerchantReportTabState();
}

class _MerchantReportTabState extends State<MerchantReportTab> {
  int? _balance;
  late final Stream<List<OrderModel>> _orders = widget.repository.watchRestaurantOrders(widget.restaurant.id);

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      final u = await context.read<UserRepository>().getById(widget.restaurant.ownerUid);
      if (mounted) setState(() => _balance = u?.bonusBalance ?? 0);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return StreamBuilder<List<OrderModel>>(
      stream: _orders,
      builder: (context, snap) {
        final stats = MerchantDailyStats.compute(snap.data ?? const [], DateTime.now());
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(context.tr('restaurants_m_today'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 8),
            Row(
              children: [
                _Stat(label: context.tr('restaurants_m_r_orders'), value: '${stats.orders}'),
                const SizedBox(width: 8),
                _Stat(label: context.tr('restaurants_m_r_delivered'), value: '${stats.delivered}'),
                const SizedBox(width: 8),
                _Stat(label: context.tr('restaurants_m_r_active'), value: '${stats.active}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Stat(label: context.tr('restaurants_m_r_revenue'), value: formatPrice(stats.revenue)),
                const SizedBox(width: 8),
                _Stat(label: context.tr('restaurants_m_r_fee'), value: formatPrice(stats.avaFee)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AvaRadius.card),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined, color: c.brandText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('restaurants_wallet_balance').replaceAll('{amount}', _balance == null ? '…' : formatPrice(_balance!)),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => WalletScreen(phone: widget.restaurant.ownerUid)),
                    ),
                    child: Text(context.tr('restaurants_m_wallet_open')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(context.tr('restaurants_m_fee_hint'), style: TextStyle(fontSize: 12, color: c.ink2)),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AvaRadius.card),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.ink)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.ink2)),
          ],
        ),
      ),
    );
  }
}

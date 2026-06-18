import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/courier_order.dart';
import '../../../repositories/courier_orders_repository.dart';
import 'courier_order_detail_screen.dart';

const _bg = Color(0xFFF6FAF2);
const _cardBorder = Color(0xFFC8DDB8);
const _sectionLabel = Color(0xFF7A9070);
const _titleDark = Color(0xFF1A3A20);
const _primaryGreen = Color(0xFF2E7D32);

/// Kuryer — yangi va faol buyurtmalar ro'yxati.
class CourierOrdersListScreen extends StatefulWidget {
  const CourierOrdersListScreen({super.key});

  @override
  State<CourierOrdersListScreen> createState() =>
      _CourierOrdersListScreenState();
}

class _CourierOrdersListScreenState extends State<CourierOrdersListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _courierUid = '';
  String _courierName = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadCourierProfile();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadCourierProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _courierUid = phoneDigits(prefs.getString('user_phone') ?? '');
      _courierName = (prefs.getString('user_name') ??
              prefs.getString('userName') ??
              '')
          .trim();
    });
  }

  Future<void> _acceptOrder(CourierOrder order) async {
    if (_courierUid.length < 9) return;

    try {
      await context.read<CourierOrdersRepository>().acceptOrder(
            id: order.id,
            courierId: _courierUid,
            courierName: _courierName.isNotEmpty ? _courierName : 'Kuryer',
            totalPrice: order.estimatedPrice + order.deliveryFee,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('courier_orders_accepted_snack'))),
      );
      _tabs.animateTo(1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CourierOrdersRepository>();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _titleDark,
        elevation: 0,
        title: Text(
          context.tr('courier_orders_list_title'),
          style: const TextStyle(fontWeight: FontWeight.w600, color: _titleDark),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: _primaryGreen,
          unselectedLabelColor: _sectionLabel,
          indicatorColor: _primaryGreen,
          tabs: [
            Tab(text: context.tr('courier_orders_new_tab')),
            Tab(text: context.tr('courier_orders_my_tab')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          StreamBuilder<List<CourierOrder>>(
            stream: repo.watchPending(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('${snap.error}'));
              }
              final orders = snap.data ?? const [];
              if (orders.isEmpty) {
                return Center(
                  child: Text(
                    context.tr('courier_orders_empty_new'),
                    style: const TextStyle(color: _sectionLabel, fontSize: 15),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _OrderCard(
                  order: orders[i],
                  showAccept: true,
                  onAccept: () => _acceptOrder(orders[i]),
                  onTap: null,
                ),
              );
            },
          ),
          StreamBuilder<List<CourierOrder>>(
            stream: repo.watchForCourier(_courierUid),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('${snap.error}'));
              }
              final orders = snap.data ?? const [];
              if (orders.isEmpty) {
                return Center(
                  child: Text(
                    context.tr('courier_orders_empty_my'),
                    style: const TextStyle(color: _sectionLabel, fontSize: 15),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _OrderCard(
                  order: orders[i],
                  showAccept: false,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CourierOrderDetailScreen(
                          order: orders[i],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.showAccept,
    this.onAccept,
    this.onTap,
  });

  final CourierOrder order;
  final bool showAccept;
  final VoidCallback? onAccept;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder, width: 0.5),
      ),
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
                          : context.tr('courier_order_customer_card'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _titleDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _maskPhone(order.customerPhone),
                      style: const TextStyle(
                        fontSize: 12,
                        color: _sectionLabel,
                      ),
                    ),
                  ],
                ),
              ),
              if (!showAccept) _StatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.deliveryAddress,
            style: const TextStyle(fontSize: 13, color: _titleDark, height: 1.3),
          ),
          const SizedBox(height: 6),
          Text(
            order.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          if (order.estimatedPrice > 0) ...[
            const SizedBox(height: 6),
            Text(
              context
                  .tr('courier_order_estimated_price')
                  .replaceAll('{price}', formatPrice(order.estimatedPrice)),
              style: const TextStyle(fontSize: 12, color: _sectionLabel),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            context
                .tr('courier_order_delivery_fee')
                .replaceAll('{fee}', formatPrice(order.deliveryFee)),
            style: const TextStyle(fontSize: 12, color: _sectionLabel),
          ),
          const SizedBox(height: 4),
          Text(
            _formatCreatedAt(order.createdAt),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          if (showAccept) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(context.tr('courier_orders_accept_btn')),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final CourierOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      CourierOrderStatus.pending => (Colors.orange.shade100, Colors.orange.shade900),
      CourierOrderStatus.accepted => (Colors.blue.shade100, Colors.blue.shade900),
      CourierOrderStatus.pickedUp => (Colors.purple.shade100, Colors.purple.shade900),
      CourierOrderStatus.delivered => (Colors.green.shade100, Colors.green.shade900),
      CourierOrderStatus.cancelled => (Colors.grey.shade200, Colors.grey.shade800),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        orderStatusLabel(context, status),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

String orderStatusLabel(BuildContext context, CourierOrderStatus status) {
  return switch (status) {
    CourierOrderStatus.pending => context.tr('courier_status_waiting'),
    CourierOrderStatus.accepted => 'Qabul qilindi',
    CourierOrderStatus.pickedUp => context.tr('courier_status_en_route'),
    CourierOrderStatus.delivered => context.tr('courier_order_delivered_badge'),
    CourierOrderStatus.cancelled => 'Bekor qilindi',
  };
}

String _maskPhone(String phone) {
  final d = phoneDigits(phone);
  if (d.length < 4) return '***';
  return '***${d.substring(d.length - 4)}';
}

String _formatCreatedAt(DateTime? dt) {
  if (dt == null) return '—';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final time = DateFormat('HH:mm').format(dt);
  if (day == today) return 'bugun $time';
  if (day == today.subtract(const Duration(days: 1))) return 'kecha $time';
  return DateFormat('dd.MM HH:mm').format(dt);
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/agro_pickup_order.dart';
import '../../../repositories/agro_pickup_orders_repository.dart';
import '../../../services/agro_pickup_service.dart';

const _green = Color(0xFF2E7D32);

/// Kuryer — sut qabul (olib ketish) vazifalari.
class AgroPickupCourierScreen extends StatefulWidget {
  const AgroPickupCourierScreen({super.key});

  @override
  State<AgroPickupCourierScreen> createState() =>
      _AgroPickupCourierScreenState();
}

class _AgroPickupCourierScreenState extends State<AgroPickupCourierScreen> {
  final _service = AgroPickupService();
  String _phone = '';

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

  Future<void> _claim(AgroPickupOrder order) async {
    try {
      await _service.courierClaimPickup(
        courierPhone: _phone,
        orderId: order.id,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _markArrived(AgroPickupOrder order) async {
    try {
      await _service.courierMarkArrived(
        courierPhone: _phone,
        orderId: order.id,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _markPickedUp(AgroPickupOrder order) async {
    try {
      await _service.courierMarkPickedUp(
        courierPhone: _phone,
        orderId: order.id,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phone.length < 9) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final repo = context.read<AgroPickupOrdersRepository>();
    final uid = phoneDigits(_phone);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6FAF2),
        appBar: AppBar(
          title: Text(context.tr('agro_courier_title')),
          backgroundColor: _green,
          foregroundColor: Colors.white,
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: context.tr('agro_courier_ready_tab')),
              Tab(text: context.tr('carpet_active_tab')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReadyTab(
              stream: repo.watchByStatus(AgroPickupOrder.statusAccepted),
              emptyText: context.tr('agro_courier_no_tasks'),
              actionLabel: context.tr('agro_courier_claim'),
              onAction: _claim,
              onCall: callPhone,
            ),
            _ActiveTab(
              courierUid: uid,
              onMarkArrived: _markArrived,
              onMarkPickedUp: _markPickedUp,
              onCall: callPhone,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyTab extends StatelessWidget {
  const _ReadyTab({
    required this.stream,
    required this.emptyText,
    required this.actionLabel,
    required this.onAction,
    required this.onCall,
  });

  final Stream<List<AgroPickupOrder>> stream;
  final String emptyText;
  final String actionLabel;
  final Future<void> Function(AgroPickupOrder order) onAction;
  final Future<bool> Function(String phone) onCall;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AgroPickupOrder>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = (snap.data ?? const [])
            .where((o) => o.productType == AgroPickupOrder.productMilk)
            .toList();
        if (orders.isEmpty) {
          return Center(
            child: Text(emptyText, style: TextStyle(color: Colors.grey.shade600)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _OrderCard(
            order: orders[i],
            primaryLabel: actionLabel,
            onPrimary: () => onAction(orders[i]),
            onCall: () => onCall(orders[i].customerPhone),
          ),
        );
      },
    );
  }
}

class _ActiveTab extends StatelessWidget {
  const _ActiveTab({
    required this.courierUid,
    required this.onMarkArrived,
    required this.onMarkPickedUp,
    required this.onCall,
  });

  final String courierUid;
  final Future<void> Function(AgroPickupOrder order) onMarkArrived;
  final Future<void> Function(AgroPickupOrder order) onMarkPickedUp;
  final Future<bool> Function(String phone) onCall;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AgroPickupOrdersRepository>();
    return StreamBuilder<List<AgroPickupOrder>>(
      stream: repo.watchByStatus(AgroPickupOrder.statusPickupInDelivery),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = (snap.data ?? const [])
            .where((o) => o.pickupCourierId == courierUid)
            .toList();
        if (orders.isEmpty) {
          return Center(
            child: Text(
              context.tr('carpet_no_active_tasks'),
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final order = orders[i];
            final hasArrived = order.arrivedAt != null;
            return _OrderCard(
              order: order,
              subtitle: context.tr('agro_courier_pickup_in_progress'),
              primaryLabel: hasArrived
                  ? context.tr('agro_courier_mark_picked_up')
                  : context.tr('courier_arrived_btn'),
              onPrimary: () {
                if (hasArrived) {
                  onMarkPickedUp(order);
                } else {
                  onMarkArrived(order);
                }
              },
              onCall: () => onCall(order.customerPhone),
            );
          },
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onCall,
    this.subtitle,
  });

  final AgroPickupOrder order;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onCall;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) ...[
            Text(
              subtitle!,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            '${order.literCount.toStringAsFixed(0)} ${context.tr('milk_liter_label')}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(order.pickupAddress),
          Text('${order.customerName} · ${order.customerPhone}'),
          if (order.note.isNotEmpty) Text(order.note),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.call, size: 18),
                  label: Text(context.tr('call_short')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(primaryLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

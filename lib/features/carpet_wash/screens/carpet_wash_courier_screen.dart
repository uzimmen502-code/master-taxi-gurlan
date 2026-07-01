import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/carpet_wash_order.dart';
import '../../../repositories/carpet_wash_orders_repository.dart';
import '../../../services/carpet_wash_service.dart';

const _brown = Color(0xFF6D4C41);

/// Kuryer — gilam olib ketish / qaytarish vazifalari.
class CarpetWashCourierScreen extends StatefulWidget {
  const CarpetWashCourierScreen({super.key});

  @override
  State<CarpetWashCourierScreen> createState() =>
      _CarpetWashCourierScreenState();
}

class _CarpetWashCourierScreenState extends State<CarpetWashCourierScreen> {
  final _service = CarpetWashService();
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

  Future<void> _claimPickup(CarpetWashOrder order) async {
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

  Future<void> _markPickedUp(CarpetWashOrder order) async {
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

  Future<void> _markPickupArrived(CarpetWashOrder order) async {
    try {
      await _service.courierMarkArrived(
        courierPhone: _phone,
        orderId: order.id,
        leg: 'pickup',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _markReturnArrived(CarpetWashOrder order) async {
    try {
      await _service.courierMarkArrived(
        courierPhone: _phone,
        orderId: order.id,
        leg: 'return',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _claimReturn(CarpetWashOrder order) async {
    try {
      await _service.courierClaimReturn(
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

  Future<void> _markDelivered(CarpetWashOrder order) async {
    try {
      await _service.courierMarkDelivered(
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

    final repo = context.read<CarpetWashOrdersRepository>();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6FAF2),
        appBar: AppBar(
          title: Text(context.tr('carpet_courier_title')),
          backgroundColor: _brown,
          foregroundColor: Colors.white,
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: context.tr('carpet_pickup_tab')),
              Tab(text: context.tr('carpet_return_tab')),
              Tab(text: context.tr('carpet_active_tab')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OrdersTab(
              stream: repo.watchByStatus(CarpetWashOrder.statusPickupReady),
              emptyText: context.tr('carpet_no_pickup_tasks'),
              actionLabel: context.tr('carpet_claim_pickup'),
              onAction: _claimPickup,
              onCall: callPhone,
            ),
            _OrdersTab(
              stream: repo.watchByStatus(CarpetWashOrder.statusReturnReady),
              emptyText: context.tr('carpet_no_return_tasks'),
              actionLabel: context.tr('carpet_claim_return'),
              onAction: _claimReturn,
              onCall: callPhone,
            ),
            _ActiveCourierTab(
              courierPhone: _phone,
              onMarkPickupArrived: _markPickupArrived,
              onMarkReturnArrived: _markReturnArrived,
              onMarkPickedUp: _markPickedUp,
              onMarkDelivered: _markDelivered,
              onCall: callPhone,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  const _OrdersTab({
    required this.stream,
    required this.emptyText,
    required this.actionLabel,
    required this.onAction,
    required this.onCall,
  });

  final Stream<List<CarpetWashOrder>> stream;
  final String emptyText;
  final String actionLabel;
  final Future<void> Function(CarpetWashOrder order) onAction;
  final Future<bool> Function(String phone) onCall;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CarpetWashOrder>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snap.data ?? const [];
        if (orders.isEmpty) {
          return Center(
            child: Text(emptyText, style: TextStyle(color: Colors.grey.shade600)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final order = orders[i];
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
                  Text(
                    '${order.carpetCount} ${context.tr('carpet_count_suffix')}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
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
                          onPressed: () => onCall(order.customerPhone),
                          icon: const Icon(Icons.call, size: 18),
                          label: Text(context.tr('call_short')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => onAction(order),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brown,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(actionLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ActiveCourierTab extends StatelessWidget {
  const _ActiveCourierTab({
    required this.courierPhone,
    required this.onMarkPickupArrived,
    required this.onMarkReturnArrived,
    required this.onMarkPickedUp,
    required this.onMarkDelivered,
    required this.onCall,
  });

  final String courierPhone;
  final Future<void> Function(CarpetWashOrder order) onMarkPickupArrived;
  final Future<void> Function(CarpetWashOrder order) onMarkReturnArrived;
  final Future<void> Function(CarpetWashOrder order) onMarkPickedUp;
  final Future<void> Function(CarpetWashOrder order) onMarkDelivered;
  final Future<bool> Function(String phone) onCall;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CarpetWashOrdersRepository>();
    final uid = phoneDigits(courierPhone);
    return StreamBuilder<List<CarpetWashOrder>>(
      stream: repo.watchAll(limit: 50),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = (snap.data ?? const []).where((o) {
          if (o.status == CarpetWashOrder.statusPickupInDelivery &&
              o.pickupCourierId == uid) {
            return true;
          }
          if (o.status == CarpetWashOrder.statusReturnInDelivery &&
              o.returnCourierId == uid) {
            return true;
          }
          return false;
        }).toList();
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
            final isPickup =
                order.status == CarpetWashOrder.statusPickupInDelivery;
            final hasArrived = isPickup
                ? order.pickupArrivedAt != null
                : order.returnArrivedAt != null;
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
                  Text(
                    isPickup
                        ? context.tr('carpet_pickup_in_progress')
                        : context.tr('carpet_return_in_progress'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(order.pickupAddress),
                  Text('${order.customerName} · ${order.customerPhone}'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onCall(order.customerPhone),
                          icon: const Icon(Icons.call, size: 18),
                          label: Text(context.tr('call_short')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            if (!hasArrived) {
                              if (isPickup) {
                                onMarkPickupArrived(order);
                              } else {
                                onMarkReturnArrived(order);
                              }
                              return;
                            }
                            if (isPickup) {
                              onMarkPickedUp(order);
                            } else {
                              onMarkDelivered(order);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brown,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            !hasArrived
                                ? context.tr('courier_arrived_btn')
                                : isPickup
                                    ? context.tr('carpet_mark_picked_up')
                                    : context.tr('carpet_mark_delivered'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

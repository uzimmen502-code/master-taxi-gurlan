import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/delivery_route.dart';
import '../../../models/order_model.dart';
import '../../../repositories/delivery_routes_repository.dart';
import '../../../repositories/orders_repository.dart';

/// Admin web — kuryer reys boshqaruvi.
/// 3 tab: Tayyor buyurtmalar → Reys yaratish | Aktiv reyslar | Onlayn kuryer'lar
class CourierAdminScreen extends StatelessWidget {
  const CourierAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          title: const Text('🛵 Kuryer boshqaruvi'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Buyurtmalar'),
              Tab(text: 'Aktiv reyslar'),
              Tab(text: 'Kuryer\'lar'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OrdersTab(),
            _RoutesTab(),
            _CouriersTab(),
          ],
        ),
      ),
    );
  }
}

// ─── Tab 1: Tayyor buyurtmalar + reys yaratish ─────────────────────────────

class _OrdersTab extends StatefulWidget {
  const _OrdersTab();

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  final Set<String> _selected = {};
  bool _creating = false;
  static final _money = NumberFormat.decimalPattern('en');
  static final _date = DateFormat('dd.MM HH:mm');

  Future<void> _createRoute() async {
    if (_selected.isEmpty) return;
    setState(() => _creating = true);
    try {
      final repo = context.read<DeliveryRoutesRepository>();
      final routeId = await repo.createRoute(orderIds: _selected.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Reys yaratildi: ${routeId.substring(0, 8)}...'),
        backgroundColor: Colors.green,
      ));
      setState(() => _selected.clear());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Xato: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_selected.isNotEmpty)
          Material(
            color: const Color(0xFF1565C0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(
                    '${_selected.length} ta tanlandi',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _creating ? null : _createRoute,
                    icon: _creating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.local_shipping, size: 18),
                    label: const Text('Reys yaratish'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1565C0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<List<OrderModel>>(
            stream:
                context.read<OrdersRepository>().watchRecentOrders(limit: 100),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final orders = snap.data!
                  .where((o) => o.status == 'accepted' || o.status == 'ready')
                  .toList();
              if (orders.isEmpty) {
                return const Center(
                  child: Text(
                    'Yetkazib berish uchun buyurtma yo\'q',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: orders.length,
                itemBuilder: (_, i) {
                  final o = orders[i];
                  final selected = _selected.contains(o.id);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: selected ? Colors.blue.shade50 : null,
                    child: CheckboxListTile(
                      value: selected,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(o.id);
                        } else {
                          _selected.remove(o.id);
                        }
                      }),
                      title: Text(
                        '${_money.format(o.total)} сўм · ${o.type == 'food' ? '🍽' : '🫓'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📞 ${o.userPhone}  👤 ${o.userName}'),
                          Text('📍 ${o.address}'),
                          if (o.createdAt != null)
                            Text(
                              _date.format(o.createdAt!),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                        ],
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Tab 2: Aktiv reyslar ──────────────────────────────────────────────────

class _RoutesTab extends StatelessWidget {
  const _RoutesTab();

  static final _date = DateFormat('dd.MM HH:mm');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeliveryRoute>>(
      stream: context.read<DeliveryRoutesRepository>().watchActiveRoutes(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final routes = snap.data!;
        if (routes.isEmpty) {
          return const Center(
            child: Text('Aktiv reys yo\'q', style: TextStyle(color: Colors.grey)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: routes.length,
          itemBuilder: (_, i) {
            final r = routes[i];
            final statusColor = r.isActive ? Colors.green : Colors.orange;
            final statusText = r.isActive ? 'Aktiv' : 'Tayyor';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child: Icon(Icons.route, color: statusColor),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${r.orderIds.length} ta buyurtma',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📦 ${r.currentIndex}/${r.orderIds.length} yetkazildi'),
                    if (r.courierId.isNotEmpty) Text('🛵 Kuryer: ${r.courierId}'),
                    if (r.startedAt != null)
                      Text(
                        '⏱ Boshlandi: ${_date.format(r.startedAt!)}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Tab 3: Onlayn kuryer'lar ──────────────────────────────────────────────

class _CouriersTab extends StatelessWidget {
  const _CouriersTab();

  static final _date = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('couriers')
          .where('isOnline', isEqualTo: true)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text('Onlayn kuryer yo\'q',
                style: TextStyle(color: Colors.grey)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final updatedAt = d['updatedAt'] as Timestamp?;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE8F5E9),
                  child: Icon(Icons.delivery_dining, color: Colors.green),
                ),
                title: Text('${d['name'] ?? '—'}'),
                subtitle: Text(
                  '📞 ${d['phone'] ?? '—'}'
                  '${updatedAt != null ? '  ⏱ ${_date.format(updatedAt.toDate())}' : ''}',
                ),
                trailing: d['lat'] != null && d['lng'] != null
                    ? Text(
                        '${(d['lat'] as num).toStringAsFixed(4)},\n${(d['lng'] as num).toStringAsFixed(4)}',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/order_model.dart';
import '../../../repositories/orders_repository.dart';
import '../../../services/admin_service.dart';

/// Админ учун — `orders` навбати (ҳолатни янгилаш).
///
/// Monitoring Center икона орқали очилади; `AdminService` билан қайта текширилади.
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  static const _blue = Color(0xFF0D47A1);
  static final _money = NumberFormat.decimalPattern('en');
  static final _date = DateFormat('dd.MM HH:mm');

  bool _adminChecked = false;
  bool _isAdmin = false;
  String _filter = 'active'; // active | new | accepted | ready | delivered | all
  String? _busyOrderId;

  static const _filters = [
    ('active', 'Жараёнда'),
    ('new', 'Янги'),
    ('accepted', 'Қабул'),
    ('ready', 'Тайёр'),
    ('delivered', 'Йетказилди'),
    ('all', 'Барчаси'),
  ];

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    bool ok = false;
    try {
      ok = await context.read<AdminService>().isCurrentUserAdmin();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _isAdmin = ok;
      _adminChecked = true;
    });
    if (!ok) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('⛔ Сизда буюртмаларни бошқариш ҳуқуқи йўқ'),
          ),
        );
        Navigator.of(context).pop();
      });
    }
  }

  List<String>? _nextActions(String status) {
    switch (status) {
      case 'new':
        return const ['accepted', 'rejected'];
      case 'accepted':
        return const ['ready', 'rejected'];
      case 'ready':
        return const ['delivered'];
      default:
        return null;
    }
  }

  String _actionLabel(String s) {
    switch (s) {
      case 'accepted':
        return 'Қабул';
      case 'ready':
        return 'Тайёр';
      case 'delivered':
        return 'Йетказилди';
      case 'rejected':
        return 'Рад этиш';
      default:
        return s;
    }
  }

  bool _passesFilter(OrderModel o) {
    switch (_filter) {
      case 'active':
        return o.status == 'new' ||
            o.status == 'accepted' ||
            o.status == 'ready';
      case 'all':
        return true;
      default:
        return o.status == _filter;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'new':
        return Colors.deepOrange;
      case 'accepted':
        return Colors.blue;
      case 'ready':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.red.shade300;
      default:
        return Colors.grey;
    }
  }

  String _statusUz(String s) {
    switch (s) {
      case 'new':
        return 'Янги';
      case 'accepted':
        return 'Қабул';
      case 'ready':
        return 'Тайёр';
      case 'delivered':
        return 'Йетказилди';
      case 'rejected':
        return 'Рад этилди';
      case 'cancelled':
        return 'Бекор';
      default:
        return s;
    }
  }

  String _typeUz(String t) {
    switch (t) {
      case 'food':
        return 'Овқат';
      case 'bread':
      default:
        return 'Нон';
    }
  }

  Future<void> _applyStatus(String orderId, String next) async {
    setState(() => _busyOrderId = orderId);
    try {
      await context.read<OrdersRepository>().setOrderStatus(orderId, next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${_actionLabel(next)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Хато: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_adminChecked || !_isAdmin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text(
          '📦 Буюртмалар',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Филтр',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _filter,
                    items: [
                      for (final e in _filters)
                        DropdownMenuItem(value: e.$1, child: Text(e.$2)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _filter = v);
                    },
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<OrderModel>>(
              stream: context.read<OrdersRepository>().watchRecentOrders(limit: 100),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Хато: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list =
                    snap.data!.where(_passesFilter).toList(growable: false);
                if (list.isEmpty) {
                  return const Center(
                    child: Text(
                      'Буюртмалар йўқ',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final o = list[i];
                    return _OrderCard(
                      order: o,
                      busy: _busyOrderId == o.id,
                      next: _nextActions(o.status),
                      statusColor: _statusColor(o.status),
                      statusUz: _statusUz(o.status),
                      typeUz: _typeUz(o.type),
                      money: _money,
                      date: _date,
                      actionLabel: _actionLabel,
                      onAction: _applyStatus,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.next,
    required this.statusColor,
    required this.statusUz,
    required this.typeUz,
    required this.money,
    required this.date,
    required this.actionLabel,
    required this.onAction,
  });

  final OrderModel order;
  final bool busy;
  final List<String>? next;
  final Color statusColor;
  final String statusUz;
  final String typeUz;
  final NumberFormat money;
  final DateFormat date;
  final String Function(String) actionLabel;
  final void Function(String orderId, String next) onAction;

  @override
  Widget build(BuildContext context) {
    final itemsLine = order.items
        .map((e) => '${e.name}×${e.count}')
        .join(', ');
    final when = order.createdAt != null ? date.format(order.createdAt!) : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusUz,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  typeUz,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  when,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${money.format(order.total)} сўм',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (order.userPhone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('📞 ${order.userPhone}',
                  style: const TextStyle(fontSize: 14)),
            ],
            if (order.userName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('👤 ${order.userName}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
            ],
            if (order.address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('📍 ${order.address}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
            ],
            if (itemsLine.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                itemsLine,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
            if (next != null && next!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final s in next!)
                    FilledButton.tonal(
                      style: s == 'rejected'
                          ? FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade50,
                              foregroundColor: Colors.red.shade700,
                            )
                          : null,
                      onPressed: busy
                          ? null
                          : () => onAction(order.id, s),
                      child: Text(actionLabel(s)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

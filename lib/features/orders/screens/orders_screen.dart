import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/agro_pickup_order.dart';
import '../../../models/carpet_wash_order.dart';
import '../../../repositories/agro_pickup_orders_repository.dart';
import '../../../repositories/carpet_wash_orders_repository.dart';
import '../../../models/order_model.dart';
import '../../../repositories/orders_repository.dart';
import '../../../services/order_payment_service.dart';
import '../../profile/widgets/order_card.dart';
import '../customer_orders_hub.dart';

/// Buyurtmalar ekrani — non/taom + gilam + sut bitta ro'yxatda.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static final _dateFmt = DateFormat('dd.MM.yyyy HH:mm');

  bool _showActive = true;
  CustomerOrderKind? _typeFilter;
  String _phone = '';
  bool _phoneLoaded = false;
  late final CustomerOrdersHub _hub;
  String? _cancellingOrderId;

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hub = CustomerOrdersHub(
      orders: context.read<OrdersRepository>(),
      carpet: context.read<CarpetWashOrdersRepository>(),
      agro: context.read<AgroPickupOrdersRepository>(),
    );
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_phone') ?? '';
    if (!mounted) return;
    setState(() {
      _phone = phoneDigits(raw);
      _phoneLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final aliases = phoneAliases(_phone);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: 'Бош саҳифа',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Буюртмалар'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _SegmentToggle(
              showActive: _showActive,
              onChanged: (v) => setState(() => _showActive = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TypeChip(
                    label: 'Ҳаммаси',
                    selected: _typeFilter == null,
                    onTap: () => setState(() => _typeFilter = null),
                  ),
                  const SizedBox(width: 8),
                  _TypeChip(
                    label: 'Нон/Таом',
                    selected: _typeFilter == CustomerOrderKind.food,
                    onTap: () =>
                        setState(() => _typeFilter = CustomerOrderKind.food),
                  ),
                  const SizedBox(width: 8),
                  _TypeChip(
                    label: 'Гилам',
                    selected: _typeFilter == CustomerOrderKind.carpet,
                    onTap: () =>
                        setState(() => _typeFilter = CustomerOrderKind.carpet),
                  ),
                  const SizedBox(width: 8),
                  _TypeChip(
                    label: 'Сут',
                    selected: _typeFilter == CustomerOrderKind.milk,
                    onTap: () =>
                        setState(() => _typeFilter = CustomerOrderKind.milk),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: !_phoneLoaded
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<CustomerOrderEntry>>(
                    stream: _hub.watchUnified(
                      phoneAliases: aliases,
                      customerPhone: _phone,
                    ),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting &&
                          !snap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(child: Text('Хатолик: ${snap.error}'));
                      }
                      final all = snap.data ?? const <CustomerOrderEntry>[];
                      final filtered = all.where((e) {
                        if (_typeFilter != null && e.kind != _typeFilter) {
                          return false;
                        }
                        return _showActive ? e.isActive : !e.isActive;
                      }).toList(growable: false);

                      if (filtered.isEmpty) {
                        return _EmptyState(showActive: _showActive);
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, i) =>
                            _entryTile(context, filtered[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _entryTile(BuildContext context, CustomerOrderEntry entry) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openEntryDetail(context, entry),
      child: _entryBody(context, entry),
    );
  }

  Widget _entryBody(BuildContext context, CustomerOrderEntry entry) {
    return switch (entry.kind) {
      CustomerOrderKind.food => OrderCard(
          order: entry.food!,
          cancelling: _cancellingOrderId == entry.food!.id,
          onCancel: entry.food!.canCustomerCancel
              ? () => _cancelFoodOrder(entry.food!)
              : null,
        ),
      CustomerOrderKind.carpet =>
        _CarpetOrderTile(order: entry.carpet!, dateFmt: _dateFmt),
      CustomerOrderKind.milk =>
        _MilkOrderTile(order: entry.milk!, dateFmt: _dateFmt),
    };
  }

  Future<void> _cancelFoodOrder(OrderModel order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('order_cancel')),
        content: Text(context.tr('order_cancel_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('order_cancel')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancellingOrderId = order.id);
    try {
      await OrderPaymentService.customerCancelOrder(orderId: order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('order_cancel_ok'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(context.tr('order_cancel_fail')),
        ),
      );
    } finally {
      if (mounted) setState(() => _cancellingOrderId = null);
    }
  }

  void _openEntryDetail(BuildContext context, CustomerOrderEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: _entryBody(ctx, entry),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      checkmarkColor: AppColors.primary,
    );
  }
}

class _CarpetOrderTile extends StatelessWidget {
  const _CarpetOrderTile({required this.order, required this.dateFmt});

  static const _accent = Color(0xFF6D4C41);

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
              const Icon(Icons.local_laundry_service_outlined,
                  size: 18, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${order.carpetCount} ${context.tr('carpet_count_suffix')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              _statusBadge(context.tr(order.statusLabelKey()), _accent),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.pickupAddress,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
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

class _MilkOrderTile extends StatelessWidget {
  const _MilkOrderTile({required this.order, required this.dateFmt});

  static const _accent = Color(0xFF4A6FA5);

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
              const Icon(Icons.water_drop_outlined, size: 18, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$liters ${context.tr('milk_liter_suffix')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              _statusBadge(context.tr(order.statusLabelKey()), _accent),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.pickupAddress,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
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

Widget _statusBadge(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w600,
        fontSize: 11,
      ),
    ),
  );
}

class _SegmentToggle extends StatelessWidget {
  const _SegmentToggle({required this.showActive, required this.onChanged});

  final bool showActive;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _seg(context, label: '📌 Фаол', selected: showActive,
              onTap: () => onChanged(true)),
          _seg(context, label: '✅ Тугаган', selected: !showActive,
              onTap: () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context,
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.showActive});

  final bool showActive;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            showActive
                ? Icons.inbox_outlined
                : Icons.check_circle_outline,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            showActive
                ? 'Фаол буюртмалар йўқ'
                : 'Тугаган буюртмалар йўқ',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

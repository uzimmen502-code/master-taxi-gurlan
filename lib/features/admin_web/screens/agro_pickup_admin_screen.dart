import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/agro_pickup_order.dart';
import '../../../repositories/agro_pickup_orders_repository.dart';
import '../../../services/agro_pickup_service.dart';
import '../services/admin_auth_service.dart';

/// Admin — sut qabul buyurtmalari.
class AgroPickupAdminScreen extends StatefulWidget {
  const AgroPickupAdminScreen({super.key});

  @override
  State<AgroPickupAdminScreen> createState() => _AgroPickupAdminScreenState();
}

class _AgroPickupAdminScreenState extends State<AgroPickupAdminScreen> {
  static final _dateFmt = DateFormat('dd.MM.yyyy HH:mm');
  final _repo = AgroPickupOrdersRepository();
  final _service = AgroPickupService();
  int _filterIndex = 0;

  static const _filters = [
    'Hammasi',
    'Yangi',
    'Faol',
    'Tugagan',
  ];

  bool _matchesFilter(AgroPickupOrder order) {
    return switch (_filterIndex) {
      1 => order.status == AgroPickupOrder.statusNew,
      2 => order.isActive,
      3 =>
        order.status == AgroPickupOrder.statusCompleted ||
            order.status == AgroPickupOrder.statusCancelled,
      _ => true,
    };
  }

  String _adminPhone(BuildContext context) =>
      context.read<AdminAuthService>().phone ?? '';

  Future<void> _setStatus(
    AgroPickupOrder order,
    String status, {
    int? finalPrice,
  }) async {
    final phone = _adminPhone(context);
    if (phone.isEmpty) return;
    try {
      await _service.adminSetStatus(
        adminPhone: phone,
        orderId: order.id,
        status: status,
        finalPrice: finalPrice,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _acceptOrder(AgroPickupOrder order) async {
    final priceCtrl = TextEditingController(
      text: order.finalPrice > 0 ? '${order.finalPrice}' : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buyurtmani qabul qilish'),
        content: TextField(
          controller: priceCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Jami narx (сўм, ixtiyoriy)',
            hintText: 'Keyinroq ham belgilash mumkin',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Qabul qilish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final price = int.tryParse(
      priceCtrl.text.replaceAll(RegExp(r'[^\d]'), ''),
    );
    await _setStatus(
      order,
      AgroPickupOrder.statusAccepted,
      finalPrice: price,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            '🥛 Sut qabul',
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
          child: StreamBuilder<List<AgroPickupOrder>>(
            stream: _repo.watchByProductType(AgroPickupOrder.productMilk),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Xato: ${snap.error}'));
              }
              final orders =
                  (snap.data ?? const []).where(_matchesFilter).toList();
              if (orders.isEmpty) {
                return const Center(child: Text('Buyurtmalar yo\'q'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final order = orders[i];
                  return _OrderCard(
                    order: order,
                    dateFmt: _dateFmt,
                    onAccept: order.status == AgroPickupOrder.statusNew
                        ? () => _acceptOrder(order)
                        : null,
                    onPickedUp: order.status == AgroPickupOrder.statusAccepted
                        ? () => _setStatus(
                              order,
                              AgroPickupOrder.statusPickedUp,
                            )
                        : null,
                    onComplete: order.status == AgroPickupOrder.statusPickedUp
                        ? () => _setStatus(
                              order,
                              AgroPickupOrder.statusCompleted,
                            )
                        : null,
                    onCancel: order.isActive
                        ? () => _setStatus(
                              order,
                              AgroPickupOrder.statusCancelled,
                            )
                        : null,
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

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.dateFmt,
    this.onAccept,
    this.onPickedUp,
    this.onComplete,
    this.onCancel,
  });

  final AgroPickupOrder order;
  final DateFormat dateFmt;
  final VoidCallback? onAccept;
  final VoidCallback? onPickedUp;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final liters = order.literCount == order.literCount.roundToDouble()
        ? '${order.literCount.toInt()}'
        : order.literCount.toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$liters L — ${order.customerName.isNotEmpty ? order.customerName : order.customerPhone}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Chip(
                  label: Text(order.status, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(order.pickupAddress),
            Text('Tel: ${order.customerPhone}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            if (order.note.isNotEmpty)
              Text('Izoh: ${order.note}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            if (order.finalPrice > 0)
              Text(
                'Narx: ${formatMoney(order.finalPrice)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            if (order.createdAt != null)
              Text(
                dateFmt.format(order.createdAt!),
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (onAccept != null)
                  FilledButton(
                    onPressed: onAccept,
                    child: const Text('Qabul'),
                  ),
                if (onPickedUp != null)
                  OutlinedButton(
                    onPressed: onPickedUp,
                    child: const Text('Olib ketildi'),
                  ),
                if (onComplete != null)
                  FilledButton.tonal(
                    onPressed: onComplete,
                    child: const Text('Yakunlash'),
                  ),
                if (onCancel != null)
                  TextButton(
                    onPressed: onCancel,
                    child: const Text('Bekor'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

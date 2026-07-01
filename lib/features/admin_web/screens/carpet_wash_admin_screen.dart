import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/carpet_wash_order.dart';
import '../../../repositories/carpet_wash_orders_repository.dart';
import '../../../services/carpet_wash_service.dart';
import '../services/admin_auth_service.dart';

/// Admin — gilam yuvish buyurtmalari boshqaruvi.
class CarpetWashAdminScreen extends StatefulWidget {
  const CarpetWashAdminScreen({super.key});

  @override
  State<CarpetWashAdminScreen> createState() => _CarpetWashAdminScreenState();
}

class _CarpetWashAdminScreenState extends State<CarpetWashAdminScreen> {
  static final _dateFmt = DateFormat('dd.MM.yyyy HH:mm');
  final _repo = CarpetWashOrdersRepository();
  final _service = CarpetWashService();
  int _filterIndex = 0;

  static const _filters = [
    'Hammasi',
    'Yangi',
    'Faol',
    'Tugagan',
  ];

  bool _matchesFilter(CarpetWashOrder order) {
    return switch (_filterIndex) {
      1 => order.status == CarpetWashOrder.statusNew,
      2 => order.isActive,
      3 =>
        order.status == CarpetWashOrder.statusCompleted ||
            order.status == CarpetWashOrder.statusCancelled,
      _ => true,
    };
  }

  String _adminPhone(BuildContext context) =>
      context.read<AdminAuthService>().phone ?? '';

  Future<void> _setStatus(
    CarpetWashOrder order,
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

  Future<void> _acceptOrder(CarpetWashOrder order) async {
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
            labelText: 'Narx (so\'m, ixtiyoriy)',
            hintText: 'Admin keyin ham qo\'yishi mumkin',
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
      CarpetWashOrder.statusAccepted,
      finalPrice: price,
    );
    await _setStatus(order, CarpetWashOrder.statusPickupReady);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            '🧺 Gilam yuvish',
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
          child: StreamBuilder<List<CarpetWashOrder>>(
            stream: _repo.watchAll(),
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
                    onAccept: order.status == CarpetWashOrder.statusNew
                        ? () => _acceptOrder(order)
                        : null,
                    onPickupReady: order.status == CarpetWashOrder.statusAccepted
                        ? () => _setStatus(
                              order,
                              CarpetWashOrder.statusPickupReady,
                            )
                        : null,
                    onWashing: () =>
                        _setStatus(order, CarpetWashOrder.statusWashing),
                    onDrying: () =>
                        _setStatus(order, CarpetWashOrder.statusDrying),
                    onReady: () =>
                        _setStatus(order, CarpetWashOrder.statusReady),
                    onReturnReady: order.status == CarpetWashOrder.statusReady
                        ? () => _setStatus(
                              order,
                              CarpetWashOrder.statusReturnReady,
                            )
                        : null,
                    onCancel: order.isActive
                        ? () => _setStatus(
                              order,
                              CarpetWashOrder.statusCancelled,
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
    this.onPickupReady,
    required this.onWashing,
    required this.onDrying,
    required this.onReady,
    this.onReturnReady,
    this.onCancel,
  });

  final CarpetWashOrder order;
  final DateFormat dateFmt;
  final VoidCallback? onAccept;
  final VoidCallback? onPickupReady;
  final VoidCallback onWashing;
  final VoidCallback onDrying;
  final VoidCallback onReady;
  final VoidCallback? onReturnReady;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
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
                    '${order.customerName.isNotEmpty ? order.customerName : order.customerPhone} · ${order.carpetCount} ta gilam',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(order.status, style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(order.pickupAddress),
            Text('Tel: ${order.customerPhone}'),
            if (order.note.isNotEmpty) Text('Izoh: ${order.note}'),
            if (order.finalPrice > 0)
              Text(
                'Narx: ${formatPrice(order.finalPrice)} so\'m',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if (order.createdAt != null)
              Text(
                dateFmt.format(order.createdAt!),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onAccept != null)
                  _btn('Qabul', onAccept!, Colors.green),
                if (onPickupReady != null)
                  _btn('Olib ketishga tayyor', onPickupReady!, Colors.orange),
                if (order.status == CarpetWashOrder.statusPickedUp ||
                    order.status == CarpetWashOrder.statusPickupInDelivery)
                  _btn('Yuvish', onWashing, Colors.blue),
                if (order.status == CarpetWashOrder.statusWashing)
                  _btn('Quritish', onDrying, Colors.indigo),
                if (order.status == CarpetWashOrder.statusDrying)
                  _btn('Tayyor', onReady, Colors.teal),
                if (onReturnReady != null)
                  _btn('Qaytarishga tayyor', onReturnReady!, Colors.deepOrange),
                if (onCancel != null)
                  _btn('Bekor', onCancel!, Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap, Color color) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';
import '../../../repositories/orders_repository.dart';
import '../../home/controllers/home_controller.dart';
import '../../profile/widgets/order_card.dart';

/// Buyurtmalar ekrani (bottom-nav). 1-bosqich: faqat non + taom (`orders`).
/// Faol / Tugagan segmentlari, real-vaqt stream, mavjud [OrderCard].
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  // Faol holatlar (hali yetkazilmagan) va tugagan holatlar.
  static const _activeStatuses = {'new', 'accepted', 'ready'};
  static const _doneStatuses = {'delivered'};

  bool _showActive = true;

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeController>();
    final aliases = phoneAliases(home.phone);
    final repo = context.read<OrdersRepository>();

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
          Expanded(
            child: StreamBuilder<List<OrderModel>>(
              stream: repo.watchByUser(aliases),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Хатолик: ${snap.error}'));
                }
                final all = snap.data ?? const <OrderModel>[];
                final filtered = all.where((o) {
                  final s = o.status;
                  return _showActive
                      ? _activeStatuses.contains(s)
                      : _doneStatuses.contains(s);
                }).toList(growable: false);

                if (filtered.isEmpty) {
                  return _EmptyState(showActive: _showActive);
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => OrderCard(order: filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
                ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
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

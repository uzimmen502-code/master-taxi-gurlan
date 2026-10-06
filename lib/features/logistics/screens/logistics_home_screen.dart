// AVA LOGISTICS — мижоз кириш экрани: «Менинг жўнатмаларим» + «Посилка
// жўнатиш». Мижоз LEG, зона, ички ҳақни КЎРМАЙДИ (45-банд): фақат
// кузатув рақами, ҳолат, нарх.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../data/logistics_repository.dart';
import '../domain/logistics_models.dart';
import '../ui/logistics_text.dart';
import 'logistics_order_screen.dart';
import 'logistics_send_screen.dart';

class LogisticsHomeScreen extends StatefulWidget {
  const LogisticsHomeScreen({super.key, required this.ownerId, this.repository});

  /// Канон телефон ID (`998XXXXXXXXX`) — сервер `ownerId` билан бир хил.
  final String ownerId;
  final LogisticsRepository? repository;

  @override
  State<LogisticsHomeScreen> createState() => _LogisticsHomeScreenState();
}

class _LogisticsHomeScreenState extends State<LogisticsHomeScreen> {
  late final LogisticsRepository _repo = widget.repository ?? LogisticsRepository();

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(
          context.tr('home_module_logistics'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<LogisticsOrder>>(
                stream: _repo.myOrders(widget.ownerId),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data ?? const <LogisticsOrder>[];
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.local_post_office_outlined, size: 44, color: c.ink3),
                            const SizedBox(height: 10),
                            Text(
                              context.tr('logistics_empty'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: c.ink2),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _OrderTile(
                      order: list[i],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LogisticsOrderScreen(
                            orderId: list[i].id,
                            ownerId: widget.ownerId,
                            repository: _repo,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LogisticsSendScreen(
                        ownerId: widget.ownerId,
                        repository: _repo,
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.brand,
                    foregroundColor: c.brandInk,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    context.tr('logistics_send'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onTap});

  final LogisticsOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final tracking = order.trackingNumbers.isNotEmpty
        ? order.trackingNumbers.join(', ')
        : context.tr('logistics_parcel');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tracking,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                LogisticsStatusChip(labelKey: order.l10nStatusKey, status: order.status),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person_outline, size: 13, color: c.ink3),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    order.recipientName,
                    style: TextStyle(fontSize: 12, color: c.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${logisticsMoney(order.customerPriceTotal)} ${context.tr('sum')}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.brand),
                ),
              ],
            ),
            if (order.createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                logisticsDateLabel(order.createdAt),
                style: TextStyle(fontSize: 11, color: c.ink3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ҳолат чипи — ранг ҳолат маъносига боғланган (мижоз тилида).
class LogisticsStatusChip extends StatelessWidget {
  const LogisticsStatusChip({super.key, required this.labelKey, required this.status});

  final String labelKey;

  /// Сервер сатри (`in_transit`, `delivered`, …) — ранг учун.
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final (bg, fg) = switch (status) {
      'awaiting_payment' || 'pending' => (c.warnSoft, c.warn),
      'ready' || 'in_transit' => (c.brandSoft, c.brand),
      'delivered' || 'closed' => (c.okSoft, c.ok),
      'disputed' || 'lost' || 'problem' => (c.dangerSoft, c.danger),
      _ => (c.chip, c.ink3),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        context.tr(labelKey),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

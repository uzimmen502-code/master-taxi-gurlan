// «Менинг буюртмаларим» (харидор) ва «Келган буюртмалар» (сотувчи).
//
// Сотувчи рўйхатида қабул/рад тугмаси ЙЎҚ (эга, 2026-10-31): буюртма
// автоматик етказишга ўтади, AVA курьери товарни олиб кетади.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../logistics/ui/logistics_text.dart' show logisticsDateLabel;
import '../models/wholesale_order.dart';
import '../repositories/wholesale_orders_repository.dart';
import '../utils/wholesale_order_errors.dart';
import '../widgets/wholesale_order_status.dart';
import 'wholesale_order_detail_screen.dart';

enum WholesaleOrdersRole { buyer, seller }

class WholesaleOrdersScreen extends StatefulWidget {
  const WholesaleOrdersScreen({
    super.key,
    required this.role,
    required this.userId,
    this.repository,
  });

  final WholesaleOrdersRole role;

  /// Жорий фойдаланувчи телефони.
  final String userId;
  final WholesaleOrdersRepository? repository;

  @override
  State<WholesaleOrdersScreen> createState() => _WholesaleOrdersScreenState();
}

class _WholesaleOrdersScreenState extends State<WholesaleOrdersScreen> {
  late final WholesaleOrdersRepository _repo = widget.repository ?? WholesaleOrdersRepository();
  late Stream<List<WholesaleOrder>> _stream = _open();

  bool get _seller => widget.role == WholesaleOrdersRole.seller;

  Stream<List<WholesaleOrder>> _open() =>
      _seller ? _repo.watchSellerOrders(widget.userId) : _repo.watchBuyerOrders(widget.userId);

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
          context.tr(_seller ? 'wholesale_incoming_orders' : 'wholesale_my_orders'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
        ),
      ),
      body: StreamBuilder<List<WholesaleOrder>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(wholesaleOrderErrorText(context, snap.error!), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  // Firestore оқими хатодан кейин ёпилади — қайта уланамиз.
                  TextButton(
                    onPressed: () => setState(() => _stream = _open()),
                    child: Text(context.tr('wholesale_quote_retry')),
                  ),
                ],
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (_seller) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    context.tr('wholesale_orders_seller_note'),
                    style: TextStyle(fontSize: 12, color: c.ink),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      context.tr(_seller ? 'wholesale_orders_empty_seller' : 'wholesale_orders_empty_buyer'),
                      style: TextStyle(color: c.ink3),
                    ),
                  ),
                ),
              for (final o in items) ...[
                WholesaleOrderTile(
                  order: o,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WholesaleOrderDetailScreen(
                        orderId: o.id,
                        viewerId: widget.userId,
                        repository: _repo,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

class WholesaleOrderTile extends StatelessWidget {
  const WholesaleOrderTile({super.key, required this.order, required this.onTap});

  final WholesaleOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = order;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.productTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [if (o.packLabel.isNotEmpty) o.packLabel, '× ${o.qty}', logisticsDateLabel(o.createdAt)]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(fontSize: 12, color: c.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  WholesaleOrderStatusChip(status: o.status),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(o.total),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.brand),
                  ),
                ],
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

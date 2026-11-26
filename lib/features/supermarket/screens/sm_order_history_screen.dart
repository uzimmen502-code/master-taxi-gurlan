import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';
import '../../../models/order_news_group.dart';
import '../../profile/screens/order_news_detail_screen.dart';
import '../data/sm_lists_repository.dart';
import '../data/supermarket_repository.dart' show smOriginReorder;
import '../domain/sm_list.dart';
import '../domain/sm_order_progress.dart';
import '../supermarket_controller.dart';
import '../widgets/sm_compare_dialog.dart';
import '../widgets/sm_widgets.dart';
import 'supermarket_home_screen.dart';

/// Ҳолат чипи калити: 5 босқич ёки бекор/рад.
String smOrderStatusKey(OrderModel o) {
  final step = smOrderStep(o.status, fulfillmentStatus: o.fulfillmentStatus);
  if (step != null) return kSmOrderStepKeys[step]!;
  return 'sm_status_cancelled';
}

String _date(DateTime? d) {
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Супермаркет буюртмаларим (2-босқич, эга 2026-11-21): ҳолат, сана, жами; босилса — мавжуд буюртма
/// тафсилоти; «Қайта буюртма» — ўша таклифлар ЖОРИЙ нархда текширилиб САВАТГА қўшилади (буюртма эмас).
class SmOrderHistoryScreen extends StatefulWidget {
  const SmOrderHistoryScreen({super.key, required this.controller, this.loader, this.openDetail});

  final SupermarketController controller;

  /// Тест учун; бўлмаса — [loadSupermarketOrders].
  final SmOrdersLoader? loader;

  /// Тест учун; бўлмаса — мавжуд [OrderNewsDetailScreen].
  final void Function(BuildContext context, OrderModel order)? openDetail;

  @override
  State<SmOrderHistoryScreen> createState() => _SmOrderHistoryScreenState();
}

class _SmOrderHistoryScreenState extends State<SmOrderHistoryScreen> {
  late Future<List<OrderModel>> _future = _load();

  Future<List<OrderModel>> _load() => (widget.loader ?? loadSupermarketOrders)();

  void _open(OrderModel o) {
    if (widget.openDetail != null) {
      widget.openDetail!(context, o);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OrderNewsDetailScreen(group: OrderNewsGroup(orderId: o.id, messages: const [], orderType: o.type)),
    ));
  }

  Future<void> _reorder(OrderModel o) async {
    final r = smReorderItems(smOrderLineRefs(o.items.map((i) => i.raw)));
    final n = await smCompareAndAddToCart(context, controller: widget.controller, items: r.items, previousPrices: r.prices, origin: smOriginReorder);
    if (!mounted || n == 0) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('sm_reorder_snack'),
        content: Text(context.tr('sm_list_added').replaceAll('{n}', '$n')),
        action: SnackBarAction(label: context.tr('sm_tab_cart'), onPressed: () => smOpenCart(context, widget.controller)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('sm_history_title')),
        actions: [SmCartAction(controller: widget.controller, onTap: () => smOpenCart(context, widget.controller))],
      ),
      body: FutureBuilder<List<OrderModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            debugPrint('[Supermarket] SM_HISTORY_LOAD_FAILED: ${snap.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(context.tr('sm_err_load'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: Text(context.tr('sm_retry')),
                  ),
                ]),
              ),
            );
          }
          final list = snap.data ?? const <OrderModel>[];
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.tr('sm_history_empty'), key: const ValueKey('sm_history_empty'),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              final f = _load();
              setState(() => _future = f);
              await f;
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _OrderTile(order: list[i], onOpen: () => _open(list[i]), onReorder: () => _reorder(list[i])),
            ),
          );
        },
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onOpen, required this.onReorder});

  final OrderModel order;
  final VoidCallback onOpen;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final key = smOrderStatusKey(order);
    final cancelled = key == 'sm_status_cancelled';
    final done = key == kSmOrderStepKeys[SmOrderStep.delivered];
    return Material(
      key: ValueKey('sm_history_${order.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    key: ValueKey('sm_history_status_${order.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cancelled ? c.dangerSoft : (done ? c.okSoft : c.brandSoft),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(context.tr(key),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cancelled ? c.danger : c.ink)),
                  ),
                  Text(_date(order.createdAt), style: TextStyle(fontSize: 14, color: c.ink2)),
                ],
              ),
              const SizedBox(height: 6),
              Text(formatMoney(order.total),
                  key: ValueKey('sm_history_total_${order.id}'),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
              Text(context.tr('sm_weekly_items_count').replaceAll('{n}', '${order.items.length}'),
                  style: TextStyle(fontSize: 14, color: c.ink2)),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: ValueKey('sm_history_reorder_${order.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: onReorder,
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(context.tr('sm_reorder'), style: const TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

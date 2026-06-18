import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/collection_task.dart';
import '../../../models/courier_order.dart';
import '../../../repositories/collection_tasks_repository.dart';
import '../../../repositories/courier_orders_repository.dart';
import '../../../repositories/couriers_repository.dart';
import '../../../repositories/delivery_routes_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../controllers/courier_controller.dart';
import '../widgets/courier_online_toggle.dart';
import '../widgets/courier_order_tile.dart';
import '../widgets/route_map_view.dart';
import 'courier_collection_tasks_screen.dart';
import 'courier_mfy_selection_screen.dart';
import '../../courier_order/screens/courier_orders_list_screen.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Kuryer paneli — yetkazib berish marshrutini ko'rsatadi va boshqaradi.
class CourierScreen extends StatelessWidget {
  const CourierScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CourierController>(
      create: (ctx) => CourierController(
        routesRepo: ctx.read<DeliveryRoutesRepository>(),
        ordersRepo: ctx.read<OrdersRepository>(),
        couriersRepo: ctx.read<CouriersRepository>(),
      )..init(),
      child: const _CourierView(),
    );
  }
}

class _CourierView extends StatefulWidget {
  const _CourierView();

  @override
  State<_CourierView> createState() => _CourierViewState();
}

class _CourierViewState extends State<_CourierView> {
  static const Color _btn = AppColors.primaryDark;

  String? _lastSnackShown;

  String _localizedMsg(String msg) {
    if (msg.startsWith('courier_')) {
      return context.trMsg(msg);
    }
    return msg;
  }

  void _showTransient(CourierController c) {
    final msg = c.errorMessage ?? c.info;
    if (msg == null || msg == _lastSnackShown) return;
    _lastSnackShown = msg;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_localizedMsg(msg)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      c.clearTransient();
      _lastSnackShown = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CourierController>();
    _showTransient(c);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(context.tr('courier_panel_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          CourierOnlineToggle(
            isOnline: c.isOnline,
            onToggle: c.toggleOnline,
          ),
        ],
      ),
      body: Column(children: [
        _CollectionTasksBanner(courierUid: c.courierUid),
        const _CourierOrdersBanner(),
        Expanded(
          child: !c.hasRoute
              ? _NoRouteView(
                  isOnline: c.isOnline,
                  onStart: c.toggleOnline,
                  onRefresh: c.loadActiveRoute,
                )
              : Column(children: [
                  RouteMapView(
                    currentLat: c.currentPos?.latitude,
                    currentLng: c.currentPos?.longitude,
                    orders: c.routeOrders,
                    currentIndex: c.currentOrderIndex,
                  ),
                  Expanded(child: _buildOrdersList(c)),
                ]),
        ),
      ]),
    );
  }

  Widget _buildOrdersList(CourierController c) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: Row(children: [
          Text(
            context.tr('courier_orders_total').replaceAll(
              '{count}',
              '${c.routeOrders.length}',
            ),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            context.tr('courier_progress').replaceAll(
              '{current}',
              '${c.currentOrderIndex}',
            ).replaceAll(
              '{total}',
              '${c.routeOrders.length}',
            ),
              style: const TextStyle(
                  fontSize: 13,
                  color: _btn,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
      LinearProgressIndicator(
        value: c.routeOrders.isEmpty
            ? 0
            : c.currentOrderIndex / c.routeOrders.length,
        backgroundColor: Colors.grey.shade200,
        valueColor: const AlwaysStoppedAnimation<Color>(_btn),
      ),
      Expanded(
          child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: c.routeOrders.length,
        itemBuilder: (_, i) {
          final o = c.routeOrders[i];
          final finalized = CourierController.isOrderFinalized(o);
          final isCurrent = i == c.currentOrderIndex;
          return CourierOrderTile(
            order: o,
            index: i,
            isDone: i < c.currentOrderIndex || finalized,
            isCurrent: isCurrent && !finalized,
            needsFinalize: isCurrent && finalized,
            onPicked: () => c.markPicked(o.id),
            onArrived: () => c.markArrived(o.id),
            onPayment: (lines) => c.submitPayment(o.id, lines),
            onFinalizeRoute: () => c.confirmAndAdvance(orderId: o.id),
          );
        },
      )),
    ]);
  }
}

/// «📦 Қабул вазифалари (N та)» — етказиш оқимидан мустақил кириш нуқтаси.
class _CollectionTasksBanner extends StatefulWidget {
  const _CollectionTasksBanner({required this.courierUid});

  final String courierUid;

  @override
  State<_CollectionTasksBanner> createState() => _CollectionTasksBannerState();
}

class _CollectionTasksBannerState extends State<_CollectionTasksBanner> {
  Stream<List<CollectionTask>>? _stream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(covariant _CollectionTasksBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courierUid != widget.courierUid) _initStream();
  }

  void _initStream() {
    _stream = context
        .read<CollectionTasksRepository>()
        .watchForCourier(widget.courierUid);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CollectionTask>>(
      stream: _stream,
      builder: (ctx, snap) {
        final count = (snap.data ?? const <CollectionTask>[]).length;
        return Material(
          color: Colors.teal.shade50,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CourierCollectionTasksScreen(
                    courierUid: widget.courierUid,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.teal.shade100),
                ),
              ),
              child: Row(children: [
                const Text('📦', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('courier_collection_tasks_banner').replaceAll(
                      '{count}',
                      '$count',
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade900,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.teal.shade700),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// «🛵 Kuryer buyurtmalari (N ta)» — yangi courier_orders oqimi.
class _CourierOrdersBanner extends StatelessWidget {
  const _CourierOrdersBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CourierOrder>>(
      stream: context.read<CourierOrdersRepository>().watchPending(),
      builder: (context, snap) {
        final count = (snap.data ?? const <CourierOrder>[]).length;
        if (count == 0) return const SizedBox.shrink();

        return Material(
          color: Colors.orange.shade50,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CourierOrdersListScreen(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.orange.shade100),
                ),
              ),
              child: Row(
                children: [
                  const Text('🛵', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Kuryer buyurtmalari ($count ta)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.orange.shade700),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoRouteView extends StatelessWidget {
  const _NoRouteView({
    required this.isOnline,
    required this.onStart,
    required this.onRefresh,
  });

  final bool isOnline;
  final VoidCallback onStart;
  final VoidCallback onRefresh;

  static const Color _btn = AppColors.primaryDark;

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          const Text('🛵', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 12),
          Text(
            isOnline
                ? context.tr('courier_no_route_online')
                : context.tr('courier_go_online_hint'),
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          if (!isOnline)
            ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: Text(context.tr('courier_start_work')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _btn,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CourierMfySelectionScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: Text(context.tr('courier_mfy_route')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _btn,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(context.tr('courier_refresh')),
                ),
              ],
            ),
        ]));
  }
}

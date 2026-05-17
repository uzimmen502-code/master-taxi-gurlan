import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../repositories/couriers_repository.dart';
import '../../../repositories/delivery_routes_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../controllers/courier_controller.dart';
import '../widgets/courier_online_toggle.dart';
import '../widgets/courier_order_tile.dart';
import '../widgets/route_map_view.dart';

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
  static const Color _blue = Color(0xFF1565C0);
  static const Color _green = Color(0xFF2E7D32);

  String? _lastSnackShown;

  void _showTransient(CourierController c) {
    final msg = c.errorMessage ?? c.info;
    if (msg == null || msg == _lastSnackShown) return;
    _lastSnackShown = msg;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
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
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text('🛵 Курьер панели'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          CourierOnlineToggle(
            isOnline: c.isOnline,
            onToggle: c.toggleOnline,
          ),
        ],
      ),
      body: !c.hasRoute
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
    );
  }

  Widget _buildOrdersList(CourierController c) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: Row(children: [
          Text('📦 Жами: ${c.routeOrders.length} та буюртма',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('✅ ${c.currentOrderIndex}/${c.routeOrders.length}',
              style: const TextStyle(
                  fontSize: 13,
                  color: _green,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
      LinearProgressIndicator(
        value: c.routeOrders.isEmpty
            ? 0
            : c.currentOrderIndex / c.routeOrders.length,
        backgroundColor: Colors.grey.shade200,
        valueColor: const AlwaysStoppedAnimation<Color>(_green),
      ),
      Expanded(
          child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: c.routeOrders.length,
        itemBuilder: (_, i) => CourierOrderTile(
          order: c.routeOrders[i],
          index: i,
          isDone: i < c.currentOrderIndex,
          isCurrent: i == c.currentOrderIndex,
          onDelivered: () => c.markDelivered(c.routeOrders[i].id),
        ),
      )),
    ]);
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

  static const Color _blue = Color(0xFF1565C0);
  static const Color _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          const Text('🛵', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 12),
          Text(isOnline ? 'Маршрут кутилмоқда...' : 'Онлайн бўлинг',
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          if (!isOnline)
            ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('ИШНИ БОШЛАШ'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )
          else
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('ЯНГИЛАШ'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
        ]));
  }
}

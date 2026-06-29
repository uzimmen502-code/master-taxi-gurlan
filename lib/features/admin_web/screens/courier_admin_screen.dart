import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/delivery_route.dart';
import '../../../models/order_model.dart';
import '../../../models/route_candidate.dart';
import '../../../repositories/delivery_routes_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../../../services/google_directions_service.dart';
import '../../../services/polyline_decoder.dart';
import '../../../shared/widgets/order_receipt_view.dart';

/// Admin web — courier dispatcher board.
class CourierAdminScreen extends StatefulWidget {
  const CourierAdminScreen({super.key});

  @override
  State<CourierAdminScreen> createState() => _CourierAdminScreenState();
}

class _CourierAdminScreenState extends State<CourierAdminScreen> {
  static const _blue = AppColors.primary;
  static final _money = NumberFormat.decimalPattern('en');
  static final _date = DateFormat('dd.MM HH:mm');
  static final _time = DateFormat('HH:mm');

  final _boardScrollController = ScrollController();
  final _directionsService = GoogleDirectionsService();
  final _polylineDecoder = const PolylineDecoder();
  final _mapPreviewKey = GlobalKey();
  String? _loadingRouteMapId;
  RouteCandidate? _selectedCandidate;
  DeliveryRoute? _selectedRoute;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _boardScrollController.dispose();
    super.dispose();
  }

  Future<void> _previewDeliveryRoute(DeliveryRoute route) async {
    setState(() {
      _selectedRoute = route;
      _selectedCandidate = null;
      _loadingRouteMapId = route.id;
    });
    var candidate = RouteCandidate.fromDeliveryRoute(route);
    if (!candidate.hasGoogleDirections || candidate.polyline.isEmpty) {
      try {
        candidate = await _directionsService.enrichCandidate(candidate);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Directions: $e (to\'g\'ri chiziq ko\'rsatiladi)'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedCandidate = candidate;
      _loadingRouteMapId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          '🛵 Kuryer boshqaruvi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.alt_route, color: _blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Курьерлар фаолиятини кузатиш',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _RouteMapPreview(
            key: _mapPreviewKey,
            candidate: _selectedCandidate,
            route: _selectedRoute,
            loading: _loadingRouteMapId != null,
            decoder: _polylineDecoder,
          ),
          Expanded(
            child: StreamBuilder<List<OrderModel>>(
              stream: context
                  .read<OrdersRepository>()
                  .watchRecentOrders(limit: 120),
              builder: (context, orderSnap) {
                if (orderSnap.hasError) {
                  return Center(
                      child: Text('Buyurtmalar xatosi: ${orderSnap.error}'));
                }
                if (!orderSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                return StreamBuilder<List<DeliveryRoute>>(
                  stream: context
                      .read<DeliveryRoutesRepository>()
                      .watchActiveRoutes(),
                  builder: (context, routeSnap) {
                    if (routeSnap.hasError) {
                      return Center(
                          child: Text('Reyslar xatosi: ${routeSnap.error}'));
                    }
                    if (!routeSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('couriers')
                          .where('isOnline', isEqualTo: true)
                          .snapshots(),
                      builder: (context, courierSnap) {
                        if (courierSnap.hasError) {
                          return Center(
                              child: Text(
                                  'Kuryerlar xatosi: ${courierSnap.error}'));
                        }
                        if (!courierSnap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        final orders = orderSnap.data!;
                        final inDeliveryOrders = orders
                            .where((o) =>
                                o.status == 'in_delivery' ||
                                o.status == 'courier')
                            .toList();
                        final deliveredOrders = orders
                            .where((o) => o.status == 'delivered')
                            .toList();
                        final routes = routeSnap.data!;
                        final readyRoutes =
                            routes.where((r) => r.status == 'ready').toList();
                        final activeRoutes =
                            routes.where((r) => r.status == 'active').toList();
                        final couriers = courierSnap.data!.docs;

                        return _DispatcherBoard(
                          scrollController: _boardScrollController,
                          columns: [
                            _BoardColumn(
                              title: 'Тасдиқланган reysлар',
                              icon: Icons.route,
                              color: Colors.orange,
                              count: readyRoutes.length,
                              child: _RouteList(
                                routes: readyRoutes,
                                date: _date,
                                emptyText: 'Курьер кутаётган reys йўқ',
                                selectedRouteId: _selectedRoute?.id,
                                loadingRouteId: _loadingRouteMapId,
                                onViewMap: _previewDeliveryRoute,
                              ),
                            ),
                            _BoardColumn(
                              title: 'Курьерда',
                              icon: Icons.delivery_dining,
                              color: AppColors.primary,
                              count:
                                  activeRoutes.length + inDeliveryOrders.length,
                              child: _InDeliveryPanel(
                                routes: activeRoutes,
                                orders: inDeliveryOrders,
                                date: _date,
                                money: _money,
                                selectedRouteId: _selectedRoute?.id,
                                loadingRouteId: _loadingRouteMapId,
                                onViewMap: _previewDeliveryRoute,
                              ),
                            ),
                            _BoardColumn(
                              title: 'Етказилган',
                              icon: Icons.check_circle_outline,
                              color: Colors.teal,
                              count: deliveredOrders.length,
                              child: _OrderList(
                                orders: deliveredOrders,
                                money: _money,
                                date: _date,
                                emptyText: 'Етказилган буюртма йўқ',
                              ),
                            ),
                            _BoardColumn(
                              title: 'Онлайн курьерлар',
                              icon: Icons.sensors,
                              color: Colors.blue,
                              count: couriers.length,
                              child: _CourierList(docs: couriers, time: _time),
                            ),
                          ],
                        );
                      },
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

class _DispatcherBoard extends StatelessWidget {
  const _DispatcherBoard({
    required this.scrollController,
    required this.columns,
  });

  final ScrollController scrollController;
  final List<_BoardColumn> columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minColumnWidth = 300.0;
        final boardWidth =
            math.max(constraints.maxWidth, minColumnWidth * columns.length);
        final boardHeight = math.max(0.0, constraints.maxHeight - 24);
        return Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(12),
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: boardWidth,
              height: boardHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final column in columns)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: column,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RouteMapPreview extends StatefulWidget {
  const _RouteMapPreview({
    super.key,
    required this.candidate,
    required this.route,
    required this.loading,
    required this.decoder,
  });

  final RouteCandidate? candidate;
  final DeliveryRoute? route;
  final bool loading;
  final PolylineDecoder decoder;

  @override
  State<_RouteMapPreview> createState() => _RouteMapPreviewState();
}

class _RouteMapPreviewState extends State<_RouteMapPreview> {
  GoogleMapController? _mapController;
  bool _cameraReady = false;
  CameraPosition? _stableInitialPosition;

  CameraPosition _computeInitialPosition(RouteCandidate c) {
    final start = LatLng(c.startLat, c.startLng);
    bool nearStart(LatLng p) {
      final dlat = p.latitude - start.latitude;
      final dlng = p.longitude - start.longitude;
      return math.sqrt(dlat * dlat + dlng * dlng) < 0.5;
    }
    final pts = [
      start,
      ...c.stops
          .map((s) => LatLng(s.lat, s.lng))
          .where(nearStart),
    ];
    final lat = pts.fold<double>(0,(s,p)=>s+p.latitude) / pts.length;
    final lng = pts.fold<double>(0,(s,p)=>s+p.longitude) / pts.length;
    var minLat=pts.first.latitude; var maxLat=pts.first.latitude;
    var minLng=pts.first.longitude; var maxLng=pts.first.longitude;
    for (final p in pts) {
      if (p.latitude <minLat) minLat=p.latitude;
      if (p.latitude >maxLat) maxLat=p.latitude;
      if (p.longitude<minLng) minLng=p.longitude;
      if (p.longitude>maxLng) maxLng=p.longitude;
    }
    final span = math.max(maxLat-minLat, maxLng-minLng);
    final zoom = span<0.02?15.0: span<0.05?14.0: span<0.10?13.0:
                 span<0.20?12.0: span<0.40?11.0: span<0.80?10.0: 9.0;
    return CameraPosition(target: LatLng(lat, lng), zoom: zoom);
  }

  @override
  void didUpdateWidget(_RouteMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newCand = widget.candidate;
    if (newCand == null) return;
    final idChanged = oldWidget.candidate?.id != newCand.id;
    final polylineAdded =
        oldWidget.candidate?.hasGoogleDirections == false &&
        newCand.hasGoogleDirections == true;
    if (idChanged) {
      _stableInitialPosition = _computeInitialPosition(newCand);
    }
    if (idChanged || polylineAdded) {
      _cameraReady = false;
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _applyCamera(RouteCandidate c) {
    final ctrl = _mapController;
    if (ctrl == null) return;

    // Start point is always correct (depot coordinates)
    final start = LatLng(c.startLat, c.startLng);

    // Only use stops within 50km of start point
    bool nearStart(LatLng p) {
      final dlat = p.latitude - start.latitude;
      final dlng = p.longitude - start.longitude;
      final dist = math.sqrt(dlat * dlat + dlng * dlng);
      return dist < 0.5; // ~50km in degrees
    }

    final validStops = c.stops
        .map((s) => LatLng(s.lat, s.lng))
        .where(nearStart)
        .toList();

    final pts = [start, ...validStops];

    final lat = pts.fold<double>(0,(s,p)=>s+p.latitude) / pts.length;
    final lng = pts.fold<double>(0,(s,p)=>s+p.longitude) / pts.length;

    var minLat=pts.first.latitude; var maxLat=pts.first.latitude;
    var minLng=pts.first.longitude; var maxLng=pts.first.longitude;
    for (final p in pts) {
      if (p.latitude <minLat) minLat=p.latitude;
      if (p.latitude >maxLat) maxLat=p.latitude;
      if (p.longitude<minLng) minLng=p.longitude;
      if (p.longitude>maxLng) maxLng=p.longitude;
    }
    final span = math.max(maxLat-minLat, maxLng-minLng);
    final zoom = span<0.02?15.0: span<0.05?14.0: span<0.10?13.0:
                 span<0.20?12.0: span<0.40?11.0: span<0.80?10.0: 9.0;

    ctrl.moveCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: LatLng(lat, lng), zoom: zoom),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    if (c == null) {
      return Container(
        height: 86,
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.map_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Тайёр буюртмаларни белгиланг ёки тавсия/reysдан «Харитада кўриш»ни босинг. '
                'Google Directions бир йўналишдаги маршрут, вақт ва курьер joyini ko\'rsatadi.',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final progressIndex = widget.route?.currentIndex ?? 0;
    final courierId = widget.route?.courierId ?? '';

    Widget mapBody(LatLng? courierPos) {
      final markers = <Marker>{
        Marker(
          markerId: const MarkerId('start'),
          position: LatLng(c.startLat, c.startLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Старт нуқта'),
        ),
        for (final stop in c.stops)
          if (stop.lat > 40.0 &&
              stop.lat < 43.5 &&
              stop.lng > 58.5 &&
              stop.lng < 63.0)
            Marker(
              markerId: MarkerId(stop.orderId),
              position: LatLng(stop.lat, stop.lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                _stopHue(stop.sequence, progressIndex),
              ),
              infoWindow: InfoWindow(
                title: '${stop.sequence + 1}. ${stop.userName}',
                snippet: stop.address,
              ),
            ),
        if (courierPos != null)
          Marker(
            markerId: const MarkerId('courier_live'),
            position: courierPos,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueViolet,
            ),
            infoWindow: const InfoWindow(title: 'Курьер (онлайн)'),
          ),
      };

      final fallbackPath = [
        LatLng(c.startLat, c.startLng),
        for (final stop in c.stops) LatLng(stop.lat, stop.lng),
      ];
      // Web: polyline decoder produces wrong coords on Flutter web (JS 32-bit issue)
      // Use straight lines between stops — sufficient for admin dispatching
      final routePath = fallbackPath;
      final initPos = _stableInitialPosition
          ?? _computeInitialPosition(c);
      _stableInitialPosition ??= initPos;

      return GoogleMap(
        key: ValueKey(widget.candidate?.id ?? 'no_candidate'),
        initialCameraPosition: initPos,
        markers: markers,
        polylines: {
          Polyline(
            polylineId: const PolylineId('route'),
            points: routePath,
            width: 5,
            color: AppColors.primary,
          ),
        },
        onMapCreated: (c) {
          _mapController = c;
          _cameraReady = false;
        },
        onCameraIdle: () {
          if (_cameraReady) return;
          final cand = widget.candidate;
          if (cand == null || _mapController == null) return;
          _cameraReady = true;
          _applyCamera(cand);
        },
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
      );
    }

    final titlePrefix = widget.route != null
        ? (widget.route!.isActive ? 'Курьер reysi' : 'Tasdiqlangan reys')
        : (c.id.startsWith('manual')
            ? 'Qo\'lda marshrut'
            : (c.id.startsWith('mfy') ? 'MFY marshrut' : 'Tavsiya'));

    return Container(
      height: 300,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(
              children: [
                const Icon(Icons.map, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$titlePrefix · ${c.directionLabel} · ${c.stops.length} та · '
                    '${c.distanceKm.toStringAsFixed(1)} км · ~${c.durationMin} дақ'
                    '${c.hasGoogleDirections ? ' · Google' : ' · тахмин'}'
                    '${widget.route != null && widget.route!.isActive ? ' · $progressIndex/${c.stops.length}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (widget.loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Expanded(
            child: courierId.isEmpty
                ? mapBody(null)
                : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('couriers')
                        .doc(courierId)
                        .snapshots(),
                    builder: (context, snap) {
                      LatLng? courierPos;
                      final data = snap.data?.data();
                      final lat = (data?['lat'] as num?)?.toDouble();
                      final lng = (data?['lng'] as num?)?.toDouble();
                      if (lat != null && lng != null) {
                        courierPos = LatLng(lat, lng);
                      }
                      return mapBody(courierPos);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  double _stopHue(int sequence, int progressIndex) {
    if (sequence < progressIndex) return BitmapDescriptor.hueGreen;
    if (sequence == progressIndex) return BitmapDescriptor.hueOrange;
    return BitmapDescriptor.hueRed;
  }

}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.orders,
    required this.money,
    required this.date,
    required this.emptyText,
  });

  final List<OrderModel> orders;
  final NumberFormat money;
  final DateFormat date;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return _EmptyColumnText(emptyText);
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: orders.length,
      itemBuilder: (_, i) => _OrderMiniCard(
        order: orders[i],
        money: money,
        date: date,
      ),
    );
  }
}

class _OrderMiniCard extends StatelessWidget {
  const _OrderMiniCard({
    required this.order,
    required this.money,
    required this.date,
  });

  final OrderModel order;
  final NumberFormat money;
  final DateFormat date;

  @override
  Widget build(BuildContext context) {
    final when = order.createdAt != null ? date.format(order.createdAt!) : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.type == 'food' ? 'Тайёр овқат' : 'Нон',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  when,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OrderReceiptView(order: order),
          ],
        ),
      ),
    );
  }
}

class _RouteList extends StatelessWidget {
  const _RouteList({
    required this.routes,
    required this.date,
    required this.emptyText,
    required this.onViewMap,
    this.selectedRouteId,
    this.loadingRouteId,
  });

  final List<DeliveryRoute> routes;
  final DateFormat date;
  final String emptyText;
  final ValueChanged<DeliveryRoute> onViewMap;
  final String? selectedRouteId;
  final String? loadingRouteId;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) return _EmptyColumnText(emptyText);
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: routes.length,
      itemBuilder: (_, i) {
        final r = routes[i];
        final statusColor = r.isActive ? AppColors.primary : Colors.orange;
        final statusText = r.isActive ? 'Aktiv' : 'Tayyor';
        final selected = selectedRouteId == r.id;
        final loading = loadingRouteId == r.id;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: selected ? Colors.orange.shade50 : null,
          child: Column(
            children: [
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child: Icon(Icons.route, color: statusColor, size: 19),
                ),
                title: Text(
                  '${r.orderIds.length} ta buyurtma · $statusText',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  [
                    if (r.directionLabel.isNotEmpty) r.directionLabel,
                    if (r.distanceKm != null)
                      '${r.distanceKm!.toStringAsFixed(1)} км',
                    if (r.durationMin != null) '~${r.durationMin} дақ',
                    if (r.startedAt != null)
                      'Бошланди: ${date.format(r.startedAt!)}',
                  ].join(' · '),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: loading ? null : () => onViewMap(r),
                    icon: loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            selected ? Icons.map : Icons.map_outlined,
                            size: 18,
                          ),
                    label: Text(
                      selected ? 'Харитада очилган' : 'Харитада кўриш',
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InDeliveryPanel extends StatelessWidget {
  const _InDeliveryPanel({
    required this.routes,
    required this.orders,
    required this.date,
    required this.money,
    required this.onViewMap,
    this.selectedRouteId,
    this.loadingRouteId,
  });

  final List<DeliveryRoute> routes;
  final List<OrderModel> orders;
  final DateFormat date;
  final NumberFormat money;
  final ValueChanged<DeliveryRoute> onViewMap;
  final String? selectedRouteId;
  final String? loadingRouteId;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty && orders.isEmpty) {
      return const _EmptyColumnText('Курьерда reys йўқ');
    }
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        for (final r in routes)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: selectedRouteId == r.id ? AppColors.scaffold : null,
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.delivery_dining, color: AppColors.primary),
                  ),
                  title: Text(
                    '${r.currentIndex}/${r.orderIds.length} yetkazildi',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    [
                      if (r.courierId.isNotEmpty) 'Kuryer: ${r.courierId}',
                      if (r.directionLabel.isNotEmpty) r.directionLabel,
                      if (r.startedAt != null) date.format(r.startedAt!),
                    ].join(' · '),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: loadingRouteId == r.id
                          ? null
                          : () => onViewMap(r),
                      icon: loadingRouteId == r.id
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              selectedRouteId == r.id
                                  ? Icons.map
                                  : Icons.map_outlined,
                              size: 18,
                            ),
                      label: Text(
                        selectedRouteId == r.id
                            ? 'Харитада (курьер GPS)'
                            : 'Маршрут ва курьер',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (orders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
            child: Text(
              'Reys ichidagi буюртмалар',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final o in orders)
            _OrderMiniCard(order: o, money: money, date: date),
        ],
      ],
    );
  }
}

class _CourierList extends StatelessWidget {
  const _CourierList({
    required this.docs,
    required this.time,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final DateFormat time;

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const _EmptyColumnText('Онлайн курьер йўқ');
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: docs.length,
      itemBuilder: (_, i) {
        final d = docs[i].data();
        final updatedAt = d['updatedAt'] as Timestamp?;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE3F2FD),
              child: Icon(Icons.sensors, color: Colors.blue),
            ),
            title: Text('${d['name'] ?? '—'}'),
            subtitle: Text(
              '📞 ${d['phone'] ?? '—'}'
              '${updatedAt != null ? ' · ${time.format(updatedAt.toDate())}' : ''}',
            ),
            trailing: d['lat'] != null && d['lng'] != null
                ? Text(
                    '${(d['lat'] as num).toStringAsFixed(4)},\n${(d['lng'] as num).toStringAsFixed(4)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _EmptyColumnText extends StatelessWidget {
  const _EmptyColumnText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500),
        ),
      ),
    );
  }
}

import '../models/directions_result.dart';
import '../models/order_model.dart';
import 'google_directions_service.dart';

/// Courier MFY tanlovidan keyin buyurtmalarni Google Directions `optimize:true`
/// bilan tartiblash (delivery_route yozish — A3).
class CourierDeliveryRouteOptimizer {
  CourierDeliveryRouteOptimizer({GoogleDirectionsService? directions})
      : _directions = directions ?? GoogleDirectionsService();

  final GoogleDirectionsService _directions;

  static bool hasValidCoords(OrderModel order) {
    final lat = order.lat;
    final lng = order.lng;
    if (lat == null || lng == null) return false;
    if (lat == 0 && lng == 0) return false;
    return true;
  }

  Future<CourierOptimizedRouteResult> optimize({
    required double originLat,
    required double originLng,
    required List<OrderModel> orders,
  }) async {
    final withCoords =
        orders.where(hasValidCoords).toList(growable: false);
    final skippedNoCoords = orders.length - withCoords.length;

    if (withCoords.isEmpty) {
      throw StateError('Буюртмаларда координата йўқ');
    }

    final DirectionsResult directions;
    if (withCoords.length == 1) {
      final only = withCoords.first;
      directions = await _directions.fetchOptimizedRoute(
        originLat: originLat,
        originLng: originLng,
        destinationLat: only.lat!,
        destinationLng: only.lng!,
        waypoints: const [],
      );
      return CourierOptimizedRouteResult(
        orderedStops: withCoords,
        skippedNoCoords: skippedNoCoords,
        directions: directions,
      );
    }

    final destination = withCoords.last;
    final waypointOrders = withCoords.sublist(0, withCoords.length - 1);
    final waypointCoords = waypointOrders
        .map((o) => (lat: o.lat!, lng: o.lng!))
        .toList(growable: false);

    directions = await _directions.fetchOptimizedRoute(
      originLat: originLat,
      originLng: originLng,
      destinationLat: destination.lat!,
      destinationLng: destination.lng!,
      waypoints: waypointCoords,
    );

    final orderedWaypoints =
        _reorderByWaypointOrder(waypointOrders, directions.waypointOrder);
    final orderedStops = [...orderedWaypoints, destination];

    return CourierOptimizedRouteResult(
      orderedStops: orderedStops,
      skippedNoCoords: skippedNoCoords,
      directions: directions,
    );
  }

  List<OrderModel> _reorderByWaypointOrder(
    List<OrderModel> waypointOrders,
    List<int> waypointOrder,
  ) {
    if (waypointOrder.length == waypointOrders.length) {
      return [
        for (final idx in waypointOrder) waypointOrders[idx],
      ];
    }
    return List<OrderModel>.from(waypointOrders);
  }
}

class CourierOptimizedRouteResult {
  const CourierOptimizedRouteResult({
    required this.orderedStops,
    required this.skippedNoCoords,
    required this.directions,
  });

  final List<OrderModel> orderedStops;
  final int skippedNoCoords;
  final DirectionsResult directions;
}

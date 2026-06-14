import '../models/directions_result.dart';
import '../models/intercity_booking.dart';
import '../models/intercity_pickup_route.dart';
import '../utils/intercity_city_coords.dart';
import 'google_directions_service.dart';

/// Haydovchi olib ketish zanjirini Google Directions `optimize:true` bilan quradi.
class IntercityPickupRouteService {
  IntercityPickupRouteService({GoogleDirectionsService? directions})
      : _directions = directions ?? GoogleDirectionsService();

  final GoogleDirectionsService _directions;

  Future<IntercityPickupRoute> build({
    required List<IntercityBooking> bookings,
    required String fromCity,
    required String toCity,
    double? driverLat,
    double? driverLng,
  }) async {
    final eligible = bookings
        .where(
          (b) =>
              b.status == IntercityBookingStatus.confirmed &&
              b.hasPickupGps &&
              b.pickupLat != null &&
              b.pickupLng != null,
        )
        .toList(growable: false);

    if (eligible.isEmpty) {
      throw StateError('pickup_route_no_gps');
    }

    final fromCoords = IntercityCityCoords.resolve(fromCity);
    final originLat = driverLat ?? fromCoords.$1;
    final originLng = driverLng ?? fromCoords.$2;
    final originLabel = driverLat != null ? fromCity : fromCity;

    final dest = IntercityCityCoords.resolve(toCity);
    final waypointCoords = eligible
        .map((b) => (lat: b.pickupLat!, lng: b.pickupLng!))
        .toList(growable: false);

    final DirectionsResult result;
    if (waypointCoords.length == 1) {
      result = await _directions.fetchOptimizedRoute(
        originLat: originLat,
        originLng: originLng,
        destinationLat: dest.$1,
        destinationLng: dest.$2,
        waypoints: waypointCoords,
      );
    } else {
      result = await _directions.fetchOptimizedRoute(
        originLat: originLat,
        originLng: originLng,
        destinationLat: dest.$1,
        destinationLng: dest.$2,
        waypoints: waypointCoords,
      );
    }

    final ordered = _orderBookings(eligible, result.waypointOrder);
    final stops = <IntercityPickupRouteStop>[];
    for (var i = 0; i < ordered.length; i++) {
      final b = ordered[i];
      stops.add(
        IntercityPickupRouteStop(
          booking: b,
          sequence: i + 1,
          lat: b.pickupLat!,
          lng: b.pickupLng!,
          label: b.pickupAddress.trim().isNotEmpty
              ? b.pickupAddress.trim()
              : b.userName,
        ),
      );
    }

    return IntercityPickupRoute(
      stops: stops,
      originLat: originLat,
      originLng: originLng,
      originLabel: originLabel,
      destinationLat: dest.$1,
      destinationLng: dest.$2,
      destinationLabel: toCity,
      totalDistanceKm: result.distanceKm,
      totalDurationMin: result.durationMin,
      polyline: result.polyline,
    );
  }

  List<IntercityBooking> _orderBookings(
    List<IntercityBooking> eligible,
    List<int> waypointOrder,
  ) {
    if (waypointOrder.length == eligible.length) {
      return [
        for (final idx in waypointOrder) eligible[idx],
      ];
    }
    return List<IntercityBooking>.from(eligible);
  }
}

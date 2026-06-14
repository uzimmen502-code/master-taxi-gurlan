import 'intercity_booking.dart';

/// Haydovchi olib ketish zanjiridagi bitta nuqta (yo'lovchi).
class IntercityPickupRouteStop {
  const IntercityPickupRouteStop({
    required this.booking,
    required this.sequence,
    required this.lat,
    required this.lng,
    required this.label,
  });

  final IntercityBooking booking;
  final int sequence;
  final double lat;
  final double lng;
  final String label;
}

/// Optimallashtirilgan: origin → yo'lovchilar → destination.
class IntercityPickupRoute {
  const IntercityPickupRoute({
    required this.stops,
    required this.originLat,
    required this.originLng,
    required this.originLabel,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationLabel,
    required this.totalDistanceKm,
    required this.totalDurationMin,
    required this.polyline,
  });

  final List<IntercityPickupRouteStop> stops;
  final double originLat;
  final double originLng;
  final String originLabel;
  final double destinationLat;
  final double destinationLng;
  final String destinationLabel;
  final double totalDistanceKm;
  final int totalDurationMin;
  final String polyline;

  int get passengerCount => stops.length;
}

import 'delivery_route.dart';
import 'route_stop.dart';

/// Admin tasdiqlashidan oldingi tavsiya qilingan courier yo'nalishi.
class RouteCandidate {
  const RouteCandidate({
    required this.id,
    required this.stops,
    required this.startLat,
    required this.startLng,
    required this.directionLabel,
    required this.directionDegrees,
    required this.distanceKm,
    required this.durationMin,
    this.polyline = '',
    this.hasGoogleDirections = false,
  });

  final String id;
  final List<RouteStop> stops;
  final double startLat;
  final double startLng;
  final String directionLabel;
  final double directionDegrees;
  final double distanceKm;
  final int durationMin;
  final String polyline;
  final bool hasGoogleDirections;

  List<String> get orderIds => stops.map((s) => s.orderId).toList();

  int get totalValue => stops.fold<int>(0, (sum, s) => sum + s.total);

  /// Firestore `delivery_routes` hujjatidan xarita ko'rinishi uchun.
  factory RouteCandidate.fromDeliveryRoute(
    DeliveryRoute route, {
    double defaultStartLat = 41.8443,
    double defaultStartLng = 60.3919,
  }) {
    final stops = route.orderedStops
        .map(RouteStop.fromMap)
        .where((s) => s.lat != 0 && s.lng != 0)
        .toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return RouteCandidate(
      id: 'route_${route.id}',
      stops: stops,
      startLat: route.startLat ?? defaultStartLat,
      startLng: route.startLng ?? defaultStartLng,
      directionLabel: route.directionLabel.isNotEmpty
          ? route.directionLabel
          : 'Reys',
      directionDegrees: 0,
      distanceKm: route.distanceKm ?? 0,
      durationMin: route.durationMin ?? 0,
      polyline: route.polyline,
      hasGoogleDirections: route.hasGoogleDirections,
    );
  }
  RouteCandidate copyWith({
    double? distanceKm,
    int? durationMin,
    String? polyline,
    bool? hasGoogleDirections,
  }) {
    return RouteCandidate(
      id: id,
      stops: stops,
      startLat: startLat,
      startLng: startLng,
      directionLabel: directionLabel,
      directionDegrees: directionDegrees,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMin: durationMin ?? this.durationMin,
      polyline: polyline ?? this.polyline,
      hasGoogleDirections: hasGoogleDirections ?? this.hasGoogleDirections,
    );
  }
}

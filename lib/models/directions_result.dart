class DirectionsResult {
  const DirectionsResult({
    required this.distanceKm,
    required this.durationMin,
    required this.polyline,
    this.waypointOrder = const [],
  });

  final double distanceKm;
  final int durationMin;
  final String polyline;

  /// Google `optimize:true` — waypoint indekslari (0-based).
  final List<int> waypointOrder;
}

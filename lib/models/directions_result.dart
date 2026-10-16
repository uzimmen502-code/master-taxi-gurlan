class DirectionsResult {
  const DirectionsResult({
    required this.distanceKm,
    required this.durationMin,
    required this.polyline,
    this.waypointOrder = const [],
    this.endLat,
    this.endLng,
  });

  final double distanceKm;
  final int durationMin;
  final String polyline;

  /// Google `optimize:true` — waypoint indekslari (0-based).
  final List<int> waypointOrder;

  /// Oxirgi leg end_location - Google marshrutning HAQIQIY tugash nuqtasi
  /// (matnli manzil uchun ham). Javobda bo'lmasa null.
  final double? endLat;
  final double? endLng;

  bool get hasEnd => endLat != null && endLng != null;
}

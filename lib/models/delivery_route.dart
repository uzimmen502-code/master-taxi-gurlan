import 'package:cloud_firestore/cloud_firestore.dart';

/// `delivery_routes/{id}` hujjati — kuryerga tayinlangan yetkazib berish reysi.
///
/// Status hayoti: `ready → active → completed`.
/// `currentIndex` — kuryer hozir qaysi `orders[i]` ustida ishlamoqda.
class DeliveryRoute {
  const DeliveryRoute({
    required this.id,
    this.courierId = '',
    this.status = 'ready',
    this.orderIds = const [],
    this.orderedStops = const [],
    this.currentIndex = 0,
    this.distanceKm,
    this.durationMin,
    this.directionLabel = '',
    this.routeSource = '',
    this.polyline = '',
    this.startLat,
    this.startLng,
    this.hasGoogleDirections = false,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String courierId;
  final String status;
  final List<String> orderIds;
  final List<Map<String, dynamic>> orderedStops;
  final int currentIndex;
  final double? distanceKm;
  final int? durationMin;
  final String directionLabel;
  final String routeSource;
  final String polyline;
  final double? startLat;
  final double? startLng;
  final bool hasGoogleDirections;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get isActive => status == 'active';
  bool get isReady => status == 'ready';
  bool get isCompleted => status == 'completed';

  factory DeliveryRoute.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return DeliveryRoute(
      id: doc.id,
      courierId: (d['courierId'] ?? '') as String,
      status: (d['status'] ?? 'ready') as String,
      orderIds: List<String>.from(d['orders'] ?? d['orderIds'] ?? const []),
      orderedStops: (d['orderedStops'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(),
      currentIndex: (d['currentIndex'] as num?)?.toInt() ?? 0,
      distanceKm: (d['distanceKm'] as num?)?.toDouble(),
      durationMin: (d['durationMin'] as num?)?.toInt(),
      directionLabel: (d['directionLabel'] ?? '') as String,
      routeSource: (d['routeSource'] ?? '') as String,
      polyline: (d['polyline'] ?? '') as String,
      startLat: (d['startLat'] as num?)?.toDouble(),
      startLng: (d['startLng'] as num?)?.toDouble(),
      hasGoogleDirections: d['hasGoogleDirections'] == true,
      startedAt: (d['startedAt'] as Timestamp?)?.toDate(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
    );
  }
}

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
    this.currentIndex = 0,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String courierId;
  final String status;
  final List<String> orderIds;
  final int currentIndex;
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
      currentIndex: (d['currentIndex'] as num?)?.toInt() ?? 0,
      startedAt: (d['startedAt'] as Timestamp?)?.toDate(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
    );
  }
}

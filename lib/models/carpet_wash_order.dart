import 'package:cloud_firestore/cloud_firestore.dart';

/// `carpet_wash_orders/{id}` — gilam yuvish buyurtmasi.
class CarpetWashOrder {
  const CarpetWashOrder({
    required this.id,
    required this.customerId,
    required this.customerPhone,
    required this.customerName,
    required this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    required this.carpetCount,
    this.note = '',
    this.priceMode = 'admin',
    this.finalPrice = 0,
    required this.status,
    this.pickupCourierId = '',
    this.returnCourierId = '',
    this.pickupArrivedAt,
    this.returnArrivedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String customerId;
  final String customerPhone;
  final String customerName;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final int carpetCount;
  final String note;
  final String priceMode;
  final int finalPrice;
  final String status;
  final String pickupCourierId;
  final String returnCourierId;
  final DateTime? pickupArrivedAt;
  final DateTime? returnArrivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const statusNew = 'new';
  static const statusAccepted = 'accepted';
  static const statusPickupReady = 'pickup_ready';
  static const statusPickupInDelivery = 'pickup_in_delivery';
  static const statusPickedUp = 'picked_up';
  static const statusWashing = 'washing';
  static const statusDrying = 'drying';
  static const statusReady = 'ready';
  static const statusReturnReady = 'return_ready';
  static const statusReturnInDelivery = 'return_in_delivery';
  static const statusDelivered = 'delivered';
  static const statusCompleted = 'completed';
  static const statusCancelled = 'cancelled';

  bool get isActive =>
      status != statusCompleted &&
      status != statusCancelled;

  bool get isPickupClaimable => status == statusPickupReady;

  bool get isReturnClaimable => status == statusReturnReady;

  String statusLabelKey() => switch (status) {
        statusNew => 'carpet_status_new',
        statusAccepted => 'carpet_status_accepted',
        statusPickupReady => 'carpet_status_pickup_ready',
        statusPickupInDelivery => 'carpet_status_pickup_in_delivery',
        statusPickedUp => 'carpet_status_picked_up',
        statusWashing => 'carpet_status_washing',
        statusDrying => 'carpet_status_drying',
        statusReady => 'carpet_status_ready',
        statusReturnReady => 'carpet_status_return_ready',
        statusReturnInDelivery => 'carpet_status_return_in_delivery',
        statusDelivered => 'carpet_status_delivered',
        statusCompleted => 'carpet_status_completed',
        statusCancelled => 'carpet_status_cancelled',
        _ => 'carpet_status_new',
      };

  factory CarpetWashOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CarpetWashOrder(
      id: doc.id,
      customerId: (d['customerId'] ?? '') as String,
      customerPhone: (d['customerPhone'] ?? '') as String,
      customerName: (d['customerName'] ?? '') as String,
      pickupAddress: (d['pickupAddress'] ?? '') as String,
      pickupLat: (d['pickupLat'] as num?)?.toDouble(),
      pickupLng: (d['pickupLng'] as num?)?.toDouble(),
      carpetCount: (d['carpetCount'] as num?)?.toInt() ?? 1,
      note: (d['note'] ?? '') as String,
      priceMode: (d['priceMode'] ?? 'admin') as String,
      finalPrice: (d['finalPrice'] as num?)?.toInt() ?? 0,
      status: (d['status'] ?? statusNew) as String,
      pickupCourierId: (d['pickupCourierId'] ?? '') as String,
      returnCourierId: (d['returnCourierId'] ?? '') as String,
      pickupArrivedAt: (d['pickupArrivedAt'] as Timestamp?)?.toDate(),
      returnArrivedAt: (d['returnArrivedAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

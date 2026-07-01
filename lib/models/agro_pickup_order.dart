import 'package:cloud_firestore/cloud_firestore.dart';

/// `agro_pickup_orders/{id}` — qishloq xo'jaligi mahsulotini qabul qilish.
class AgroPickupOrder {
  const AgroPickupOrder({
    required this.id,
    required this.customerId,
    required this.customerPhone,
    required this.customerName,
    required this.productType,
    required this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    required this.literCount,
    this.note = '',
    this.priceMode = 'admin',
    this.finalPrice = 0,
    required this.status,
    this.pickupCourierId = '',
    this.arrivedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String customerId;
  final String customerPhone;
  final String customerName;
  final String productType;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double literCount;
  final String note;
  final String priceMode;
  final int finalPrice;
  final String status;
  final String pickupCourierId;
  final DateTime? arrivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const productMilk = 'milk';

  static const statusNew = 'new';
  static const statusAccepted = 'accepted';
  static const statusPickupInDelivery = 'pickup_in_delivery';
  static const statusPickedUp = 'picked_up';
  static const statusCompleted = 'completed';
  static const statusCancelled = 'cancelled';

  bool get isActive =>
      status != statusCompleted && status != statusCancelled;

  String statusLabelKey() => switch (status) {
        statusNew => 'agro_status_new',
        statusAccepted => 'agro_status_accepted',
        statusPickupInDelivery => 'agro_status_pickup_in_delivery',
        statusPickedUp => 'agro_status_picked_up',
        statusCompleted => 'agro_status_completed',
        statusCancelled => 'agro_status_cancelled',
        _ => 'agro_status_new',
      };

  factory AgroPickupOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return AgroPickupOrder(
      id: doc.id,
      customerId: (d['customerId'] ?? '') as String,
      customerPhone: (d['customerPhone'] ?? '') as String,
      customerName: (d['customerName'] ?? '') as String,
      productType: (d['productType'] ?? productMilk) as String,
      pickupAddress: (d['pickupAddress'] ?? '') as String,
      pickupLat: (d['pickupLat'] as num?)?.toDouble(),
      pickupLng: (d['pickupLng'] as num?)?.toDouble(),
      literCount: (d['literCount'] as num?)?.toDouble() ?? 0,
      note: (d['note'] ?? '') as String,
      priceMode: (d['priceMode'] ?? 'admin') as String,
      finalPrice: (d['finalPrice'] as num?)?.toInt() ?? 0,
      status: (d['status'] ?? statusNew) as String,
      pickupCourierId: (d['pickupCourierId'] ?? '') as String,
      arrivedAt: (d['arrivedAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

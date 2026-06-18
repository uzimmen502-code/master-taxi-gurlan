import 'package:cloud_firestore/cloud_firestore.dart';

enum CourierOrderStatus {
  pending,
  accepted,
  pickedUp,
  delivered,
  cancelled,
}

/// `courier_orders` — kuryer buyurtma (sotib olish / yetkazish).
class CourierOrder {
  const CourierOrder({
    required this.id,
    required this.customerPhone,
    required this.customerName,
    required this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    required this.description,
    required this.estimatedPrice,
    required this.deliveryFee,
    required this.totalPrice,
    required this.status,
    this.courierId = '',
    this.courierName = '',
    this.createdAt,
    this.acceptedAt,
    this.deliveredAt,
  });

  final String id;
  final String customerPhone;
  final String customerName;
  final String deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final String description;
  final int estimatedPrice;
  final int deliveryFee;
  final int totalPrice;
  final CourierOrderStatus status;
  final String courierId;
  final String courierName;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? deliveredAt;

  bool get isActive =>
      status == CourierOrderStatus.pending ||
      status == CourierOrderStatus.accepted ||
      status == CourierOrderStatus.pickedUp;

  String get statusLabel => switch (status) {
        CourierOrderStatus.pending => 'Kutilmoqda',
        CourierOrderStatus.accepted => 'Qabul qilindi',
        CourierOrderStatus.pickedUp => 'Yo\'lda',
        CourierOrderStatus.delivered => 'Yetkazildi',
        CourierOrderStatus.cancelled => 'Bekor qilindi',
      };

  static String statusToFirestore(CourierOrderStatus status) =>
      switch (status) {
        CourierOrderStatus.pending => 'pending',
        CourierOrderStatus.accepted => 'accepted',
        CourierOrderStatus.pickedUp => 'picked_up',
        CourierOrderStatus.delivered => 'delivered',
        CourierOrderStatus.cancelled => 'cancelled',
      };

  static CourierOrderStatus statusFromFirestore(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'accepted':
        return CourierOrderStatus.accepted;
      case 'picked_up':
      case 'pickedup':
        return CourierOrderStatus.pickedUp;
      case 'delivered':
        return CourierOrderStatus.delivered;
      case 'cancelled':
      case 'canceled':
        return CourierOrderStatus.cancelled;
      default:
        return CourierOrderStatus.pending;
    }
  }

  factory CourierOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CourierOrder(
      id: doc.id,
      customerPhone: (d['customerPhone'] ?? '') as String,
      customerName: (d['customerName'] ?? '') as String,
      deliveryAddress: (d['deliveryAddress'] ?? '') as String,
      deliveryLat: (d['deliveryLat'] as num?)?.toDouble(),
      deliveryLng: (d['deliveryLng'] as num?)?.toDouble(),
      description: (d['description'] ?? '') as String,
      estimatedPrice: (d['estimatedPrice'] as num?)?.toInt() ?? 0,
      deliveryFee: (d['deliveryFee'] as num?)?.toInt() ?? 0,
      totalPrice: (d['totalPrice'] as num?)?.toInt() ?? 0,
      status: statusFromFirestore((d['status'] ?? 'pending') as String),
      courierId: (d['courierId'] ?? '') as String,
      courierName: (d['courierName'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      acceptedAt: (d['acceptedAt'] as Timestamp?)?.toDate(),
      deliveredAt: (d['deliveredAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'customerPhone': customerPhone,
        'customerName': customerName,
        'deliveryAddress': deliveryAddress,
        if (deliveryLat != null) 'deliveryLat': deliveryLat,
        if (deliveryLng != null) 'deliveryLng': deliveryLng,
        'description': description,
        'estimatedPrice': estimatedPrice,
        'deliveryFee': deliveryFee,
        'totalPrice': totalPrice,
        'status': statusToFirestore(status),
        'courierId': courierId,
        'courierName': courierName,
        'createdAt': FieldValue.serverTimestamp(),
      };

  CourierOrder copyWith({
    String? id,
    String? customerPhone,
    String? customerName,
    String? deliveryAddress,
    double? deliveryLat,
    double? deliveryLng,
    String? description,
    int? estimatedPrice,
    int? deliveryFee,
    int? totalPrice,
    CourierOrderStatus? status,
    String? courierId,
    String? courierName,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? deliveredAt,
  }) {
    return CourierOrder(
      id: id ?? this.id,
      customerPhone: customerPhone ?? this.customerPhone,
      customerName: customerName ?? this.customerName,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryLat: deliveryLat ?? this.deliveryLat,
      deliveryLng: deliveryLng ?? this.deliveryLng,
      description: description ?? this.description,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      totalPrice: totalPrice ?? this.totalPrice,
      status: status ?? this.status,
      courierId: courierId ?? this.courierId,
      courierName: courierName ?? this.courierName,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
    );
  }
}

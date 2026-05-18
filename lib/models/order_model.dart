import 'package:cloud_firestore/cloud_firestore.dart';

/// `orders` collection — non/ovqat buyurtmasi.
class OrderModel {
  final String id;
  final String type; // bread | food
  final int total;
  final String status; // new | accepted | ready | delivered | rejected
  final List<OrderItem> items;
  final String address;
  final String deliveryTime;
  final String rejectReason;
  final DateTime? createdAt;

  // Kuryer pipeline'ida ishlatiladigan qo'shimcha maydonlar
  final String userName;
  final String userPhone;
  final double? lat;
  final double? lng;

  const OrderModel({
    required this.id,
    required this.type,
    required this.total,
    required this.status,
    required this.items,
    this.address = '',
    this.deliveryTime = '',
    this.rejectReason = '',
    this.createdAt,
    this.userName = '',
    this.userPhone = '',
    this.lat,
    this.lng,
  });

  bool get hasCoordinates => lat != null && lng != null;
  bool get isDelivered => status == 'delivered';

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  factory OrderModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawItems = (d['items'] as List?) ?? const [];
    return OrderModel(
      id: doc.id,
      type: d['type'] ?? 'bread',
      total: (d['total'] as num?)?.toInt() ?? 0,
      status: d['status'] ?? 'new',
      items: rawItems
          .whereType<Map>()
          .map((m) => OrderItem.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      address: d['address'] ?? '',
      deliveryTime: d['deliveryTime'] ?? '',
      rejectReason: d['rejectReason'] ?? '',
      createdAt: _parseDate(d['createdAt']),
      userName: d['userName'] ?? '',
      userPhone: d['userPhone'] ?? '',
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
    );
  }
}

class OrderItem {
  final String name;
  final int count;
  final num? qty;
  final String unit;

  const OrderItem({
    required this.name,
    this.count = 1,
    this.qty,
    this.unit = '',
  });

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
        name: m['name'] ?? '',
        count: (m['count'] as num?)?.toInt() ?? 1,
        qty: m['qty'] as num?,
        unit: m['unit'] ?? '',
      );
}

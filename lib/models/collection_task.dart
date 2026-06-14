import 'package:cloud_firestore/cloud_firestore.dart';

/// Битта йиғиб оlish qator — каталог + miqdor + narx.
class CollectionItem {
  const CollectionItem({
    required this.code,
    required this.label,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String code;
  final String label;
  final String unit;
  final num qty;
  final int unitPrice;
  final int lineTotal;

  Map<String, dynamic> toMap() => {
        'code': code,
        'label': label,
        'unit': unit,
        'qty': qty,
        'unitPrice': unitPrice,
        'lineTotal': lineTotal,
      };

  factory CollectionItem.fromMap(Map<String, dynamic> m) {
    return CollectionItem(
      code: (m['code'] ?? '') as String,
      label: (m['label'] ?? '') as String,
      unit: (m['unit'] ?? '') as String,
      qty: (m['qty'] as num?) ?? 0,
      unitPrice: (m['unitPrice'] as num?)?.toInt() ?? 0,
      lineTotal: (m['lineTotal'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `collection_tasks` — сotish taklifidan operational йиғиб оlish vazifasi.
class CollectionTask {
  const CollectionTask({
    required this.id,
    required this.submissionId,
    required this.customerPhone,
    required this.customerUid,
    required this.customerName,
    required this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    required this.items,
    required this.totalValue,
    required this.courierId,
    required this.status,
    this.createdAt,
    this.createdBy = '',
  });

  final String id;
  final String submissionId;
  final String customerPhone;
  final String customerUid;
  final String customerName;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final List<CollectionItem> items;
  final int totalValue;
  final String courierId;
  final String status;
  final DateTime? createdAt;
  final String createdBy;

  bool get hasPickupGps => pickupLat != null && pickupLng != null;

  bool get isActive =>
      status == 'assigned' || status == 'collecting';

  String? get mapsUrl {
    if (!hasPickupGps) return null;
    return 'https://www.google.com/maps?q=$pickupLat,$pickupLng';
  }

  static String statusLabel(String s) {
    switch (s) {
      case 'collecting':
        return 'Йиғилмоқда';
      case 'completed':
        return 'Якунланган';
      case 'cancelled':
        return 'Бекор қилинган';
      default:
        return 'Тайинланган';
    }
  }

  factory CollectionTask.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawItems = d['items'];
    final items = <CollectionItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          items.add(CollectionItem.fromMap(Map<String, dynamic>.from(e)));
        }
      }
    }
    return CollectionTask(
      id: doc.id,
      submissionId: (d['submissionId'] ?? '') as String,
      customerPhone: (d['customerPhone'] ?? '') as String,
      customerUid: (d['customerUid'] ?? '') as String,
      customerName: (d['customerName'] ?? '') as String,
      pickupAddress: (d['pickupAddress'] ?? '') as String,
      pickupLat: (d['pickupLat'] as num?)?.toDouble(),
      pickupLng: (d['pickupLng'] as num?)?.toDouble(),
      items: items,
      totalValue: (d['totalValue'] as num?)?.toInt() ?? 0,
      courierId: (d['courierId'] ?? '') as String,
      status: (d['status'] ?? 'assigned') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      createdBy: (d['createdBy'] ?? '') as String,
    );
  }
}

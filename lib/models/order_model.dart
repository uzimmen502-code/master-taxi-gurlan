import 'package:cloud_firestore/cloud_firestore.dart';

/// `orders` collection — non/ovqat buyurtmasi.
class OrderModel {
  final String id;
  final String type; // bread | food
  final int total;
  final String status; // legacy
  final List<OrderItem> items;
  final String address;
  final String deliveryTime;
  final String rejectReason;
  final DateTime? createdAt;

  final String userName;
  final String userPhone;
  final String? mfy;
  final double? lat;
  final double? lng;

  final int balanceApplied;
  final int cashDue;
  final int cashPaid;

  final List<Map<String, dynamic>> extras;

  /// Нон: туз/хамирта (мижоз савати билан бир хил чек).
  final int saltYeastCost;
  final bool cartHadYopishBread;

  /// Post-paid pipeline (Phase 1+).
  final String fulfillmentStatus;
  final String paymentStatus;
  final String fulfillmentMode;
  final String? courierId;
  final String? routeId;
  final String paymentMethod;
  final int paidAmount;
  final bool customerConfirmed;

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
    this.mfy,
    this.lat,
    this.lng,
    this.balanceApplied = 0,
    this.cashDue = 0,
    this.cashPaid = 0,
    this.extras = const [],
    this.saltYeastCost = 0,
    this.cartHadYopishBread = false,
    this.fulfillmentStatus = '',
    this.paymentStatus = '',
    this.fulfillmentMode = 'delivery',
    this.courierId,
    this.routeId,
    this.paymentMethod = '',
    this.paidAmount = 0,
    this.customerConfirmed = false,
  });

  bool get hasCoordinates => lat != null && lng != null;

  String get effectiveFulfillment {
    final fs = fulfillmentStatus.trim();
    if (fs.isNotEmpty) return fs;
    return _legacyToFulfillment(status);
  }

  String get effectivePayment {
    final ps = paymentStatus.trim();
    if (ps.isNotEmpty) return ps;
    if (status == 'delivered') return 'paid';
    return 'unpaid';
  }

  bool get isDelivered =>
      status == 'delivered' || effectiveFulfillment == 'completed';

  bool get canCourierPick =>
      effectiveFulfillment == 'confirmed' ||
      effectiveFulfillment == 'pending' ||
      status == 'accepted' ||
      status == 'ready' ||
      status == 'new';

  bool get canCourierArrive => effectiveFulfillment == 'courier_picked';

  bool get canCourierPay => effectiveFulfillment == 'arrived';

  /// Мижоз бекор: курьер олмаган / етиб келмаган / якунланмаган.
  bool get canCustomerCancel {
    if (effectivePayment == 'paid' &&
        effectiveFulfillment == 'completed') {
      return false;
    }
    final fs = effectiveFulfillment;
    if (fs == 'courier_picked' ||
        fs == 'arrived' ||
        fs == 'completed' ||
        fs == 'cancelled') {
      return false;
    }
    if (status == 'in_delivery' ||
        status == 'delivered' ||
        status == 'cancelled' ||
        status == 'rejected') {
      return false;
    }
    return status == 'new' ||
        status == 'accepted' ||
        status == 'ready' ||
        fs == 'pending' ||
        fs == 'confirmed' ||
        fs == 'ready';
  }

  /// Курьер/seller тўлаши керак бўлган қолдиқ.
  int get collectibleDue {
    if (cashDue > 0) return cashDue;
    if (balanceApplied > 0) {
      final d = total - balanceApplied;
      return d < 0 ? 0 : d;
    }
    return total;
  }

  static String _legacyToFulfillment(String s) {
    switch (s) {
      case 'accepted':
      case 'ready':
        return 'confirmed';
      case 'in_delivery':
      case 'courier':
        return 'courier_picked';
      case 'delivered':
        return 'completed';
      case 'rejected':
      case 'cancelled':
        return 'cancelled';
      default:
        return 'pending';
    }
  }

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
      mfy: d['mfy'] as String?,
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      balanceApplied: (d['balanceApplied'] as num?)?.toInt() ?? 0,
      cashDue: (d['cashDue'] as num?)?.toInt() ?? 0,
      cashPaid: (d['cashPaid'] as num?)?.toInt() ?? 0,
      extras: (d['extras'] as List?)
              ?.whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList() ??
          const [],
      saltYeastCost: (d['saltYeastCost'] as num?)?.toInt() ?? 0,
      cartHadYopishBread: d['cartHadYopishBread'] == true,
      fulfillmentStatus: (d['fulfillmentStatus'] ?? '') as String,
      paymentStatus: (d['paymentStatus'] ?? '') as String,
      fulfillmentMode: (d['fulfillmentMode'] ?? 'delivery') as String,
      courierId: d['courierId'] as String?,
      routeId: d['routeId'] as String?,
      paymentMethod: (d['paymentMethod'] ?? '') as String,
      paidAmount: (d['paidAmount'] as num?)?.toInt() ?? 0,
      customerConfirmed: d['customerConfirmed'] == true,
    );
  }
}

class OrderItem {
  final String name;
  final int count;
  final num? qty;
  final String unit;
  final String emoji;
  final int unitPrice;
  final int baseLineTotal;
  final int flourMilkCost;
  final int lineTotal;
  final String flourMilk;
  final String productType;
  final int itemTotal;

  const OrderItem({
    required this.name,
    this.count = 1,
    this.qty,
    this.unit = '',
    this.emoji = '',
    this.unitPrice = 0,
    this.baseLineTotal = 0,
    this.flourMilkCost = 0,
    this.lineTotal = 0,
    this.flourMilk = 'none',
    this.productType = '',
    this.itemTotal = 0,
  });

  bool get isYopishOrToy =>
      productType == 'ёпиш' || productType == 'той';

  factory OrderItem.fromMap(Map<String, dynamic> m) {
    final price = (m['price'] as num?)?.toInt() ?? 0;
    final count = (m['count'] as num?)?.toInt() ?? 1;
    final base = (m['baseLineTotal'] as num?)?.toInt() ??
        (price > 0 ? price * count : 0);
    final fm = (m['flourMilkCost'] as num?)?.toInt() ?? 0;
    final line = (m['lineTotal'] as num?)?.toInt() ?? (base + fm);
    final foodTotal = (m['total'] as num?)?.toInt() ?? 0;
    return OrderItem(
      name: m['name'] ?? '',
      count: count,
      qty: m['qty'] as num?,
      unit: m['unit'] ?? '',
      emoji: (m['emoji'] ?? '') as String,
      unitPrice: price,
      baseLineTotal: base,
      flourMilkCost: fm,
      lineTotal: line,
      flourMilk: (m['flourMilk'] ?? 'none') as String,
      productType: (m['type'] ?? '') as String,
      itemTotal: foodTotal,
    );
  }
}

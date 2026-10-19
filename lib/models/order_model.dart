import 'package:cloud_firestore/cloud_firestore.dart';

/// `orders` collection — non/ovqat buyurtmasi.
class OrderModel {
  final String id;
  final String type; // bread | platform | restaurant (эски: food)
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

  /// Кафе-ресторан буюртмаси (`type: 'restaurant'`, restaurant_orders.js).
  /// Ҳолат — `restaurantStatus` (ягона жадвал); `status`/`fulfillmentStatus`
  /// ундан ҳосил қилинган (эски экранлар учун).
  final String restaurantId;
  final String restaurantName;
  final String restaurantStatus;

  /// Ресторан жойлашуви — курьернинг биринчи бекати (буюртмага snapshot).
  final String restaurantAddress;
  final double? restaurantLat;
  final double? restaurantLng;
  final int itemsTotal;

  /// ФАҚАТ ЭСКИ буюртмалар: қадоқлаш ҳақи олиб ташланган (D-REST-28), янги буюртмада 0.
  /// Эски ҳужжатларнинг жами суммаси тўғри кўриниши учун ўқилади — тўғридан-тўғри эмас,
  /// [foodAmount] орқали.
  final int packagingTotal;

  /// Миқдорга чегирма жами (D-REST-25): `itemsTotal` ШУ чегирмадан кейинги сумма; йўқ ҳужжатда — 0.
  final int qtyDiscountTotal;
  final int deliveryFee;

  /// Таом пули (мижоз ресторанга тўлайдиган / курьер выкуп қиладиган сумма) = таом + эски
  /// қадоқлаш. Ягона ҳисоб (7-қоида); сервердаги `foodAmountOf` билан бир хил.
  int get foodAmount => itemsTotal + packagingTotal;

  /// `ava_courier` · `own_courier` · `pickup`.
  final String deliveryMode;

  /// `prepay` · `cash_buyout` · `cash_to_restaurant`.
  final String foodPaymentMethod;

  /// `cash` · `wallet` · `none`.
  final String deliveryPaymentMethod;

  /// Олдиндан тўлов реквизити snapshot'и (`cardNumber`, `cardHolder`, `qrImageUrl`).
  final Map<String, dynamic>? restaurantPayment;
  final int prepTimeMin;
  final String note;
  final DateTime? acceptDeadlineAt;
  final int utensils;

  /// AVA ҳақи (2 %): `avaFee.amount` / `charged` / `refunded` — ҳисобот учун.
  final int avaFeeAmount;
  final bool avaFeeCharged;
  final bool avaFeeRefunded;

  /// Мижоз қўйган таом баҳолари: `itemId → 1..5`. Фақат сервер ёзади
  /// (`submitDishRatings`); эски буюртмаларда йўқ — бўш харита.
  final Map<String, int> dishRatings;

  /// Ресторан буюртмаси етказилган вақт (`deliveredAt`, эскиларда `statusUpdatedAt`) — баҳолаш
  /// муддати шундан ҳисобланади.
  final DateTime? deliveredAt;

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
    this.restaurantId = '',
    this.restaurantName = '',
    this.restaurantStatus = '',
    this.restaurantAddress = '',
    this.restaurantLat,
    this.restaurantLng,
    this.itemsTotal = 0,
    this.packagingTotal = 0,
    this.qtyDiscountTotal = 0,
    this.deliveryFee = 0,
    this.deliveryMode = '',
    this.foodPaymentMethod = '',
    this.deliveryPaymentMethod = '',
    this.restaurantPayment,
    this.prepTimeMin = 0,
    this.note = '',
    this.acceptDeadlineAt,
    this.utensils = 0,
    this.avaFeeAmount = 0,
    this.avaFeeCharged = false,
    this.avaFeeRefunded = false,
    this.dishRatings = const {},
    this.deliveredAt,
  });

  bool get isRestaurant => type == 'restaurant';

  /// Таомларни баҳолаш мумкин: ресторан буюртмаси ва ЕТКАЗИЛГАН (сервер ҳам шуни талаб қилади).
  bool get canRateDishes => isRestaurant && restaurantStatus == 'delivered';

  /// Серверга юбориладиган хом харита → `itemId → 1..5` (нотўғри қийматлар ташланади).
  static Map<String, int> parseDishRatings(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      final n = v is num && v == v.toInt() ? v.toInt() : null;
      if (k is String && n != null && n >= 1 && n <= 5) out[k] = n;
    });
    return out;
  }

  /// Олиб ташланган «Овқат» модулининг буюртмаси (эга, 2026-10-11) — ҳеч
  /// бир рўйхатда кўрсатилмайди; прод ҳужжатлари алоҳида тозаланади.
  bool get isRemovedFoodOrder => type == 'food';

  /// Админ доскалари ва чек учун тур номи — ягона манба (аввал уч жойда
  /// алоҳида ёзилган, улгуржи буюртма «Нон» кўринарди).
  String get typeLabelUz => switch (type) {
        'restaurant' => 'Кафе-ресторан',
        'platform' => 'Улгуржи бозор',
        _ => 'Нон',
      };

  bool get hasCoordinates => lat != null && lng != null;

  bool get hasRestaurantCoordinates =>
      restaurantLat != null && restaurantLng != null;

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

  /// Админ устунидаги якуний ҳолат: «Етказилди» ёки «Рад қилинган».
  /// Бу буюртмада бошқа ҳаракат қолмаган.
  bool get hasFinalStatus =>
      status == 'delivered' || status == 'rejected' || status == 'cancelled';

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
    // Ресторан буюртмаси — фақат ресторан қабул қилгунча (2 % ҳали
    // ечилмаган; `customerCancelRestaurantOrder`).
    if (isRestaurant) return restaurantStatus == 'placed';
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
      restaurantId: (d['restaurantId'] ?? '') as String,
      restaurantName: (d['restaurantName'] ?? '') as String,
      restaurantStatus: (d['restaurantStatus'] ?? '') as String,
      restaurantAddress: (d['restaurantAddress'] ?? '') as String,
      restaurantLat: (d['restaurantLat'] as num?)?.toDouble(),
      restaurantLng: (d['restaurantLng'] as num?)?.toDouble(),
      itemsTotal: (d['itemsTotal'] as num?)?.toInt() ?? 0,
      packagingTotal: (d['packagingTotal'] as num?)?.toInt() ?? 0,
      qtyDiscountTotal: (d['qtyDiscountTotal'] as num?)?.toInt() ?? 0,
      deliveryFee: (d['deliveryFee'] as num?)?.toInt() ?? 0,
      deliveryMode: (d['deliveryMode'] ?? '') as String,
      foodPaymentMethod: (d['foodPaymentMethod'] ?? '') as String,
      deliveryPaymentMethod: (d['deliveryPaymentMethod'] ?? '') as String,
      restaurantPayment: d['restaurantPayment'] is Map
          ? Map<String, dynamic>.from(d['restaurantPayment'] as Map)
          : null,
      prepTimeMin: (d['prepTimeMin'] as num?)?.toInt() ?? 0,
      note: (d['note'] ?? '') as String,
      acceptDeadlineAt: _parseDate(d['acceptDeadlineAt']),
      utensils: (d['utensils'] as num?)?.toInt() ?? 0,
      avaFeeAmount: ((d['avaFee'] is Map ? (d['avaFee'] as Map)['amount'] : null) as num?)?.toInt() ?? 0,
      avaFeeCharged: d['avaFee'] is Map && (d['avaFee'] as Map)['charged'] == true,
      avaFeeRefunded: d['avaFee'] is Map && (d['avaFee'] as Map)['refunded'] == true,
      dishRatings: parseDishRatings(d['dishRatings']),
      deliveredAt: _parseDate(d['deliveredAt']) ?? _parseDate(d['statusUpdatedAt']),
    );
  }
}

class OrderItem {
  /// Фақат ресторан буюртмасида: меню таомининг идентификатори (баҳолаш учун).
  final String itemId;
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
    this.itemId = '',
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
      itemId: (m['itemId'] ?? '') as String,
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

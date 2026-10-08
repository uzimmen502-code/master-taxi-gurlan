// Кафе-ресторанлар — репозиторий.
//
// ЁЗИШ — фақат callable орқали (`functions/restaurant_orders.js`, default
// codebase, us-central1): нарх, ҳолат ўтишлари, 2 % — серверда. ЎҚИШ —
// Firestore stream (ресторанлар, меню, буюртма). Қоидалар:
// `restaurants` `status == approved` рўйхати ҳаммага; буюртма — эгасига.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../models/order_model.dart';
import '../domain/restaurant_models.dart';

class RestaurantsException implements Exception {
  const RestaurantsException(this.code, this.reason, this.message, {this.details});

  /// `FirebaseFunctionsException.code` (`failed-precondition`, …).
  final String code;

  /// Сервер `details.code` — диагностика коди (`RESTAURANT_PAUSED`, …).
  final String reason;
  final String message;
  final Map<String, dynamic>? details;

  String get l10nKey => restaurantsErrorKey(reason);

  @override
  String toString() => 'RestaurantsException($code/$reason): $message';
}

class DeliveryQuote {
  const DeliveryQuote({
    required this.deliveryMode,
    required this.deliveryFee,
    this.distanceMeters,
    this.tariffVersion,
  });

  final String deliveryMode;
  final int deliveryFee;
  final int? distanceMeters;
  final int? tariffVersion;

  factory DeliveryQuote.fromMap(Map<String, dynamic> m) => DeliveryQuote(
        deliveryMode: (m['deliveryMode'] ?? '') as String,
        deliveryFee: (m['deliveryFee'] as num?)?.toInt() ?? 0,
        distanceMeters: (m['distanceMeters'] as num?)?.toInt(),
        tariffVersion: (m['tariffVersion'] as num?)?.toInt(),
      );
}

class PlaceOrderResult {
  const PlaceOrderResult({
    required this.orderId,
    required this.itemsTotal,
    required this.packagingTotal,
    required this.deliveryFee,
    required this.total,
    this.duplicate = false,
  });

  final String orderId;
  final int itemsTotal;
  final int packagingTotal;
  final int deliveryFee;
  final int total;
  final bool duplicate;

  factory PlaceOrderResult.fromMap(Map<String, dynamic> m) => PlaceOrderResult(
        orderId: (m['orderId'] ?? '') as String,
        itemsTotal: (m['itemsTotal'] as num?)?.toInt() ?? 0,
        packagingTotal: (m['packagingTotal'] as num?)?.toInt() ?? 0,
        deliveryFee: (m['deliveryFee'] as num?)?.toInt() ?? 0,
        total: (m['total'] as num?)?.toInt() ?? 0,
        duplicate: m['duplicate'] == true,
      );
}

/// Курьер учун яқиндаги буюртма проекцияси (`listNearbyRestaurantOrders`):
/// мижоз телефони ва аниқ манзили ЙЎҚ (40-қоида).
class NearbyRestaurantOrder {
  const NearbyRestaurantOrder({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantAddress,
    required this.restaurantStatus,
    required this.deliveryFee,
    required this.deliveryPaymentMethod,
    required this.foodPaymentMethod,
    required this.buyoutAmount,
    this.restaurantLat,
    this.restaurantLng,
    this.distanceMeters,
    this.courierToRestaurantM,
    this.prepTimeMin,
    this.readyAt,
    this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String restaurantAddress;
  final String restaurantStatus;
  final int deliveryFee;
  final String deliveryPaymentMethod;
  final String foodPaymentMethod;

  /// Выкуп суммаси (нақд буюртмада курьер ресторанга тўлайди); 0 — олдиндан тўланган.
  final int buyoutAmount;
  final double? restaurantLat;
  final double? restaurantLng;
  final int? distanceMeters;
  final int? courierToRestaurantM;
  final int? prepTimeMin;
  final DateTime? readyAt;
  final DateTime? createdAt;

  bool get isBuyout => foodPaymentMethod == 'cash_buyout';

  factory NearbyRestaurantOrder.fromMap(Map<String, dynamic> m) {
    DateTime? ms(dynamic v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return NearbyRestaurantOrder(
      id: (m['id'] ?? '') as String,
      restaurantId: (m['restaurantId'] ?? '') as String,
      restaurantName: (m['restaurantName'] ?? '') as String,
      restaurantAddress: (m['restaurantAddress'] ?? '') as String,
      restaurantStatus: (m['restaurantStatus'] ?? '') as String,
      deliveryFee: (m['deliveryFee'] as num?)?.toInt() ?? 0,
      deliveryPaymentMethod: (m['deliveryPaymentMethod'] ?? 'cash') as String,
      foodPaymentMethod: (m['foodPaymentMethod'] ?? '') as String,
      buyoutAmount: (m['buyoutAmount'] as num?)?.toInt() ?? 0,
      restaurantLat: (m['restaurantLat'] as num?)?.toDouble(),
      restaurantLng: (m['restaurantLng'] as num?)?.toDouble(),
      distanceMeters: (m['distanceMeters'] as num?)?.toInt(),
      courierToRestaurantM: (m['courierToRestaurantM'] as num?)?.toInt(),
      prepTimeMin: (m['prepTimeMin'] as num?)?.toInt(),
      readyAt: ms(m['readyAtMs']),
      createdAt: ms(m['createdAtMs']),
    );
  }
}

class RestaurantsRepository {
  RestaurantsRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _db = firestore ?? FirebaseFirestore.instance,
        _fn = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  CollectionReference<Map<String, dynamic>> get _restaurants => _db.collection('restaurants');
  CollectionReference<Map<String, dynamic>> get _orders => _db.collection('orders');

  // ── Ўқиш ───────────────────────────────────────────────────────────

  /// Тасдиқланган ресторанлар — қоида `where status == approved` талаб қилади.
  /// Масофа бўйича тартиб — чақирувчида (фойдаланувчи координатаси билан).
  Stream<List<Restaurant>> watchApproved({int limit = 50}) => _restaurants
      .where('status', isEqualTo: 'approved')
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(Restaurant.fromDoc).toList(growable: false));

  Stream<Restaurant?> watchRestaurant(String id) => _restaurants
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Restaurant.fromDoc(d) : null);

  Future<Restaurant?> getRestaurant(String id) async {
    final d = await _restaurants.doc(id).get();
    return d.exists ? Restaurant.fromDoc(d) : null;
  }

  /// Эганинг ўз ресторанлари (қоида: `where ownerUid == мен`).
  Stream<List<Restaurant>> watchMine(String ownerUid) => _restaurants
      .where('ownerUid', isEqualTo: ownerUid)
      .snapshots()
      .map((s) => s.docs.map(Restaurant.fromDoc).toList(growable: false));

  Stream<List<MenuCategory>> watchCategories(String restaurantId) => _restaurants
      .doc(restaurantId)
      .collection('menu_categories')
      .snapshots()
      .map((s) => s.docs.map(MenuCategory.fromDoc).toList()
        ..sort((a, b) => a.sort.compareTo(b.sort)));

  Stream<List<MenuItem>> watchMenu(String restaurantId) => _restaurants
      .doc(restaurantId)
      .collection('menu_items')
      .snapshots()
      .map((s) => s.docs.map(MenuItem.fromDoc).toList()
        ..sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.name.compareTo(b.name)));

  Stream<OrderModel?> watchOrder(String orderId) => _orders
      .doc(orderId)
      .snapshots()
      .map((d) => d.exists ? OrderModel.fromDoc(d) : null);

  /// Ресторан а'зоси учун — ўз ресторанининг буюртмалари (қоида:
  /// `where restaurantId == X`).
  Stream<List<OrderModel>> watchRestaurantOrders(String restaurantId, {int limit = 100}) => _orders
      .where('restaurantId', isEqualTo: restaurantId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(OrderModel.fromDoc).toList(growable: false));

  // ── Callable'лар ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _fn.httpsCallable(name).call<dynamic>(data);
      final raw = res.data;
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : null;
      final reason = (details?['code'] ?? e.message ?? e.code).toString();
      throw RestaurantsException(e.code, reason, e.message ?? e.code, details: details);
    }
  }

  /// INTERNAL босқич (42-қоида): модул «Тез кунда» бўлса ҳам синовчи кира
  /// оладими. Хато — ёпиқ томонга.
  Future<bool> hasAccess() async {
    try {
      return (await _call('getRestaurantsAccess', const {}))['allowed'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<DeliveryQuote> quoteDelivery({
    required String restaurantId,
    required double lat,
    required double lng,
    int itemsTotal = 0,
  }) async =>
      DeliveryQuote.fromMap(await _call('quoteRestaurantDelivery', {
        'restaurantId': restaurantId,
        'lat': lat,
        'lng': lng,
        'itemsTotal': itemsTotal,
      }));

  Future<PlaceOrderResult> placeOrder({
    required String idempotencyKey,
    required String restaurantId,
    required List<Map<String, dynamic>> items,
    required String fulfillmentMode,
    required String foodPaymentMethod,
    required String deliveryPaymentMethod,
    String address = '',
    double? lat,
    double? lng,
    String note = '',
    int utensils = 0,
    String userName = '',
  }) async =>
      PlaceOrderResult.fromMap(await _call('placeRestaurantOrder', {
        'idempotencyKey': idempotencyKey,
        'restaurantId': restaurantId,
        'items': items,
        'fulfillmentMode': fulfillmentMode,
        'foodPaymentMethod': foodPaymentMethod,
        'deliveryPaymentMethod': deliveryPaymentMethod,
        'address': address,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'note': note,
        'utensils': utensils,
        'userName': userName,
      }));

  Future<void> markPaid(String orderId) =>
      _call('customerMarkRestaurantOrderPaid', {'orderId': orderId});

  Future<void> cancel(String orderId, {String reason = ''}) =>
      _call('customerCancelRestaurantOrder', {'orderId': orderId, 'reason': reason});

  // ── Ресторан (а'зо) ────────────────────────────────────────────────

  Future<Map<String, dynamic>> register(Map<String, dynamic> payload) =>
      _call('restaurantRegister', payload);

  Future<Map<String, dynamic>> accept(String orderId, {int? prepTimeMin}) =>
      _call('restaurantAcceptOrder', {
        'orderId': orderId,
        if (prepTimeMin != null) 'prepTimeMin': prepTimeMin,
      });

  Future<void> reject(String orderId, {String reason = ''}) =>
      _call('restaurantRejectOrder', {'orderId': orderId, 'reason': reason});

  Future<void> markReady(String orderId) =>
      _call('restaurantMarkReady', {'orderId': orderId});

  Future<void> confirmPayment(String orderId) =>
      _call('restaurantConfirmPayment', {'orderId': orderId});

  Future<void> markDelivered(String orderId) =>
      _call('restaurantMarkDelivered', {'orderId': orderId});

  // ── Курьер ─────────────────────────────────────────────────────────

  Future<List<NearbyRestaurantOrder>> listNearby({double? lat, double? lng, int? radiusKm}) async {
    final data = await _call('listNearbyRestaurantOrders', {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (radiusKm != null) 'radiusKm': radiusKm,
    });
    final raw = (data['orders'] as List?) ?? const [];
    return [
      for (final m in raw.whereType<Map>())
        NearbyRestaurantOrder.fromMap(Map<String, dynamic>.from(m)),
    ];
  }

  Future<Map<String, dynamic>> claim(String orderId) =>
      _call('courierClaimRestaurantOrder', {'orderId': orderId});

  Future<void> pickup(String orderId, {required String pickupCode}) =>
      _call('courierPickupRestaurantOrder', {'orderId': orderId, 'pickupCode': pickupCode});

  Future<void> arrive(String orderId) =>
      _call('courierArriveRestaurantOrder', {'orderId': orderId});

  Future<Map<String, dynamic>> complete(
    String orderId, {
    required bool delivered,
    String failReason = 'other',
  }) =>
      _call('courierCompleteRestaurantDelivery', {
        'orderId': orderId,
        'outcome': delivered ? 'delivered' : 'failed',
        'failReason': failReason,
      });

  Future<void> setBuyoutPrefs({required bool enabled, required int limit}) =>
      _call('courierSetBuyoutPrefs', {'buyoutEnabled': enabled, 'buyoutLimit': limit});

  // ── Админ ──────────────────────────────────────────────────────────

  Future<void> adminSetStatus(String restaurantId, String status, {String reason = ''}) =>
      _call('adminSetRestaurantStatus', {
        'restaurantId': restaurantId,
        'status': status,
        'reason': reason,
      });
}

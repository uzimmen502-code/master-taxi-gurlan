// Кафе-ресторанлар — репозиторий.
//
// ЁЗИШ — фақат callable орқали (`functions/restaurant_orders.js`, default
// codebase, us-central1): нарх, ҳолат ўтишлари, 2 % — серверда. ЎҚИШ —
// Firestore stream (ресторанлар, меню, буюртма). Қоидалар:
// `restaurants` `status == approved` рўйхати ҳаммага; буюртма — эгасига.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/utils/merged_stream.dart';
import '../../../models/order_model.dart';
import '../../../utils/geo_hash.dart';
import '../domain/cuisine.dart';
import '../domain/dish_facts.dart';
import '../domain/menu_category_choice.dart';
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
    required this.deliveryFee,
    required this.total,
    this.duplicate = false,
  });

  final String orderId;
  final int itemsTotal;
  final int deliveryFee;
  final int total;
  final bool duplicate;

  factory PlaceOrderResult.fromMap(Map<String, dynamic> m) => PlaceOrderResult(
        orderId: (m['orderId'] ?? '') as String,
        itemsTotal: (m['itemsTotal'] as num?)?.toInt() ?? 0,
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

/// Курьер выкуп созламаси (`courierSetBuyoutPrefs`): ёқилган бўлса нақд
/// буюртмаларда курьер таом пулини ресторанга ўзи тўлайди, лимитгача.
class CourierBuyoutPrefs {
  const CourierBuyoutPrefs({required this.enabled, required this.limit});

  final bool enabled;
  final int limit;
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

  /// «Яқиндаги» радиуси (D-GEO-4, геo 4-босқич). PROPOSED: етказиб бериш
  /// тарифи стандарти 15 км (`DEFAULT_MAX_KM`) + олиб кетиш учун захира.
  static const nearbyRadiusKm = 20.0;

  /// Яқиндаги тасдиқланган ресторанлар — СЕРВЕР сўрови (D-GEO-4): мавжуд
  /// `geohash` (7 белги, `restaurantRegister` / [updateProfile] ёзади)
  /// префикси бўйича 9 та geohash-4 катак (~20×39 км), кейин аниқ масофа
  /// [radiusKm] ичида. Аввал бутун тасдиқланган рўйхат юкланиб, масофа
  /// фақат тартиб учун эди. Индекс: (status, geohash).
  Stream<List<Restaurant>> watchNearby({
    required double lat,
    required double lng,
    double radiusKm = nearbyRadiusKm,
    int perCellLimit = 50,
  }) {
    final cells = GeoHash.neighborsForRadius(lat, lng, precision: 4);
    Stream<List<Restaurant>> cell(String h) => _restaurants
        .where('status', isEqualTo: 'approved')
        .orderBy('geohash')
        .startAt([h])
        .endAt(['$h~'])
        .limit(perCellLimit)
        .snapshots()
        .map((s) => s.docs.map(Restaurant.fromDoc).toList(growable: false));
    var merged = cell(cells.first);
    for (final h in cells.skip(1)) {
      merged = mergeListStreams(merged, cell(h), idOf: (r) => r.id);
    }
    return merged.map((all) => withinRadius(all, lat, lng, radiusKm));
  }

  /// [radiusKm] ичидагилар, энг яқини биринчи. Координатасиз — чиқмайди.
  static List<Restaurant> withinRadius(
    Iterable<Restaurant> all,
    double lat,
    double lng,
    double radiusKm,
  ) {
    final rows = <(Restaurant, double)>[];
    for (final r in all) {
      final d = r.distanceKmFrom(lat, lng);
      if (d != null && d <= radiusKm) rows.add((r, d));
    }
    rows.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final x in rows) x.$1];
  }

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

  /// Олиб кетиш коди — `orders/{id}/private/secrets` (қоида: фақат ресторан
  /// а'зоси ва админ; курьерга ресторан оғзаки айтади).
  Stream<String?> watchPickupCode(String orderId) => _orders
      .doc(orderId)
      .collection('private')
      .doc('secrets')
      .snapshots()
      .map((d) => d.exists ? (d.data()?['pickupCode'] as String?) : null);

  // ── Ресторан а'зоси — ТЎҒРИДАН-ТЎҒРИ ёзиш (rules whitelist) ──────────
  // Профил/меню — улгуржи намунаси: server-only майдонлар (`status`,
  // `ownerUid`, рейтинг…) қоидада ёпиқ; буюртма нархи барибир серверда
  // менюдан қайта ҳисобланади (18-қоида).

  static const double _geohashPrecisionMeters = 7;

  /// Профил майдонлари (whitelist қоидадаги билан бир хил). `lat`/`lng`
  /// ўзгарса `geohash` ҳам янгиланади — серверники билан бир хил аниқлик.
  Future<void> updateProfile(String restaurantId, Map<String, dynamic> patch) {
    final data = Map<String, dynamic>.from(patch);
    final lat = data['lat'];
    final lng = data['lng'];
    if (lat is num && lng is num) {
      data['geohash'] = GeoHash.encode(lat.toDouble(), lng.toDouble(), precision: _geohashPrecisionMeters.toInt());
    }
    data['updatedAt'] = FieldValue.serverTimestamp();
    return _restaurants.doc(restaurantId).update(data);
  }

  /// Пауза: `until` — шу вақтгача; `null` — давом эттириш.
  Future<void> setPaused(String restaurantId, DateTime? until) => _restaurants.doc(restaurantId).update({
        'pausedUntil': until == null ? null : Timestamp.fromDate(until),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Stream<Map<String, dynamic>?> watchPaymentDetails(String restaurantId) =>
      _restaurants.doc(restaurantId).collection('private').doc('payment').snapshots().map((d) => d.data());

  Future<void> savePaymentDetails(
    String restaurantId, {
    required String cardNumber,
    required String cardHolder,
    String qrImageUrl = '',
  }) =>
      _restaurants.doc(restaurantId).collection('private').doc('payment').set({
        'cardNumber': cardNumber,
        'cardHolder': cardHolder,
        'qrImageUrl': qrImageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<String> upsertCategory(String restaurantId, {String? id, required String name, required int sort}) async {
    final col = _restaurants.doc(restaurantId).collection('menu_categories');
    final ref = id == null ? col.doc() : col.doc(id);
    await ref.set({
      'name': name,
      'sort': sort,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  /// Категорияни ўчиради; ундаги таомлар ЎЧМАЙДИ — «категориясиз»
  /// (`categoryId: ''`, мижозда «Бошқалар») бўлади. Аввал таомларда ўлик
  /// `categoryId` қолиб кетарди (эга рўйхатида категория номи йўқолар, форма
  /// эса жимгина бошқа бўлимга ўтказарди).
  Future<void> deleteCategory(String restaurantId, String id) async {
    final rest = _restaurants.doc(restaurantId);
    try {
      final snap = await rest.collection('menu_items').where('categoryId', isEqualTo: id).get();
      for (final part in MenuCategoryChoice.chunks(snap.docs)) {
        final batch = _db.batch();
        for (final d in part) {
          batch.update(d.reference, {'categoryId': MenuCategoryChoice.none, 'updatedAt': FieldValue.serverTimestamp()});
        }
        await batch.commit();
      }
    } catch (_) {
      // Қайта ўтказиш йиқилса ҳам категория ўчади: таомлар мижозда барибир
      // «Бошқалар»да чиқади (`_sections`), форма эса ўликни `none` деб олади.
    }
    await rest.collection('menu_categories').doc(id).delete();
  }

  Future<String> upsertMenuItem(
    String restaurantId, {
    String? id,
    required String name,
    required int price,
    String description = '',
    String photoUrl = '',
    String categoryId = '',
    int sort = 0,
    bool available = true,
    DateTime? stopUntil,
    DishFacts? facts,
  }) async {
    final col = _restaurants.doc(restaurantId).collection('menu_items');
    final ref = id == null ? col.doc() : col.doc(id);
    await ref.set({
      'name': name,
      'price': price,
      'description': description,
      'photoUrl': photoUrl,
      // Қадоқлаш ҳақи олиб ташланган (D-REST-28): таҳрирда ESKI ҳужжатдаги майдон тозаланади.
      'packagingFee': FieldValue.delete(),
      'categoryId': categoryId,
      'sort': sort,
      'available': available,
      'stopUntil': stopUntil == null ? null : Timestamp.fromDate(stopUntil),
      // Фактлар: [facts] `null` — тегилмайди; берилса — киритилмагани ўчирилади.
      ...DishFacts.patch(facts, FieldValue.delete()),
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  // ── Кухналар (D-REST-24) ───────────────────────────────────────────

  static const _cuisineTtl = Duration(minutes: 10);
  List<Cuisine>? _cuisinesCache;
  DateTime? _cuisinesAt;

  /// Танлаш мумкин кухналар (яширилмаган). Рўйхат кичик ва кам ўзгаради —
  /// форма очилган сайин ўқимаслик учун [_cuisineTtl] кэш (36-қоида: ўқишлар/фойдаланувчи).
  Future<List<Cuisine>> listCuisines({bool force = false}) async {
    final at = _cuisinesAt;
    final cached = _cuisinesCache;
    if (!force && cached != null && at != null && DateTime.now().difference(at) < _cuisineTtl) {
      return cached;
    }
    final snap = await _db.collection('restaurant_cuisines').limit(500).get();
    final list = snap.docs.map(Cuisine.fromDoc).where((c) => !c.hidden).toList();
    _cuisinesCache = list;
    _cuisinesAt = DateTime.now();
    return list;
  }

  /// Сотувчи ўз кухна номини қўшади (ёки бор бўлса — ўшани олади). Сервер
  /// дубликатни нормаллаштириб топади; кунлик лимит — `CUISINE_RATE_LIMIT`.
  Future<Cuisine> addCuisine({required String restaurantId, required String name, required String group}) async {
    final r = await _call('restaurantAddCuisine', {'restaurantId': restaurantId, 'name': name, 'group': group});
    _cuisinesCache = null; // навбатдаги ўқишда янги рўйхат
    return Cuisine(
      id: (r['id'] ?? '') as String,
      name: (r['name'] ?? name) as String,
      group: (r['group'] ?? group) as String,
    );
  }

  Future<void> setItemAvailability(String restaurantId, String id, {required bool available, DateTime? stopUntil}) =>
      _restaurants.doc(restaurantId).collection('menu_items').doc(id).update({
        'available': available,
        'stopUntil': stopUntil == null ? null : Timestamp.fromDate(stopUntil),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteMenuItem(String restaurantId, String id) =>
      _restaurants.doc(restaurantId).collection('menu_items').doc(id).delete();

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

  /// Курьернинг выкуп созламаси — `restaurant_courier_prefs/{uid}` (қоида:
  /// фақат ўзи ва админ ўқийди; ёзиш — фақат CF). Йўқ бўлса `null`.
  Future<CourierBuyoutPrefs?> getBuyoutPrefs(String courierUid) async {
    if (courierUid.isEmpty) return null;
    final d = await _db.collection('restaurant_courier_prefs').doc(courierUid).get();
    if (!d.exists) return null;
    final m = d.data() ?? const <String, dynamic>{};
    return CourierBuyoutPrefs(
      enabled: m['buyoutEnabled'] == true,
      limit: (m['buyoutLimit'] as num?)?.toInt() ?? 0,
    );
  }

  // ── Админ ──────────────────────────────────────────────────────────

  Future<void> adminSetStatus(String restaurantId, String status, {String reason = ''}) =>
      _call('adminSetRestaurantStatus', {
        'restaurantId': restaurantId,
        'status': status,
        'reason': reason,
      });
}

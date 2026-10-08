// Кафе-ресторанлар — моделлар (D-REST-1…14, docs/kafe_restoran_taklifi_uz.md §11.4).
//
// Firestore ҳужжатларининг ЎҚИШ томони. Нарх, статус, 2 % — серверда
// (`functions/restaurant_orders.js`); бу ерда фақат кўрсатиш учун
// ҳисоблар (масофа, очиқ/ёпиқ, сават йиғиндиси). Пул — бутун сўм.

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// `restaurantStatus` қийматлари — сервердаги жадвал билан бир хил.
abstract final class RestaurantOrderStatus {
  static const placed = 'placed';
  static const accepted = 'accepted';
  static const ready = 'ready';
  static const picked = 'picked';
  static const arrived = 'arrived';
  static const delivered = 'delivered';
  static const rejected = 'rejected';
  static const cancelled = 'cancelled';
  static const deliveryFailed = 'delivery_failed';

  /// Мижоз кузатув босқичлари (тартиб билан). Якуний салбий ҳолатлар
  /// босқич эмас — улар алоҳида кўрсатилади.
  static const steps = [placed, accepted, ready, picked, arrived, delivered];

  static bool isTerminal(String s) =>
      s == delivered || s == rejected || s == cancelled || s == deliveryFailed;

  static bool isFailed(String s) =>
      s == rejected || s == cancelled || s == deliveryFailed;

  /// Босқич индекси (0..5); якуний салбий ҳолатда — охирги етилган босқич
  /// номаълум, шунинг учун `-1`.
  static int stepIndex(String s) => steps.indexOf(s);

  /// Матн калити — 3 тилда (`restaurants_status_*`).
  static String labelKey(String s) => 'restaurants_status_$s';
}

DateTime? _ts(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

int _int(dynamic v, [int def = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return def;
}

double? _dbl(dynamic v) => v is num ? v.toDouble() : null;

String _str(dynamic v) => v is String ? v : '';

/// Икки нуқта орасидаги тўғри чизиқ (метр) — серверники билан бир хил.
int haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return (2 * r * math.asin(math.sqrt(a))).round();
}

/// `restaurants.delivery.ownFee` — ўз курьери нархи (серверда ҳам шу формула).
class RestaurantOwnFee {
  const RestaurantOwnFee({
    this.type = 'fixed',
    this.fixed = 0,
    this.base = 0,
    this.perKm = 0,
    this.freeAbove,
    this.maxKm,
  });

  final String type;
  final int fixed;
  final int base;
  final int perKm;
  final int? freeAbove;
  final int? maxKm;

  factory RestaurantOwnFee.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const RestaurantOwnFee();
    return RestaurantOwnFee(
      type: _str(m['type']) == 'distance' ? 'distance' : 'fixed',
      fixed: _int(m['fixed']),
      base: _int(m['base']),
      perKm: _int(m['perKm']),
      freeAbove: m['freeAbove'] is num ? _int(m['freeAbove']) : null,
      maxKm: m['maxKm'] is num ? _int(m['maxKm']) : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'fixed': fixed,
        'base': base,
        'perKm': perKm,
        'freeAbove': freeAbove,
        'maxKm': maxKm,
      };

  /// Кўрсатиш учун тахмин; `null` — чегарадан узоқ. Ҳал қилувчи — сервер.
  int? feeFor({required int distanceMeters, required int itemsTotal}) {
    final m = math.max(0, distanceMeters);
    if (maxKm != null && m > maxKm! * 1000) return null;
    if (freeAbove != null && itemsTotal >= freeAbove!) return 0;
    if (type == 'distance') {
      final extra = math.max(0, m - 1000);
      return base + ((extra * perKm + 500) ~/ 1000);
    }
    return fixed;
  }
}

class RestaurantDelivery {
  const RestaurantDelivery({
    this.mode = 'none',
    this.pickup = false,
    this.ownFee = const RestaurantOwnFee(),
  });

  /// `ava_courier` · `own_courier` · `none`.
  final String mode;
  final bool pickup;
  final RestaurantOwnFee ownFee;

  bool get hasDelivery => mode == 'ava_courier' || mode == 'own_courier';
  bool get isAvaCourier => mode == 'ava_courier';
  bool get isOwnCourier => mode == 'own_courier';

  factory RestaurantDelivery.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const RestaurantDelivery();
    final mode = _str(m['mode']);
    return RestaurantDelivery(
      mode: const ['ava_courier', 'own_courier'].contains(mode) ? mode : 'none',
      pickup: m['pickup'] == true,
      ownFee: RestaurantOwnFee.fromMap(
        m['ownFee'] is Map ? Map<String, dynamic>.from(m['ownFee'] as Map) : null,
      ),
    );
  }

  Map<String, dynamic> toMap() =>
      {'mode': mode, 'pickup': pickup, 'ownFee': ownFee.toMap()};
}

class RestaurantPaymentOptions {
  const RestaurantPaymentOptions({this.prepay = true, this.cash = true});

  final bool prepay;
  final bool cash;

  factory RestaurantPaymentOptions.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const RestaurantPaymentOptions();
    return RestaurantPaymentOptions(
      prepay: m['prepay'] != false,
      cash: m['cash'] != false,
    );
  }
}

/// Иш вақти `HH:mm` — `open == close` ёки йўқ → доим очиқ.
class OpeningHours {
  const OpeningHours({required this.open, required this.close});

  final String open;
  final String close;

  static int? _min(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return null;
    return h * 60 + mi;
  }

  static OpeningHours? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final o = _str(m['open']);
    final c = _str(m['close']);
    if (_min(o) == null || _min(c) == null) return null;
    return OpeningHours(open: o, close: c);
  }

  /// Ярим тундан ўтадиган оралиқ (`20:00–02:00`) ҳам қўлланади.
  bool isOpenAt(DateTime at) {
    final o = _min(open);
    final c = _min(close);
    if (o == null || c == null || o == c) return true;
    final n = at.hour * 60 + at.minute;
    return o < c ? (n >= o && n < c) : (n >= o || n < c);
  }

  String get label => '$open–$close';
}

/// `restaurants/{id}` — оммавий қисми.
class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    this.description = '',
    this.cuisineTags = const [],
    this.address = '',
    this.contactPhone = '',
    this.lat,
    this.lng,
    this.logoUrl = '',
    this.coverUrl = '',
    this.announcement = '',
    this.openingHours,
    this.prepTimeMin = 20,
    this.minOrderAmount = 0,
    this.delivery = const RestaurantDelivery(),
    this.payment = const RestaurantPaymentOptions(),
    this.pausedUntil,
    this.status = 'applied',
    this.legalType = 'individual',
    this.ownerUid = '',
    this.ratingAvg = 0,
    this.ratingCount = 0,
  });

  final String id;
  final String name;
  final String description;
  final List<String> cuisineTags;
  final String address;
  final String contactPhone;
  final double? lat;
  final double? lng;
  final String logoUrl;
  final String coverUrl;
  final String announcement;
  final OpeningHours? openingHours;
  final int prepTimeMin;
  final int minOrderAmount;
  final RestaurantDelivery delivery;
  final RestaurantPaymentOptions payment;
  final DateTime? pausedUntil;

  /// `applied` · `approved` · `rejected` · `suspended` · `closed` (server-only).
  final String status;

  /// `individual` (уй ошпази) · `yatt` · `llc`.
  final String legalType;
  final String ownerUid;
  final double ratingAvg;
  final int ratingCount;

  bool get isApproved => status == 'approved';
  bool get isHomeCook => legalType == 'individual';
  bool get hasLocation => lat != null && lng != null;

  bool isPausedAt(DateTime at) =>
      pausedUntil != null && pausedUntil!.isAfter(at);

  bool isOpenAt(DateTime at) =>
      !isPausedAt(at) && (openingHours?.isOpenAt(at) ?? true);

  bool get isOpenNow => isOpenAt(DateTime.now());

  /// Фойдаланувчидан масофа (км); координата йўқ бўлса `null`.
  double? distanceKmFrom(double? userLat, double? userLng) {
    if (userLat == null || userLng == null || !hasLocation) return null;
    return haversineMeters(userLat, userLng, lat!, lng!) / 1000;
  }

  factory Restaurant.fromMap(String id, Map<String, dynamic> d) {
    return Restaurant(
      id: id,
      name: _str(d['name']),
      description: _str(d['description']),
      cuisineTags: (d['cuisineTags'] as List?)?.whereType<String>().toList() ?? const [],
      address: _str(d['address']),
      contactPhone: _str(d['contactPhone']),
      lat: _dbl(d['lat']),
      lng: _dbl(d['lng']),
      logoUrl: _str(d['logoUrl']),
      coverUrl: _str(d['coverUrl']),
      announcement: _str(d['announcement']),
      openingHours: OpeningHours.fromMap(
        d['openingHours'] is Map ? Map<String, dynamic>.from(d['openingHours'] as Map) : null,
      ),
      prepTimeMin: _int(d['prepTimeMin'], 20),
      minOrderAmount: _int(d['minOrderAmount']),
      delivery: RestaurantDelivery.fromMap(
        d['delivery'] is Map ? Map<String, dynamic>.from(d['delivery'] as Map) : null,
      ),
      payment: RestaurantPaymentOptions.fromMap(
        d['payment'] is Map ? Map<String, dynamic>.from(d['payment'] as Map) : null,
      ),
      pausedUntil: _ts(d['pausedUntil']),
      status: _str(d['status']),
      legalType: _str(d['legalType']).isEmpty ? 'individual' : _str(d['legalType']),
      ownerUid: _str(d['ownerUid']),
      ratingAvg: _dbl(d['ratingAvg']) ?? 0,
      ratingCount: _int(d['ratingCount']),
    );
  }

  factory Restaurant.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Restaurant.fromMap(doc.id, doc.data() ?? const {});
}

class MenuCategory {
  const MenuCategory({required this.id, required this.name, this.sort = 0});

  final String id;
  final String name;
  final int sort;

  factory MenuCategory.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return MenuCategory(id: doc.id, name: _str(d['name']), sort: _int(d['sort']));
  }
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    this.description = '',
    this.photoUrl = '',
    this.packagingFee = 0,
    this.categoryId = '',
    this.sort = 0,
    this.available = true,
    this.stopUntil,
  });

  final String id;
  final String name;
  final String description;
  final String photoUrl;

  /// Бутун сўм. Буюртма нархи барибир серверда менюдан қайта ҳисобланади.
  final int price;
  final int packagingFee;
  final String categoryId;
  final int sort;
  final bool available;
  final DateTime? stopUntil;

  bool isAvailableAt(DateTime at) =>
      available && (stopUntil == null || !stopUntil!.isAfter(at));

  bool get isAvailable => isAvailableAt(DateTime.now());

  factory MenuItem.fromMap(String id, Map<String, dynamic> d) => MenuItem(
        id: id,
        name: _str(d['name']),
        description: _str(d['description']),
        photoUrl: _str(d['photoUrl']),
        price: _int(d['price']),
        packagingFee: _int(d['packagingFee']),
        categoryId: _str(d['categoryId']),
        sort: _int(d['sort']),
        available: d['available'] != false,
        stopUntil: _ts(d['stopUntil']),
      );

  factory MenuItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      MenuItem.fromMap(doc.id, doc.data() ?? const {});
}

class CartLine {
  const CartLine({required this.item, required this.qty});

  final MenuItem item;
  final int qty;

  int get lineTotal => item.price * qty;
  int get packagingTotal => item.packagingFee * qty;
}

/// Сават — БИТТА ресторандан (Meituan/Ele.me қоидаси, §12.4). Бошқа
/// ресторандан қўшилса [add] `false` қайтаради — UI «тозалаймизми?» сўрайди.
class RestaurantCart extends ChangeNotifier {
  RestaurantCart();

  /// Илова бўйлаб битта сават — экранлар орасида сақланади.
  static final RestaurantCart instance = RestaurantCart();

  static const maxQty = 50;

  String? _restaurantId;
  String _restaurantName = '';
  final Map<String, CartLine> _lines = {};

  String? get restaurantId => _restaurantId;
  String get restaurantName => _restaurantName;
  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;

  List<CartLine> get lines => List.unmodifiable(_lines.values);

  int get count => _lines.values.fold(0, (s, l) => s + l.qty);
  int get itemsTotal => _lines.values.fold(0, (s, l) => s + l.lineTotal);
  int get packagingTotal => _lines.values.fold(0, (s, l) => s + l.packagingTotal);

  int qtyOf(String itemId) => _lines[itemId]?.qty ?? 0;

  /// Категория бўйича саватдаги таомлар сони (чап устун badge'и).
  int countInCategory(String categoryId) => _lines.values
      .where((l) => l.item.categoryId == categoryId)
      .fold(0, (s, l) => s + l.qty);

  bool belongsTo(String restaurantId) =>
      _restaurantId == null || _restaurantId == restaurantId;

  /// Қўшиш. Бошқа ресторан савати бўлса — ҳеч нарса қилмай `false`.
  bool add(MenuItem item, {required Restaurant restaurant}) {
    if (!belongsTo(restaurant.id)) return false;
    _restaurantId = restaurant.id;
    _restaurantName = restaurant.name;
    final cur = _lines[item.id]?.qty ?? 0;
    if (cur >= maxQty) return true;
    _lines[item.id] = CartLine(item: item, qty: cur + 1);
    notifyListeners();
    return true;
  }

  void decrement(String itemId) {
    final cur = _lines[itemId];
    if (cur == null) return;
    if (cur.qty <= 1) {
      _lines.remove(itemId);
    } else {
      _lines[itemId] = CartLine(item: cur.item, qty: cur.qty - 1);
    }
    if (_lines.isEmpty) _restaurantId = null;
    notifyListeners();
  }

  void remove(String itemId) {
    if (_lines.remove(itemId) == null) return;
    if (_lines.isEmpty) _restaurantId = null;
    notifyListeners();
  }

  void clear() {
    if (_lines.isEmpty && _restaurantId == null) return;
    _lines.clear();
    _restaurantId = null;
    _restaurantName = '';
    notifyListeners();
  }

  /// Бошқа ресторанга ўтиш: тозалаб, янгисини қўшиш.
  void replaceWith(MenuItem item, {required Restaurant restaurant}) {
    _lines.clear();
    _restaurantId = null;
    add(item, restaurant: restaurant);
  }

  /// `placeRestaurantOrder` учун `items`.
  List<Map<String, dynamic>> toOrderItems() => [
        for (final l in _lines.values) {'itemId': l.item.id, 'qty': l.qty},
      ];
}

/// Сервер хато коди → матн калити (25-қоида: кодлар серверда, матн клиентда).
String restaurantsErrorKey(String code) =>
    'restaurants_err_${code.isEmpty ? 'generic' : code}';

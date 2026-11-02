// «Менинг бизнесим» маҳсулот буюртмаси (AVA курьери билан) — мижоз томони домени (эга 2026-11-03).
//
// Сервер: `functions/business_orders.js` + `functions/business_order_states.js` (feat/biz-order-srv). Бу файл
// СЕРВЕР жадвалининг кўзгуси — ҳолат номлари, ўтишлар ва чекловлар ўша ерда (ягона манба, 7/17-қоида); бу ерда
// фақат КЎРСАТИШ учун ўқилади. Нарх, ҳолат ўтиши ва рухсат — фақат серверда (18/44-қоида): мижоз юборган нарх
// эътиборсиз, сават фақат `{itemId, qty}` юборади.
//
// Пул — бутун сўм (8-қоида).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/delivery_failed.dart';
import '../../tv_market/domain/price_unit.dart';
import '../../tv_market/models/tv_shop.dart';

/// `businessStatus` қийматлари ва ўтишлар (сервер `BS` / `TRANSITIONS` нусхаси — фақат кўрсатиш учун).
abstract final class BusinessOrderStatus {
  static const placed = 'placed';
  static const accepted = 'accepted';
  static const ready = 'ready';
  static const picked = 'picked';
  static const arrived = 'arrived';
  static const delivered = 'delivered';
  static const rejected = 'rejected';
  static const cancelled = 'cancelled';
  static const deliveryFailed = 'delivery_failed';

  /// Мижоз кўрадиган асосий йўл (вақт чизиғи).
  static const timeline = [placed, accepted, ready, picked, arrived, delivered];

  static const finals = {delivered, rejected, cancelled, deliveryFailed};

  /// Курьер қўлида (`IN_DELIVERY`).
  static const inDelivery = {picked, arrived};

  /// Курьер ола оладиган (`CLAIMABLE`).
  static const claimable = {accepted, ready};

  static bool isFinal(String s) => finals.contains(s);

  /// Сотувчи кутаётган/юритаётган (фаол) буюртма.
  static bool isActive(String s) => s.isNotEmpty && !isFinal(s);

  /// Ҳолат матни калити (номаълум ҳолат — «юборилди»).
  static String labelKey(String s) => switch (s) {
        accepted || ready || picked || arrived || delivered || rejected || cancelled || deliveryFailed =>
          'biz_order_status_$s',
        _ => 'biz_order_status_placed',
      };

  /// Вақт чизиғидаги қадам номи калити.
  static String stepKey(String s) => 'biz_order_step_$s';

  /// Вақт чизиғида ўтилган қадамлар сони (якуний салбий ҳолатда — `-1`).
  static int timelineIndex(String s) => timeline.indexOf(s);
}

/// Буюртма қатори (сервер `priceLines` натижаси — нарх каталогдан).
class BusinessOrderLine {
  const BusinessOrderLine({
    required this.itemId,
    required this.title,
    required this.unitPrice,
    required this.priceUnit,
    required this.qty,
    required this.lineTotal,
  });

  final String itemId;
  final String title;
  final int unitPrice;
  final PriceUnit priceUnit;
  final int qty;
  final int lineTotal;

  static BusinessOrderLine? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['itemId'];
    if (id is! String || id.isEmpty) return null;
    return BusinessOrderLine(
      itemId: id,
      title: raw['title'] is String ? raw['title'] as String : '',
      unitPrice: _int(raw['unitPrice']),
      priceUnit: PriceUnit.fromWire(raw['priceUnit']),
      qty: _int(raw['qty']),
      lineTotal: _int(raw['lineTotal']),
    );
  }

  static List<BusinessOrderLine> listFrom(Object? raw) => [
        if (raw is List)
          for (final e in raw)
            if (fromMap(e) case final BusinessOrderLine l) l,
      ];
}

int _int(Object? v) => v is num ? v.toInt() : 0;
String _str(Object? v) => v is String ? v : '';
double? _dbl(Object? v) => v is num ? v.toDouble() : null;
DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

/// `orders/{id}` (`type: 'business'`) — мижоз, сотувчи ва курьер экранлари учун.
class BusinessOrder {
  const BusinessOrder({
    required this.id,
    required this.status,
    this.businessId = '',
    this.businessName = '',
    this.businessAddress = '',
    this.businessLat,
    this.businessLng,
    this.sellerUid = '',
    this.userPhone = '',
    this.userName = '',
    this.address = '',
    this.lat,
    this.lng,
    this.note = '',
    this.items = const [],
    this.itemsTotal = 0,
    this.deliveryFee = 0,
    this.total = 0,
    this.deliveryPaymentMethod = 'cash',
    this.goodsPaymentMethod = 'cash_buyout',
    this.paymentStatus = '',
    this.acceptDeadlineAt,
    this.courierId = '',
    this.courierName = '',
    this.rejectReason = '',
    this.createdAt,
    this.awaitingStep = '',
    this.awaitingModule = '',
    this.deliveryFailed = DeliveryFailedState.none,
  });

  /// «Етказилмади» кутиш ҳолати (`awaitingCustomerConfirm`, модул `business`) — умумий курьер виджети учун.
  final DeliveryFailedState deliveryFailed;

  final String id;

  /// `businessStatus` ([BusinessOrderStatus]).
  final String status;
  final String businessId;
  final String businessName;
  final String businessAddress;
  final double? businessLat;
  final double? businessLng;
  final String sellerUid;
  final String userPhone;
  final String userName;
  final String address;
  final double? lat;
  final double? lng;
  final String note;
  final List<BusinessOrderLine> items;
  final int itemsTotal;
  final int deliveryFee;
  final int total;

  /// `cash` | `wallet`.
  final String deliveryPaymentMethod;

  /// `cash_buyout` — маҳсулот пулини курьер сотувчига тўлайди, мижоз эшик олдида курьерга қайтаради.
  final String goodsPaymentMethod;
  final String paymentStatus;
  final DateTime? acceptDeadlineAt;
  final String courierId;
  final String courierName;
  final String rejectReason;
  final DateTime? createdAt;

  /// `awaitingCustomerConfirm.step` / `.module` (фақат сервер ёзади).
  final String awaitingStep;
  final String awaitingModule;

  bool get isFinal => BusinessOrderStatus.isFinal(status);
  bool get isActive => !isFinal;
  bool get hasCourier => courierId.isNotEmpty;
  bool get canCustomerCancel => status == BusinessOrderStatus.placed;
  int get itemsCount => items.fold<int>(0, (s, l) => s + l.qty);

  /// Мижоз эшик олдида курьерга НАҚД берадиган сумма: маҳсулот пули (выкуп) + нақд етказиш ҳақи.
  int get cashAtDoor =>
      (goodsPaymentMethod == 'cash_buyout' ? itemsTotal : 0) + (deliveryPaymentMethod == 'cash' ? deliveryFee : 0);

  /// Курьер «етказиб бўлмади» деди — мижоз ёки сотувчи қарорини кутмоқда.
  bool get deliveryFailedPending =>
      (deliveryFailed.pending || awaitingStep == 'delivery_failed') && BusinessOrderStatus.inDelivery.contains(status);

  /// Курьер «етказиб бўлмади» юбора оладими (қўлида ва ҳали юбормаган).
  bool get courierCanReportFailed => BusinessOrderStatus.inDelivery.contains(status) && !deliveryFailedPending;

  bool get hasBusinessCoordinates => businessLat != null && businessLng != null;
  bool get hasCustomerCoordinates => lat != null && lng != null;

  static BusinessOrder fromMap(String id, Map<String, dynamic> d) {
    final aw = d['awaitingCustomerConfirm'];
    return BusinessOrder(
      id: id,
      status: _str(d['businessStatus']),
      businessId: _str(d['businessId']),
      businessName: _str(d['businessName']),
      businessAddress: _str(d['businessAddress']),
      businessLat: _dbl(d['businessLat']),
      businessLng: _dbl(d['businessLng']),
      sellerUid: _str(d['sellerUid']),
      userPhone: _str(d['userPhone']),
      userName: _str(d['userName']),
      address: _str(d['address']),
      lat: _dbl(d['lat']),
      lng: _dbl(d['lng']),
      note: _str(d['note']),
      items: BusinessOrderLine.listFrom(d['items']),
      itemsTotal: _int(d['itemsTotal']),
      deliveryFee: _int(d['deliveryFee']),
      total: _int(d['total']),
      deliveryPaymentMethod: _str(d['deliveryPaymentMethod']).isEmpty ? 'cash' : _str(d['deliveryPaymentMethod']),
      goodsPaymentMethod: _str(d['goodsPaymentMethod']).isEmpty ? 'cash_buyout' : _str(d['goodsPaymentMethod']),
      paymentStatus: _str(d['paymentStatus']),
      acceptDeadlineAt: _date(d['acceptDeadlineAt']),
      courierId: _str(d['courierId']),
      courierName: _str(d['courierName']),
      rejectReason: _str(d['rejectReason']),
      createdAt: _date(d['createdAt']),
      awaitingStep: aw is Map ? _str(aw['step']) : '',
      awaitingModule: aw is Map ? _str(aw['module']) : '',
      deliveryFailed: DeliveryFailedState.fromDoc(d, DeliveryFailedModule.business),
    );
  }
}

/// `getBusinessOrdersAccess` жавоби. Хато/номаълум — ЁПИҚ ([BusinessOrdersAccess.closed]).
class BusinessOrdersAccess {
  const BusinessOrdersAccess({required this.allowed, this.stage = 'off', this.reason = ''});

  final bool allowed;

  /// `off` | `internal` | `pilot` | `public`.
  final String stage;
  final String reason;

  static const closed = BusinessOrdersAccess(allowed: false);

  /// Курьер панелидаги кириш: курьер callable'лари босқични текширмайди (фақат курьер рухсати), лекин
  /// модул ёпиқ ёки фақат синовчиларга бўлса — яширамиз. Пилот/оммавий босқичда (буюртмалар фақат пилот
  /// туманларида пайдо бўлади) — кўринади. INFERRED (сервер `listNearbyBusinessOrders` гардига қараб).
  bool get courierVisible => allowed || stage == 'pilot' || stage == 'public';

  static BusinessOrdersAccess fromMap(Object? raw) {
    if (raw is! Map) return closed;
    return BusinessOrdersAccess(
      allowed: raw['allowed'] == true,
      stage: _str(raw['stage']).isEmpty ? 'off' : _str(raw['stage']),
      reason: _str(raw['reason']),
    );
  }
}

/// `quoteBusinessOrder` натижаси (ёзувсиз; нарх фақат сервердан).
class BusinessOrderQuote {
  const BusinessOrderQuote({
    required this.itemsTotal,
    required this.deliveryFee,
    required this.total,
    this.items = const [],
    this.deliveryTariffVersion,
    this.distanceMeters,
    this.goodsPaymentMethods = const ['cash_buyout'],
    this.deliveryPaymentMethods = const ['cash', 'wallet'],
  });

  final int itemsTotal;
  final int deliveryFee;
  final int total;
  final List<BusinessOrderLine> items;
  final int? deliveryTariffVersion;
  final int? distanceMeters;
  final List<String> goodsPaymentMethods;
  final List<String> deliveryPaymentMethods;

  static List<String> _strings(Object? v, List<String> fallback) =>
      v is List ? [for (final e in v) if (e is String) e] : fallback;

  static BusinessOrderQuote fromMap(Map<String, dynamic> m) => BusinessOrderQuote(
        itemsTotal: _int(m['itemsTotal']),
        deliveryFee: _int(m['deliveryFee']),
        total: _int(m['total']),
        items: BusinessOrderLine.listFrom(m['items']),
        deliveryTariffVersion: m['deliveryTariffVersion'] is num ? (m['deliveryTariffVersion'] as num).toInt() : null,
        distanceMeters: m['distanceMeters'] is num ? (m['distanceMeters'] as num).toInt() : null,
        goodsPaymentMethods: _strings(m['goodsPaymentMethods'], const ['cash_buyout']),
        deliveryPaymentMethods: _strings(m['deliveryPaymentMethods'], const ['cash', 'wallet']),
      );
}

/// `placeBusinessOrder` натижаси.
class BusinessPlaceResult {
  const BusinessPlaceResult({
    required this.orderId,
    this.itemsTotal = 0,
    this.deliveryFee = 0,
    this.total = 0,
    this.duplicate = false,
  });

  final String orderId;
  final int itemsTotal;
  final int deliveryFee;
  final int total;
  final bool duplicate;

  static BusinessPlaceResult fromMap(Map<String, dynamic> m) => BusinessPlaceResult(
        orderId: _str(m['orderId']),
        itemsTotal: _int(m['itemsTotal']),
        deliveryFee: _int(m['deliveryFee']),
        total: _int(m['total']),
        duplicate: m['duplicate'] == true,
      );
}

/// Курьер учун проекция (`listNearbyBusinessOrders`): мижоз телефони ва аниқ манзили ЙЎҚ (40-қоида).
class NearbyBusinessOrder {
  const NearbyBusinessOrder({
    required this.id,
    required this.businessName,
    required this.status,
    this.businessId = '',
    this.businessAddress = '',
    this.deliveryFee = 0,
    this.deliveryPaymentMethod = 'cash',
    this.buyoutAmount = 0,
    this.buyoutAllowed = false,
    this.itemsCount = 0,
    this.distanceMeters,
    this.courierToPickupM,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String businessAddress;
  final String status;
  final int deliveryFee;
  final String deliveryPaymentMethod;
  final int buyoutAmount;
  final bool buyoutAllowed;
  final int itemsCount;
  final int? distanceMeters;
  final int? courierToPickupM;

  static NearbyBusinessOrder fromMap(Map<String, dynamic> m) => NearbyBusinessOrder(
        id: _str(m['id']),
        businessId: _str(m['businessId']),
        businessName: _str(m['businessName']),
        businessAddress: _str(m['businessAddress']),
        status: _str(m['businessStatus']),
        deliveryFee: _int(m['deliveryFee']),
        deliveryPaymentMethod: _str(m['deliveryPaymentMethod']).isEmpty ? 'cash' : _str(m['deliveryPaymentMethod']),
        buyoutAmount: _int(m['buyoutAmount']),
        buyoutAllowed: m['buyoutAllowed'] == true,
        itemsCount: _int(m['itemsCount']),
        distanceMeters: m['distanceMeters'] is num ? (m['distanceMeters'] as num).toInt() : null,
        courierToPickupM: m['courierToPickupM'] is num ? (m['courierToPickupM'] as num).toInt() : null,
      );
}

/// `listNearbyBusinessOrders` жавоби.
class NearbyBusinessOrders {
  const NearbyBusinessOrders(this.orders, {this.buyoutLimit = 0});

  final List<NearbyBusinessOrder> orders;
  final int buyoutLimit;
}

/// `courierCompleteBusinessOrder` натижаси.
class BusinessCompleteResult {
  const BusinessCompleteResult({
    this.delivered = false,
    this.awaitingCustomer = false,
    this.walletPaid = 0,
    this.cashCollected = 0,
  });

  final bool delivered;

  /// Мижоз ўз қурилмасида «Олдим»ни босиши кутилмоқда — ҳали ЕТКАЗИЛМАГАН.
  final bool awaitingCustomer;
  final int walletPaid;
  final int cashCollected;

  static BusinessCompleteResult fromMap(Map<String, dynamic> m) => BusinessCompleteResult(
        delivered: m['outcome'] == 'delivered',
        awaitingCustomer: m['awaitingCustomer'] == true,
        walletPaid: _int(m['walletPaid']),
        cashCollected: _int(m['cashCollected']),
      );
}

// ── Буюртма бериш мумкинлиги ва сават (СОФ мантиқ — тестланади) ──────────────────────────────────────

/// Сервер чеклари билан бир хил (`MAX_QTY`, `MAX_ITEMS`, `ORDERABLE_PRICE_UNITS`).
abstract final class BusinessOrderLimits {
  static const maxQtyPerItem = 100;
  static const maxItems = 30;
  static const orderableUnits = {PriceUnit.fixed, PriceUnit.piece, PriceUnit.kg, PriceUnit.m2};
}

/// Таклифни саватга қўшиш мумкинми (фақат кўриниш учун; сервер барибир текширади): объектга боғланган,
/// фаол МАҲСУЛОТ, қатъий нарх (белгиланган / дона / кг / м²) ва нарх > 0.
bool businessItemOrderable(TvShopItem item) =>
    item.businessId.isNotEmpty &&
    item.isActive &&
    item.kind == 'product' &&
    item.price > 0 &&
    BusinessOrderLimits.orderableUnits.contains(item.priceUnit);

/// Миқдор ёнидаги бирлик калити (`null` — бирликсиз, «× 2»).
String? businessQtyUnitKey(PriceUnit u) => switch (u) {
      PriceUnit.piece => 'piece',
      PriceUnit.kg || PriceUnit.m2 => 'price_unit_short_${u.name}',
      _ => null,
    };

class BusinessCartLine {
  BusinessCartLine({
    required this.itemId,
    required this.title,
    required this.unitPrice,
    required this.priceUnit,
    required this.qty,
    this.photoUrl = '',
  });

  final String itemId;
  final String title;

  /// Кўрсатиш учун (каталог нархи); якуний нарх — сервер квотасидан.
  final int unitPrice;
  final PriceUnit priceUnit;
  int qty;
  final String photoUrl;

  int get lineTotal => unitPrice * qty;
}

/// Битта объект савати. Миқдор 1..[BusinessOrderLimits.maxQtyPerItem], қаторлар ≤ [BusinessOrderLimits.maxItems].
class BusinessCart {
  BusinessCart({required this.businessId, this.businessName = ''});

  final String businessId;
  String businessName;
  final Map<String, BusinessCartLine> _lines = {};

  List<BusinessCartLine> get lines => List.unmodifiable(_lines.values);
  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;
  int get itemsCount => _lines.values.fold<int>(0, (s, l) => s + l.qty);
  int get itemsTotal => _lines.values.fold<int>(0, (s, l) => s + l.lineTotal);
  int qtyOf(String itemId) => _lines[itemId]?.qty ?? 0;

  static int clampQty(int q) => q < 1 ? 1 : (q > BusinessOrderLimits.maxQtyPerItem ? BusinessOrderLimits.maxQtyPerItem : q);

  /// Қўшиш (бор бўлса миқдор қўшилади, чегарада тўхтайди). Бошқа объект маҳсулоти ёки буюртма қилиб
  /// бўлмайдиган таклиф, ёки 30 қатордан ошиш — `false`.
  bool add(TvShopItem item, int qty) {
    if (item.businessId != businessId || !businessItemOrderable(item) || qty < 1) return false;
    final cur = _lines[item.id];
    if (cur != null) {
      cur.qty = clampQty(cur.qty + qty);
      return true;
    }
    if (_lines.length >= BusinessOrderLimits.maxItems) return false;
    _lines[item.id] = BusinessCartLine(
      itemId: item.id,
      title: item.title,
      unitPrice: item.price,
      priceUnit: item.priceUnit,
      qty: clampQty(qty),
      photoUrl: item.coverPhotoUrl,
    );
    return true;
  }

  /// Миқдорни ўрнатиш; 0 ва кам — қатор олиб ташланади.
  void setQty(String itemId, int qty) {
    if (qty < 1) {
      _lines.remove(itemId);
      return;
    }
    _lines[itemId]?.qty = clampQty(qty);
  }

  void remove(String itemId) => _lines.remove(itemId);
  void clear() => _lines.clear();

  /// Серверга юбориладиган қаторлар — фақат `{itemId, qty}` (нарх юборилмайди, 18-қоида).
  List<Map<String, Object>> toItems() => [
        for (final l in _lines.values) {'itemId': l.itemId, 'qty': l.qty},
      ];

  /// Мазмун имзоси — идемпотентлик ниятини аниқлаш учун (сават ўзгарса — янги калит).
  String get signature => [for (final l in _lines.values) '${l.itemId}x${l.qty}'].join(',');
}

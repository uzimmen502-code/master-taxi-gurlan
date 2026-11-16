// «Менинг бизнесим» буюртмаси — репозиторий (эга 2026-11-03).
//
// ЁЗИШ — фақат callable (`functions/business_orders.js`, default codebase): нарх, ҳолат ўтиши, рухсат,
// идемпотентлик — серверда. ЎҚИШ — Firestore: мижоз ўз буюртмасини (`userPhone`), сотувчи `sellerUid ==
// ўз телефони` сўрови билан (rules: list фақат шу тенглик бўлса — `biz_order_rules.patch`), курьер маршрутидаги
// буюртмани (`get`). Олиб кетиш коди — `orders/{id}/private/secrets` (фақат сотувчи ўқийди).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';
import '../domain/business_order.dart';
import '../domain/delivery_quote.dart';

/// Callable хатоси: [reason] — сервер `details.code` (масалан `DELIVERY_TOO_FAR`), [code] — Firebase коди.
class BusinessOrderException implements Exception {
  const BusinessOrderException(this.code, this.reason, {this.details});

  final String code;
  final String reason;
  final Map<String, dynamic>? details;

  @override
  String toString() => 'BusinessOrderException($code/$reason)';
}

/// Сотувчи рўйхати сўровининг шакли (rules шуни талаб қилади: `where sellerUid == <ўз телефони>`,
/// `orderBy createdAt desc`). Сўров ШУ спецификациядан қурилади — тест шаклни қулфлайди.
typedef SellerOrdersQuerySpec = ({String field, String isEqualTo, String orderBy, bool descending, int limit});

class BusinessOrdersRepository {
  BusinessOrdersRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore,
        _functions = functions;

  // Лазй: Firebase инициализациясиз (виджет тестларида) обуна/чақирув яратилмайди.
  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  CollectionReference<Map<String, dynamic>> get _orders => _db.collection('orders');

  static const sellerListLimit = 100;

  /// [sellerPhone] — исталган шаклдаги телефон; сўровда КАНОН 998… рақамлар (rules `phoneFromToken()` шакли).
  static SellerOrdersQuerySpec sellerQuerySpec(String sellerPhone, {int limit = sellerListLimit}) => (
        field: 'sellerUid',
        isEqualTo: canonicalPhoneId(sellerPhone),
        orderBy: 'createdAt',
        descending: true,
        limit: limit,
      );

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _fns.httpsCallable(name).call<Object?>(data);
      final d = res.data;
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : null;
      final reason = '${details?['code'] ?? ''}';
      debugPrint('[BusinessOrders] $name failed: ${e.code}/$reason');
      throw BusinessOrderException(e.code, reason, details: details);
    }
  }

  // ── Дарвоза ────────────────────────────────────────────────────────────────────────────────────

  /// Хато — ЁПИҚ томонга ([BusinessOrdersAccess.closed]): дарвоза ёпиқ бўлса тугма кўринмайди.
  /// [itemId] — ўз дўкони маҳсулоти (объектсиз; пилот тумани маҳсулот бўйича, STAGE 11).
  Future<BusinessOrdersAccess> access({String businessId = '', String itemId = ''}) async {
    try {
      return BusinessOrdersAccess.fromMap(
        await _call('getBusinessOrdersAccess', {
          if (businessId.isNotEmpty) 'businessId': businessId,
          if (businessId.isEmpty && itemId.isNotEmpty) 'itemId': itemId,
        }),
      );
    } catch (e) {
      debugPrint('[BusinessOrders] access: $e');
      return BusinessOrdersAccess.closed;
    }
  }

  // ── Мижоз ──────────────────────────────────────────────────────────────────────────────────────

  /// [businessId] бўш — ўз дўкони маҳсулотлари (сервер STAGE 11: `businessId` юборилмайди).
  Future<BusinessOrderQuote> quote({
    required String businessId,
    required List<Map<String, Object>> items,
    required double lat,
    required double lng,
  }) async =>
      BusinessOrderQuote.fromMap(await _call('quoteBusinessOrder', {
        if (businessId.isNotEmpty) 'businessId': businessId,
        'items': items,
        'lat': lat,
        'lng': lng,
      }));

  Future<BusinessPlaceResult> place({
    required String idempotencyKey,
    required String businessId,
    required List<Map<String, Object>> items,
    required double lat,
    required double lng,
    required String deliveryPaymentMethod,
    String address = '',
    String note = '',
    String userName = '',
  }) async =>
      BusinessPlaceResult.fromMap(await _call('placeBusinessOrder', {
        'idempotencyKey': idempotencyKey,
        if (businessId.isNotEmpty) 'businessId': businessId,
        'items': items,
        'lat': lat,
        'lng': lng,
        if (address.isNotEmpty) 'address': address,
        if (note.isNotEmpty) 'note': note,
        if (userName.isNotEmpty) 'userName': userName,
        'deliveryPaymentMethod': deliveryPaymentMethod,
        'goodsPaymentMethod': 'cash_buyout',
      }));

  Future<void> cancel(String orderId, {String reason = ''}) =>
      _call('customerCancelBusinessOrder', {'orderId': orderId, if (reason.isNotEmpty) 'reason': reason});

  // ── Сотувчи ────────────────────────────────────────────────────────────────────────────────────

  Future<void> accept(String orderId) => _call('businessAcceptOrder', {'orderId': orderId});

  Future<void> reject(String orderId, {String reason = ''}) =>
      _call('businessRejectOrder', {'orderId': orderId, if (reason.isNotEmpty) 'reason': reason});

  Future<void> markReady(String orderId) => _call('businessMarkReady', {'orderId': orderId});

  // ── Курьер ─────────────────────────────────────────────────────────────────────────────────────

  Future<NearbyBusinessOrders> listNearby({double? lat, double? lng, int? radiusKm}) async {
    final d = await _call('listNearbyBusinessOrders', {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (radiusKm != null) 'radiusKm': radiusKm,
    });
    final raw = d['orders'] is List ? d['orders'] as List : const [];
    return NearbyBusinessOrders(
      [for (final m in raw.whereType<Map>()) NearbyBusinessOrder.fromMap(Map<String, dynamic>.from(m))],
      buyoutLimit: d['buyoutLimit'] is num ? (d['buyoutLimit'] as num).toInt() : 0,
    );
  }

  Future<void> claim(String orderId) => _call('courierClaimBusinessOrder', {'orderId': orderId});

  // ── Етказиш нархи сўрови (йирик техника, STAGE 11) ─────────────────────────────────────────────────

  /// Харидор: сўров (идемпотент — шу маҳсулот учун очиқ сўров бўлса ўшаниси, `duplicate: true`).
  Future<DeliveryQuoteRequestResult> requestDeliveryQuote({
    required String itemId,
    required int qty,
    required double lat,
    required double lng,
    required String address,
    int? floor,
    String note = '',
  }) async =>
      DeliveryQuoteRequestResult.fromMap(await _call('requestDeliveryQuote', {
        'itemId': itemId,
        'qty': qty,
        'lat': lat,
        'lng': lng,
        'address': address,
        'floor': floor,
        if (note.isNotEmpty) 'note': note,
      }));

  /// Админ ёки тасдиқланган курьер: нарх (бутун сўм). Биринчи жавоб ғолиб (`QUOTE_ALREADY_ANSWERED`).
  Future<DeliveryQuoteRespondResult> respondDeliveryQuote({required String quoteId, required int priceUzs}) async =>
      DeliveryQuoteRespondResult.fromMap(
        await _call('respondDeliveryQuote', {'quoteId': quoteId, 'priceUzs': priceUzs}),
      );

  /// Харидор: нархни тасдиқлаш → буюртма (`placeBusinessOrder` натижаси; сўров бўйича идемпотент).
  Future<BusinessPlaceResult> acceptDeliveryQuote({
    required String quoteId,
    required String deliveryPaymentMethod,
    String note = '',
  }) async =>
      BusinessPlaceResult.fromMap(await _call('acceptDeliveryQuote', {
        'quoteId': quoteId,
        'deliveryPaymentMethod': deliveryPaymentMethod,
        if (note.isNotEmpty) 'note': note,
      }));

  /// Курьер/админ: очиқ сўровлар (курьерга мижоз манзили ва телефони берилмайди — сервер).
  Future<OpenDeliveryQuotes> listOpenDeliveryQuotes({double? lat, double? lng, int? radiusKm}) async {
    final d = await _call('listOpenDeliveryQuotes', {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (radiusKm != null) 'radiusKm': radiusKm,
    });
    final raw = d['quotes'] is List ? d['quotes'] as List : const [];
    return OpenDeliveryQuotes(
      [for (final m in raw.whereType<Map>()) OpenDeliveryQuote.fromMap(Map<String, dynamic>.from(m))],
      viewer: d['viewer'] is String ? d['viewer'] as String : '',
    );
  }

  /// Харидор: ўз сўрови ҳолати (rules — `buyerUid == ўз телефони`). Йўқ/рухсат йўқ — `null`.
  Stream<DeliveryQuote?> watchDeliveryQuote(String quoteId) =>
      _db.collection('delivery_quotes').doc(quoteId).snapshots().map((s) {
        final d = s.data();
        return s.exists && d != null ? DeliveryQuote.fromMap(s.id, d) : null;
      });

  Future<void> pickup(String orderId, {required String pickupCode}) =>
      _call('courierPickupBusinessOrder', {'orderId': orderId, 'pickupCode': pickupCode});

  Future<void> arrive(String orderId) => _call('courierArriveBusinessOrder', {'orderId': orderId});

  Future<BusinessCompleteResult> complete(String orderId) async =>
      BusinessCompleteResult.fromMap(await _call('courierCompleteBusinessOrder', {'orderId': orderId}));

  // ── Ўқиш ──────────────────────────────────────────────────────────────────────────────────────

  Stream<BusinessOrder?> watchOrder(String orderId) => _orders.doc(orderId).snapshots().map((s) {
        final d = s.data();
        return s.exists && d != null ? BusinessOrder.fromMap(s.id, d) : null;
      });

  /// Сотувчининг буюртмалари (энг янгиси биринчи). Фақат `type: business` қолдирилади.
  Stream<List<BusinessOrder>> watchSellerOrders(String sellerPhone, {int limit = sellerListLimit}) {
    final spec = sellerQuerySpec(sellerPhone, limit: limit);
    if (spec.isEqualTo.length < 11) return Stream.value(const []);
    return _orders
        .where(spec.field, isEqualTo: spec.isEqualTo)
        .orderBy(spec.orderBy, descending: spec.descending)
        .limit(spec.limit)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (d.data()['type'] == 'business') BusinessOrder.fromMap(d.id, d.data()),
            ]);
  }

  /// Бир марта ўқиш (эга хабидаги «Янги буюртмалар» сони — листенер йўқ, 36-қоида).
  Future<List<BusinessOrder>> fetchSellerOrders(String sellerPhone, {int limit = 50}) async =>
      watchSellerOrders(sellerPhone, limit: limit).first;

  /// Олиб кетиш коди (4 рақам). Йўқ/рухсат йўқ — `null`.
  Stream<String?> watchPickupCode(String orderId) => _orders
      .doc(orderId)
      .collection('private')
      .doc('secrets')
      .snapshots()
      .map((d) => d.exists ? (d.data()?['pickupCode'] as String?) : null);
}

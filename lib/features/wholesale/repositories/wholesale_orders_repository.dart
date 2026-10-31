import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../../../core/utils/formatters.dart' show canonicalPhoneId;
import '../../demand_offer/data/demand_repository.dart' show kDemandCoreRegion;
import '../models/wholesale_order.dart';
import '../models/wholesale_quote.dart';

/// Улгуржи буюртма хатоси: [reason] — сервер `details.reason` (UI матн
/// калитини танлаш учун, 25-банд). Фойдаланувчига [reason] ЎЗИ кўрсатилмайди.
class WholesaleOrderException implements Exception {
  const WholesaleOrderException(this.code, this.reason, {this.details = const {}});

  final String code;
  final String reason;
  final Map<String, dynamic> details;

  int? detailInt(String key) {
    final v = details[key];
    return v is num ? v.toInt() : null;
  }

  @override
  String toString() => 'WholesaleOrderException($code/$reason)';
}

/// Улгуржи буюртма занжири (4-босқич клиенти).
///
/// ЁЗИШ — фақат callable (Rules: `wholesale_orders` клиентга ёпиқ). ЎҚИШ —
/// харидор/сотувчи ўз буюртмаларини тинглайди.
///
/// Икки codebase (ҳужжат `docs/ulgurji_buyurtma_zanjiri_uz.md` §2):
///   europe-west1 (`functions_demand`) — квота, бекор, етказиш коди, 3b карта
///   us-central1 (default, ҳамён/ledger) — `placeWholesaleOrder`
class WholesaleOrdersRepository {
  WholesaleOrdersRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? demandFunctions,
    FirebaseFunctions? walletFunctions,
    Uuid? uuid,
  })  : _dbOverride = firestore,
        _demandOverride = demandFunctions,
        _walletOverride = walletFunctions,
        _uuid = uuid ?? const Uuid();

  final FirebaseFirestore? _dbOverride;
  final FirebaseFunctions? _demandOverride;
  final FirebaseFunctions? _walletOverride;
  final Uuid _uuid;

  // Ленивый: тестда Firebase'сиз яратиш мумкин бўлсин.
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseFunctions get _demand =>
      _demandOverride ?? FirebaseFunctions.instanceFor(region: kDemandCoreRegion);
  FirebaseFunctions get _wallet => _walletOverride ?? FirebaseFunctions.instance;

  CollectionReference<Map<String, dynamic>> get _orders => _db.collection('wholesale_orders');

  /// Сервер қабул қиладиган шакл: `^[A-Za-z0-9_-]{8,80}$`.
  /// Битта УРИНИШ (битта квота) учун бир марта яратилади, қайта юборишда
  /// ўша калит — икки марта босилса ҳам битта буюртма (21-банд).
  String newRequestId() => 'wo-${_uuid.v4().replaceAll('-', '')}';

  // ── Дарвоза (кириш нуқтаси учун) ──────────────────────────────────

  static Future<WholesaleOrdersGate>? _gateCache;
  static DateTime? _gateAt;
  static const _gateTtl = Duration(minutes: 10);

  /// `module_config/wholesale_orders_all` — сеансда 10 дақиқада бир марта
  /// ўқилади (свайпда ҳар товарга қайта ўқиш йўқ, 36/37-банд). Хато — ёпиқ.
  Future<WholesaleOrdersGate> gate() {
    final now = DateTime.now();
    final cached = _gateCache;
    if (cached != null && _gateAt != null && now.difference(_gateAt!) < _gateTtl) {
      return cached;
    }
    _gateAt = now;
    return _gateCache = _readGate();
  }

  Future<WholesaleOrdersGate> _readGate() async {
    try {
      final s = await _db.collection('module_config').doc('wholesale_orders_all').get();
      return WholesaleOrdersGate.fromMap(s.data());
    } catch (e) {
      // Ўқилмади (тармоқ, Firebase тайёр эмас) — ЁПИҚ; кейинги сафар қайта уринади.
      debugPrint('[WholesaleOrder] gate read failed: ${e.runtimeType}');
      _gateAt = null;
      return WholesaleOrdersGate.closed;
    }
  }

  /// Сервер `module_disabled`/`module_internal_only` қайтарса — кешни ёпиқ
  /// деб белгилаймиз (тугма шу сеансда яширинади).
  static void markGateClosed() {
    _gateCache = Future.value(WholesaleOrdersGate.closed);
    _gateAt = DateTime.now();
  }

  // ── Харидор ───────────────────────────────────────────────────────

  Future<WholesaleQuote> quote({
    required String productId,
    required String packId,
    required int qty,
    required WholesaleDestination destination,
    String? paymentMethod,
  }) async {
    final d = await _call(_demand, 'quoteWholesaleOrder', {
      'productId': productId,
      'packId': packId,
      'qty': qty,
      'destination': destination.toInput(),
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
    });
    return WholesaleQuote.fromMap(d);
  }

  Future<WholesalePlaceResult> place({
    required String quoteId,
    required String clientRequestId,
  }) async =>
      WholesalePlaceResult.fromMap(await _call(_wallet, 'placeWholesaleOrder', {
        'quoteId': quoteId,
        'clientRequestId': clientRequestId,
      }));

  Future<void> cancel(String orderId) => _call(_demand, 'cancelWholesaleOrder', {'orderId': orderId});

  Future<WholesaleDeliveryCode> deliveryCode(String orderId) async =>
      WholesaleDeliveryCode.fromMap(await _call(_demand, 'getWholesaleDeliveryCode', {'orderId': orderId}));

  /// 3b. Регион: europe-west1 (ҳамкор сессия контракти: `submitWholesaleCardReceipt`
  /// europe-west1; қолган карта callable'лари ҳам шу ерда деб олинди — UNKNOWN).
  Future<WholesaleCardInfo> cardPaymentInfo(String orderId) async =>
      WholesaleCardInfo.fromMap(await _call(_demand, 'getWholesaleCardPaymentInfo', {'orderId': orderId}));

  Future<void> submitCardReceipt({required String orderId, required String receiptPath}) =>
      _call(_demand, 'submitWholesaleCardReceipt', {'orderId': orderId, 'receiptPath': receiptPath});

  // ── Сотувчи ───────────────────────────────────────────────────────

  /// 3b: «Пул тушди». Сотувчининг БУЮРТМАДАГИ ЯГОНА амали (қабул/рад йўқ).
  Future<void> confirmCardPayment(String orderId) =>
      _call(_demand, 'confirmWholesaleCardPayment', {'orderId': orderId});

  /// 3b: тўлов қабул қилиш картаси.
  Future<void> setSellerCard({required String cardNumber, required String holderName}) =>
      _call(_demand, 'setWholesaleSellerCard', {
        'cardNumber': cardNumber.replaceAll(RegExp(r'\D'), ''),
        'holderName': holderName.trim(),
      });

  // ── Жонли ўқиш ────────────────────────────────────────────────────
  //
  // Индекслар (композит): wholesale_orders (buyerId ASC, createdAt DESC) ва
  // (sellerId ASC, createdAt DESC).

  Stream<List<WholesaleOrder>> watchBuyerOrders(String buyerId, {int limit = 50}) =>
      _list('buyerId', buyerId, limit);

  Stream<List<WholesaleOrder>> watchSellerOrders(String sellerId, {int limit = 50}) =>
      _list('sellerId', sellerId, limit);

  Stream<List<WholesaleOrder>> _list(String field, String id, int limit) {
    final uid = canonicalPhoneId(id);
    if (uid.isEmpty) return Stream.value(const []);
    return _orders
        .where(field, isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => WholesaleOrder.fromMap(d.id, d.data())).toList());
  }

  Stream<WholesaleOrder?> watchOrder(String orderId) => _orders.doc(orderId).snapshots().map((s) {
        final d = s.data();
        return d == null ? null : WholesaleOrder.fromMap(s.id, d);
      });

  // ── Ички ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _call(
    FirebaseFunctions fn,
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await fn.httpsCallable(name).call<Object?>(payload);
      final d = res.data;
      if (d is Map) return d.map((k, v) => MapEntry(k.toString(), v));
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final raw = e.details;
      final details = raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
      final reason = '${details['reason'] ?? ''}'.trim();
      if (reason == 'module_disabled' || reason == 'module_internal_only') markGateClosed();
      throw WholesaleOrderException(e.code, reason.isEmpty ? e.code : reason, details: details);
    }
  }
}

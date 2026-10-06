// AVA LOGISTICS (Relay) — репозиторий.
//
// ЁЗИШ — фақат callable орқали (Firestore қоидаси: ҳамма коллекция
// `write: false`). ЎҚИШ — жонли stream (кузатув тасмаси, буюртмалар).
//
// Иккита codebase (ҳужжат 7.8 + 7.6):
//   `functions_demand` (europe-west1) — буюртма, LEG, custody, сирлар, бекор
//   `functions` default (us-central1)  — ЭСКРОУ (ledger ўша ерда):
//                                         `fundShipmentEscrow`
// Такси billing репозиторийси билан бир хил андоза.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../../demand_offer/data/demand_repository.dart' show kDemandCoreRegion;
import '../domain/logistics_models.dart';

class LogisticsException implements Exception {
  const LogisticsException(this.code, this.reason, this.message, {this.details});

  final String code;

  /// Сервер `details.reason` — UI матн танлаш учун (25-банд).
  final String reason;
  final String message;
  final Map<String, dynamic>? details;

  /// Фойдаланувчига кўрсатиладиган матн калити.
  String get l10nKey => 'logistics_err_$reason';

  @override
  String toString() => 'LogisticsException($code/$reason): $message';
}

class LogisticsRepository {
  LogisticsRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? demandFunctions,
    FirebaseFunctions? escrowFunctions,
    Uuid? uuid,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _demand = demandFunctions ?? FirebaseFunctions.instanceFor(region: kDemandCoreRegion),
        _escrow = escrowFunctions ?? FirebaseFunctions.instance,
        _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _db;
  final FirebaseFunctions _demand;
  final FirebaseFunctions _escrow;
  final Uuid _uuid;

  CollectionReference<Map<String, dynamic>> get _orders => _db.collection('logistics_orders');
  CollectionReference<Map<String, dynamic>> get _shipments => _db.collection('shipments');
  CollectionReference<Map<String, dynamic>> get _custody => _db.collection('custody_events');

  /// Т-12 идемпотентлик калити — форма очилганда БИР МАРТА.
  String newRequestId() => 'req-${_uuid.v4().replaceAll('-', '').substring(0, 20)}';

  // ── Мижоз (жўнатувчи) ──────────────────────────────────────────────

  Future<LogisticsQuote> quote({
    required LogisticsPoint origin,
    required LogisticsPoint destination,
    required List<ParcelSpec> parcels,
  }) async {
    final data = await _call(_demand, 'quoteLogisticsOrder', {
      'origin': origin.toInput(),
      'destination': destination.toInput(),
      'parcels': parcels.map((p) => p.toInput()).toList(),
    });
    return LogisticsQuote.fromMap(data);
  }

  Future<CreateOrderResult> createOrder({
    required String clientRequestId,
    required LogisticsPoint origin,
    required LogisticsPoint destination,
    required List<ParcelSpec> parcels,
    required String recipientName,
    required String recipientPhone,
    String note = '',
    DateTime? termsAcceptedAt,
  }) async {
    final data = await _call(_demand, 'createLogisticsOrder', {
      'clientRequestId': clientRequestId,
      'origin': origin.toInput(),
      'destination': destination.toInput(),
      'parcels': parcels.map((p) => p.toInput()).toList(),
      'recipient': {'name': recipientName, 'phone': recipientPhone},
      if (note.isNotEmpty) 'note': note,
      if (termsAcceptedAt != null) 'termsAcceptedAt': termsAcceptedAt.toUtc().toIso8601String(),
    });
    return CreateOrderResult.fromMap(data);
  }

  /// Ҳамён → эскроу (D-11). Default codebase (ledger).
  Future<Map<String, dynamic>> fundEscrow(String shipmentId) =>
      _call(_escrow, 'fundShipmentEscrow', {'shipmentId': shipmentId});

  Future<ShipmentSecrets> secrets(String shipmentId) async =>
      ShipmentSecrets.fromMap(await _call(_demand, 'getShipmentSecrets', {'shipmentId': shipmentId}));

  Future<Map<String, dynamic>> cancelOrder(String orderId) =>
      _call(_demand, 'cancelLogisticsOrder', {'orderId': orderId});

  // ── Ижрочи ─────────────────────────────────────────────────────────

  Future<void> acceptLeg(String legId) async {
    await _call(_demand, 'acceptLeg', {'legId': legId});
  }

  /// Посилкани ОЛДИМ — код ёки QR + расм (мажбурий) + ҳолат белгиси.
  Future<Map<String, dynamic>> scanHandover({
    required String legId,
    String? code,
    String? qrPayload,
    required List<String> photoUrls,
    List<String> conditionFlags = const [ConditionFlags.intact],
    double? lat,
    double? lng,
    double? accuracy,
  }) =>
      _call(_demand, 'scanHandover', {
        'legId': legId,
        if (code != null && code.isNotEmpty) 'code': code,
        if (qrPayload != null && qrPayload.isNotEmpty) 'qrPayload': qrPayload,
        'photoUrls': photoUrls,
        'conditionFlags': conditionFlags,
        if (lat != null && lng != null)
          'location': {'lat': lat, 'lng': lng, if (accuracy != null) 'accuracy': accuracy},
        'clientRequestId': newRequestId(),
      });

  /// Қабул қилувчига ТОПШИРДИМ — алоҳида 6 хонали код.
  Future<Map<String, dynamic>> confirmDelivery({
    required String legId,
    required String deliveryCode,
    required List<String> photoUrls,
    double? lat,
    double? lng,
  }) =>
      _call(_demand, 'confirmDelivery', {
        'legId': legId,
        'deliveryCode': deliveryCode,
        'photoUrls': photoUrls,
        if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
        'clientRequestId': newRequestId(),
      });

  // ── Жонли ўқиш ─────────────────────────────────────────────────────

  Stream<List<LogisticsOrder>> myOrders(String ownerId, {int limit = 50}) => _orders
      .where('ownerId', isEqualTo: ownerId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => LogisticsOrder.fromMap(d.id, d.data())).toList());

  Stream<LogisticsOrder?> watchOrder(String orderId) => _orders.doc(orderId).snapshots().map((s) {
        final d = s.data();
        return d == null ? null : LogisticsOrder.fromMap(s.id, d);
      });

  /// Буюртманинг жўнатмалари. `ownerId` филтри ШАРТ: Firestore қоидаси
  /// сўровни фақат «эгаси ўзиники» деб исботлай олганда ўтказади
  /// (`logistics_rules.test.js`да қулфланган). Иккита тенглик — композит
  /// индекс керак эмас.
  Stream<List<Shipment>> watchShipmentsOfOrder(
    String orderId, {
    required String ownerId,
  }) =>
      _shipments
          .where('ownerId', isEqualTo: ownerId)
          .where('orderId', isEqualTo: orderId)
          .snapshots()
          .map((s) => s.docs.map((d) => Shipment.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.trackingNumber.compareTo(b.trackingNumber)));

  Stream<Shipment?> watchShipment(String shipmentId) => _shipments.doc(shipmentId).snapshots().map((s) {
        final d = s.data();
        return d == null ? null : Shipment.fromMap(s.id, d);
      });

  /// Кузатув тасмаси (эгаси). `ownerId` филтри қоида учун шарт (юқоридаги
  /// каби). Индекс: `custody_events(ownerId, shipmentId, timestamp)`.
  Stream<List<CustodyEvent>> watchCustody(
    String shipmentId, {
    required String ownerId,
  }) =>
      _custody
          .where('ownerId', isEqualTo: ownerId)
          .where('shipmentId', isEqualTo: shipmentId)
          .orderBy('timestamp')
          .snapshots()
          .map((s) => s.docs.map((d) => CustodyEvent.fromMap(d.id, d.data())).toList());

  /// Ижрочининг жўнатмалари. Индекс: `shipments(assignedProviderIds, updatedAt)`.
  Stream<List<Shipment>> providerShipments(String providerId, {int limit = 50}) => _shipments
      .where('assignedProviderIds', arrayContains: providerId)
      .orderBy('updatedAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => Shipment.fromMap(d.id, d.data())).toList());

  // ── Ички ───────────────────────────────────────────────────────────

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
      final details = e.details;
      final map = details is Map ? details.map((k, v) => MapEntry(k.toString(), v)) : null;
      final reason = (map?['reason'] ?? '').toString();
      throw LogisticsException(e.code, reason.isEmpty ? e.code : reason, e.message ?? 'Xatolik', details: map);
    }
  }
}

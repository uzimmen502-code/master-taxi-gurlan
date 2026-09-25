import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../core/ev_charging_rules_holder.dart';
import '../core/utils/formatters.dart';
import '../models/ev_charging_report.dart';
import '../models/ev_charging_station.dart';
import '../utils/geo_hash.dart';

/// `ev_charging_stations` — ⚡ jamoa tomonidan to'ldiriladigan zaryadlash
/// nuqtalari xaritasi. Geohash so'rov naqshi `rides_repository.dart`dan
/// qayta ishlatilgan (`GeoHash.neighborsForRadius` + `whereIn`).
class EvStationRepository {
  EvStationRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> get _stations =>
      _db.collection('ev_charging_stations');

  /// Joriy foydalanuvchining `users/{phoneDigits}` hujjat ID'i — rules'dagi
  /// `userDocIdFromPhoneToken()` bilan mos.
  String get _currentUserId =>
      canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');

  /// Atrofdagi aktiv nuqtalar — GPS radius (km) ichida, geohash4 katakchalar
  /// bo'yicha so'rov, aniq masofa bo'yicha client-side filtr.
  Stream<List<EvChargingStation>> watchNearby({
    required double lat,
    required double lng,
    double radiusKm = 20,
  }) {
    final cells = GeoHash.neighborsForRadius(lat, lng, precision: 4);
    return _stations
        .where('isActive', isEqualTo: true)
        .where('geohash4', whereIn: cells)
        .snapshots()
        .map((snap) {
      final radiusMeters = radiusKm * 1000;
      return snap.docs
          .map(EvChargingStation.fromDoc)
          .where((s) =>
              Geolocator.distanceBetween(lat, lng, s.latitude, s.longitude) <=
              radiusMeters)
          .toList();
    });
  }

  /// Барча аktiv nuqtalar — masofaga qaramasdan (ega qarori, 2026-09-22:
  /// harita 20 km radius bilan cheklanmasin, 456 ta import qilingan nuqta
  /// ham ko'rinsin). `EvMapView` klasterlash orqali zich hududlarni
  /// birlashtiradi, shuning uchun bu so'rov hajmi muammo emas.
  Stream<List<EvChargingStation>> watchAllActive() {
    return _stations
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map(EvChargingStation.fromDoc).toList());
  }

  /// Yangi koordinata atrofida allaqachon mavjud nuqtalar —
  /// `evChargingConfig.duplicateRadiusMeters` ichida (22-band).
  Future<List<EvChargingStation>> findDuplicatesNear(
    double lat,
    double lng,
  ) async {
    final radiusMeters = EvChargingRulesHolder.current.duplicateRadiusMeters;
    final cells = GeoHash.neighborsForRadius(lat, lng, precision: 4);
    final snap = await _stations
        .where('isActive', isEqualTo: true)
        .where('geohash4', whereIn: cells)
        .get();
    return snap.docs
        .map(EvChargingStation.fromDoc)
        .where((s) =>
            Geolocator.distanceBetween(lat, lng, s.latitude, s.longitude) <=
            radiusMeters)
        .toList();
  }

  /// Тариф рўйхати (id → {months, price}) — `settings`га боғлиқ бўлиши
  /// мумкин, шунинг учун серверда сақланади (эга қарори, 2026-09-22).
  Future<Map<String, EvStationTariff>> fetchStationTariffs() async {
    final res = await _functions.httpsCallable('getEvStationTariffs').call();
    final raw = Map<String, dynamic>.from(res.data as Map? ?? const {});
    final tariffs = Map<String, dynamic>.from(raw['tariffs'] as Map? ?? const {});
    return tariffs.map((id, v) {
      final m = Map<String, dynamic>.from(v as Map);
      return MapEntry(id, EvStationTariff(
        id: id,
        months: (m['months'] as num).toInt(),
        price: (m['price'] as num).toInt(),
      ));
    });
  }

  /// Янги нуқта — ПУЛЛИК (эга қарори, 2026-09-22): координата мажбурий,
  /// қолгани ихтиёрий, лекин энди тўғридан-тўғри Firestore'га эмас —
  /// `payAndCreateEvStation` callable орқали (AVA ҳамёнидан, идемпотент;
  /// `firestore.rules`'да client `create` энди рухсат этилмайди).
  Future<EvStationPaymentResult> payAndCreateStation({
    required String tariffId,
    required double lat,
    required double lng,
    List<String> chargingTypes = const [],
    List<String> connectors = const [],
    num? powerKw,
    num? price,
    String? operatorName,
    String? note,
  }) async {
    try {
      final res = await _functions
          .httpsCallable(
            'payAndCreateEvStation',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call({
        'tariff': tariffId,
        'lat': lat,
        'lng': lng,
        'chargingTypes': chargingTypes,
        'connectors': connectors,
        if (powerKw != null) 'powerKw': powerKw,
        if (price != null) 'price': price,
        if ((operatorName ?? '').trim().isNotEmpty) 'operatorName': operatorName!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
        'idempotencyKey': _uuid.v4(),
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? const {});
      return EvStationPaymentResult(
        stationId: (data['stationId'] ?? '') as String,
        debited: (data['debited'] as num?)?.toInt() ?? 0,
        balance: (data['balance'] as num?)?.toInt() ?? 0,
        paidUntil: DateTime.fromMillisecondsSinceEpoch(
            (data['paidUntil'] as num?)?.toInt() ?? 0),
      );
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map
          ? Map<String, dynamic>.from(e.details as Map)
          : const <String, dynamic>{};
      final reason = (details['reason'] ?? e.message ?? e.code).toString();
      throw EvStationPaymentException(reason, details: details);
    }
  }

  /// Admin: `reportCount > 0` stansiyalar navbati (moderatsiya, 6-band).
  Stream<List<EvChargingStation>> watchReportedStations() {
    return _stations
        .where('reportCount', isGreaterThan: 0)
        .orderBy('reportCount', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(EvChargingStation.fromDoc).toList());
  }

  /// Admin: bitta stansiyaning report tafsilotlari.
  Stream<List<EvChargingReport>> watchReports(String stationId) {
    return _stations
        .doc(stationId)
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => EvChargingReport.fromDoc(d, stationId)).toList());
  }

  /// Mavjud nuqtani to'ldirish/to'g'irlash — faqat ixtiyoriy maydonlar
  /// (19-band, `evStationCommunityPatch()` bilan mos whitelist).
  Future<void> updateStationDetails(
    String stationId, {
    List<String>? chargingTypes,
    List<String>? connectors,
    num? powerKw,
    num? price,
    String? operatorName,
    String? note,
  }) {
    return _stations.doc(stationId).update({
      if (chargingTypes != null) 'chargingTypes': chargingTypes,
      if (connectors != null) 'connectors': connectors,
      if (powerKw != null) 'powerKw': powerKw,
      if (price != null) 'price': price,
      if (operatorName != null) 'operatorName': operatorName,
      if (note != null) 'note': note,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// «Ҳозир банд» / «Бўш» — жамоа хабари.
  ///
  /// `status` (станция умуман ишлайдими) га ТЕГМАЙДИ — бу бошқа нарса.
  /// Белги `EvChargingStation.occupancyTtl` давомида амал қилади, кейин
  /// UI уни «маълумот йўқ» деб кўрсатади (эскирган қиймат ўчирилмайди —
  /// ортиқча ёзув қилмаслик учун, фақат ҳисобга олинмайди).
  Future<void> setOccupancy(String stationId, {required bool busy}) {
    return _stations.doc(stationId).update({
      'occupancy': busy ? 'busy' : 'free',
      'occupancyAt': FieldValue.serverTimestamp(),
    });
  }

  /// "Ҳа, шу ерда" — idempotent, docId = joriy foydalanuvchi (26-band).
  Future<void> confirmStation(String stationId) {
    final userId = _currentUserId;
    return _stations.doc(stationId).collection('confirmations').doc(userId).set({
      'userId': userId,
      'confirmedAt': FieldValue.serverTimestamp(),
    });
  }

  /// "Йўқ, нуқта йўқ" → хабар бериш (limit — Security Rules'da tekshiriladi,
  /// oshib ketsa `FirebaseException(code: 'permission-denied')` chiqadi).
  Future<void> reportStation(
    String stationId, {
    required EvReportReason reason,
    String comment = '',
  }) {
    return _stations.doc(stationId).collection('reports').add({
      'reporterId': _currentUserId,
      'reason': reason.key,
      'comment': comment.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Станция қўшиш тарифи (`getEvStationTariffs` callable'идан).
class EvStationTariff {
  const EvStationTariff({required this.id, required this.months, required this.price});

  final String id;
  final int months;
  final int price;
}

/// `payAndCreateEvStation` муваффақиятли натижаси.
class EvStationPaymentResult {
  const EvStationPaymentResult({
    required this.stationId,
    required this.debited,
    required this.balance,
    required this.paidUntil,
  });

  final String stationId;
  final int debited;
  final int balance;
  final DateTime paidUntil;
}

/// Тўлов хатоси. [code] қийматлари: `insufficient_balance`, `unknown_tariff`,
/// `upstream_unavailable` ва ҳ.к. (`assistant_service.dart`даги
/// `AssistantException` билан бир хил нақш).
class EvStationPaymentException implements Exception {
  const EvStationPaymentException(this.code, {this.details = const {}});

  final String code;
  final Map<String, dynamic> details;

  bool get isInsufficientBalance => code == 'insufficient_balance';

  @override
  String toString() => 'EvStationPaymentException($code)';
}

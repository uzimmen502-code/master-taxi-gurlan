import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../core/ev_charging_rules_holder.dart';
import '../core/utils/formatters.dart';
import '../models/ev_charging_report.dart';
import '../models/ev_charging_station.dart';
import '../utils/geo_hash.dart';

/// `ev_charging_stations` — ⚡ jamoa tomonidan to'ldiriladigan zaryadlash
/// nuqtalari xaritasi. Geohash so'rov naqshi `rides_repository.dart`dan
/// qayta ishlatilgan (`GeoHash.neighborsForRadius` + `whereIn`).
class EvStationRepository {
  EvStationRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

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

  /// Yangi nuqta — koordinata majburiy, qolgan hammasi ixtiyoriy (9-band).
  Future<String> createStation({
    required double lat,
    required double lng,
    List<String> chargingTypes = const [],
    List<String> connectors = const [],
    num? powerKw,
    num? price,
    String? operatorName,
    String? note,
  }) async {
    final userId = _currentUserId;
    final ref = await _stations.add({
      'location': {'latitude': lat, 'longitude': lng},
      'geohash4': GeoHash.encode(lat, lng, precision: 4),
      'chargingTypes': chargingTypes,
      'connectors': connectors,
      if (powerKw != null) 'powerKw': powerKw,
      if (price != null) 'price': price,
      if ((operatorName ?? '').trim().isNotEmpty) 'operatorName': operatorName!.trim(),
      if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      'status': 'unknown',
      'verificationStatus': 'community',
      'confirmationCount': 0,
      'reportCount': 0,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isActive': true,
    });
    return ref.id;
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

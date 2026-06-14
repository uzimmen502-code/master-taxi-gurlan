import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/utils/formatters.dart';
import '../models/driver_model.dart';
import '../models/driver_stats.dart';
import 'user_repository.dart';

/// Haydovchi arizasi yuborish natijasi.
class DriverApplicationSubmitResult {
  const DriverApplicationSubmitResult({
    required this.autoApproved,
    required this.isFirstSubmission,
  });

  final bool autoApproved;
  final bool isFirstSubmission;
}

/// `drivers` collection.
class DriverRepository {
  DriverRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('drivers');
  DocumentReference<Map<String, dynamic>> get _appSettings =>
      _db.collection('settings').doc('app');
  CollectionReference<Map<String, dynamic>> get _driverRequests =>
      _db.collection('driver_requests');

  Future<DriverStats?> getStats(String uid) async {
    if (uid.isEmpty) return null;
    final snap = await _col.doc(uid).get();
    if (!snap.exists) return null;
    return DriverStats.fromDoc(snap);
  }

  /// Online va bo'sh haydovchilar (filtrlash uchun koordinatasi borlari).
  ///
  /// E'tibor: bu so'rov barcha online+bo'sh haydovchilarni qaytaradi.
  /// Yo'lovchi tarafida masofa bo'yicha filtrlanadi. Katta hududda
  /// kelajakda geohash-based query bilan optimallashtirilishi mumkin.
  Future<List<DriverModel>> getAvailable() async {
    // 'local' va 'alone' — mahalliy taksi uchun ikki xil nom (nomenklatura birlashtirilguncha).
    final snap = await _col
        .where('isOnline', isEqualTo: true)
        .where('isBusy', isEqualTo: false)
        .where('taxiType', whereIn: ['local', 'alone', 'both']).get();
    return snap.docs
        .map(DriverModel.fromDoc)
        .where((d) => d.hasCoordinates)
        .toList();
  }

  /// Ҳайдовчи профилини upsert қилиш (умумий kalit'лар).
  Future<void> upsertProfile({
    required String uid,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
  }) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).set({
        'name': name,
        'phone': phone,
        'car': car,
        'plate': plate,
        'taxiType': taxiType,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// `auto` — haydovchi darhol faol. `manual` — admin tasdiqi.
  Stream<String> watchDriverApprovalMode() {
    return _appSettings.snapshots().map((snap) {
      final mode = snap.data()?['driverApprovalMode'] as String? ?? 'manual';
      return mode == 'auto' ? 'auto' : 'manual';
    });
  }

  Future<String> getDriverApprovalMode() async {
    try {
      final snap = await _appSettings.get();
      final mode = snap.data()?['driverApprovalMode'] as String? ?? 'manual';
      return mode == 'auto' ? 'auto' : 'manual';
    } catch (_) {
      return 'manual';
    }
  }

  Future<void> setDriverApprovalMode(String mode) async {
    final v = mode == 'auto' ? 'auto' : 'manual';
    await _appSettings.set({
      'driverApprovalMode': v,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _driverDocId(String uid) => canonicalPhoneId(uid);

  List<String> _driverDocIds(String uid) {
    final canon = canonicalPhoneId(uid);
    final raw = phoneDigits(uid);
    return {canon, raw, uid.trim()}
        .where((id) => phoneDigits(id).length >= 9)
        .toList(growable: false);
  }

  /// Mobil: `driverApprovalMode` bo'yicha ariza yoki avto-tasdiq.
  Future<DriverApplicationSubmitResult> submitDriverApplication({
    required String uid,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
    String routeFrom = '',
    String routeTo = '',
    List<String> routeStops = const [],
  }) async {
    final docId = _driverDocId(uid);
    final mode = await getDriverApprovalMode();
    if (mode == 'auto') {
      await _autoApproveViaCloudFunction(
        docId: docId,
        name: name,
        phone: phone,
        car: car,
        plate: plate,
        taxiType: taxiType,
        routeFrom: routeFrom,
        routeTo: routeTo,
        routeStops: routeStops,
      );
      return const DriverApplicationSubmitResult(
        autoApproved: true,
        isFirstSubmission: false,
      );
    }
    final isFirst = await submitDriverRequest(
      uid: docId,
      name: name,
      phone: phone,
      car: car,
      plate: plate,
      taxiType: taxiType,
      routeFrom: routeFrom,
      routeTo: routeTo,
      routeStops: routeStops,
    );
    return DriverApplicationSubmitResult(
      autoApproved: false,
      isFirstSubmission: isFirst,
    );
  }

  Future<void> _autoApproveViaCloudFunction({
    required String docId,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
    String routeFrom = '',
    String routeTo = '',
    List<String> routeStops = const [],
  }) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('autoApproveDriverApplication');
    await callable.call<Map<String, dynamic>>({
      'uid': docId,
      'name': name,
      'phone': phone,
      'car': car,
      'plate': plate,
      'taxiType': taxiType,
      'routeFrom': routeFrom,
      'routeTo': routeTo,
      'routeStops': routeStops,
    });
  }

  Future<bool> isApprovedForTaxi({
    required String uid,
    required String taxiType,
  }) async {
    if (uid.isEmpty) return false;
    for (final docId in _driverDocIds(uid)) {
      final snap = await _col.doc(docId).get();
      final data = snap.data();
      if (data == null) continue;
      if (_isApprovedForTaxiType(data, taxiType)) return true;
    }
    return false;
  }

  bool _isApprovedForTaxiType(Map<String, dynamic> data, String taxiType) {
    final approved =
        data['approved'] == true || data['approvalStatus'] == 'approved';
    if (!approved) return false;

    final rawTaxiTypes = data['taxiTypes'];
    if (rawTaxiTypes is List && rawTaxiTypes.contains(taxiType)) return true;

    final primaryTaxiType = (data['taxiType'] ?? '') as String;
    if (primaryTaxiType == taxiType || primaryTaxiType == 'both') return true;
    if (taxiType == 'alone' && primaryTaxiType == 'local') return true;
    if (taxiType == 'local' &&
        (primaryTaxiType == 'alone' || primaryTaxiType == 'local')) {
      return true;
    }
    if (taxiType == 'marshrut' && primaryTaxiType == 'marshrut') return true;
    if (taxiType == 'intercity' && primaryTaxiType == 'intercity') return true;
    return false;
  }

  /// Фойдаланувчининг ҳайдовчи аризаси (doc id = телефон).
  Stream<Map<String, dynamic>?> watchMyDriverRequest(String uid) {
    final id = canonicalPhoneId(uid);
    if (id.length < 9) return Stream.value(null);
    return _driverRequests.doc(id).snapshots().map((s) {
      if (!s.exists) return null;
      return s.data();
    });
  }

  /// `true` — yangi hujjat yaratildi (birinchi ariza).
  Future<bool> submitDriverRequest({
    required String uid,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
    String routeFrom = '',
    String routeTo = '',
    List<String> routeStops = const [],
  }) async {
    final docId = _driverDocId(uid);
    if (docId.length < 12) {
      throw Exception('invalid_phone_format');
    }

    final ref = _driverRequests.doc(docId);
    final snap = await ref.get();
    final route = _routeFields(routeFrom, routeTo, routeStops);

    var carValue = car.trim();
    var plateValue = plate.trim();
    if (carValue.isEmpty || plateValue.isEmpty) {
      final carInfo =
          await UserRepository().getCarInfo(canonicalPhoneId(uid));
      if (carInfo != null) {
        carValue = carInfo['carModel'] ?? carValue;
        plateValue = carInfo['carPlate'] ?? plateValue;
      }
    }

    final payload = <String, dynamic>{
      'uid': docId,
      'name': name.trim(),
      'phone': phone.trim(),
      'car': carValue,
      'plate': plateValue,
      'taxiType': taxiType,
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
      ...route,
    };

    if (!snap.exists) {
      await ref.set({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    }

    final prevStatus = snap.data()?['status'] as String? ?? '';
    if (prevStatus == 'rejected') {
      payload['rejectedAt'] = FieldValue.delete();
      payload['rejectedReason'] = FieldValue.delete();
      payload['rejectedBy'] = FieldValue.delete();
    }

    await ref.set(payload, SetOptions(merge: true));
    return false;
  }

  Map<String, dynamic> _routeFields(
    String routeFrom,
    String routeTo,
    List<String> routeStops,
  ) {
    final from = routeFrom.trim();
    final to = routeTo.trim();
    final stops = routeStops.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (from.isEmpty && to.isEmpty) return {};
    final label = stops.isEmpty
        ? '$from → $to'
        : '$from → ${stops.join(' → ')} → $to';
    return {
      'routeFrom': from,
      'routeTo': to,
      if (stops.isNotEmpty) 'routeStops': stops,
      'routeLabel': label,
    };
  }

  /// Auto-rejimда CF орқали тасдиқ; aks holda faqat `drivers` profilini yangilaydi.
  Future<void> approveDriverAutomatically({
    required String uid,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
    String routeFrom = '',
    String routeTo = '',
    List<String> routeStops = const [],
  }) async {
    final docId = _driverDocId(uid);
    final mode = await getDriverApprovalMode();
    if (mode != 'auto') {
      await upsertProfile(
        uid: docId,
        name: name,
        phone: phone,
        car: car,
        plate: plate,
        taxiType: taxiType,
      );
      return;
    }
    await _autoApproveViaCloudFunction(
      docId: docId,
      name: name,
      phone: phone,
      car: car,
      plate: plate,
      taxiType: taxiType,
      routeFrom: routeFrom,
      routeTo: routeTo,
      routeStops: routeStops,
    );
  }

  /// Онлайн ҳолатга ўтиш (универсал — barcha taxi турлари учун).
  Future<void> goOnline({
    required String uid,
    required String name,
    required String phone,
    required String taxiType,
    double? lat,
    double? lng,
  }) async {
    if (uid.isEmpty) return;
    await _col.doc(uid).set({
      'name': name,
      'phone': phone,
      'isOnline': true,
      'taxiType': taxiType,
      'lat': lat,
      'lng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> goOffline(String uid) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).update({
        'isOnline': false,
        'lat': null,
        'lng': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> updateLocation({
    required String uid,
    required double lat,
    required double lng,
  }) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).update({
        'lat': lat,
        'lng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> decrementSeats(String uid) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).update({
        'seatsLeft': FieldValue.increment(-1),
      });
    } catch (_) {}
  }

  Future<void> incrementSeats(String uid) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).update({
        'seatsLeft': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  Future<void> markUnavailable(String uid) async {
    if (uid.isEmpty) return;
    try {
      await _col.doc(uid).update({
        'isAvailable': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}

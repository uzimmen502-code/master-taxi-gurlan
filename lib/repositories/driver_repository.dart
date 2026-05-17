import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/driver_model.dart';
import '../models/driver_stats.dart';

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
        .where('taxiType', whereIn: ['local', 'alone', 'both'])
        .get();
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

  /// `auto` — стартда haydovchi darhol faol bo'ladi.
  /// `manual` — admin approval talab qilinadi.
  Stream<String> watchDriverApprovalMode() {
    return _appSettings.snapshots().map((snap) {
      final mode = snap.data()?['driverApprovalMode'] as String?;
      return mode == 'manual' ? 'manual' : 'auto';
    });
  }

  Future<String> getDriverApprovalMode() async {
    final snap = await _appSettings.get();
    final mode = snap.data()?['driverApprovalMode'] as String?;
    return mode == 'manual' ? 'manual' : 'auto';
  }

  Future<void> setDriverApprovalMode(String mode) async {
    await _appSettings.set({
      'driverApprovalMode': mode == 'manual' ? 'manual' : 'auto',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> submitDriverRequest({
    required String uid,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
    String status = 'pending',
  }) async {
    if (uid.isEmpty) return;
    await _driverRequests.doc(uid).set({
      'uid': uid,
      'name': name.trim(),
      'phone': phone.trim(),
      'car': car.trim(),
      'plate': plate.trim(),
      'taxiType': taxiType,
      'status': status,
      if (status == 'approved') 'approvedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> approveDriverAutomatically({
    required String uid,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required String taxiType,
  }) async {
    if (uid.isEmpty) return;
    final batch = _db.batch();
    batch.set(_col.doc(uid), {
      'name': name.trim(),
      'phone': phone.trim(),
      'car': car.trim(),
      'plate': plate.trim(),
      'taxiType': taxiType,
      'approvalStatus': 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_driverRequests.doc(uid), {
      'uid': uid,
      'name': name.trim(),
      'phone': phone.trim(),
      'car': car.trim(),
      'plate': plate.trim(),
      'taxiType': taxiType,
      'status': 'approved',
      'approvalMode': 'auto',
      'approvedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final userId = phoneDigits(phone);
    if (userId.length >= 9) {
      batch.set(_db.collection('users').doc(userId), {
        'role': 'driver',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
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

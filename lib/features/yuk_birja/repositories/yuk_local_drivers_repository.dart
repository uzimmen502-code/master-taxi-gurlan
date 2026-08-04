import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart';
import '../models/yuk_local_driver.dart';
import '../yuk_accept_radius.dart';
import '../yuk_vehicle_types.dart';

/// Firestore `yuk_local_drivers/{phoneUid}` — туман ичида live машиналар.
class YukLocalDriversRepository {
  YukLocalDriversRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const int watchLimit = 200;

  /// Охирги онлайндан кейин рўйхатда қолиш (дақиқа).
  static const onlineStaleMinutes = 15;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('yuk_local_drivers');

  DocumentReference<Map<String, dynamic>> docRef(String ownerId) =>
      _col.doc(canonicalPhoneId(ownerId));

  Stream<List<YukLocalDriver>> watchOnline({int limit = watchLimit}) {
    return _col
        .where('online', isEqualTo: true)
        .orderBy('lastOnlineAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).toList());
  }

  Future<YukLocalDriver?> getMine(String ownerId) async {
    final id = canonicalPhoneId(ownerId);
    if (id.isEmpty) return null;
    final snap = await docRef(id).get();
    if (!snap.exists) return null;
    return _fromDoc(snap);
  }

  Stream<YukLocalDriver?> watchMine(String ownerId) {
    final id = canonicalPhoneId(ownerId);
    if (id.isEmpty) {
      return Stream.value(null);
    }
    return docRef(id).snapshots().map((snap) {
      if (!snap.exists) return null;
      return _fromDoc(snap);
    });
  }

  /// Профил + онлайн + GPS (бир merge).
  Future<void> publishPresence({
    required String ownerId,
    required String ownerName,
    required String phone,
    required String vehicleType,
    required String plateNumber,
    required double capacityTons,
    required double bodyLengthM,
    required double bodyWidthM,
    required double bodyHeightM,
    required int acceptRadiusKm,
    required YukLocalLoadStatus loadStatus,
    required double lat,
    required double lng,
    String locationLabel = '',
  }) async {
    final id = canonicalPhoneId(ownerId);
    if (id.isEmpty) {
      throw StateError('ownerId required');
    }
    final callPhone = phone.trim().isNotEmpty
        ? phone.trim()
        : (id.length >= 12 ? '+$id' : id);
    final ref = docRef(id);
    final existing = await ref.get();
    await ref.set({
      'ownerId': id,
      'ownerName': ownerName.trim(),
      'phone': callPhone,
      'vehicleType': normalizeYukVehicleType(vehicleType),
      'plateNumber': plateNumber.trim().toUpperCase(),
      'capacityTons': capacityTons,
      'bodyLengthM': bodyLengthM,
      'bodyWidthM': bodyWidthM,
      'bodyHeightM': bodyHeightM,
      'acceptRadiusKm': YukAcceptRadius.normalize(acceptRadiusKm),
      'loadStatus': loadStatus.wire,
      'online': true,
      'lat': lat,
      'lng': lng,
      if (locationLabel.trim().isNotEmpty) 'locationLabel': locationLabel.trim(),
      'lastOnlineAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (!existing.exists) ...{
        'rating': 5.0,
        'completedLoads': 0,
      },
    }, SetOptions(merge: true));
  }

  Future<void> heartbeat({
    required String ownerId,
    required double lat,
    required double lng,
    String? locationLabel,
  }) async {
    final id = canonicalPhoneId(ownerId);
    if (id.isEmpty) return;
    await docRef(id).set({
      'online': true,
      'lat': lat,
      'lng': lng,
      if (locationLabel != null && locationLabel.trim().isNotEmpty)
        'locationLabel': locationLabel.trim(),
      'lastOnlineAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setOffline(String ownerId) async {
    final id = canonicalPhoneId(ownerId);
    if (id.isEmpty) return;
    await docRef(id).set({
      'online': false,
      'loadStatus': YukLocalLoadStatus.offline.wire,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateAcceptRadius({
    required String ownerId,
    required int acceptRadiusKm,
  }) async {
    final id = canonicalPhoneId(ownerId);
    if (id.isEmpty) return;
    await docRef(id).set({
      'acceptRadiusKm': YukAcceptRadius.normalize(acceptRadiusKm),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  YukLocalDriver _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return YukLocalDriver.fromFirestore(doc.id, doc.data() ?? {});
  }
}

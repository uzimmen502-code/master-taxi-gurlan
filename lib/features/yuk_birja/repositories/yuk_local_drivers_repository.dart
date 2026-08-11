import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart';
import '../models/yuk_local_driver.dart';
import '../yuk_accept_radius.dart';
import '../yuk_local_schedule.dart';
import '../yuk_vehicle_types.dart';

/// Firestore `yuk_local_drivers/{autoId}` — туман ичида эълонлар.
///
/// Эгалик `ownerId` (каноник телефон). Бир фойдаланувчи бир нечта эълон
/// қўшиши мумкин. Кўриниш: жойлашув + иш вақти + expiresAt (онлайн йўқ).
class YukLocalDriversRepository {
  YukLocalDriversRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const int watchLimit = 200;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('yuk_local_drivers');

  /// Каталог (қидирув) — онлайн фильтрсиз; клиентда иш вақти/TTL/GPS.
  Stream<List<YukLocalDriver>> watchCatalog({int limit = watchLimit}) {
    return _col.limit(limit).snapshots().map(
          (snap) => snap.docs.map(_fromDoc).toList(),
        );
  }

  /// Эски API — [watchCatalog] га йўналтиради.
  @Deprecated('Use watchCatalog')
  Stream<List<YukLocalDriver>> watchOnline({int limit = watchLimit}) =>
      watchCatalog(limit: limit);

  /// Ўз эълонлари — `createdAt` бўйича (янги тепада).
  Stream<List<YukLocalDriver>> watchMine(String ownerId) {
    final id = canonicalPhoneId(ownerId);
    if (id.isEmpty) {
      return Stream.value(const <YukLocalDriver>[]);
    }
    return _col.where('ownerId', isEqualTo: id).snapshots().map((snap) {
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final at = a.data()['createdAt'];
          final bt = b.data()['createdAt'];
          if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
          if (at is Timestamp) return -1;
          if (bt is Timestamp) return 1;
          return a.id.compareTo(b.id);
        });
      return docs.map(_fromDoc).toList();
    });
  }

  DocumentReference<Map<String, dynamic>> _ownerMeta(String ownerId) =>
      _db.collection('yuk_local_owner_meta').doc(ownerId);

  /// Биринчи эълон эдими (ўчирилганлар ҳам ҳисобга — meta).
  Future<bool> _ownerHadListingBefore(String ownerId) async {
    final meta = await _ownerMeta(ownerId).get();
    if (meta.data()?['everPublished'] == true) return true;
    final snap = await _col.where('ownerId', isEqualTo: ownerId).limit(1).get();
    return snap.docs.isNotEmpty;
  }

  /// Яратиш/таҳрир — GPS + иш вақти мажбурий. Онлайн/heartbeat йўқ.
  ///
  /// [docId] бўш → янги эълон. Қайтаради: ҳужжат ID.
  Future<String> publishListing({
    String? docId,
    required String ownerId,
    required String ownerName,
    required String phone,
    required String vehicleType,
    required String plateNumber,
    required double capacityKg,
    required double bodyLengthM,
    required double bodyWidthM,
    required double bodyHeightM,
    required int acceptRadiusKm,
    required YukLocalLoadStatus loadStatus,
    required double lat,
    required double lng,
    required int workStartMinutes,
    required int workEndMinutes,
    String locationLabel = '',
  }) async {
    final id = canonicalPhoneId(ownerId);
    if (id.isEmpty) {
      throw StateError('ownerId required');
    }
    final callPhone = phone.trim().isNotEmpty
        ? phone.trim()
        : (id.length >= 12 ? '+$id' : id);
    final trimmedDocId = (docId ?? '').trim();
    final ref = trimmedDocId.isEmpty ? _col.doc() : _col.doc(trimmedDocId);
    final existing = await ref.get();

    final start = YukLocalSchedule.clampMinutes(workStartMinutes);
    final end = YukLocalSchedule.clampMinutes(workEndMinutes);

    final payload = <String, dynamic>{
      'ownerId': id,
      'ownerName': ownerName.trim(),
      'phone': callPhone,
      'vehicleType': normalizeYukVehicleType(vehicleType),
      'plateNumber': plateNumber.trim().toUpperCase(),
      'capacityKg': capacityKg,
      'capacityTons': FieldValue.delete(),
      'bodyLengthM': bodyLengthM,
      'bodyWidthM': bodyWidthM,
      'bodyHeightM': bodyHeightM,
      'acceptRadiusKm': YukAcceptRadius.normalize(acceptRadiusKm),
      'loadStatus': loadStatus == YukLocalLoadStatus.offline
          ? YukLocalLoadStatus.empty.wire
          : loadStatus.wire,
      'lat': lat,
      'lng': lng,
      if (locationLabel.trim().isNotEmpty) 'locationLabel': locationLabel.trim(),
      'workStartMinutes': start,
      'workEndMinutes': end,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!existing.exists) {
      final hadBefore = await _ownerHadListingBefore(id);
      final ttl = hadBefore
          ? YukLocalSchedule.nextListingTtl
          : YukLocalSchedule.firstListingTtl;
      payload.addAll({
        'rating': 0,
        'completedLoads': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(ttl)),
      });
    } else {
      // Эски онлайн модель қолдиқларини тозалаш.
      payload['online'] = FieldValue.delete();
      payload['lastOnlineAt'] = FieldValue.delete();
    }

    await ref.set(payload, SetOptions(merge: true));
    await _ownerMeta(id).set({
      'everPublished': true,
      'ownerId': id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  /// Эски ном — [publishListing].
  @Deprecated('Use publishListing')
  Future<String> publishPresence({
    String? docId,
    required String ownerId,
    required String ownerName,
    required String phone,
    required String vehicleType,
    required String plateNumber,
    required double capacityKg,
    required double bodyLengthM,
    required double bodyWidthM,
    required double bodyHeightM,
    required int acceptRadiusKm,
    required YukLocalLoadStatus loadStatus,
    required double lat,
    required double lng,
    String locationLabel = '',
    int workStartMinutes = YukLocalSchedule.defaultWorkStartMinutes,
    int workEndMinutes = YukLocalSchedule.defaultWorkEndMinutes,
  }) {
    return publishListing(
      docId: docId,
      ownerId: ownerId,
      ownerName: ownerName,
      phone: phone,
      vehicleType: vehicleType,
      plateNumber: plateNumber,
      capacityKg: capacityKg,
      bodyLengthM: bodyLengthM,
      bodyWidthM: bodyWidthM,
      bodyHeightM: bodyHeightM,
      acceptRadiusKm: acceptRadiusKm,
      loadStatus: loadStatus,
      lat: lat,
      lng: lng,
      locationLabel: locationLabel,
      workStartMinutes: workStartMinutes,
      workEndMinutes: workEndMinutes,
    );
  }

  Future<void> deleteMine(String docId) async {
    if (docId.trim().isEmpty) return;
    await _col.doc(docId).delete();
  }

  Future<void> updateAcceptRadius({
    required String docId,
    required int acceptRadiusKm,
  }) async {
    if (docId.trim().isEmpty) return;
    await _col.doc(docId).set({
      'acceptRadiusKm': YukAcceptRadius.normalize(acceptRadiusKm),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  YukLocalDriver _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return YukLocalDriver.fromFirestore(doc.id, doc.data() ?? {});
  }
}

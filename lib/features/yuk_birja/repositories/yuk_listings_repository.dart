import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/yuk_listing.dart';
import '../yuk_vehicle_types.dart';

/// Firestore `yuk_listings` — умумий юк биржаси.
class YukListingsRepository {
  YukListingsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('yuk_listings');

  Stream<List<YukListing>> watchActive({int limit = 200}) {
    return _col
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).toList());
  }

  Future<String> create(YukListing item) async {
    final ref = _col.doc();
    final now = DateTime.now();
    final createdAt = item.createdAt;
    final expiresAt = item.expiresAt.isAfter(createdAt)
        ? item.expiresAt
        : createdAt.add(YukListing.ttl);
    await ref.set({
      'type': item.type.name,
      'from': item.from,
      'to': item.to,
      'stops': item.stops,
      'vehicleType': normalizeYukVehicleType(item.vehicleType),
      'ownerId': item.ownerId,
      'ownerName': item.ownerName,
      'phone': item.phone,
      'status': 'active',
      'cargo': item.cargo,
      'weight': item.weight,
      'capacity': item.capacity,
      'freeSpace': item.freeSpace,
      'price': item.price,
      'comment': item.comment,
      'stars': item.stars,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.fromDate(now),
    });
    return ref.id;
  }

  Future<void> update(YukListing item) async {
    if (item.id.isEmpty) return;
    await _col.doc(item.id).update({
      'from': item.from,
      'to': item.to,
      'stops': item.stops,
      'vehicleType': normalizeYukVehicleType(item.vehicleType),
      'cargo': item.cargo,
      'weight': item.weight,
      'capacity': item.capacity,
      'freeSpace': item.freeSpace,
      'price': item.price,
      'comment': item.comment,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> close(String id) async {
    if (id.isEmpty) return;
    await _col.doc(id).update({
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  YukListing _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final j = doc.data() ?? {};
    return YukListing.fromFirestore(doc.id, j);
  }
}

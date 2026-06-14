import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/delivery_route.dart';

/// `delivery_routes` collection — kuryer reysi.
class DeliveryRoutesRepository {
  DeliveryRoutesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('delivery_routes');

  /// Kuryerning aktiv reysi (bor bo'lsa).
  Future<DeliveryRoute?> getActiveForCourier(String courierId) async {
    if (courierId.isEmpty) return null;
    final snap = await _col
        .where('courierId', isEqualTo: courierId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return DeliveryRoute.fromDoc(snap.docs.first);
  }

  /// Hech kim olmagan navbatdagi `ready` reys (preview uchun).
  Future<DeliveryRoute?> getNextReady() async {
    final snap = await _col.where('status', isEqualTo: 'ready').limit(1).get();
    if (snap.docs.isEmpty) return null;
    return DeliveryRoute.fromDoc(snap.docs.first);
  }

  /// `ready → active` — atomic transaction: race condition himoyasi.
  /// Qaytish: `true` muvaffaqiyatli, `false` — reys allaqachon band yoki yo'q.
  Future<bool> startRoute({
    required String routeId,
    required String courierId,
  }) async {
    if (routeId.isEmpty) return false;
    try {
      return await _db.runTransaction<bool>((tx) async {
        final ref = _col.doc(routeId);
        final snap = await tx.get(ref);
        if (!snap.exists) return false;

        final currentStatus = (snap.data()?['status'] ?? '') as String;
        if (currentStatus != 'ready') {
          return false;
        }

        tx.update(ref, {
          'status': 'active',
          'courierId': courierId,
          'startedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  Future<void> advanceIndex(String routeId, int nextIndex) async {
    if (routeId.isEmpty) return;
    await _col.doc(routeId).update({'currentIndex': nextIndex});
  }

  Future<void> completeRoute(String routeId) async {
    if (routeId.isEmpty) return;
    await _col.doc(routeId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Barcha aktiv va tayyor reyslar real-time stream.
  Stream<List<DeliveryRoute>> watchActiveRoutes() {
    return _col
        .where('status', whereIn: ['ready', 'active'])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(DeliveryRoute.fromDoc).toList());
  }

  /// Kuryerning aktiv yoki ready reysini real-time tinglash.
  Stream<DeliveryRoute?> watchActiveForCourier(String courierId) {
    if (courierId.isEmpty) return Stream.value(null);
    return _col
        .where('courierId', isEqualTo: courierId)
        .where('status', whereIn: ['active', 'ready'])
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          return DeliveryRoute.fromDoc(snap.docs.first);
        });
  }
}

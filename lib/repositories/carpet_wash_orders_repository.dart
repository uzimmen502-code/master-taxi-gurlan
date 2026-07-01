import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/carpet_wash_order.dart';

/// `carpet_wash_orders` — gilam yuvish buyurtmalari.
class CarpetWashOrdersRepository {
  CarpetWashOrdersRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('carpet_wash_orders');

  Stream<List<CarpetWashOrder>> watchForCustomer(String customerPhone) {
    final phone = phoneDigits(customerPhone);
    if (phone.length < 9) return Stream.value(const []);
    return _col
        .where('customerPhone', isEqualTo: phone)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map(_mapSnapshot);
  }

  Stream<List<CarpetWashOrder>> watchAll({int limit = 100}) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(_mapSnapshot);
  }

  Stream<List<CarpetWashOrder>> watchByStatus(String status, {int limit = 50}) {
    return _col
        .where('status', isEqualTo: status)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(_mapSnapshot);
  }

  Future<CarpetWashOrder?> getById(String id) async {
    if (id.isEmpty) return null;
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return CarpetWashOrder.fromDoc(snap);
  }

  List<CarpetWashOrder> _mapSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    return snap.docs.map(CarpetWashOrder.fromDoc).toList(growable: false);
  }
}

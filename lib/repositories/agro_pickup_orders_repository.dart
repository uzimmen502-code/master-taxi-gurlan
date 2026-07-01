import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/agro_pickup_order.dart';

/// `agro_pickup_orders` — sut va boshqa agro qabul buyurtmalari.
class AgroPickupOrdersRepository {
  AgroPickupOrdersRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('agro_pickup_orders');

  Stream<List<AgroPickupOrder>> watchForCustomer(String customerPhone) {
    final phone = phoneDigits(customerPhone);
    if (phone.length < 9) return Stream.value(const []);
    return _col
        .where('customerPhone', isEqualTo: phone)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map(_mapSnapshot);
  }

  Stream<List<AgroPickupOrder>> watchAll({int limit = 100}) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(_mapSnapshot);
  }

  Stream<List<AgroPickupOrder>> watchByProductType(
    String productType, {
    int limit = 100,
  }) {
    return _col
        .where('productType', isEqualTo: productType)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(_mapSnapshot);
  }

  Stream<List<AgroPickupOrder>> watchByStatus(String status, {int limit = 50}) {
    return _col
        .where('status', isEqualTo: status)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(_mapSnapshot);
  }

  Future<AgroPickupOrder?> getById(String id) async {
    if (id.isEmpty) return null;
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return AgroPickupOrder.fromDoc(snap);
  }

  List<AgroPickupOrder> _mapSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    return snap.docs.map(AgroPickupOrder.fromDoc).toList(growable: false);
  }
}

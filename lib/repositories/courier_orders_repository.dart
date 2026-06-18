import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/courier_order.dart';

/// `courier_orders` — kuryer buyurtmalari (sotib olish / yetkazish).
class CourierOrdersRepository {
  CourierOrdersRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _courierActiveStatuses = ['accepted', 'picked_up'];

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('courier_orders');

  Stream<List<CourierOrder>> watchPending() {
    return _col
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(_mapSnapshot);
  }

  Stream<List<CourierOrder>> watchForCourier(String courierUid) {
    final uid = phoneDigits(courierUid);
    if (uid.length < 9) return Stream.value(const []);
    return _col
        .where('courierId', isEqualTo: uid)
        .where('status', whereIn: _courierActiveStatuses)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_mapSnapshot);
  }

  Stream<List<CourierOrder>> watchForCustomer(String customerPhone) {
    final phone = phoneDigits(customerPhone);
    if (phone.length < 9) return Stream.value(const []);
    return _col
        .where('customerPhone', isEqualTo: phone)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map(_mapSnapshot);
  }

  Stream<List<CourierOrder>> watchAll() {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(_mapSnapshot);
  }

  List<CourierOrder> _mapSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    return snap.docs.map(CourierOrder.fromDoc).toList(growable: false);
  }

  Future<String> create(CourierOrder order) async {
    final ref = order.id.isNotEmpty ? _col.doc(order.id) : _col.doc();
    await ref.set(order.toCreateMap());
    return ref.id;
  }

  Future<void> acceptOrder({
    required String id,
    required String courierId,
    required String courierName,
    required int totalPrice,
  }) async {
    if (id.isEmpty) return;
    await _col.doc(id).update({
      'courierId': phoneDigits(courierId),
      'courierName': courierName.trim(),
      'totalPrice': totalPrice,
      'status': CourierOrder.statusToFirestore(CourierOrderStatus.accepted),
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markPickedUp(String id) async {
    if (id.isEmpty) return;
    await _col.doc(id).update({
      'status': CourierOrder.statusToFirestore(CourierOrderStatus.pickedUp),
    });
  }

  Future<void> markDelivered(String id) async {
    if (id.isEmpty) return;
    await _col.doc(id).update({
      'status': CourierOrder.statusToFirestore(CourierOrderStatus.delivered),
      'deliveredAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelOrder(String id) async {
    if (id.isEmpty) return;
    await _col.doc(id).update({
      'status': CourierOrder.statusToFirestore(CourierOrderStatus.cancelled),
    });
  }
}

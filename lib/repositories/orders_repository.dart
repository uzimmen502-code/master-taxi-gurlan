import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/order_model.dart';

/// `orders` collection (non + ovqat buyurtmalari).
class OrdersRepository {
  OrdersRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('orders');

  /// Foydalanuvchining oxirgi buyurtmalari. Telefon turli formatda yozilishi
  /// mumkin bo'lgani uchun aliaslar bo'yicha qidiramiz.
  Future<List<OrderModel>> recentByUser(
    List<String> phoneAliases, {
    int limit = 20,
  }) async {
    if (phoneAliases.isEmpty) return const [];
    final snap = await _col
        .where('userPhone', whereIn: phoneAliases)
        .limit(limit)
        .get();
    final list = snap.docs.map(OrderModel.fromDoc).toList();
    list.sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return list;
  }

  /// Bir martalik buyurtma o'qish (kuryer flow yoki detail screen uchun).
  Future<OrderModel?> getById(String id) async {
    if (id.isEmpty) return null;
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return OrderModel.fromDoc(snap);
  }

  /// Bir nechta buyurtmani parallel o'qish — kuryer marshrutidagi tartiblanган
  /// orderIds bo'yicha. Topilmaganlari o'tkazib yuboriladi.
  Future<List<OrderModel>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final snaps = await Future.wait(ids.map((id) => _col.doc(id).get()));
    return [
      for (final s in snaps)
        if (s.exists) OrderModel.fromDoc(s),
    ];
  }

  /// Kuryer buyurtmani yetkazganini belgilash.
  Future<void> markDelivered({
    required String orderId,
    required String courierId,
  }) async {
    if (orderId.isEmpty) return;
    await _col.doc(orderId).update({
      'status': 'delivered',
      'deliveredAt': FieldValue.serverTimestamp(),
      'courierId': courierId,
    });
  }

  /// Овқат buyurtmasi yaratish — `type:'food'`. Xato yuz bersa
  /// [FirebaseException] qaytaradi, caller tomonda catch qilinadi.
  Future<void> createFoodOrder({
    required String userName,
    required String userPhone,
    required String address,
    required String phone,
    required List<Map<String, dynamic>> items,
    required int total,
  }) async {
    await _col.add({
      'type': 'food',
      'userName': userName,
      'userPhone': userPhone,
      'address': address,
      'phone': phone,
      'items': items,
      'total': total,
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Нон buyurtmasi yaratish. Tayyor map қабул қилинади — pricing/extras
  /// caller тарафда йиғилади. Reference қайтарилади (id кейинги
  /// `BalanceService` чақириқлари учун керак).
  Future<DocumentReference<Map<String, dynamic>>> createBreadOrder(
      Map<String, dynamic> data) async {
    return _col.add(data);
  }

  /// Админ навбати: охирги buyurtmalar (`createdAt` бўйича). Индекс — фақат
  /// `createdAt` (Firestore default single-field).
  Stream<List<OrderModel>> watchRecentOrders({int limit = 100}) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(OrderModel.fromDoc).toList());
  }

  /// Буюртма `status`ини ўзгартириш (админ ёки рухсатли client).
  Future<void> setOrderStatus(String orderId, String status) async {
    if (orderId.isEmpty) return;
    await _col.doc(orderId).update({'status': status});
  }

  /// Bir foydalanuvchining oxirgi buyurtmalari (telefon raqami bo'yicha).
  /// `recentByUser` дан фарқли — бу йерда индексланган `orderBy` ишлатилади.
  Future<List<OrderModel>> recentByPhone(
    String phone, {
    int limit = 20,
  }) async {
    if (phone.isEmpty) return const [];
    final snap = await _col
        .where('userPhone', isEqualTo: phone)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(OrderModel.fromDoc).toList(growable: false);
  }

  /// Жараёнда муваффақиятсизлик бўлганда оrder ҳужжатини ўчириш (atomicity).
  Future<void> deleteOrderRef(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      await ref.delete();
    } catch (_) {}
  }
}

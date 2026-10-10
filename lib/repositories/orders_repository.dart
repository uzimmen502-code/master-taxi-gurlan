import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/service_config_holder.dart';
import '../models/order_model.dart';

/// `orders` collection (non, ulgurji, kafe-restoran buyurtmalari).
///
/// Олиб ташланган «Овқат» буюртмалари (`type:'food'`) рўйхатлардан шу ерда
/// чиқарилади — [OrderModel.isRemovedFoodOrder].
class OrdersRepository {
  OrdersRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('orders');

  DocumentReference<Map<String, dynamic>> get _appSettings =>
      _db.collection('settings').doc('app');

  static List<OrderModel> _visible(
          Iterable<DocumentSnapshot<Map<String, dynamic>>> docs) =>
      docs
          .map(OrderModel.fromDoc)
          .where((o) => !o.isRemovedFoodOrder)
          .toList();

  /// Foydalanuvchining oxirgi buyurtmalari. Telefon turli formatda yozilishi
  /// mumkin bo'lgani uchun aliaslar bo'yicha qidiramiz.
  Future<List<OrderModel>> recentByUser(
    List<String> phoneAliases, {
    int limit = 20,
  }) async {
    if (phoneAliases.isEmpty) return const [];
    final snap =
        await _col.where('userPhone', whereIn: phoneAliases).limit(limit).get();
    final list = _visible(snap.docs);
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

  /// Foydalanuvchi buyurtmalarini real-vaqtda kuzatish (Buyurtmalar ekrani).
  /// Telefon aliaslari bo'yicha, eng yangi birinchi.
  Stream<List<OrderModel>> watchByUser(
    List<String> phoneAliases, {
    int limit = 50,
  }) {
    if (phoneAliases.isEmpty) {
      return Stream.value(const <OrderModel>[]);
    }
    return _col
        .where('userPhone', whereIn: phoneAliases)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = _visible(snap.docs);
      list.sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return list;
    });
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

  /// Нон buyurtmasi yaratish. Tayyor map қабул қилинади — pricing/extras
  /// caller тарафда йиғилади. Reference қайтарилади (id кейинги
  /// `BalanceService` чақириқлари учун керак).
  /// Direct write — use only for admin/test purposes.
  Future<DocumentReference<Map<String, dynamic>>> createBreadOrder(
      Map<String, dynamic> data) async {
    return _col.add({...data, ...ServiceConfigHolder.reportStamp()});
  }

  /// Админ навбати: охирги buyurtmalar (`createdAt` бўйича). Индекс — фақат
  /// `createdAt` (Firestore default single-field).
  Stream<List<OrderModel>> watchRecentOrders({int limit = 100}) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => _visible(s.docs));
  }

  /// Админ курьер доскаси: `ready` статусдаги барча буюртмалар (тўлиқ ҳужжат).
  /// Фақат staff учун — `orders` қоидаси курьерга бу рўйхатни бермайди;
  /// курьер иловаси `CourierRouteService.listReadyOrders`ни ишлатади.
  Stream<List<OrderModel>> watchReadyOrders() {
    return _col
        .where('status', isEqualTo: 'ready')
        .snapshots()
        .map((snap) {
          final list = _visible(snap.docs);
          list.sort((a, b) {
            final ta = a.createdAt;
            final tb = b.createdAt;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
          return list;
        });
  }

  /// Буюртма `status`ини ўзгартириш (админ ёки рухсатли client).
  Future<void> setOrderStatus(String orderId, String status) async {
    if (orderId.isEmpty) return;
    await _col.doc(orderId).update(_statusPatch(status));
  }

  /// Бир неchta buyurtma statusini bir vaqtda (admin ustun tugmasi).
  Future<void> setOrderStatusBatch(List<String> orderIds, String status) async {
    final ids = orderIds.where((id) => id.isNotEmpty).toList(growable: false);
    if (ids.isEmpty) return;
    const chunkSize = 450;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final batch = _db.batch();
      final end = math.min(i + chunkSize, ids.length);
      for (var j = i; j < end; j++) {
        batch.update(_col.doc(ids[j]), _statusPatch(status));
      }
      await batch.commit();
    }
  }

  Map<String, dynamic> _statusPatch(String status) {
    final data = <String, dynamic>{
      'status': status,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    };
    final fs = _legacyStatusToFulfillment(status);
    if (fs != null) {
      data['fulfillmentStatus'] = fs;
    }
    if (status == 'in_delivery') {
      data['inDeliveryAt'] = FieldValue.serverTimestamp();
      data['fulfillmentStatus'] = 'courier_picked';
    }
    if (status == 'delivered') {
      data['deliveredAt'] = FieldValue.serverTimestamp();
      data['fulfillmentStatus'] = 'completed';
      data['paymentStatus'] = 'paid';
    }
    if (status == 'rejected') {
      data['rejectedAt'] = FieldValue.serverTimestamp();
      data['fulfillmentStatus'] = 'cancelled';
    }
    if (status == 'accepted' || status == 'ready') {
      data['fulfillmentStatus'] = 'confirmed';
      if (status == 'accepted') {
        data['confirmedAt'] = FieldValue.serverTimestamp();
      }
    }
    if (status == 'new') {
      data['fulfillmentStatus'] = 'pending';
    }
    return data;
  }

  static String? _legacyStatusToFulfillment(String status) {
    switch (status) {
      case 'new':
        return 'pending';
      case 'accepted':
      case 'ready':
        return 'confirmed';
      case 'in_delivery':
        return 'courier_picked';
      case 'delivered':
        return 'completed';
      case 'rejected':
      case 'cancelled':
        return 'cancelled';
      default:
        return null;
    }
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
    return List.unmodifiable(_visible(snap.docs));
  }

  /// Жараёнда муваффақиятсизлик бўлганда оrder ҳужжатини ўчириш (atomicity).
  Future<void> deleteOrderRef(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      await ref.delete();
    } catch (_) {}
  }

  /// `auto` — янги буюртма автомат «Қабул». `manual` — админ қўлда.
  Stream<String> watchOrderAcceptMode() {
    return _appSettings.snapshots().map((snap) {
      final mode = snap.data()?['orderAcceptMode'] as String? ?? 'manual';
      return mode == 'auto' ? 'auto' : 'manual';
    });
  }

  /// `auto` — қабулдан кейин автомат «Тайёр». `manual` — админ қўлда.
  Stream<String> watchOrderReadyMode() {
    return _appSettings.snapshots().map((snap) {
      final mode = snap.data()?['orderReadyMode'] as String? ?? 'manual';
      return mode == 'auto' ? 'auto' : 'manual';
    });
  }

  Stream<OrderFlowModes> watchOrderFlowModes() {
    return _appSettings.snapshots().map((snap) {
      final d = snap.data();
      String norm(String? v) => v == 'auto' ? 'auto' : 'manual';
      return OrderFlowModes(
        accept: norm(d?['orderAcceptMode'] as String?),
        ready: norm(d?['orderReadyMode'] as String?),
      );
    });
  }

  Future<void> setOrderAcceptMode(String mode) async {
    final v = mode == 'auto' ? 'auto' : 'manual';
    await _appSettings.set({
      'orderAcceptMode': v,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setOrderReadyMode(String mode) async {
    final v = mode == 'auto' ? 'auto' : 'manual';
    await _appSettings.set({
      'orderReadyMode': v,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Админ тарихи: шу санадан олдин яратилган якунланган буюртмалар
  /// админ устунларида кўрсатилмайди (базадан ўчирилмайди).
  /// `null` — чегара йўқ, ҳаммаси кўринади.
  Stream<DateTime?> watchAdminOrderHistoryFrom() {
    return _appSettings.snapshots().map((snap) {
      final v = snap.data()?['adminOrderHistoryFrom'];
      return v is Timestamp ? v.toDate() : null;
    });
  }

  Future<void> setAdminOrderHistoryFrom(DateTime? from) async {
    await _appSettings.set({
      'adminOrderHistoryFrom':
          from == null ? FieldValue.delete() : Timestamp.fromDate(from),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// Буюртма Kanban: қабул / тайёр автомат ёки қўлда.
class OrderFlowModes {
  const OrderFlowModes({this.accept = 'manual', this.ready = 'manual'});

  final String accept;
  final String ready;

  bool get acceptAuto => accept == 'auto';
  bool get readyAuto => ready == 'auto';
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// `marshrut_route_prices/{from|to}` — yo'nalish bo'yicha flat narx (bir o'rin).
///
/// Yozish faqat CF orqali (birinchi haydovchi seed / admin tahrir). Bu
/// repository faqat O'QIYDI: haydovchi onlayn ekrani (narx bormi?) va admin
/// ro'yxati uchun.
class MarshrutRoutePriceRepository {
  MarshrutRoutePriceRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('marshrut_route_prices');

  static String routeKey(String from, String to) =>
      '${from.trim()}|${to.trim()}';

  /// Yo'nalish narxi (so'm/o'rin) yoki `null` (hali belgilanmagan).
  Future<int?> getPrice(String from, String to) async {
    final snap = await _col.doc(routeKey(from, to)).get();
    if (!snap.exists) return null;
    final p = (snap.data()?['price'] as num?)?.toInt() ?? 0;
    return p > 0 ? p : null;
  }

  Stream<int?> watchPrice(String from, String to) {
    return _col.doc(routeKey(from, to)).snapshots().map((snap) {
      if (!snap.exists) return null;
      final p = (snap.data()?['price'] as num?)?.toInt() ?? 0;
      return p > 0 ? p : null;
    });
  }

  /// Admin ro'yxati uchun — barcha belgilangan yo'nalish narxlari.
  Stream<List<MarshrutRoutePrice>> watchAll() {
    return _col.snapshots().map((snap) =>
        snap.docs.map(MarshrutRoutePrice.fromDoc).toList(growable: false));
  }
}

class MarshrutRoutePrice {
  const MarshrutRoutePrice({
    required this.routeKey,
    required this.from,
    required this.to,
    required this.price,
    this.setByName = '',
    this.lockedByAdmin = false,
  });

  final String routeKey;
  final String from;
  final String to;
  final int price;
  final String setByName;
  final bool lockedByAdmin;

  factory MarshrutRoutePrice.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return MarshrutRoutePrice(
      routeKey: doc.id,
      from: (d['from'] ?? '') as String,
      to: (d['to'] ?? '') as String,
      price: (d['price'] as num?)?.toInt() ?? 0,
      setByName: (d['setByName'] ?? '') as String,
      lockedByAdmin: (d['lockedByAdmin'] ?? false) as bool,
    );
  }
}

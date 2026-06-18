import 'package:cloud_firestore/cloud_firestore.dart';

/// `settings/*` — ilova sozlamalari.
class SettingsRepository {
  SettingsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const int defaultCourierDeliveryFee = 5000;

  DocumentReference<Map<String, dynamic>> get _courierSettings =>
      _db.collection('settings').doc('courier');

  /// Yetkazish narxi — `settings/courier.deliveryFee` (default 5000).
  Future<int> getCourierDeliveryFee() async {
    try {
      final snap = await _courierSettings.get();
      final fee = (snap.data()?['deliveryFee'] as num?)?.toInt();
      if (fee != null && fee >= 0) return fee;
    } catch (_) {}
    return defaultCourierDeliveryFee;
  }

  /// Admin: yetkazish narxini yangilash.
  Future<void> setCourierDeliveryFee(int fee) async {
    if (fee < 0) {
      throw ArgumentError('deliveryFee manfiy bo\'lishi mumkin emas');
    }
    await _courierSettings.set({
      'deliveryFee': fee,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

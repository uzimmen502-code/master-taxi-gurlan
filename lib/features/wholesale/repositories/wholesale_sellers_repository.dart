import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart';
import '../models/wholesale_seller.dart';

/// `wholesale_sellers/{phone}` — Cloud Function йўқ, ҳаммаси Firestore Rules
/// орқали чекланади: эга фақат `pending` ҳолатда яратади, admin эса фақат
/// `approvalStatus`/`approvedAt`/`approvedBy`/`adminNote`ни ўзгартиради
/// (`firestore.rules`даги `wholesaleSellerApprovalPatchOnly()`).
class WholesaleSellersRepository {
  WholesaleSellersRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('wholesale_sellers');

  DocumentReference<Map<String, dynamic>> get _appSettings =>
      _db.collection('settings').doc('app');

  /// `settings/app.wholesaleSellerAutoApprove` — admin ёққан/ўчирган
  /// ҚЎЛДА/АВТО тасдиқ ҳолати.
  Future<bool> isAutoApproveOn() async {
    try {
      final snap = await _appSettings.get();
      return snap.data()?['wholesaleSellerAutoApprove'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Рўйхатдан ўтиш — фақат телефон + компания номи (MVP). Аллақачон
  /// мавжуд бўлса (қайта уриниш) — устидан ёзмайди, ҳозирги ҳолатни олади.
  Future<WholesaleSeller> register({
    required String phone,
    required String companyName,
    String ownerName = '',
    String sellerType = '',
  }) async {
    final id = canonicalPhoneId(phone);
    final ref = _col.doc(id);
    final existing = await ref.get();
    if (existing.exists) {
      return WholesaleSeller.fromFirestore(existing);
    }
    final autoApproved = await isAutoApproveOn();
    final seller = WholesaleSeller(
      phone: id,
      companyName: companyName.trim(),
      ownerName: ownerName.trim(),
      sellerType: sellerType,
    );
    await ref.set(seller.toFirestoreCreate(autoApproved: autoApproved));
    final saved = await ref.get();
    return WholesaleSeller.fromFirestore(saved);
  }

  Future<WholesaleSeller?> fetchByPhone(String phone) async {
    final id = canonicalPhoneId(phone);
    if (id.isEmpty) return null;
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return WholesaleSeller.fromFirestore(snap);
  }

  /// Ўз ҳолатини кузатиш (рўйхатдан ўтиш экрани — pending/approved/rejected).
  Stream<WholesaleSeller?> watchByPhone(String phone) {
    final id = canonicalPhoneId(phone);
    if (id.isEmpty) return Stream.value(null);
    return _col.doc(id).snapshots().map(
          (snap) => snap.exists ? WholesaleSeller.fromFirestore(snap) : null,
        );
  }

  /// Admin — тасдиқлаш кутаётганлар рўйхати.
  Stream<List<WholesaleSeller>> watchPendingForAdmin() {
    return _col
        .where('approvalStatus', isEqualTo: WholesaleSeller.statusPending)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(WholesaleSeller.fromFirestore).toList();
      list.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return list;
    });
  }

  /// Admin — барча сотувчилар (модерация экрани учун, лимит 500).
  Stream<List<WholesaleSeller>> watchAllForAdmin({int limit = 500}) {
    return _col.limit(limit).snapshots().map((snap) {
      final list = snap.docs.map(WholesaleSeller.fromFirestore).toList();
      list.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return list;
    });
  }

  /// Admin — тасдиқлаш.
  Future<void> approve(String phone, {required String adminId}) async {
    final id = canonicalPhoneId(phone);
    await _col.doc(id).update({
      'approvalStatus': WholesaleSeller.statusApproved,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': adminId,
    });
  }

  /// Admin — рад этиш (изоҳ билан).
  Future<void> reject(
    String phone, {
    required String adminId,
    String note = '',
  }) async {
    final id = canonicalPhoneId(phone);
    await _col.doc(id).update({
      'approvalStatus': WholesaleSeller.statusRejected,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': adminId,
      'adminNote': note,
    });
  }
}

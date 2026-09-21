import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/formatters.dart';
import '../models/wholesale_product.dart';

/// `wholesale_products/{id}` — Cloud Function йўқ, Firestore Rules орқали:
/// эга фақат `pending` ҳолатда яратади/қайтаради, admin эса
/// `status`/`adminNote`/`moderatedAt`/`moderatedBy`/`publishedAt`ни
/// ўзгартиради (`firestore.rules`даги `wholesaleProductAdminPatchOnly()`).
/// Яратишда сотувчи `wholesale_sellers`да `approved` бўлиши шарт (Rules
/// `get()` орқали текширади).
class WholesaleProductsRepository {
  WholesaleProductsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const feedLimit = 200;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('wholesale_products');

  DocumentReference<Map<String, dynamic>> get _appSettings =>
      _db.collection('settings').doc('app');

  /// `settings/app.wholesaleProductAutoApprove` — admin ёққан/ўчирган
  /// ҚЎЛДА/АВТО тасдиқ ҳолати.
  Future<bool> isAutoApproveOn() async {
    try {
      final snap = await _appSettings.get();
      return snap.data()?['wholesaleProductAutoApprove'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String> create(WholesaleProduct product) async {
    final autoApproved = await isAutoApproveOn();
    final ref =
        await _col.add(product.toFirestoreCreate(autoApproved: autoApproved));
    return ref.id;
  }

  Future<WholesaleProduct?> fetchById(String productId) async {
    if (productId.isEmpty) return null;
    final snap = await _col.doc(productId).get();
    if (!snap.exists) return null;
    return WholesaleProduct.fromFirestore(snap);
  }

  Future<void> ownerUpdate(String productId, WholesaleProduct product) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update(product.toFirestoreOwnerUpdate());
  }

  Future<void> deactivate(String productId) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update({
      'status': WholesaleProduct.statusInactive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String productId) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).delete();
  }

  Future<void> incrementViews(String productId) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update({'views': FieldValue.increment(1)});
  }

  /// Видеообзор/пуллик реклама клипини маҳсулотга боғлаш —
  /// `TvShopRepository.addClipToItem` андозаси.
  Future<void> addVideoClip(String productId, String clipId) async {
    if (productId.isEmpty || clipId.isEmpty) return;
    await _col.doc(productId).update({
      'videoClipIds': FieldValue.arrayUnion([clipId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeVideoClip(String productId, String clipId) async {
    if (productId.isEmpty || clipId.isEmpty) return;
    await _col.doc(productId).update({
      'videoClipIds': FieldValue.arrayRemove([clipId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Умумий бозор — фаол маҳсулотлар.
  Stream<List<WholesaleProduct>> getActiveProducts({int limit = feedLimit}) {
    return _col
        .where('status', isEqualTo: WholesaleProduct.statusActive)
        .orderBy('publishedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(WholesaleProduct.fromFirestore).toList());
  }

  /// Фаол маҳсулотлар — қидирув (кирилл↔лотин, `CatalogSearch`).
  Stream<List<WholesaleProduct>> searchActiveProducts(
    String query, {
    int limit = 100,
  }) {
    final q = query.trim();
    final poolLimit = q.isEmpty ? limit : feedLimit;
    return getActiveProducts(limit: poolLimit).map((items) {
      final filtered = items.where((p) {
        return CatalogSearch.matches(q, [
          p.title,
          p.description,
          p.sellerCompanyName,
          '${p.basePrice}',
          ...p.searchTokens,
        ]);
      }).toList();
      if (filtered.length > limit) return filtered.sublist(0, limit);
      return filtered;
    });
  }

  /// Сотувчининг ўз маҳсулотлари (ҳар қандай статус).
  Stream<List<WholesaleProduct>> watchBySeller(String sellerPhone) {
    final id = canonicalPhoneId(sellerPhone);
    if (id.isEmpty) return Stream.value(const []);
    return _col.where('sellerId', isEqualTo: id).snapshots().map((snap) {
      final list = snap.docs.map(WholesaleProduct.fromFirestore).toList();
      list.sort((a, b) {
        final at = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return list;
    });
  }

  /// Admin — барча маҳсулотлар (лимит 500).
  Stream<List<WholesaleProduct>> watchAllForAdmin({int limit = 500}) {
    return _col.limit(limit).snapshots().map((snap) {
      final list = snap.docs.map(WholesaleProduct.fromFirestore).toList();
      list.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return list;
    });
  }

  /// Admin — фаоллаштириш.
  Future<void> approve(String productId, {required String adminId}) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update({
      'status': WholesaleProduct.statusActive,
      'publishedAt': FieldValue.serverTimestamp(),
      'moderatedAt': FieldValue.serverTimestamp(),
      'moderatedBy': adminId,
    });
  }

  /// Admin — рад этиш/ёпиш (изоҳ билан).
  Future<void> reject(
    String productId, {
    required String adminId,
    String note = '',
  }) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update({
      'status': WholesaleProduct.statusInactive,
      'adminNote': note,
      'moderatedAt': FieldValue.serverTimestamp(),
      'moderatedBy': adminId,
    });
  }
}

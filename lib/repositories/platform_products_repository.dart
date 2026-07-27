import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/platform_product.dart';

/// `platform_products` — платформа дўкони каталоги.
class PlatformProductsRepository {
  PlatformProductsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('platform_products');

  /// Фаол товарлар (дўкон / витрина).
  Stream<List<PlatformProduct>> watchActive({int limit = 200}) {
    return _col
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map(PlatformProduct.fromFirestore)
            .toList(growable: false));
  }

  /// Админ: барча товарлар.
  Stream<List<PlatformProduct>> watchAll({int limit = 500}) {
    return _col
        .orderBy('sortOrder')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map(PlatformProduct.fromFirestore)
            .toList(growable: false));
  }

  Future<List<PlatformProduct>> fetchActive({int limit = 200}) async {
    final snap = await _col
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .limit(limit)
        .get();
    return snap.docs
        .map(PlatformProduct.fromFirestore)
        .toList(growable: false);
  }

  /// Уй «Тавсия этамиз» учун.
  /// АВТО (`platformFeaturedAuto`): барча фаол/бор товарлар.
  /// ҚЎЛДА: фақат `featuredOnHome == true`.
  Future<List<PlatformProduct>> fetchForHomeFeatured({int take = 2}) async {
    final settings = await _db.collection('settings').doc('app').get();
    // Default АВТО — витрина бўш қолмасин.
    final auto = settings.data()?['platformFeaturedAuto'] != false;
    final all = await fetchActive(limit: 48);
    final eligible = all.where((p) => p.price > 0 && p.inStock);
    if (auto) {
      return eligible.take(take).toList(growable: false);
    }
    return eligible
        .where((p) => p.featuredOnHome)
        .take(take)
        .toList(growable: false);
  }

  /// Онлайн бозор лентаси учун.
  Future<List<PlatformProduct>> fetchForMarket({int limit = 40}) async {
    final all = await fetchActive(limit: limit * 2);
    return all
        .where((p) => p.showInMarket && p.price > 0)
        .take(limit)
        .toList(growable: false);
  }

  Future<PlatformProduct?> getById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return PlatformProduct.fromFirestore(doc);
  }

  Future<String> create(PlatformProduct product) async {
    final ref = _col.doc();
    await ref.set(product.toFirestoreCreate());
    return ref.id;
  }

  Future<void> update(PlatformProduct product) async {
    await _col.doc(product.id).update(product.toFirestoreUpdate());
  }

  Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }

  Future<void> setActive(String id, bool active) async {
    await _col.doc(id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

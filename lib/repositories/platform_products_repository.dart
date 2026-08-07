import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/platform_product.dart';

/// `platform_products` — платформа дўкони каталоги.
class PlatformProductsRepository {
  PlatformProductsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('platform_products');

  static const catalogLimit = 2000;

  List<PlatformProduct> _sorted(Iterable<PlatformProduct> raw) {
    final list = raw.toList();
    list.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      final byTime = at.compareTo(bt);
      if (byTime != 0) return byTime;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// Кейинги тартиб рақами (рўйхат охирига қўшиш).
  Future<int> nextSortOrder() async {
    try {
      final snap = await _col
          .orderBy('sortOrder', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return 1;
      final max = (snap.docs.first.data()['sortOrder'] as num?)?.toInt() ?? 0;
      return max < 0 ? 1 : max + 1;
    } catch (_) {
      // Индекс/бўш коллекция — каталогдан максимум.
      final all = await _col.limit(catalogLimit).get();
      var max = 0;
      for (final d in all.docs) {
        final v = (d.data()['sortOrder'] as num?)?.toInt() ?? 0;
        if (v > max) max = v;
      }
      return max + 1;
    }
  }

  /// Мижоз каталоги: барча маҳсулотлар (active/stock/price чекловсиз).
  Stream<List<PlatformProduct>> watchCatalog({int limit = catalogLimit}) {
    return _col.limit(limit).snapshots().map(
          (snap) => _sorted(snap.docs.map(PlatformProduct.fromFirestore)),
        );
  }

  /// Мижоз каталоги: барча маҳсулотлар (active/stock/price чекловсиз).
  Future<List<PlatformProduct>> fetchCatalog({int limit = catalogLimit}) async {
    final snap = await _col.limit(limit).get();
    return _sorted(snap.docs.map(PlatformProduct.fromFirestore));
  }

  /// Фаол товарлар (дўкон / витрина) — legacy; янги код `fetchCatalog` ишлатсин.
  Stream<List<PlatformProduct>> watchActive({int limit = catalogLimit}) {
    return _col
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map(PlatformProduct.fromFirestore)
            .toList(growable: false));
  }

  /// Админ: барча товарлар (жойлаштириш тартиби).
  Stream<List<PlatformProduct>> watchAll({int limit = catalogLimit}) {
    return _col.limit(limit).snapshots().map(
          (snap) => _sorted(snap.docs.map(PlatformProduct.fromFirestore)),
        );
  }

  Future<List<PlatformProduct>> fetchActive({int limit = catalogLimit}) async {
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
    final all = await fetchCatalog(limit: catalogLimit);
    final eligible = all.where((p) => p.price > 0).toList();
    final pool = auto
        ? eligible
        : eligible.where((p) => p.featuredOnHome).toList();
    pool.shuffle(Random());
    return pool.take(take).toList(growable: false);
  }

  /// Онлайн бозор лентаси учун.
  Future<List<PlatformProduct>> fetchForMarket({int limit = 40}) async {
    final all = await fetchCatalog(limit: catalogLimit);
    return all
        .where((p) => p.price > 0)
        .take(limit)
        .toList(growable: false);
  }

  Future<PlatformProduct?> getById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return PlatformProduct.fromFirestore(doc);
  }

  /// Янги маҳсулот — ҳамиша рўйхат охирига (`sortOrder` = next).
  Future<String> create(PlatformProduct product) async {
    final order = await nextSortOrder();
    return createAppended(product, sortOrder: order);
  }

  /// Берилган `sortOrder` билан яратиш (кўп қўшиш учун кетма-кет).
  Future<String> createAppended(
    PlatformProduct product, {
    required int sortOrder,
  }) async {
    final ref = product.id.isEmpty ? _col.doc() : _col.doc(product.id);
    await ref.set(product.copyWith(sortOrder: sortOrder).toFirestoreCreate());
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

  /// Танланганларга `food` | `non_food` қўйиш (batch).
  Future<void> setGoodsKindBatch(Iterable<String> ids, String kind) async {
    final k = PlatformProduct.normalizeKind(kind);
    if (k.isEmpty) {
      throw ArgumentError('goodsKind food|non_food бўлиши керак');
    }
    final list = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (list.isEmpty) return;
    const chunk = 400;
    for (var i = 0; i < list.length; i += chunk) {
      final batch = _db.batch();
      final end = (i + chunk < list.length) ? i + chunk : list.length;
      for (var j = i; j < end; j++) {
        batch.update(_col.doc(list[j]), {
          'goodsKind': k,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  /// Танланганлар → `non_food`, қолган каталог → `food`.
  Future<void> setNonFoodSelectedRestFood({
    required Iterable<String> nonFoodIds,
    required Iterable<String> allIds,
  }) async {
    final nonFood = nonFoodIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (nonFood.isEmpty) return;
    final rest = allIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !nonFood.contains(e))
        .toList(growable: false);
    await setGoodsKindBatch(nonFood, PlatformProduct.kindNonFood);
    if (rest.isNotEmpty) {
      await setGoodsKindBatch(rest, PlatformProduct.kindFood);
    }
  }
}

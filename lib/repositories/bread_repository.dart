import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/bread_extra_product.dart';
import '../models/bread_product.dart';

/// Нон каталоги ва қўшимча маҳсулотларга оид Firestore-ҳаракатлар.
class BreadRepository {
  BreadRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('bread_products');

  CollectionReference<Map<String, dynamic>> get _extras =>
      _db.collection('extra_products');

  Stream<List<BreadProduct>> watchProducts() {
    return _products.orderBy('createdAt', descending: false).snapshots().map(
        (snap) =>
            snap.docs.map(BreadProduct.fromFirestore).toList(growable: false));
  }

  Stream<List<BreadExtraProduct>> watchExtraProducts() {
    return _extras.orderBy('createdAt', descending: false).snapshots().map(
        (snap) => snap.docs
            .map(BreadExtraProduct.fromFirestore)
            .toList(growable: false));
  }

  /// `settings/prices` ҳужжатини бир мартада ўқиш.
  Future<Map<String, dynamic>> getPrices() async {
    try {
      final doc = await _db.collection('settings').doc('prices').get();
      return doc.data() ?? const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // CRUD — фaқaт админ web панeлидaн чaқирилaди (`firestore.rules`'дa
  // ҳали auth check ёқ — security debt, Phase 7.8'да тузамиз).
  // ═══════════════════════════════════════════════════════════════════

  /// Нoн мaҳсулoтини яратиш ёки янгилaш.
  /// [id] — Firestore doc ID. Бўш бўлсa авто-яратилaди.
  Future<String> upsertProduct({
    String? id,
    required String name,
    required String type, // 'tayyor' | 'yopish' | 'toy'
    required int price,
    String emoji = '🫓',
    String imageUrl = '',
    String description = '',
    String category = '',
    String unit = 'дона',
    int? flourG,
    int? milkMl,
    double? milkRatio,
    String? priceKey,
    int totalStock = 0,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'type': type,
      'price': price,
      'emoji': emoji,
      'imageUrl': imageUrl,
      'description': description,
      'category': category,
      'unit': unit,
      'totalStock': totalStock,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (flourG != null) data['flourG'] = flourG;
    if (milkMl != null) data['milkMl'] = milkMl;
    if (milkRatio != null) data['milkRatio'] = milkRatio;
    if (priceKey != null && priceKey.isNotEmpty) data['priceKey'] = priceKey;
    if (id == null || id.isEmpty) {
      final docRef = _products.doc();
      data['createdAt'] = FieldValue.serverTimestamp();
      data['soldToday'] = 0;
      await docRef.set(data);
      return docRef.id;
    }
    final ref = _products.doc(id);
    final exists = (await ref.get()).exists;
    if (!exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
      data['soldToday'] = 0;
    }
    await ref.set(data, SetOptions(merge: true));
    return id;
  }

  /// Расм URLни алоҳида сақлаш (юклашдан кейин фойдаланувчи иловаси дарҳал кўрсин).
  Future<void> mergeProductFields(
    String firestoreId,
    Map<String, dynamic> fields,
  ) async {
    if (firestoreId.isEmpty) return;
    await _products.doc(firestoreId).set({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Янги нон ҳужжати учун ID (расмни `bread_images/{id}`га юклашдан олдин).
  String allocateProductDocId() => _products.doc().id;

  Future<void> deleteProduct(String id) async {
    if (id.isEmpty) return;
    await _products.doc(id).delete();
  }

  /// `soldToday` ни нолгa қaйтaриш (ҳaр кун тoнггa ёки aдмин қўлдa).
  Future<void> resetProductSold(String id) async {
    if (id.isEmpty) return;
    await _products.doc(id).set({'soldToday': 0}, SetOptions(merge: true));
  }

  /// Қўшимчa мaҳсулoт яратиш/янгилaш.
  Future<String> upsertExtra({
    String? id,
    required String name,
    required int price,
    String unit = 'dona',
    int totalStock = 0,
    bool bonusEnabled = false,
    int bonusThreshold = 0,
    int bonusQty = 0,
    int bonusPercent = 0,
    String emoji = '',
    String caption = '',
    String imageUrl = '',
    bool tieToYopishBread = false,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'price': price,
      'unit': unit,
      'totalStock': totalStock,
      'bonusEnabled': bonusEnabled,
      'bonusThreshold': bonusThreshold,
      'bonusQty': bonusQty,
      'bonusPercent': bonusPercent,
      'emoji': emoji,
      'caption': caption,
      'imageUrl': imageUrl,
      'tieToYopishBread': tieToYopishBread,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (id == null || id.isEmpty) {
      data['createdAt'] = FieldValue.serverTimestamp();
      data['soldToday'] = 0;
      final ref = await _extras.add(data);
      return ref.id;
    }
    await _extras.doc(id).set(data, SetOptions(merge: true));
    return id;
  }

  Future<void> deleteExtra(String id) async {
    if (id.isEmpty) return;
    await _extras.doc(id).delete();
  }

  Future<void> resetExtraSold(String id) async {
    if (id.isEmpty) return;
    await _extras.doc(id).set({'soldToday': 0}, SetOptions(merge: true));
  }

  /// `settings/prices` ҳужжaтини янгилaш (қисмaн merge).
  Future<void> updatePrices(Map<String, dynamic> changes) async {
    if (changes.isEmpty) return;
    await _db.collection('settings').doc('prices').set(
      {
        ...changes,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

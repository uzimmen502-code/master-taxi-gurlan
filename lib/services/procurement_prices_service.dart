import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/procurement_product.dart';

/// `procurement_products` — харид ва тўлов нархлари.
class ProcurementPricesService {
  ProcurementPricesService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('procurement_products');

  Stream<List<ProcurementProduct>> watchAll() {
    return _col.snapshots().map(_mapSnapshot);
  }

  Future<List<ProcurementProduct>> getAll() async {
    final snap = await _col.get();
    return _mapSnapshot(snap);
  }

  List<ProcurementProduct> _mapSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    if (snap.docs.isEmpty) {
      return ProcurementProduct.fromPaymentDefaults();
    }
    final list = snap.docs.map(ProcurementProduct.fromDoc).toList()
      ..sort(ProcurementProduct.compareByDefaultOrder);
    return list;
  }

  Future<bool> isCollectionEmpty() async {
    final snap = await _col.limit(1).get();
    return snap.docs.isEmpty;
  }

  /// Биринчи ochilish — коллекция бўш бўлса `payment_products` дан тўлдиради.
  Future<void> ensureSeededIfEmpty() async {
    if (!await isCollectionEmpty()) return;
    await seedFromDefaults(overwrite: true);
  }

  /// `payment_products.dart` стандарт нархларини ёзади.
  Future<void> seedFromDefaults({required bool overwrite}) async {
    if (!overwrite && !await isCollectionEmpty()) return;

    final batch = _db.batch();
    for (final product in ProcurementProduct.fromPaymentDefaults()) {
      final ref = _col.doc(product.code);
      batch.set(
        ref,
        product.toFirestore(),
        SetOptions(merge: !overwrite),
      );
    }
    await batch.commit();
  }

  Future<void> saveAll(Iterable<ProcurementProduct> products) async {
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();
    for (final product in products) {
      batch.set(_col.doc(product.code), {
        ...product.toFirestore(),
        'updatedAt': now,
      });
    }
    await batch.commit();
  }

  Future<void> savePrice({
    required String code,
    required int price,
    required ProcurementProduct template,
  }) async {
    await _col.doc(code).set({
      'code': code,
      'label': template.label,
      'unit': template.unit,
      'price': price,
      'active': template.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../features/oil_change/data/oil_catalog.dart';

/// Firestore `oil_change_catalog/{id}` — админ каталог (мой + фильтр).
class OilCatalogRepository {
  OilCatalogRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('oil_change_catalog');

  Stream<List<OilProduct>> watchActive() {
    // orderBy сервер индексига боғлиқ бўлмасин — клиентда сортлаймиз.
    return _col.snapshots().map((snap) {
      final list = snap.docs
          .map(_fromDoc)
          .where((p) => p.active)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    });
  }

  Stream<List<OilProduct>> watchAll() {
    return _col.snapshots().map((snap) {
      final list = snap.docs.map(_fromDoc).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    });
  }

  Future<List<OilProduct>> listActive() async {
    final snap = await _col.get();
    return snap.docs
        .map(_fromDoc)
        .where((p) => p.active)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// Firestore бўш бўлса статиқ; бор бўлса Firestore (расм/нарх билан).
  static List<OilProduct> resolveCatalog(List<OilProduct>? remote) {
    if (remote != null && remote.isNotEmpty) return remote;
    return [...OilCatalog.oils, ...OilCatalog.filters];
  }

  Future<void> save(OilProduct product) async {
    final ref = product.id.isEmpty ? _col.doc() : _col.doc(product.id);
    final data = _toMap(product);
    final snap = await ref.get();
    if (!snap.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> setActive(String id, bool active) async {
    await _col.doc(id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateImageUrl(String id, String imageUrl) async {
    await _col.doc(id).update({
      'imageUrl': imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }

  /// Статик дефолт каталогни Firestore’га бир марта юклаш.
  Future<int> seedFromDefaults({
    required String Function(String key) tr,
  }) async {
    final existing = await _col.limit(1).get();
    if (existing.docs.isNotEmpty) return 0;

    final batch = _db.batch();
    var order = 0;
    for (final p in [...OilCatalog.oils, ...OilCatalog.filters]) {
      final ref = _col.doc(p.id);
      final name = p.fixedName ?? tr(p.nameKey);
      final meta = tr(p.metaKey);
      final reason = tr(p.reasonKey);
      final specs = <String, String>{};
      for (final e in p.specKeys.entries) {
        final label = tr(e.key);
        final value =
            e.value.startsWith('oil_') ? tr(e.value) : e.value;
        specs[label] = value;
      }
      batch.set(ref, {
        'kind': p.isFilter ? 'filter' : 'oil',
        'name': name,
        'meta': meta,
        'price': p.price,
        'reason': reason,
        'imageUrl': '',
        'specs': specs,
        'sortOrder': order++,
        'active': true,
        'must': p.must,
        'dust': p.dust,
        'gas': p.gas,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return order;
  }

  OilProduct _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final kind = (d['kind'] as String?) ?? 'oil';
    final specsRaw = d['specs'];
    final specs = <String, String>{};
    if (specsRaw is Map) {
      for (final e in specsRaw.entries) {
        specs['${e.key}'] = '${e.value}';
      }
    }
    return OilProduct(
      id: doc.id,
      nameKey: '',
      metaKey: '',
      reasonKey: '',
      specKeys: const {},
      fixedName: (d['name'] as String?) ?? doc.id,
      plainMeta: (d['meta'] as String?) ?? '',
      plainReason: (d['reason'] as String?) ?? '',
      plainSpecs: specs,
      price: (d['price'] as num?)?.toInt() ?? 0,
      imageUrl: (d['imageUrl'] as String?) ?? '',
      isFilter: kind == 'filter',
      must: d['must'] == true,
      dust: d['dust'] == true,
      gas: d['gas'] == true,
      sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
      active: d['active'] != false,
    );
  }

  Map<String, dynamic> _toMap(OilProduct p) {
    return {
      'kind': p.isFilter ? 'filter' : 'oil',
      'name': p.fixedName ?? p.id,
      'meta': p.plainMeta ?? '',
      'price': p.price,
      'reason': p.plainReason ?? '',
      'imageUrl': p.imageUrl,
      'specs': p.plainSpecs ?? {},
      'sortOrder': p.sortOrder,
      'active': p.active,
      'must': p.must,
      'dust': p.dust,
      'gas': p.gas,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/home_ticker_ad.dart';

/// `home_ticker_ads` — bosh ekran begushchaya qator matnlari.
class HomeTickerRepository {
  HomeTickerRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('home_ticker_ads');

  Stream<List<HomeTickerAd>> watchForRole(String role) {
    return watchForModule('home', role);
  }

  /// Berilgan modul (`home` | `bread`) va rol uchun faol matnlar.
  Stream<List<HomeTickerAd>> watchForModule(String module, String role) {
    return _col.orderBy('priority', descending: true).snapshots().map((snap) {
      final now = DateTime.now();
      return snap.docs
          .map(HomeTickerAd.fromDoc)
          .where((a) =>
              a.module == module &&
              a.active &&
              a.text.isNotEmpty &&
              a.isVisibleForRole(role) &&
              a.isVisibleNow(now))
          .toList(growable: false);
    });
  }

  /// Admin panel — barcha yozuvlar (faol/faol emas).
  Stream<List<HomeTickerAd>> watchForAdmin({int limit = 100}) {
    return _col
        .orderBy('priority', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs.map(HomeTickerAd.fromDoc).toList(growable: false),
        );
  }

  Future<String> create(HomeTickerAd ad) async {
    final ref = await _col.add(ad.toCreateMap());
    return ref.id;
  }

  Future<void> update(HomeTickerAd ad) async {
    if (ad.id.isEmpty) return;
    await _col.doc(ad.id).update(ad.toUpdateMap());
  }

  Future<void> setActive(String id, bool active) async {
    if (id.isEmpty) return;
    await _col.doc(id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) async {
    if (id.isEmpty) return;
    await _col.doc(id).delete();
  }
}

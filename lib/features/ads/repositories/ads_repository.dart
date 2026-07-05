import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ad_model.dart';
import '../services/ads_storage_service.dart';

/// Firestore access for cheap product ads (`ads` + `type: cheap_product`).
class AdsRepository {
  AdsRepository({
    FirebaseFirestore? firestore,
    AdsStorageService? storage,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? AdsStorageService();

  final FirebaseFirestore _db;
  final AdsStorageService _storage;

  static const _maxActivePerUser = 50;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('ads');

  Query<Map<String, dynamic>> _cheapQuery() =>
      _col.where('type', isEqualTo: AdModel.typeKey);

  Future<String> createAd(AdModel ad) async {
    final ref = _col.doc();
    final data = ad.toMap(forCreate: true);
    data['status'] = 'active';
    data['views'] = 0;
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateAd(String adId, Map<String, dynamic> data) async {
    if (adId.isEmpty) return;
    final patch = Map<String, dynamic>.from(data);
    if (patch.containsKey('title')) {
      final title = (patch['title'] as String?) ?? '';
      patch['titleLower'] = title.toLowerCase();
    }
    patch['updatedAt'] = FieldValue.serverTimestamp();
    await _col.doc(adId).update(patch);
  }

  Future<void> deleteAd(String adId) async {
    if (adId.isEmpty) return;
    final snap = await _col.doc(adId).get();
    if (!snap.exists) return;
    final ad = AdModel.fromFirestore(snap);
    await _col.doc(adId).delete();
    if (ad.imageUrls.isNotEmpty) {
      await _storage.deleteAdImages(
        ownerId: ad.ownerId,
        imageUrls: ad.imageUrls,
      );
    }
  }

  Future<void> activateAd(String adId) async {
    await updateAd(adId, {
      'status': 'active',
      'publishedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deactivateAd(String adId) async {
    await updateAd(adId, {'status': 'inactive'});
  }

  Future<void> incrementViews(String adId) async {
    if (adId.isEmpty) return;
    await _col.doc(adId).update({
      'views': FieldValue.increment(1),
    });
  }

  Stream<List<AdModel>> getActiveAds() {
    return _cheapQuery()
        .where('status', isEqualTo: 'active')
        .orderBy('publishedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map(AdModel.fromFirestore).toList(),
        );
  }

  Stream<List<AdModel>> searchActiveAds(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getActiveAds();
    return _cheapQuery()
        .where('status', isEqualTo: 'active')
        .where('titleLower', isGreaterThanOrEqualTo: q)
        .where('titleLower', isLessThanOrEqualTo: '$q\uf8ff')
        .orderBy('titleLower')
        .orderBy('publishedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map(AdModel.fromFirestore).toList(),
        );
  }

  Stream<List<AdModel>> getMyAds(String uid, {String? status}) {
    if (uid.isEmpty) return Stream.value(const []);
    Query<Map<String, dynamic>> q = _cheapQuery()
        .where('ownerId', isEqualTo: uid);
    if (status != null && status.isNotEmpty) {
      q = q.where('status', isEqualTo: status);
    }
    return q.orderBy('publishedAt', descending: true).snapshots().map(
          (snap) => snap.docs.map(AdModel.fromFirestore).toList(),
        );
  }

  Future<bool> canCreateAd(String uid) async {
    if (uid.isEmpty) return false;
    final snap = await _cheapQuery()
        .where('ownerId', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .get();
    return snap.size < _maxActivePerUser;
  }

  /// One-time client migration helper for docs missing `titleLower`.
  Future<int> migrateTitleLowerForCheapProducts() async {
    final snap = await _cheapQuery().limit(500).get();
    var count = 0;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['titleLower'] != null && (d['titleLower'] as String).isNotEmpty) {
        continue;
      }
      final title = (d['title'] ?? '') as String;
      if (title.isEmpty) continue;
      batch.update(doc.reference, {'titleLower': title.toLowerCase()});
      count++;
    }
    if (count > 0) await batch.commit();
    return count;
  }

  /// Returns similar active cheap-product ads for details page.
  ///
  /// Weighted scoring (50/30/20):
  /// - 50% keyword overlap
  /// - 30% price proximity
  /// - 20% freshness (newer first)
  Future<List<AdModel>> getSimilarAds({
    required AdModel current,
    int limit = 6,
    double minScore = 0.35,
  }) async {
    if (current.id.isEmpty || limit <= 0) return const [];

    final poolSnap = await _cheapQuery()
        .where('status', isEqualTo: 'active')
        .orderBy('publishedAt', descending: true)
        .limit(40)
        .get();

    final all = poolSnap.docs.map(AdModel.fromFirestore).toList();
    final candidates = all.where((a) => a.id != current.id).toList();
    if (candidates.isEmpty) return const [];

    final currentWords = current.titleLower
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().length >= 3)
        .take(6)
        .toSet();

    double clamp01(double v) {
      if (v < 0) return 0;
      if (v > 1) return 1;
      return v;
    }

    double keywordScore(AdModel ad) {
      if (currentWords.isEmpty) return 0;
      final words = ad.titleLower
          .split(RegExp(r'\s+'))
          .where((w) => w.trim().length >= 3)
          .toSet();
      final overlap = words.intersection(currentWords).length;
      return clamp01(overlap / currentWords.length);
    }

    double priceScore(AdModel ad) {
      if (current.price <= 0 || ad.price <= 0) return 0;
      final ratio = (ad.price - current.price).abs() / current.price;
      // 0 difference => 1.0, >=100% difference => 0.0
      return clamp01(1 - ratio);
    }

    double freshnessScore(AdModel ad) {
      final now = DateTime.now();
      final published = ad.publishedAt ?? ad.createdAt ?? now;
      final ageDays = now.difference(published).inDays;
      // 0 days => 1.0, 30+ days => 0.0
      return clamp01(1 - (ageDays / 30.0));
    }

    double finalScore(AdModel ad) {
      const keywordWeight = 0.50;
      const priceWeight = 0.30;
      const freshnessWeight = 0.20;
      return (keywordScore(ad) * keywordWeight) +
          (priceScore(ad) * priceWeight) +
          (freshnessScore(ad) * freshnessWeight);
    }

    final scored = candidates
        .map((ad) => (ad: ad, score: finalScore(ad)))
        .where((item) => item.score >= minScore)
        .toList();

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final ap = a.ad.publishedAt?.millisecondsSinceEpoch ?? 0;
      final bp = b.ad.publishedAt?.millisecondsSinceEpoch ?? 0;
      return bp.compareTo(ap);
    });

    final filtered = scored.map((item) => item.ad).toList();
    if (filtered.length > limit) {
      return filtered.sublist(0, limit);
    }
    return filtered;
  }

  /// Admin web — barcha Onlayn BOZOR e'lonlari (limit 500).
  Stream<List<AdModel>> watchAllForAdmin() {
    return _cheapQuery().limit(500).snapshots().map((snap) {
      final list = snap.docs.map(AdModel.fromFirestore).toList();
      list.sort((a, b) {
        final ap = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bp = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bp.compareTo(ap);
      });
      return list;
    });
  }
}

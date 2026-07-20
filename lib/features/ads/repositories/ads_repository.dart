import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart';
import '../../../services/market_ad_service.dart';
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

  static const maxActivePerUser = 50;
  static const feedLimit = 200;
  static const searchLimit = 100;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('ads');

  Query<Map<String, dynamic>> _cheapQuery() =>
      _col.where('type', isEqualTo: AdModel.typeKey);

  List<String> _ownerAliases(String uid) {
    return phoneAliases(uid)
        .map(phoneDigits)
        .where((p) => p.length >= 9)
        .toSet()
        .take(10)
        .toList(growable: false);
  }

  /// Янги эълон — CF `submitMarketAd` (auth + phone=token + лимитлар).
  Future<String> createAd({
    required String title,
    required String description,
    required int price,
    required String sellerName,
    required List<String> imageUrls,
  }) {
    return MarketAdService.submitAd(
      title: title,
      description: description,
      price: price,
      sellerName: sellerName,
      imageUrls: imageUrls,
    );
  }

  Future<void> updateAd(String adId, Map<String, dynamic> data) async {
    if (adId.isEmpty) return;
    final patch = Map<String, dynamic>.from(data);
    patch.remove('phone');
    patch.remove('ownerId');
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

  Future<void> requestRepublish(String adId) async {
    await updateAd(adId, {'status': 'pending'});
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

  Future<void> submitComplaint({
    required String adId,
    required String reason,
  }) {
    return MarketAdService.submitComplaint(adId: adId, reason: reason);
  }

  Stream<List<AdModel>> getActiveAds({int limit = feedLimit}) {
    return _cheapQuery()
        .where('status', isEqualTo: 'active')
        .orderBy('publishedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs.map(AdModel.fromFirestore).toList(),
        );
  }

  Stream<List<AdModel>> searchActiveAds(String query, {int limit = searchLimit}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getActiveAds(limit: limit);
    return _cheapQuery()
        .where('status', isEqualTo: 'active')
        .where('titleLower', isGreaterThanOrEqualTo: q)
        .where('titleLower', isLessThanOrEqualTo: '$q\uf8ff')
        .orderBy('titleLower')
        .orderBy('publishedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs.map(AdModel.fromFirestore).toList(),
        );
  }

  Stream<List<AdModel>> getMyAds(String uid, {String? status}) {
    final aliases = _ownerAliases(uid);
    if (aliases.isEmpty) return Stream.value(const []);

    Query<Map<String, dynamic>> q = _cheapQuery()
        .where('ownerId', whereIn: aliases);
    if (status != null && status.isNotEmpty) {
      q = q.where('status', isEqualTo: status);
    }
    return q.snapshots().map((snap) {
      final list = snap.docs.map(AdModel.fromFirestore).toList();
      list.sort((a, b) {
        final da = b.updatedAt ?? b.createdAt ?? b.publishedAt;
        final db = a.updatedAt ?? a.createdAt ?? a.publishedAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
      return list;
    });
  }

  Future<bool> canCreateAd(String uid) async {
    final aliases = _ownerAliases(uid);
    if (aliases.isEmpty) return false;
    var active = 0;
    for (final id in aliases) {
      final snap = await _cheapQuery()
          .where('ownerId', isEqualTo: id)
          .where('status', isEqualTo: 'active')
          .get();
      active += snap.size;
      if (active >= maxActivePerUser) return false;
    }
    return true;
  }

  /// Returns similar active cheap-product ads for details page.
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
      return clamp01(1 - ratio);
    }

    double freshnessScore(AdModel ad) {
      final now = DateTime.now();
      final published = ad.publishedAt ?? ad.createdAt ?? now;
      final ageDays = now.difference(published).inDays;
      return clamp01(1 - (ageDays / 30.0));
    }

    double finalScore(AdModel ad) {
      return (keywordScore(ad) * 0.50) +
          (priceScore(ad) * 0.30) +
          (freshnessScore(ad) * 0.20);
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

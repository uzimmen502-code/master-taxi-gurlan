import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/tv_clip.dart';

class TvClipsRepository {
  TvClipsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('tv_clips');

  /// Яқиндаги клиплар — шу туман, сўнг янги.
  Future<List<TvClip>> fetchNearby({
    required String districtId,
    int limit = 20,
  }) async {
    final snap = await _col
        .where('status', isEqualTo: 'active')
        .where('districtId', isEqualTo: districtId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(TvClip.fromFirestore).toList();
  }

  /// Тавсиялар (шу ҳудуд, лайк/кўриш бўйича).
  Future<List<TvClip>> fetchRecommended({
    required String districtId,
    int limit = 20,
  }) async {
    final snap = await _col
        .where('status', isEqualTo: 'active')
        .where('districtId', isEqualTo: districtId)
        .orderBy('viewCount', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(TvClip.fromFirestore).toList();
  }

  /// Уй лентаси — 3–5 та охирги фаол клип.
  Future<List<TvClip>> fetchHomeClips({
    required String districtId,
    int limit = 5,
  }) async {
    if (districtId.isNotEmpty) {
      final nearby = await fetchNearby(districtId: districtId, limit: limit);
      if (nearby.isNotEmpty) return nearby;
    }
    return fetchAllActive(limit: limit);
  }

  /// Уйдаги бир клип (витрина).
  Future<TvClip?> fetchHomeClip({required String districtId}) async {
    final snap = await _col
        .where('status', isEqualTo: 'active')
        .where('districtId', isEqualTo: districtId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : TvClip.fromFirestore(snap.docs.first);
  }

  /// Фаол клиплардан охиргиси — индексга боғлиқ эмас (fallback).
  Future<TvClip?> fetchLatestActive() async {
    final snap = await _col
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : TvClip.fromFirestore(snap.docs.first);
  }

  /// Барча фаол клиплар — ҳудудсиз (fallback).
  Future<List<TvClip>> fetchAllActive({int limit = 30}) async {
    final snap = await _col
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(TvClip.fromFirestore).toList();
  }

  /// Эгаси клиплари.
  Future<List<TvClip>> fetchByOwner(String phone, {int limit = 50}) async {
    final snap = await _col
        .where('ownerPhone', isEqualTo: phone)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(TvClip.fromFirestore).toList();
  }
}

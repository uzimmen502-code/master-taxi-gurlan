import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/tv_clip.dart';
import '../services/tv_storage_service.dart';

/// Home / TV Market клип саҳифаси — курсор билан давом эттириш учун.
class TvClipPage {
  const TvClipPage({
    required this.clips,
    this.nearbyCursor,
    this.allCursor,
    this.nearbyExhausted = false,
    this.hasMore = false,
  });

  final List<TvClip> clips;
  final DocumentSnapshot<Map<String, dynamic>>? nearbyCursor;
  final DocumentSnapshot<Map<String, dynamic>>? allCursor;
  final bool nearbyExhausted;
  final bool hasMore;
}

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

  /// Уй лентаси — аввал шу туман, етишмаса барча фаол клиплар.
  Future<List<TvClip>> fetchHomeClips({
    required String districtId,
    int limit = 7,
  }) async {
    final page = await fetchHomePage(districtId: districtId, limit: limit);
    return page.clips;
  }

  /// Home чексиз лента: [excludeIds] аллақачон кўрсатилганлар.
  Future<TvClipPage> fetchHomePage({
    required String districtId,
    int limit = 7,
    Set<String> excludeIds = const {},
    DocumentSnapshot<Map<String, dynamic>>? nearbyCursor,
    DocumentSnapshot<Map<String, dynamic>>? allCursor,
    bool nearbyExhausted = false,
  }) async {
    final out = <TvClip>[];
    final seen = {...excludeIds};
    var nCur = nearbyCursor;
    var aCur = allCursor;
    var nExh = nearbyExhausted || districtId.isEmpty;
    var aExh = false;

    Future<QuerySnapshot<Map<String, dynamic>>> run(
      Query<Map<String, dynamic>> base,
      DocumentSnapshot<Map<String, dynamic>>? cursor,
      int lim,
    ) {
      var q = base;
      if (cursor != null) q = q.startAfterDocument(cursor);
      return q.limit(lim).get();
    }

    Query<Map<String, dynamic>> nearbyQ() => _col
        .where('status', isEqualTo: 'active')
        .where('districtId', isEqualTo: districtId)
        .orderBy('createdAt', descending: true);

    Query<Map<String, dynamic>> allQ() => _col
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true);

    if (!nExh && out.length < limit) {
      final snap = await run(nearbyQ(), nCur, limit);
      for (final d in snap.docs) {
        nCur = d;
        final c = TvClip.fromFirestore(d);
        if (seen.add(c.id)) out.add(c);
      }
      nExh = snap.docs.length < limit;
    }

    while (out.length < limit && !aExh) {
      final need = limit - out.length;
      final snap = await run(allQ(), aCur, need + 8);
      if (snap.docs.isEmpty) {
        aExh = true;
        break;
      }
      for (final d in snap.docs) {
        aCur = d;
        final c = TvClip.fromFirestore(d);
        if (seen.add(c.id)) {
          out.add(c);
          if (out.length >= limit) break;
        }
      }
      if (snap.docs.length < need + 8) aExh = true;
    }

    return TvClipPage(
      clips: out,
      nearbyCursor: nCur,
      allCursor: aCur,
      nearbyExhausted: nExh,
      hasMore: !nExh || !aExh,
    );
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

  /// Эгаси ўз клипини ўчиради — аввал Firestore, сўнг файллар.
  Future<void> deleteOwnClip(TvClip clip) async {
    await _col.doc(clip.id).delete();
    await TvStorageService().deleteClipFiles(
      videoUrl: clip.videoUrl,
      posterUrl: clip.posterUrl,
    );
  }
}

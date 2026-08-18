import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart';
import '../../ads/utils/ad_search_text.dart';
import '../models/tv_clip.dart';
import '../services/tv_storage_service.dart';
import '../utils/tv_clip_search.dart';
import 'tv_shop_repository.dart';

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

  List<TvClip>? _searchPool;
  String? _searchPoolKey;
  DateTime? _searchPoolAt;

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

  Future<List<TvClip>> _recentSearchPool(String districtId) async {
    final key = districtId.isEmpty ? '*' : districtId;
    final now = DateTime.now();
    if (_searchPool != null &&
        _searchPoolKey == key &&
        _searchPoolAt != null &&
        now.difference(_searchPoolAt!) < const Duration(seconds: 45)) {
      return _searchPool!;
    }
    final list = districtId.isEmpty
        ? await fetchAllActive(limit: TvClipSearch.poolLimit)
        : await fetchNearby(
            districtId: districtId,
            limit: TvClipSearch.poolLimit,
          );
    _searchPool = list;
    _searchPoolKey = key;
    _searchPoolAt = now;
    return list;
  }

  Future<List<TvClip>> _bySearchToken(String token) async {
    if (token.length < AdSearchText.minTokenLen) return const [];
    try {
      final snap = await _col
          .where('status', isEqualTo: 'active')
          .where('searchTokens', arrayContains: token)
          .limit(TvClipSearch.tokenQueryLimit)
          .get();
      return snap.docs.map(TvClip.fromFirestore).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Сарлавҳа / тавсиф / туман / категория — CatalogSearch + токен сўрови.
  Future<List<TvClip>> searchByTitle({
    required String query,
    String districtId = '',
    int limit = TvClipSearch.resultLimit,
  }) async {
    final q = query.trim();
    if (q.length < AdSearchText.minTokenLen) return const [];

    final probe = <String>{};
    for (final t in AdSearchText.queryTokens(q)) {
      if (t.length >= AdSearchText.minTokenLen) probe.add(t);
      if (probe.length >= 3) break;
    }

    final parts = await Future.wait<List<TvClip>>([
      _recentSearchPool(districtId),
      ...probe.map(_bySearchToken),
    ]);

    final byId = <String, TvClip>{};
    for (final list in parts) {
      for (final c in list) {
        if (districtId.isNotEmpty && c.districtId != districtId) continue;
        byId[c.id] = c;
      }
    }

    final hit = byId.values.where((c) => TvClipSearch.matches(c, q)).toList();
    hit.sort((a, b) {
      final byScore = TvClipSearch.score(b, q).compareTo(TvClipSearch.score(a, q));
      if (byScore != 0) return byScore;
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    if (hit.length > limit) return hit.sublist(0, limit);
    return hit;
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
    if (clip.shopItemId.isNotEmpty) {
      try {
        await TvShopRepository(db: _db).removeClipFromItem(
          itemId: clip.shopItemId,
          clipId: clip.id,
        );
      } catch (_) {}
    }
    await TvStorageService().deleteClipFiles(
      videoUrl: clip.videoUrl,
      posterUrl: clip.posterUrl,
    );
  }

  Future<void> patchOwnerName({
    required String clipId,
    required String ownerName,
  }) async {
    final name = tvOwnerDisplayName(ownerName);
    if (clipId.isEmpty || name.isEmpty) return;
    await _col.doc(clipId).update({'ownerName': name});
  }

  /// Эгаси ном/нарх/тавсиф/видеони янгилайди. status ва likeCount тегилмайди.
  Future<void> updateOwnClip({
    required String clipId,
    required String title,
    required int price,
    required String description,
    required String category,
    required List<String> searchTokens,
    String? videoUrl,
    String? posterUrl,
  }) async {
    if (clipId.isEmpty) return;
    final data = <String, dynamic>{
      'title': title.trim(),
      'price': price,
      'description': description.trim(),
      'category': category,
      'searchTokens': searchTokens,
    };
    if (videoUrl != null && videoUrl.isNotEmpty) data['videoUrl'] = videoUrl;
    if (posterUrl != null && posterUrl.isNotEmpty) data['posterUrl'] = posterUrl;
    await _col.doc(clipId).update(data);
  }

  Future<bool> isLiked({
    required String clipId,
    required String likerId,
  }) async {
    if (clipId.isEmpty || likerId.isEmpty) return false;
    final snap = await _col.doc(clipId).collection('likes').doc(likerId).get();
    return snap.exists;
  }

  Future<Set<String>> likedClipIds({
    required String likerId,
    required Iterable<String> clipIds,
  }) async {
    final out = <String>{};
    if (likerId.isEmpty) return out;
    for (final id in clipIds) {
      if (id.isEmpty) continue;
      final snap = await _col.doc(id).collection('likes').doc(likerId).get();
      if (snap.exists) out.add(id);
    }
    return out;
  }

  /// Бир фойдаланувчи — бир лайк. [likeCount] ±1.
  Future<bool> toggleLike({
    required String clipId,
    required String likerId,
  }) async {
    if (clipId.isEmpty || likerId.isEmpty) return false;
    final clipRef = _col.doc(clipId);
    final likeRef = clipRef.collection('likes').doc(likerId);
    return _db.runTransaction((tx) async {
      final likeSnap = await tx.get(likeRef);
      final clipSnap = await tx.get(clipRef);
      final count = (clipSnap.data()?['likeCount'] as num?)?.toInt() ?? 0;
      if (likeSnap.exists) {
        tx.delete(likeRef);
        if (count > 0) {
          tx.update(clipRef, {'likeCount': FieldValue.increment(-1)});
        }
        return false;
      }
      tx.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
      tx.update(clipRef, {'likeCount': FieldValue.increment(1)});
      return true;
    });
  }

  /// Haqiqiy ko‘rish: viewer 24 soatda 1 marta; clip + kanal jami +1.
  Future<bool> recordView({
    required String clipId,
    required String viewerId,
    required String ownerPhone,
  }) async {
    if (clipId.isEmpty || viewerId.isEmpty) return false;
    final clipRef = _col.doc(clipId);
    final viewRef = clipRef.collection('views').doc(viewerId);
    final ownerId = canonicalPhoneId(ownerPhone);
    final profileRef = _db.collection('tv_public_profiles').doc(ownerId);

    return _db.runTransaction((tx) async {
      final viewSnap = await tx.get(viewRef);
      final now = DateTime.now();
      if (viewSnap.exists) {
        final ts = viewSnap.data()?['viewedAt'];
        if (ts is Timestamp) {
          if (now.difference(ts.toDate()) < const Duration(hours: 24)) {
            return false;
          }
        }
        tx.update(viewRef, {'viewedAt': FieldValue.serverTimestamp()});
      } else {
        tx.set(viewRef, {'viewedAt': FieldValue.serverTimestamp()});
      }
      tx.update(clipRef, {'viewCount': FieldValue.increment(1)});
      if (ownerId.isNotEmpty) {
        final profileSnap = await tx.get(profileRef);
        if (profileSnap.exists) {
          tx.update(profileRef, {'totalViewCount': FieldValue.increment(1)});
        }
      }
      return true;
    });
  }

  Future<Set<String>> savedClipIds(String userId) async {
    if (userId.isEmpty) return {};
    final snap = await _db
        .collection('users')
        .doc(userId)
        .collection('saved_tv_clips')
        .limit(200)
        .get();
    return snap.docs.map((d) => d.id).toSet();
  }

  Future<bool> toggleSave({
    required String userId,
    required String clipId,
  }) async {
    if (userId.isEmpty || clipId.isEmpty) return false;
    final ref = _db
        .collection('users')
        .doc(userId)
        .collection('saved_tv_clips')
        .doc(clipId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return false;
    }
    await ref.set({
      'clipId': clipId,
      'savedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }
}

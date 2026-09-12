import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart';
import '../../ads/utils/ad_search_text.dart';
import '../models/tv_clip.dart';
import '../models/tv_comment.dart';
import '../services/tv_storage_service.dart';
import '../utils/tv_clip_search.dart';
import '../utils/tv_clip_shuffle.dart';
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

  /// Томошабин лентаси учун ҳужжатларни клипга ўгиради ва transcode'и
  /// йиқилганларини чиқариб ташлайди (қаранг: [TvClip.isPlayable]).
  ///
  /// Буни Firestore сўровининг ўзида қилиб бўлмайди: эски клипларда
  /// `processingStatus` майдони умуман йўқ, `isNotEqualTo` эса майдони
  /// йўқ ҳужжатларни ҳам натижадан ташлаб юборади — яъни бутун эски
  /// архив лентадан йўқолган бўларди.
  List<TvClip> _playable(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs.map(TvClip.fromFirestore).where((c) => c.isPlayable).toList();

  /// `categories` берилса — AVAGram'нинг «Кун янгиликлари» / «Реклама ва
  /// Эълонлар» таблари учун `category whereIn` фильтри (max 30 қиймат).
  /// `null`/бўш = AVAGram (барча category).
  Query<Map<String, dynamic>> _withCategory(
    Query<Map<String, dynamic>> q,
    List<String>? categories,
  ) {
    if (categories == null || categories.isEmpty) return q;
    return q.where('category', whereIn: categories);
  }

  /// Яқиндаги клиплар — шу туман, сўнг янги. `regionId` берилса — «вилоят»
  /// ва «республика» қамровли эълонлар ҳам туман фильтридан қатъи назар
  /// шу лентага қўшилади (🟡6 — эълон ҳудуд қамрови).
  Future<List<TvClip>> fetchNearby({
    required String districtId,
    int limit = 20,
    List<String>? categories,
    String regionId = '',
  }) async {
    var q = _col
        .where('status', isEqualTo: 'active')
        .where('districtId', isEqualTo: districtId);
    q = _withCategory(q, categories);
    final snap = await q.orderBy('createdAt', descending: true).limit(limit).get();
    final items = _playable(snap.docs);
    // Таб 'ad'ни ичига олмаса (мас. фақат 'news') — қамровли эълонлар
    // ўша табга умуман тегишли эмас.
    final adOk = categories == null || categories.isEmpty || categories.contains('ad');
    if (regionId.isNotEmpty && adOk) {
      final scoped = await _fetchScopedAds(
        excludeDistrictId: districtId,
        regionId: regionId,
      );
      for (final c in scoped) {
        if (items.every((e) => e.id != c.id)) items.add(c);
      }
    }
    return tvApplyAdTierPriority(tvShuffleClips(items));
  }

  /// «Вилоят»/«республика» қамровли пуллик реклама — бошқа туманнинг
  /// эълони бўлса ҳам феддда кўринади. Кичик, чекланган сўров (20 та) —
  /// катта ҳудудларда ҳам лентани тўлдириб юбормаслик учун.
  Future<List<TvClip>> _fetchScopedAds({
    required String excludeDistrictId,
    required String regionId,
  }) async {
    try {
      final snap = await _col
          .where('category', isEqualTo: 'ad')
          .where('status', isEqualTo: 'active')
          .where('adScope', whereIn: ['region', 'national'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
      return _playable(snap.docs)
          .where((c) =>
              c.districtId != excludeDistrictId &&
              (c.adScope == 'national' || c.regionId == regionId))
          .toList();
    } catch (e) {
      return const [];
    }
  }

  /// Вилоят бўйича лента — туман танланмаганда ишлатилади.
  ///
  /// `regionId` клипда денормал сақланади (`tv_clip_geo.dart` жойлаштириш
  /// пайтида ёзади). Майдони йўқ эски клиплар бу сўровга тушмайди — бу
  /// тўғри хулқ: вилояти номаълум клип «Хоразм» фильтрида кўринмаслиги
  /// керак. Фильтрсиз («Барча вилоятлар») ҳолатда бу метод умуман
  /// чақирилмайди, шунинг учун эски клиплар лентадан йўқолмайди.
  Future<List<TvClip>> fetchByRegion({
    required String regionId,
    int limit = 40,
    List<String>? categories,
  }) async {
    var q = _col
        .where('status', isEqualTo: 'active')
        .where('regionId', isEqualTo: regionId);
    q = _withCategory(q, categories);
    final snap =
        await q.orderBy('createdAt', descending: true).limit(limit).get();
    return tvApplyAdTierPriority(tvShuffleClips(_playable(snap.docs)));
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
    return tvShuffleClips(_playable(snap.docs));
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
    List<String>? categories,
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

    Query<Map<String, dynamic>> nearbyQ() => _withCategory(
          _col
              .where('status', isEqualTo: 'active')
              .where('districtId', isEqualTo: districtId),
          categories,
        ).orderBy('createdAt', descending: true);

    Query<Map<String, dynamic>> allQ() => _withCategory(
          _col.where('status', isEqualTo: 'active'),
          categories,
        ).orderBy('createdAt', descending: true);

    if (!nExh && out.length < limit) {
      final snap = await run(nearbyQ(), nCur, limit);
      for (final d in snap.docs) {
        nCur = d;
        final c = TvClip.fromFirestore(d);
        // `seen` барибир белгиланади (тарихда бўлса), тариф жадвали
        // «Реклама жойлашуви»: basic/visibility Home'да кўринмайди.
        if (seen.add(c.id) && c.showsOnHome && c.isPlayable) out.add(c);
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
        if (seen.add(c.id) && c.showsOnHome && c.isPlayable) {
          out.add(c);
          if (out.length >= limit) break;
        }
      }
      if (snap.docs.length < need + 8) aExh = true;
    }

    return TvClipPage(
      clips: tvApplyAdTierPriority(tvShuffleClips(out)),
      nearbyCursor: nCur,
      allCursor: aCur,
      nearbyExhausted: nExh,
      hasMore: !nExh || !aExh,
    );
  }

  /// Уйдаги бир клип (витрина). Биттагина керак бўлса ҳам бир нечтаси
  /// сўралади — энг янгиси transcode'да йиқилган бўлса, витрина бўш
  /// қолмай, ундан кейингиси кўрсатилади.
  Future<TvClip?> fetchHomeClip({required String districtId}) async {
    final snap = await _col
        .where('status', isEqualTo: 'active')
        .where('districtId', isEqualTo: districtId)
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get();
    final items = _playable(snap.docs);
    return items.isEmpty ? null : items.first;
  }

  /// Фаол клиплардан охиргиси — индексга боғлиқ эмас (fallback).
  Future<TvClip?> fetchLatestActive() async {
    final snap = await _col
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get();
    final items = _playable(snap.docs);
    return items.isEmpty ? null : items.first;
  }

  /// Барча фаол клиплар — ҳудудсиз (fallback).
  Future<List<TvClip>> fetchAllActive({
    int limit = 30,
    List<String>? categories,
  }) async {
    var q = _col.where('status', isEqualTo: 'active');
    q = _withCategory(q, categories);
    final snap = await q.orderBy('createdAt', descending: true).limit(limit).get();
    return tvApplyAdTierPriority(tvShuffleClips(_playable(snap.docs)));
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
      return _playable(snap.docs);
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

  /// Эгаси клиплари. Бу ерда [_playable] АТАЙИН қўлланмайди — эгаси ўз
  /// клипи transcode'да йиқилганини кўриши керак, акс ҳолда видео
  /// изсиз йўқолгандек туюлади.
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
    required bool showPhone,
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
      'showPhone': showPhone,
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
      // Firestore: transaction ичида БАРЧА read'лар write'лардан олдин
      // бўлиши шарт — иккала get() ҳам аввал.
      final viewSnap = await tx.get(viewRef);
      final profileSnap =
          ownerId.isNotEmpty ? await tx.get(profileRef) : null;
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
      if (profileSnap != null && profileSnap.exists) {
        tx.update(profileRef, {'totalViewCount': FieldValue.increment(1)});
      }
      return true;
    });
  }

  /// Playback sifat metrikalari — bitta ko'rish uchun bitta yozuv
  /// (event-stream emas, denormalized counter — `viewCount` bilan bir xil
  /// naqsh). Monitoring Center shu maydonlardan rebuffer ratio, completion
  /// rate, first-frame time hisoblaydi.
  Future<void> recordPlaybackStats({
    required String clipId,
    required Duration watched,
    required Duration buffered,
    required int bufferEvents,
    Duration? firstFrame,
    required bool completed,
    required bool skipped,
    bool hadError = false,
  }) async {
    if (clipId.isEmpty) return;
    final data = <String, dynamic>{
      'playbackStats.views': FieldValue.increment(1),
      'playbackStats.watchedMs': FieldValue.increment(watched.inMilliseconds),
      'playbackStats.bufferMs': FieldValue.increment(buffered.inMilliseconds),
      'playbackStats.bufferEvents': FieldValue.increment(bufferEvents),
      if (firstFrame != null)
        'playbackStats.firstFrameMsSum':
            FieldValue.increment(firstFrame.inMilliseconds),
      if (firstFrame != null)
        'playbackStats.firstFrameSamples': FieldValue.increment(1),
      if (completed) 'playbackStats.completedViews': FieldValue.increment(1),
      if (skipped) 'playbackStats.skippedViews': FieldValue.increment(1),
      if (hadError) 'playbackStats.errors': FieldValue.increment(1),
      'playbackStats.updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      await _col.doc(clipId).update(data);
    } catch (_) {
      // Klip o'chirilgan yoki write muvaffaqiyatsiz — analitika uchun
      // retry qilinmaydi (viewCount'dagi kabi best-effort).
    }
  }

  /// Изоҳлар — эскидан янгига (чат тарзида ўқилсин).
  Future<List<TvComment>> fetchComments(String clipId) async {
    if (clipId.isEmpty) return const [];
    final snap = await _col
        .doc(clipId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .limit(200)
        .get();
    return snap.docs.map(TvComment.fromFirestore).toList();
  }

  /// Тайёр савол қўшади (тезкор, spam хавфи паст) — `commentCount` +1.
  Future<void> addQuickComment({
    required String clipId,
    required String authorPhone,
    required String authorName,
    required String key,
  }) async {
    if (!tvCommentQuickKeys.contains(key)) return;
    await _addComment(
      clipId: clipId,
      authorPhone: authorPhone,
      authorName: authorName,
      type: 'quick',
      key: key,
    );
  }

  /// Эркин матнли изоҳ (≤ [tvCommentTextMaxLen] белги) — `commentCount` +1.
  Future<void> addTextComment({
    required String clipId,
    required String authorPhone,
    required String authorName,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > tvCommentTextMaxLen) return;
    await _addComment(
      clipId: clipId,
      authorPhone: authorPhone,
      authorName: authorName,
      type: 'text',
      text: trimmed,
    );
  }

  Future<void> _addComment({
    required String clipId,
    required String authorPhone,
    required String authorName,
    required String type,
    String key = '',
    String text = '',
  }) async {
    if (clipId.isEmpty || authorPhone.isEmpty) return;
    final clipRef = _col.doc(clipId);
    final commentRef = clipRef.collection('comments').doc();
    await _db.runTransaction((tx) async {
      tx.set(commentRef, {
        'authorPhone': authorPhone,
        'authorName': authorName,
        'type': type,
        if (key.isNotEmpty) 'key': key,
        if (text.isNotEmpty) 'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(clipRef, {'commentCount': FieldValue.increment(1)});
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

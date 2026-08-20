import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart';
import '../models/tv_shop.dart';

class TvShopRepository {
  TvShopRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _shops =>
      _db.collection('tv_shops');
  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('tv_shop_items');

  Future<bool> hasShop(String ownerPhone) async {
    final id = canonicalPhoneId(ownerPhone);
    if (id.isEmpty) return false;
    final snap = await _shops.doc(id).get();
    return snap.exists;
  }

  /// Feed CTA: qaysi nashriyotchilarda `tv_shops` bor.
  Future<Set<String>> ownerIdsWithShop(Iterable<String> phones) async {
    final ids = phones
        .map(canonicalPhoneId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return {};
    final out = <String>{};
    await Future.wait(ids.map((id) async {
      try {
        final snap = await _shops.doc(id).get();
        if (snap.exists) out.add(id);
      } catch (_) {}
    }));
    return out;
  }

  Future<TvShop?> fetchShop(String ownerPhone) async {
    final id = canonicalPhoneId(ownerPhone);
    if (id.isEmpty) return null;
    final snap = await _shops.doc(id).get();
    if (!snap.exists) return null;
    return TvShop.fromFirestore(snap);
  }

  Future<void> ensureShop({
    required String ownerPhone,
    required String name,
  }) async {
    final id = canonicalPhoneId(ownerPhone);
    if (id.isEmpty) return;
    final ref = _shops.doc(id);
    final snap = await ref.get();
    if (snap.exists) return;
    await ref.set({
      'name': name,
      'ownerPhone': id,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<TvShopItem>> fetchByOwner(String ownerPhone) async {
    final id = canonicalPhoneId(ownerPhone);
    if (id.isEmpty) return const [];
    final snap = await _items
        .where('ownerPhone', isEqualTo: id)
        .orderBy('createdAt', descending: true)
        .limit(80)
        .get();
    return snap.docs.map(TvShopItem.fromFirestore).toList();
  }

  Future<TvShopItem?> fetchItem(String itemId) async {
    if (itemId.isEmpty) return null;
    final snap = await _items.doc(itemId).get();
    if (!snap.exists) return null;
    return TvShopItem.fromFirestore(snap);
  }

  /// Аҳоли бозори лентаси: фаол товарлар (қоплама расм бор).
  Future<List<TvShopItem>> fetchForMarket({int limit = 80}) async {
    final snap = await _items
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map(TvShopItem.fromFirestore)
        .where((i) => i.coverPhotoUrl.isNotEmpty)
        .toList(growable: false);
  }

  /// Фаол витрина: расм + видео мажбурий; нарх ихтиёрий (клиентда фильтр).
  Future<List<TvShopItem>> fetchVitrine({
    String districtId = '',
    int limit = 80,
  }) async {
    Query<Map<String, dynamic>> q = _items
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true);
    if (districtId.isNotEmpty) {
      q = _items
          .where('status', isEqualTo: 'active')
          .where('districtId', isEqualTo: districtId)
          .orderBy('createdAt', descending: true);
    }
    final snap = await q.limit(limit).get();
    final items = snap.docs
        .map(TvShopItem.fromFirestore)
        .where((i) => i.isVitrineReady)
        .toList();
    items.sort(_vitrineRank);
    return items;
  }

  int _vitrineRank(TvShopItem a, TvShopItem b) {
    if (a.isBoosted != b.isBoosted) return a.isBoosted ? -1 : 1;
    if (a.hasVideo != b.hasVideo) return a.hasVideo ? -1 : 1;
    final byViews = b.viewCount.compareTo(a.viewCount);
    if (byViews != 0) return byViews;
    final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bt.compareTo(at);
  }

  Future<String> createItem(TvShopItem item) async {
    final ref = await _items.add(item.toMap());
    return ref.id;
  }

  Future<void> addClipToItem({
    required String itemId,
    required String clipId,
  }) async {
    await _items.doc(itemId).update({
      'clipIds': FieldValue.arrayUnion([clipId]),
    });
  }

  Future<void> removeClipFromItem({
    required String itemId,
    required String clipId,
  }) async {
    if (itemId.isEmpty || clipId.isEmpty) return;
    await _items.doc(itemId).update({
      'clipIds': FieldValue.arrayRemove([clipId]),
    });
  }

  Future<void> updateItem(
    String itemId,
    Map<String, dynamic> patch,
  ) async {
    await _items.doc(itemId).update(patch);
  }

  Future<void> deleteItem(String itemId) async {
    await _items.doc(itemId).update({'status': 'deleted'});
  }
}

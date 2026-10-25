import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart';
import '../models/tv_shop.dart';

/// [TvShopRepository.fetchOwnerPage] натижаси.
class ShopItemsPage {
  const ShopItemsPage({required this.items, required this.cursor, required this.hasMore});

  final List<TvShopItem> items;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

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

  /// Дўкон номини сақлайди («Менинг дўконим»). Ҳужжат бор бўлса — фақат `name`
  /// ўзгаради (`createdAt` сақланади), йўқ бўлса — [ensureShop] билан бир хил шаклда
  /// яратилади. Rules: эга `create` ва `update`ни ўзи қила олади (`tv_shops/{phone}`).
  Future<void> saveName({
    required String ownerPhone,
    required String name,
  }) async {
    final id = canonicalPhoneId(ownerPhone);
    final clean = name.trim();
    if (id.isEmpty || clean.length < 2) {
      throw ArgumentError('shop name must be at least 2 characters');
    }
    final ref = _shops.doc(id);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.update({'name': clean});
    } else {
      await ref.set({
        'name': clean,
        'ownerPhone': id,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<List<TvShopItem>> fetchByOwner(String ownerPhone, {int limit = 80}) async {
    final id = canonicalPhoneId(ownerPhone);
    if (id.isEmpty) return const [];
    final snap = await _items
        .where('ownerPhone', isEqualTo: id)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(TvShopItem.fromFirestore).toList();
  }

  /// Дўкон саҳифаси: эганинг маҳсулотлари саҳифалаб (энг янгиси биринчи; [fetchByOwner] билан бир хил индекс).
  /// [after] — олдинги саҳифанинг [ShopItemsPage.cursor]и. Юзлаб маҳсулотли дўкон бир сўровда юкланмайди (36-банд).
  Future<ShopItemsPage> fetchOwnerPage(
    String ownerPhone, {
    int limit = 100,
    DocumentSnapshot<Map<String, dynamic>>? after,
  }) async {
    final id = canonicalPhoneId(ownerPhone);
    if (id.isEmpty) return const ShopItemsPage(items: [], cursor: null, hasMore: false);
    var q = _items.where('ownerPhone', isEqualTo: id).orderBy('createdAt', descending: true).limit(limit);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.get();
    return ShopItemsPage(
      items: snap.docs.map(TvShopItem.fromFirestore).toList(growable: false),
      cursor: snap.docs.isEmpty ? after : snap.docs.last,
      hasMore: snap.docs.length >= limit,
    );
  }

  /// Эганинг ЎЗ дўкони маҳсулотлари: `businessId`и бўш (Бизнес харитаси объектига боғланмаган),
  /// ўчирилмаган, [onlyActive]да фаол. Мавжуд [fetchByOwner] сўрови (индекс бор), фильтр клиентда.
  Future<List<TvShopItem>> fetchOwnShopItems(String ownerPhone, {bool onlyActive = false}) async {
    final all = await fetchByOwner(ownerPhone, limit: 200);
    return visibleOwnShopItems(all, ownerPhone: ownerPhone, onlyActive: onlyActive);
  }

  /// [fetchOwnShopItems] фильтри (соф функция — тест учун).
  static List<TvShopItem> visibleOwnShopItems(
    Iterable<TvShopItem> all, {
    required String ownerPhone,
    bool onlyActive = false,
  }) =>
      visibleBusinessItems(all.where((i) => i.businessId.isEmpty), ownerPhone: ownerPhone, onlyActive: onlyActive);

  /// Бизнес харитаси объектининг маҳсулотлари (`businessId`). Битта майдонли сўров — композит индекс керак эмас;
  /// ўчирилганлар ва [onlyActive] да фаол бўлмаганлар клиентда чиқарилади, энг янгиси биринчи.
  /// [ownerPhone] берилса — бошқа эганинг `businessId` ёзиб қўйган «ёт» ҳужжатлари кўрсатилмайди (спуфинг).
  Future<List<TvShopItem>> fetchByBusiness(
    String businessId, {
    String ownerPhone = '',
    bool onlyActive = true,
    int limit = 200,
  }) async {
    if (businessId.isEmpty) return const [];
    final snap = await _items.where('businessId', isEqualTo: businessId).limit(limit).get();
    return visibleBusinessItems(
      snap.docs.map(TvShopItem.fromFirestore),
      ownerPhone: ownerPhone,
      onlyActive: onlyActive,
    );
  }

  /// [fetchByBusiness] фильтри (соф функция — тест учун): ўчирилганлар, [onlyActive]да фаол бўлмаганлар ва
  /// [ownerPhone]дан бошқа эганинг ҳужжатлари чиқарилади; энг янгиси биринчи.
  static List<TvShopItem> visibleBusinessItems(
    Iterable<TvShopItem> all, {
    String ownerPhone = '',
    bool onlyActive = true,
  }) {
    final owner = canonicalPhoneId(ownerPhone);
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return all.where((i) {
      if (i.status == 'deleted') return false;
      if (onlyActive && !i.isActive) return false;
      if (owner.isNotEmpty && canonicalPhoneId(i.ownerPhone) != owner) return false;
      return true;
    }).toList()
      ..sort((a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
  }

  Future<TvShopItem?> fetchItem(String itemId) async {
    if (itemId.isEmpty) return null;
    final snap = await _items.doc(itemId).get();
    if (!snap.exists) return null;
    return TvShopItem.fromFirestore(snap);
  }

  /// Админ: энг янги маҳсулотлар — барча ҳолатда (фаол, кутилаётган, блокланган, ўчирилган). Битта майдонли
  /// тартиб — автоматик индекс.
  Future<List<TvShopItem>> fetchRecentAll({int limit = 100}) async {
    final snap = await _items.orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map(TvShopItem.fromFirestore).toList(growable: false);
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

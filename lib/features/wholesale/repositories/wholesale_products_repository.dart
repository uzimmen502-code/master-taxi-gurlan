import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_query.dart';
import '../../../core/geo/module_geo_policy.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/formatters.dart';
import '../models/wholesale_product.dart';

/// `wholesale_products/{id}` — Cloud Function йўқ, Firestore Rules орқали:
/// эга фақат `pending` ҳолатда яратади/қайтаради, admin эса
/// `status`/`adminNote`/`moderatedAt`/`moderatedBy`/`publishedAt`ни
/// ўзгартиради (`firestore.rules`даги `wholesaleProductAdminPatchOnly()`).
/// Яратишда сотувчи `wholesale_sellers`да `approved` бўлиши шарт (Rules
/// `get()` орқали текширади).
class WholesaleProductsRepository {
  WholesaleProductsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const feedLimit = 200;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('wholesale_products');

  DocumentReference<Map<String, dynamic>> get _appSettings =>
      _db.collection('settings').doc('app');

  /// `settings/app.wholesaleProductAutoApprove` — admin ёққан/ўчирган
  /// ҚЎЛДА/АВТО тасдиқ ҳолати.
  Future<bool> isAutoApproveOn() async {
    try {
      final snap = await _appSettings.get();
      return snap.data()?['wholesaleProductAutoApprove'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String> create(WholesaleProduct product) async {
    final autoApproved = await isAutoApproveOn();
    final ref =
        await _col.add(product.toFirestoreCreate(autoApproved: autoApproved));
    return ref.id;
  }

  Future<WholesaleProduct?> fetchById(String productId) async {
    if (productId.isEmpty) return null;
    final snap = await _col.doc(productId).get();
    if (!snap.exists) return null;
    return WholesaleProduct.fromFirestore(snap);
  }

  Future<void> ownerUpdate(String productId, WholesaleProduct product) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update(product.toFirestoreOwnerUpdate());
  }

  Future<void> deactivate(String productId) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update({
      'status': WholesaleProduct.statusInactive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Яширилган (`inactive`) маҳсулотни қайта текширувга юбориш. Эга ўзини
  /// `active` қила олмайди (Rules): `inactive → pending`, admin тасдиқлагач
  /// яна лентада чиқади.
  Future<void> republish(String productId) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update({
      'status': WholesaleProduct.statusPending,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String productId) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).delete();
  }

  Future<void> incrementViews(String productId) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update({'views': FieldValue.increment(1)});
  }

  /// Видеообзор/пуллик реклама клипини маҳсулотга боғлаш —
  /// `TvShopRepository.addClipToItem` андозаси.
  Future<void> addVideoClip(String productId, String clipId) async {
    if (productId.isEmpty || clipId.isEmpty) return;
    await _col.doc(productId).update({
      'videoClipIds': FieldValue.arrayUnion([clipId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeVideoClip(String productId, String clipId) async {
    if (productId.isEmpty || clipId.isEmpty) return;
    await _col.doc(productId).update({
      'videoClipIds': FieldValue.arrayRemove([clipId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Умумий бозор — фаол маҳсулотлар.
  ///
  /// [market] берилса фақат ўша бозор (`wholesale` ёки `china`).
  /// Эски ёзувларда `market` майдони йўқ — улар улгуржи бозорга
  /// тегишли, шунинг учун улгуржи сўровида клиентда қўшилади
  /// (Firestore'да «майдон йўқ» бўйича сўров қилиб бўлмайди).
  Stream<List<WholesaleProduct>> getActiveProducts({
    int limit = feedLimit,
    String? market,
    GeoScope? geo,
  }) {
    // Улгуржи ҳудуд фильтри (D-GEO-10): вилоят/туман танланса — товар
    // ҳудуди (сотувчи манзилидан, сервер ёзади — `wholesale_geo.js`)
    // бўйича сервер сўрови. Ҳудудсиз товарлар (манзилсиз эски сотувчи)
    // фақат «Бутун Ўзбекистон»да. Индекс: (status, districtId, publishedAt↓).
    if (geo != null && geo.level != GeoLevel.nation) {
      return geoScopedStream<WholesaleProduct>(
        scope: geo,
        nation: () => getActiveProducts(limit: limit, market: market),
        byDistricts: (ids) => _col
            .where('status', isEqualTo: WholesaleProduct.statusActive)
            .where('districtId', whereIn: ids)
            .orderBy('publishedAt', descending: true)
            .limit(limit * 4)
            .snapshots()
            .map((s) {
          final all = s.docs.map(WholesaleProduct.fromFirestore);
          return market == null ? all.toList() : filterByMarket(all, market);
        }),
        idOf: (p) => p.id,
        compare: (a, b) => (b.publishedAt?.millisecondsSinceEpoch ?? 0)
            .compareTo(a.publishedAt?.millisecondsSinceEpoch ?? 0),
        limit: limit,
      );
    }
    final base = _col
        .where('status', isEqualTo: WholesaleProduct.statusActive)
        .orderBy('publishedAt', descending: true);

    if (market == null) {
      return base
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(WholesaleProduct.fromFirestore).toList());
    }

    if (market == WholesaleProduct.marketChina) {
      return base
          .where('market', isEqualTo: WholesaleProduct.marketChina)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(WholesaleProduct.fromFirestore).toList());
    }

    // Улгуржи: `market == 'wholesale'` ва майдони умуман йўқ эскилар.
    // Иккови ҳам керак, шунинг учун филтр клиентда.
    return base
        .limit(limit * 4)
        .snapshots()
        .map((s) => filterByMarket(
              s.docs.map(WholesaleProduct.fromFirestore),
              market,
            ).take(limit).toList());
  }

  /// [market] бозорига тегишли маҳсулотлар, тартиб сақланади —
  /// [WholesaleProduct.belongsToMarket] қоидаси бўйича.
  static List<WholesaleProduct> filterByMarket(
    Iterable<WholesaleProduct> all,
    String market,
  ) =>
      all.where((p) => p.belongsToMarket(market)).toList();

  /// Фаол маҳсулотлар — қидирув (кирилл↔лотин, `CatalogSearch`).
  ///
  /// [market] берилса қидирув фақат ўша бозор ичида кечади — Хитой
  /// бозоридан улгуржи маҳсулот чиқиб қолмаслиги учун.
  Stream<List<WholesaleProduct>> searchActiveProducts(
    String query, {
    int limit = 100,
    String? market,
    GeoScope? geo,
  }) {
    final q = query.trim();
    final poolLimit = q.isEmpty ? limit : feedLimit;
    return getActiveProducts(limit: poolLimit, market: market, geo: geo)
        .map((items) => filterBySearch(items, q, limit: limit));
  }

  /// Қидирув филтри (кирилл↔лотин) — Firestore сўровисиз. Экран лентани БИР
  /// марта олади ва ҳар ҳарфда шу функция билан филтрлайди: аввал ҳар ҳарф
  /// янги Firestore сўрови очарди.
  static List<WholesaleProduct> filterBySearch(
    List<WholesaleProduct> items,
    String query, {
    int limit = 100,
  }) {
    final q = query.trim();
    if (q.isEmpty) return items;
    final filtered = items.where((p) {
      return CatalogSearch.matches(q, [
        p.title,
        p.description,
        p.sellerCompanyName,
        '${p.basePrice}',
        ...p.searchTokens,
      ]);
    }).toList();
    if (filtered.length > limit) return filtered.sublist(0, limit);
    return filtered;
  }

  /// Сотувчининг ўз маҳсулотлари (ҳар қандай статус).
  ///
  /// [market] берилса фақат ўша бозордагилари — сотувчи «Хитой бозори»
  /// табида улгуржи маҳсулотларини кўрмасин. Филтр клиентда: сотувчида
  /// маҳсулот кам, устига эски ёзувларда `market` майдони йўқ.
  Stream<List<WholesaleProduct>> watchBySeller(
    String sellerPhone, {
    String? market,
  }) {
    final id = canonicalPhoneId(sellerPhone);
    if (id.isEmpty) return Stream.value(const []);
    return _col.where('sellerId', isEqualTo: id).snapshots().map((snap) {
      final all = snap.docs.map(WholesaleProduct.fromFirestore);
      final list =
          market == null ? all.toList() : filterByMarket(all, market);
      list.sort((a, b) {
        final at = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return list;
    });
  }

  /// Сотувчининг ОММАВИЙ (фаол) маҳсулотлари — харидор кўради.
  ///
  /// [watchBySeller] дан фарқи: `status == active` сўровда қайд қилинади.
  /// `wholesale_products` қоидаси фақат фаол ёки ўз ҳужжатини ўқишга
  /// рухсат беради, шунинг учун бегона сотувчининг рўйхат сўрови шу
  /// шартсиз рад этилади. Тартиб клиентда (янгиси биринчи): `orderBy`
  /// қўшилса таркибий индекс керак бўлади.
  Stream<List<WholesaleProduct>> watchActiveBySeller(
    String sellerId, {
    String? market,
  }) {
    final id = canonicalPhoneId(sellerId);
    if (id.isEmpty) return Stream.value(const []);
    return _col
        .where('sellerId', isEqualTo: id)
        .where('status', isEqualTo: WholesaleProduct.statusActive)
        .snapshots()
        .map((snap) => sortActiveSellerProducts(
              snap.docs.map(WholesaleProduct.fromFirestore),
              market: market,
            ));
  }

  /// [watchActiveBySeller] тартиби: бозор филтри + `publishedAt` камаювчи.
  static List<WholesaleProduct> sortActiveSellerProducts(
    Iterable<WholesaleProduct> all, {
    String? market,
  }) {
    final list = market == null ? all.toList() : filterByMarket(all, market);
    int ms(WholesaleProduct p) =>
        (p.publishedAt ?? p.updatedAt ?? p.createdAt)?.millisecondsSinceEpoch ??
        0;
    list.sort((a, b) => ms(b).compareTo(ms(a)));
    return list;
  }

  /// Admin рўйхати — барча маҳсулотлар, энг янгиси биринчи. Саҳифалар
  /// (500 та + «Яна юклаш») — экранда, `AdminPagedList` орқали.
  ///
  /// Бозор филтри ([WholesaleProduct.belongsToMarket], 2026-10-07) —
  /// клиентда: эски ёзувларда `market` майдони йўқ, Firestore'да «майдон
  /// йўқ» бўйича сўраб бўлмайди. Шунинг учун саҳифалар бутун коллекция
  /// бўйича.
  ///
  /// Энг янгиси биринчи СЕРВЕРДА (2026-10-08): аввал `limit` тартибсиз эди —
  /// Firestore ID тартибида биринчи 500 тасини берарди, маҳсулот кўпайса
  /// янги/кутаётганлари рўйхатга тушмай қоларди. Бир майдонли саралаш —
  /// композит индекс керак эмас. `createdAt` ни ҳар доим илова ёзади.
  Query<Map<String, dynamic>> adminListQuery() =>
      _col.orderBy('createdAt', descending: true);

  /// Admin — фаоллаштириш.
  Future<void> approve(String productId, {required String adminId}) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update({
      'status': WholesaleProduct.statusActive,
      'publishedAt': FieldValue.serverTimestamp(),
      'moderatedAt': FieldValue.serverTimestamp(),
      'moderatedBy': adminId,
    });
  }

  /// Admin — рад этиш/ёпиш (изоҳ билан).
  Future<void> reject(
    String productId, {
    required String adminId,
    String note = '',
  }) async {
    if (productId.isEmpty) return;
    await _col.doc(productId).update({
      'status': WholesaleProduct.statusInactive,
      'adminNote': note,
      'moderatedAt': FieldValue.serverTimestamp(),
      'moderatedBy': adminId,
    });
  }
}

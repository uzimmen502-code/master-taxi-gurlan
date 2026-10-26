import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../domain/business.dart';

/// `businesses` — мижоз томони (`functions/business_directory.js`).
///
/// Ёзув ФАҚАТ callable орқали (rules'да client-write ёпиқ); ўқиш — логин қилган фойдаланувчи.
class BusinessRepository {
  BusinessRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore,
        _functions = functions;

  // Лазй: Firebase инициализациясиз (виджет тестларида) обуна яратилмайди.
  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('businesses');

  /// Камера қоплаган `geohash4` катакчаларидаги объектлар (≤ 30 катак, ≤ [limit] ёзув).
  Future<List<Business>> fetchInCells(List<String> cells, {int limit = 400}) async {
    if (cells.isEmpty) return const [];
    final snap = await _col.where('geohash4', whereIn: cells).limit(limit).get();
    return _parse(snap.docs);
  }

  /// Менинг объектларим. Индекс керак эмас (битта тенглик); тартиб — мижозда.
  Stream<List<Business>> watchMine(String ownerId) {
    return _col.where('ownerId', isEqualTo: ownerId).snapshots().map((s) {
      final list = _parse(s.docs);
      list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  /// Админ рўйхати: энг янгилари (чекланган).
  Future<List<Business>> fetchRecent({int limit = 200}) async {
    final snap = await _col.orderBy('createdAt', descending: true).limit(limit).get();
    return _parse(snap.docs);
  }

  /// Админ: битта эганинг барча объектлари (бир марта ўқиш; [watchMine] сўрови билан бир хил).
  Future<List<Business>> fetchByOwner(String ownerId) async {
    if (ownerId.isEmpty) return const [];
    final snap = await _col.where('ownerId', isEqualTo: ownerId).get();
    return _parse(snap.docs);
  }

  List<Business> _parse(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <Business>[];
    for (final d in docs) {
      final b = Business.tryFromMap(d.id, d.data());
      if (b != null) out.add(b);
    }
    return out;
  }

  /// Яратиш (ID'сиз) ёки таҳрир ([businessId] билан). Яратишда [clientRequestId] шарт: икки марта
  /// босилса ҳам битта ёзув (21-банд).
  Future<String> upsertMine(
    Business b, {
    String? businessId,
    required String clientRequestId,
  }) async {
    final res = await _fns.httpsCallable('upsertMyBusiness').call<Object?>({
      ...b.toCallable(),
      if (businessId != null && businessId.isNotEmpty) 'businessId': businessId,
      'clientRequestId': clientRequestId,
    });
    final d = res.data as Map;
    return '${d['businessId']}';
  }

  Future<void> deleteMine(String businessId) async {
    await _fns.httpsCallable('deleteMyBusiness').call<Object?>({'businessId': businessId});
  }

  /// Асосий онлайн дўконни ўчириш (`deleteMyMainShop`): ичида дўкон бўлса — `SHOP_HAS_INNER_SHOPS`, блокланган —
  /// `SHOP_BLOCKED` ([errorCode]). Дўкон номи ва ўз маҳсулотлари ўчади; улгуржи/Аҳоли эълонлари қолади.
  Future<void> deleteMainShop() async {
    await _fns.httpsCallable('deleteMyMainShop').call<Object?>(const {});
  }

  /// Админ ЯНГИ объект қўшади (эга қарори 2026-10-23). [ownerPhone] берилса — ёзув шу фойдаланувчиники;
  /// берилмаса — эгасиз (фақат админ таҳрирлайди). [clientRequestId] такрор босишда битта ёзув беради.
  Future<String> adminCreate(
    Business b, {
    required String reason,
    required String clientRequestId,
    String ownerPhone = '',
  }) async {
    final res = await _fns.httpsCallable('adminCreateBusiness').call<Object?>({
      ...b.toCallable(),
      if (ownerPhone.trim().isNotEmpty) 'ownerPhone': ownerPhone.trim(),
      'reason': reason,
      'clientRequestId': clientRequestId,
    });
    return '${(res.data as Map)['businessId']}';
  }

  Future<void> adminUpdate(Business b, {required String reason}) async {
    await _fns.httpsCallable('adminUpdateBusiness').call<Object?>({
      ...b.toCallable(),
      'businessId': b.id,
      'reason': reason,
    });
  }

  Future<void> adminDelete(String businessId, {required String reason}) async {
    await _fns.httpsCallable('adminDeleteBusiness').call<Object?>({
      'businessId': businessId,
      'reason': reason,
    });
  }

  /// Админ объект маҳсулотини таҳрирлайди (сервер: `adminUpdateBusinessProduct`, audit + сабаб шарт, 41-банд).
  /// Фақат берилган майдонлар юборилади; [status] — `active` | `blocked`.
  Future<void> adminUpdateProduct(
    String itemId, {
    required String reason,
    String? title,
    int? price,
    String? description,
    String? kind,
    String? status,
  }) async {
    await _fns.httpsCallable('adminUpdateBusinessProduct').call<Object?>({
      'itemId': itemId,
      'reason': reason,
      if (title != null) 'title': title,
      if (price != null) 'price': price,
      if (description != null) 'description': description,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
    });
  }

  /// Йўналиш дўконини блоклаш/очиш (`adminSetBusinessStatus`): харитадан йўқолади, маҳсулотлари блокланади.
  /// [status] — `active` | `blocked`. Блокланган маҳсулотлар сони қайтарилади.
  Future<int> adminSetStatus(String businessId, {required String status, required String reason}) async {
    final res = await _fns.httpsCallable('adminSetBusinessStatus').call<Object?>({
      'businessId': businessId,
      'status': status,
      'reason': reason,
    });
    final n = (res.data as Map?)?['products'];
    return n is int ? n : 0;
  }

  /// Бутун онлайн дўконни блоклаш/очиш (`adminSetShopStatus`): эганинг барча йўналишлари ва маҳсулотлари.
  Future<void> adminSetShopStatus(String ownerPhone, {required String status, required String reason}) async {
    await _fns.httpsCallable('adminSetShopStatus').call<Object?>({
      'ownerPhone': ownerPhone,
      'status': status,
      'reason': reason,
    });
  }

  /// Эганинг онлайн дўкони, йўналиши [businessId] ёки а'зоси бўлган кафе-ресторан [restaurantId] доимий ҳаволаси
  /// (`getMyShopLink`): бир марта берилади, ўзгармайди; телефон йўқ. Қайтаради: `https://…/s/<publicId>`.
  Future<String> getMyShopLink({String businessId = '', String restaurantId = ''}) async {
    final res = await _fns.httpsCallable('getMyShopLink').call<Object?>({
      if (businessId.isNotEmpty) 'businessId': businessId,
      if (restaurantId.isNotEmpty) 'restaurantId': restaurantId,
    });
    return '${(res.data as Map)['url']}';
  }

  /// Веб-ҳаволадаги ID → қайси онлайн дўкон ва йўналиш ёки қайси кафе-ресторан (`resolveShopLink`, логинсиз).
  /// Блокланган/тасдиқланмаган/номаълум — `null` (бошқа объект очилмайди).
  Future<({String ownerPhone, String businessId, String restaurantId})?> resolveShopLink(String publicId) async {
    final res = await _fns.httpsCallable('resolveShopLink').call<Object?>({'publicId': publicId});
    final d = res.data as Map;
    if (d['available'] != true) return null;
    if (d['kind'] == 'restaurant') {
      final rid = '${d['restaurantId'] ?? ''}';
      return rid.isEmpty ? null : (ownerPhone: '', businessId: '', restaurantId: rid);
    }
    final owner = '${d['ownerPhone'] ?? ''}';
    if (owner.isEmpty) return null;
    return (ownerPhone: owner, businessId: '${d['businessId'] ?? ''}', restaurantId: '');
  }

  /// Харидор шикояти (`submitShopComplaint`): [targetType] — `shop_item` (маҳсулот ID) ёки `shop` (сотувчи телефони).
  /// Такрор юборилса сервер янги ёзув очмайди.
  Future<void> submitComplaint({required String targetType, required String targetId, required String reason}) async {
    await _fns.httpsCallable('submitShopComplaint').call<Object?>({
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
    });
  }

  /// Юмшоқ ўчириш (`status: deleted`), audit'да нусха сақланади.
  Future<void> adminDeleteProduct(String itemId, {required String reason}) async {
    await _fns.httpsCallable('adminDeleteBusinessProduct').call<Object?>({
      'itemId': itemId,
      'reason': reason,
    });
  }

  /// Callable хатосидан диагностика коди (`details.code`) — UI оддий жумла кўрсатади (25-банд).
  static String errorCode(Object e) {
    if (e is FirebaseFunctionsException) {
      final d = e.details;
      if (d is Map && d['code'] != null) return '${d['code']}';
    }
    debugPrint('[BusinessRepository] $e');
    return '';
  }
}

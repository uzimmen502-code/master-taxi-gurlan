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

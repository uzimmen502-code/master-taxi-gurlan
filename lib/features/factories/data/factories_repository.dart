import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../business_map/domain/business.dart';
import '../domain/factory_profile.dart';

/// «Ишлаб чиқарувчи завод/фабрикалар» (эга 2026-11-28) — `businesses` (category `manufacturing`) устида.
/// Ёзув ФАҚАТ callable орқали (`functions/factories.js`); ўқиш — логин қилган фойдаланувчи (rules).
class FactoriesRepository {
  FactoriesRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  static const category = 'manufacturing';

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('businesses');

  List<Business> _parse(QuerySnapshot<Map<String, dynamic>> s) => [
        for (final d in s.docs)
          if (Business.tryFromMap(d.id, d.data()) case final b?) b,
      ];

  /// Ҳудуд ҳалқалари: туман → вилоят → Республика ([limit] гача, такрорсиз). Фақат тенглик филтрлари
  /// (`category` + `districtId`/`regionId`) — композит индекс керак эмас. Блокланганлар чиқарилади.
  Future<List<Business>> fetchRings({String districtId = '', String regionId = '', int limit = 60}) async {
    final base = _col.where('category', isEqualTo: category);
    final rings = <Future<List<Business>>>[
      if (districtId.isNotEmpty) base.where('districtId', isEqualTo: districtId).limit(limit).get().then(_parse),
      if (regionId.isNotEmpty) base.where('regionId', isEqualTo: regionId).limit(limit).get().then(_parse),
      base.limit(limit).get().then(_parse),
    ];
    return mergeFactoryRings(await Future.wait(rings), limit: limit);
  }

  /// `setMyFactoryOptions` → `verification` (ҳолат).
  Future<String> setOptions(String businessId, FactoryOptions options, {bool requestVerification = false}) async {
    final res = await _fns.httpsCallable('setMyFactoryOptions').call<Object?>({
      'businessId': businessId,
      ...options.toCallable(),
      if (requestVerification) 'requestVerification': true,
    });
    final d = res.data;
    return d is Map ? '${d['verification'] ?? ''}' : '';
  }

  // ─── Админ ───

  /// Тасдиқ кутаётганлар (`producerVerification.status == pending`), тартиб мижозда.
  Future<List<Business>> fetchPendingVerification({int limit = 100}) async =>
      _parse(await _col.where('producerVerification.status', isEqualTo: ProducerStatus.pending).limit(limit).get());

  /// «AVA'га таъминотчи бўлишга тайёрман» белгисини қўйганлар.
  Future<List<Business>> fetchAvaSuppliers({int limit = 100}) async =>
      _parse(await _col.where('factory.avaSupplierReady', isEqualTo: true).limit(limit).get());

  Future<void> adminSetVerification(String businessId, {required bool approve, String reason = ''}) async {
    await _fns.httpsCallable('adminSetProducerVerification').call<Object?>({
      'businessId': businessId,
      'decision': approve ? ProducerStatus.approved : ProducerStatus.rejected,
      if (reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  Future<void> adminSetAutoApprove(bool enabled) async {
    await _fns.httpsCallable('adminSetProducerAutoApprove').call<Object?>({'enabled': enabled});
  }

  /// `settings/app.producerVerifyAutoApprove` (админ экрани).
  Stream<bool> watchAutoApprove() =>
      _db.doc('settings/app').snapshots().map((s) => s.data()?['producerVerifyAutoApprove'] == true);
}

/// Ҳалқаларни бирлаштириш (соф функция): тартиб сақланади, такрор id ташланади, блокланганлар чиқади;
/// ҳар ҳалқа ичида тасдиқланганлар олдинда, кейин янгилари.
List<Business> mergeFactoryRings(List<List<Business>> rings, {int limit = 60}) {
  final seen = <String>{};
  final out = <Business>[];
  for (final ring in rings) {
    final sorted = [...ring.where(isFactoryBusiness)]..sort((a, b) {
        final va = a.producerStatus == ProducerStatus.approved ? 0 : 1;
        final vb = b.producerStatus == ProducerStatus.approved ? 0 : 1;
        if (va != vb) return va - vb;
        return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
      });
    for (final b in sorted) {
      if (out.length >= limit) return out;
      if (seen.add(b.id)) out.add(b);
    }
  }
  return out;
}

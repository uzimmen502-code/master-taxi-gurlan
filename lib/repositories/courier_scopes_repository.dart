import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/utils/formatters.dart';

/// Курьер тоифалари — туман / вилоят / республика (эга қарори 2026-10-31).
///
/// Ҳақиқат манбаи СЕРВЕР (`functions/courier_scopes.js`):
///   • `provider_capabilities/{accountId}.courier.scopes` — курьер танлаган тоифалар;
///   • `review.courierScopes.{region|republic}.status` — тасдиқ (`pending` / `approved` / `rejected`),
///     уни фақат сервер ёзади;
///   • `courier_documents/{uid12}` — машина ва ҳужжат (вилоят/республика учун шарт).
/// Бу класс фақат ўқийди ва `courierRequestScopes`ни чақиради; ҳуқуқни сервер текширади.
class CourierScopes {
  const CourierScopes({
    required this.scopes,
    required this.review,
    required this.vehicle,
  });

  /// Танланган тоифалар. Майдон йўқ эски ҳужжат — `['district']` (сервер билан бир хил).
  final List<String> scopes;

  /// `region` / `republic` → `pending` | `approved` | `rejected`.
  final Map<String, String> review;

  /// `courier_documents` майдонлари: vehicleType, carPlate, carModel, driverLicenseNo.
  final Map<String, String> vehicle;

  static const all = ['district', 'region', 'republic'];
  static const reviewed = ['region', 'republic'];

  bool isActive(String scope) {
    if (!scopes.contains(scope)) return false;
    if (scope == 'district') return true;
    return review[scope] == 'approved';
  }
}

class CourierScopesRepository {
  CourierScopesRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  /// `courier_documents` калити — 12 хонали (сервер `uid12` ўқийди).
  static String docId(String uid) {
    final d = uid.replaceAll(RegExp(r'\D'), '');
    return d.length == 9 ? '998$d' : d;
  }

  Future<CourierScopes> load(String uid) async {
    var scopes = const ['district'];
    final review = <String, String>{};
    for (final id in userDocIdCandidates(uid)) {
      final user = await _db.collection('users').doc(id).get();
      if (!user.exists) continue;
      final accountId = user.data()?['accountId']?.toString() ?? '';
      if (accountId.isEmpty) break;
      final cap = (await _db.collection('provider_capabilities').doc(accountId).get()).data() ?? const {};
      final raw = (cap['courier'] as Map?)?['scopes'];
      if (raw is List) {
        scopes = CourierScopes.all.where((s) => raw.contains(s)).toList();
      }
      final r = ((cap['review'] as Map?)?['courierScopes'] as Map?) ?? const {};
      for (final s in CourierScopes.reviewed) {
        final st = (r[s] as Map?)?['status']?.toString() ?? '';
        if (st.isNotEmpty) review[s] = st;
      }
      break;
    }
    final docs = (await _db.collection('courier_documents').doc(docId(uid)).get()).data() ?? const {};
    final vehicle = <String, String>{
      for (final k in const ['vehicleType', 'carPlate', 'carModel', 'driverLicenseNo'])
        k: (docs[k] ?? '').toString(),
    };
    return CourierScopes(scopes: scopes, review: review, vehicle: vehicle);
  }

  /// Машина маълумоти — курьернинг ўз ҳужжати (`firestore.rules`: эгаси ёзади,
  /// `verified*` майдонларини эмас).
  Future<void> saveVehicle(String uid, Map<String, String> vehicle) {
    return _db.collection('courier_documents').doc(docId(uid)).set({
      ...vehicle,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Сервер: `{ scopes, review: {region: 'pending'|...}, mode }`.
  Future<Map<String, String>> requestScopes(List<String> scopes) async {
    final res = await _functions.httpsCallable('courierRequestScopes').call<Object?>({'scopes': scopes});
    final d = res.data is Map ? res.data as Map : const {};
    final r = d['review'] is Map ? d['review'] as Map : const {};
    return {for (final e in r.entries) e.key.toString(): e.value.toString()};
  }
}

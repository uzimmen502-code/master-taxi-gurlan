import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/utils/formatters.dart';
import '../features/demand_offer/data/demand_repository.dart'
    show kDemandCoreRegion;

/// Курьерлик ҲУҚУҚИ — `provider_capabilities/{accountId}.status.courier`
/// (D-12, D-CLEAN-1). Эски `users.role == 'courier'` ҳуқуқ бермайди.
///
/// Ҳолатлар ва уларнинг маъноси серверда (`functions_demand/core/
/// capabilities.js` → `LIFECYCLES.courier`). Бу ердаги тўпламлар фақат
/// UI учун — нима кўрсатиш; ҳуқуқни барибир сервер текширади.
class CourierCapabilityRepository {
  CourierCapabilityRepository({
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
  })  : _db = db ?? FirebaseFirestore.instance,
        _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions? _functions;

  static const notRegistered = 'not_registered';

  /// D-15.5: ариза админ навбатида — иш йўқ.
  static const applied = 'applied';

  /// Курьер панели очиладиган ҳолатлар = сервердаги `canFinishActive`:
  /// ишлаяпти ёки (тўхтатилган бўлса ҳам) қўлидаги ишни тугатади (D-15.4).
  static const panelStatuses = {
    'trial',
    'trial_expired',
    'document_submitted',
    'under_review',
    'approved',
    'document_rejected',
    'suspended',
  };

  /// Янги иш ололмайди, фақат бошланганини тугатади.
  static const finishOnlyStatuses = {'document_rejected', 'suspended'};

  /// Жорий ҳолат. Ҳужжат ёки `accountId` бўлмаса — `not_registered`.
  /// Битта `users` + битта `provider_capabilities` ўқиш (listener йўқ).
  Future<String> fetchStatus(String uid) async {
    for (final id in userDocIdCandidates(uid)) {
      final user = await _db.collection('users').doc(id).get();
      if (!user.exists) continue;
      final accountId = user.data()?['accountId']?.toString() ?? '';
      if (accountId.isEmpty) return notRegistered;
      final cap =
          await _db.collection('provider_capabilities').doc(accountId).get();
      final status =
          ((cap.data()?['status'] as Map?)?['courier'] ?? '').toString();
      return status.isEmpty ? notRegistered : status;
    }
    return notRegistered;
  }

  /// «Курьер бўлиш» — `requestCapability({service: 'courier'})`.
  ///
  /// Сервер қарор қилади (D-15.3, D-15.5): Мануал — `applied` (админ
  /// тасдиғигача иш йўқ), Авто — дарҳол `approved`. Қайта босиш
  /// idempotent. Қайтаради: серверда ёзилган ҳолат.
  Future<String> apply() async {
    final fns =
        _functions ?? FirebaseFunctions.instanceFor(region: kDemandCoreRegion);
    final res = await fns
        .httpsCallable('requestCapability')
        .call<Object?>({'service': 'courier'});
    final d = res.data is Map ? (res.data as Map) : const {};
    return (d['status'] ?? '').toString();
  }
}

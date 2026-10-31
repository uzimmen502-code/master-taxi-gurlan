import 'package:cloud_functions/cloud_functions.dart';

import '../models/customer_confirm.dart';

/// Мижоз тасдиғи Cloud Functions wrapper (қаранг: `models/customer_confirm.dart`).
///
/// Рўйхат ва тасдиқ — фақат сервер орқали: ҳолат ва «ким тасдиқлай олади»
/// серверда текширилади (18/19-қоидалар), клиент фақат кўрсатади ва босади.
class CustomerConfirmService {
  CustomerConfirmService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Шу мижознинг тасдиқ кутаётган элементлари (сервер чегараланган рўйхат беради).
  Future<List<CustomerConfirmation>> listPending() async {
    try {
      final result = await _functions
          .httpsCallable('getCustomerPendingConfirmations')
          .call(<String, dynamic>{});
      return CustomerConfirmation.listFromResponse(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw _toException(e);
    }
  }

  /// Мижоз ўз қурилмасида тасдиқлайди. Қайта чақирув хавфсиз (`idempotent`).
  ///
  /// [reject] — «Олмоқчиман» (фақат сервер `canReject` берган қадамда, масалан
  /// «етказилмади»). [requestedAt] берилса — сервер бошқа (янгироқ) сўровга бу
  /// тугма таъсир қилишига йўл қўймайди (`STATE_CHANGED`).
  Future<CustomerConfirmResult> confirm({
    required String module,
    required String id,
    required String step,
    bool reject = false,
    DateTime? requestedAt,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('customerConfirmHandover')
          .call(<String, dynamic>{
        'module': module,
        'id': id,
        'step': step,
        if (reject) 'decision': 'reject',
        if (requestedAt != null) 'requestedAtMs': requestedAt.millisecondsSinceEpoch,
      });
      return CustomerConfirmResult.fromResponse(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw _toException(e);
    }
  }

  static CustomerConfirmException _toException(FirebaseFunctionsException e) {
    final details = e.details;
    final reason = details is Map ? (details['reason'] ?? '').toString() : '';
    return CustomerConfirmException(e.code, reason, e.message ?? '');
  }
}

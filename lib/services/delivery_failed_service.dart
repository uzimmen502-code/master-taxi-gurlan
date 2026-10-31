import 'package:cloud_functions/cloud_functions.dart';

import '../models/customer_confirm.dart';
import '../models/delivery_failed.dart';

/// «Етказилмади» Cloud Functions wrapper (қаранг: `models/delivery_failed.dart`).
/// Рухсат ва ҳолат — фақат серверда (18/19-қоидалар); клиент кўрсатади ва юборади.
class DeliveryFailedService {
  DeliveryFailedService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Курьер: «етказиб бўлмади» (сабаб билан). Ҳолат ва пул ўзгармайди — мижоз тасдиғи сўралади.
  /// Қайта чақирув хавфсиз (сервер idempotent).
  Future<CourierActionResult> report({
    required String module,
    required String id,
    required String reason,
  }) async {
    try {
      final r = await _functions
          .httpsCallable('courierReportDeliveryFailed')
          .call(<String, dynamic>{'module': module, 'id': id, 'reason': reason});
      return CourierActionResult.fromResponse(r.data);
    } on FirebaseFunctionsException catch (e) {
      throw _toException(e);
    }
  }

  /// Сотувчи/админ қарори: `failed` — етказилмади, `continue` — курьер давом этади.
  Future<void> resolve({
    required String module,
    required String id,
    required bool failed,
  }) async {
    try {
      await _functions.httpsCallable('resolveDeliveryFailed').call(<String, dynamic>{
        'module': module,
        'id': id,
        'decision': failed ? 'failed' : 'continue',
      });
    } on FirebaseFunctionsException catch (e) {
      throw _toException(e);
    }
  }

  /// Қарор кутаётганлар (сервер ролга қараб модулларни чеклайди).
  Future<List<DeliveryFailedPendingItem>> listPending() async {
    try {
      final r = await _functions.httpsCallable('listDeliveryFailedPending').call(<String, dynamic>{});
      return DeliveryFailedPendingItem.listFromResponse(r.data);
    } on FirebaseFunctionsException catch (e) {
      throw _toException(e);
    }
  }

  static DeliveryFailedException _toException(FirebaseFunctionsException e) {
    final d = e.details;
    final reason = d is Map ? (d['reason'] ?? d['code'] ?? '').toString() : '';
    return DeliveryFailedException(e.code, reason);
  }
}

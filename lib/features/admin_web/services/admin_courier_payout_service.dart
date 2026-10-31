// Админ — курьер хизмат ҳақи callable'лари (default codebase, us-central1):
// `adminGetCourierServiceFee` (ўқиш) ва `adminSetCourierServiceFee` (ёзув).

import 'package:cloud_functions/cloud_functions.dart';

import '../utils/courier_service_fee_admin.dart';
import 'admin_callable.dart';

class AdminCourierPayoutService {
  AdminCourierPayoutService({AdminCallable? callable})
      : _call = callable ?? AdminCallable(FirebaseFunctions.instance);

  final AdminCallable _call;

  Future<CourierServiceFeeState> getServiceFee() async =>
      CourierServiceFeeState.fromMap(await _call.call('adminGetCourierServiceFee', const {}));

  /// Жавоб: `{ok, feeVersion, unchanged, feeBps, autoPayoutEnabled}`.
  Future<Map<String, dynamic>> setServiceFee({
    int? feeBps,
    bool? autoPayoutEnabled,
    required String reason,
  }) =>
      _call.call('adminSetCourierServiceFee', {
        if (feeBps != null) 'feeBps': feeBps,
        if (autoPayoutEnabled != null) 'autoPayoutEnabled': autoPayoutEnabled,
        'reason': reason,
      });
}

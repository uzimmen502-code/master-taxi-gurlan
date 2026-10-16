// Админ — курьер вазифалари callable'лари (default codebase, us-central1):
// ҳақ фоизи (`adminGetCourierTaskPayoutSettings`, `adminSetCourierTaskPayoutPct`)
// ва қотиб қолган вазифалар (`adminListStaleTasks`, фақат ўқиш).

import 'package:cloud_functions/cloud_functions.dart';

import '../utils/courier_tasks_admin.dart';
import 'admin_callable.dart';

class AdminCourierTasksService {
  AdminCourierTasksService({AdminCallable? callable})
      : _call = callable ?? AdminCallable(FirebaseFunctions.instance);

  final AdminCallable _call;

  Future<CourierPayoutSettings> getPayoutSettings() async =>
      CourierPayoutSettings.fromMap(await _call.call('adminGetCourierTaskPayoutSettings', const {}));

  /// [bps] `null` — «созланмаган»га қайтариш. Жавоб: `{ok, version, unchanged, module, bps}`.
  Future<Map<String, dynamic>> setPayoutPct({
    required String module,
    required int? bps,
    required String reason,
  }) =>
      _call.call('adminSetCourierTaskPayoutPct', {'module': module, 'bps': bps, 'reason': reason});

  Future<StaleTasksResult> listStaleTasks({required int hours}) async =>
      StaleTasksResult.fromMap(await _call.call('adminListStaleTasks', {'hours': hours}));
}

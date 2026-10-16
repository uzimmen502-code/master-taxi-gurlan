// Админ — «Мижоз тасдиғи» callable'лари (default codebase, us-central1):
// `adminGetCustomerConfirmation` (ўқиш) ва `adminSetCustomerConfirmation`
// (босқич ва/ёки синовчилар; audit сабаби билан).

import 'package:cloud_functions/cloud_functions.dart';

import '../utils/customer_confirm_admin.dart';
import 'admin_callable.dart';

class AdminCustomerConfirmService {
  AdminCustomerConfirmService({AdminCallable? callable})
      : _call = callable ?? AdminCallable(FirebaseFunctions.instance);

  final AdminCallable _call;

  Future<CustomerConfirmState> get() async =>
      CustomerConfirmState.fromMap(await _call.call('adminGetCustomerConfirmation', const {}));

  /// Фақат берилган майдонлар юборилади (`stage`, `addTesterIds`, `removeTesterIds`);
  /// [module] ва [reason] ҳар доим. Жавоб: `{ok, unchanged, stage, testerCount}`.
  Future<CustomerConfirmSetResult> set({
    required String module,
    String? stage,
    List<String>? addTesterIds,
    List<String>? removeTesterIds,
    required String reason,
  }) async {
    final res = await _call.call('adminSetCustomerConfirmation', {
      'module': module,
      if (stage != null) 'stage': stage,
      if (addTesterIds != null && addTesterIds.isNotEmpty) 'addTesterIds': addTesterIds,
      if (removeTesterIds != null && removeTesterIds.isNotEmpty) 'removeTesterIds': removeTesterIds,
      'reason': reason.trim(),
    });
    return CustomerConfirmSetResult.fromMap(res);
  }
}
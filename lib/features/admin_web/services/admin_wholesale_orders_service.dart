// Админ — Улгуржи буюртма занжири (5-босқич) callable'лари. Ҳаммаси demand
// codebase (europe-west1):
//
//   adminGetWholesaleOrdersStage / adminSetWholesaleOrdersStage  — дарвоза ва тестчилар
//     (feat/ulg-admin-srv; production'да ҲАЛИ йўқ бўлиши мумкин — deploy алоҳида)
//   setWholesaleOrderSettings({avaFeeBps, reason})                — AVA улуши (LIVE, 2-босқич)
//   adminResolveWholesaleCardDispute({orderId, decision, reason}) — карта тўлови низоси
//     (3b карта занжири, параллел агент; номи ва шакли ўша агентнинг шартномаси)
//
// Default codebase (us-central1, `FirebaseFunctions.instance`):
//   adminRecordWholesaleLostFeePayment({orderId, amount, opId, note}) — йўқолган посилка:
//     масъул курьер етказиш пули қарзини ўзи тўлади, админ олинган суммани ёзади
//     (`functions/wholesale_orders.js` `recordLostFeePayment`, feat/ulg-card 2fec8ce8).
//     Idempotent (`opId`), қолган қарздан ошмайди — СЕРВЕР текширади.
//
// Ҳамма ёзув, чегара, audit — СЕРВЕРДА (19, 41, 44-банд). Экран фақат чақиради.

import 'package:cloud_functions/cloud_functions.dart';

import '../../demand_offer/data/demand_repository.dart' show kDemandCoreRegion;
import '../utils/wholesale_orders_admin.dart';
import 'admin_callable.dart';

class AdminWholesaleOrdersService {
  AdminWholesaleOrdersService({AdminCallable? demand, AdminCallable? main})
      : _demand = demand ?? AdminCallable(FirebaseFunctions.instanceFor(region: kDemandCoreRegion)),
        _mainOverride = main;

  final AdminCallable _demand;
  final AdminCallable? _mainOverride;

  /// Default codebase — биринчи чақирувда (эски `demand:`-ли конструкторлар Firebase'сиз ишлайди).
  late final AdminCallable _main = _mainOverride ?? AdminCallable(FirebaseFunctions.instance);

  /// Йўқолган посилка — курьер етказиш пули қарзини тўлади (бутун сўм > 0). `opId` — битта
  /// админ амалига битта (ўша амални қайта уриниш — ўша `opId`). Жавоб: `{ok, idempotent,
  /// orderId, amount, outstanding, paidTotal}`.
  Future<Map<String, dynamic>> recordLostFeePayment({
    required String orderId,
    required int amount,
    required String opId,
    required String note,
  }) {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'мусбат бутун сўм');
    return _main.call('adminRecordWholesaleLostFeePayment', {
      'orderId': orderId,
      'amount': amount,
      'opId': opId,
      'note': note.trim(),
    });
  }

  Future<WholesaleGateState> getStage() async =>
      WholesaleGateState.fromMap(await _demand.call('adminGetWholesaleOrdersStage', const {}));

  /// Фақат берилган майдонлар юборилади; `reason` — мажбурий (сервер ≥3 белги).
  Future<WholesaleGateChange> setStage({
    bool? enabled,
    String? stage,
    List<String>? addTesterIds,
    List<String>? removeTesterIds,
    required String reason,
  }) async {
    final res = await _demand.call('adminSetWholesaleOrdersStage', {
      if (enabled != null) 'enabled': enabled,
      if (stage != null) 'stage': stage,
      if (addTesterIds != null && addTesterIds.isNotEmpty) 'addTesterIds': addTesterIds,
      if (removeTesterIds != null && removeTesterIds.isNotEmpty) 'removeTesterIds': removeTesterIds,
      'reason': reason.trim(),
    });
    return WholesaleGateChange.fromMap(res);
  }

  /// AVA улуши — бутун bps (0..3000). Жавоб: `{ok, unchanged, avaFeeBps, feeVersion}`.
  Future<Map<String, dynamic>> setFeeSettings({required int avaFeeBps, required String reason}) =>
      _demand.call('setWholesaleOrderSettings', {
        'avaFeeBps': avaFeeBps,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

  /// Карта тўлови низоси: `confirm` — тўлов тасдиқланди, `reject` — рад (сабаб мажбурий).
  Future<Map<String, dynamic>> resolveCardDispute({
    required String orderId,
    required String decision,
    required String reason,
  }) {
    if (decision != 'confirm' && decision != 'reject') {
      throw ArgumentError.value(decision, 'decision', "'confirm' | 'reject'");
    }
    return _demand.call('adminResolveWholesaleCardDispute', {
      'orderId': orderId,
      'decision': decision,
      'reason': reason.trim(),
    });
  }
}

// Админ — AVA Logistics callable'лари (йўқолган посилка D1, босқич D8).
//
//   demand codebase (europe-west1):  adminMarkShipmentLost, adminSetLogisticsStage
//   default codebase (us-central1):  adminRecordLostParcelPayment, adminListLossIncidents
//
// Ҳамма ёзув ва пул ҳисоби СЕРВЕРДА (idempotent, audit). `opId` — битта
// фойдаланувчи амалига битта: янги амал — янги `opId`, ўша амални ҚАЙТА
// уриниш — ўша `opId` (экран диалоги ичида сақланади).

import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../../demand_offer/data/demand_repository.dart' show kDemandCoreRegion;
import '../utils/loss_incident.dart';
import 'admin_callable.dart';

/// `^[A-Za-z0-9_-]{6,64}$` талабига мос (UUID v4 — 36 белги).
String newAdminOpId() => const Uuid().v4();

class StageChangeResult {
  const StageChangeResult({
    required this.unchanged,
    required this.stage,
    required this.testerCount,
    required this.added,
    required this.removed,
    required this.effectiveWithinSeconds,
  });

  final bool unchanged;
  final String stage;
  final int testerCount;
  final int added;
  final int removed;
  final int? effectiveWithinSeconds;

  static StageChangeResult fromMap(Map<String, dynamic> m) => StageChangeResult(
        unchanged: m['unchanged'] == true,
        stage: (m['stage'] ?? '').toString(),
        testerCount: adminInt(m['testerCount']) ?? 0,
        added: adminInt(m['added']) ?? 0,
        removed: adminInt(m['removed']) ?? 0,
        effectiveWithinSeconds: adminInt(m['effectiveWithinSeconds']),
      );
}

class AdminLogisticsService {
  AdminLogisticsService({AdminCallable? demand, AdminCallable? main})
      : _demand = demand ?? AdminCallable(FirebaseFunctions.instanceFor(region: kDemandCoreRegion)),
        _main = main ?? AdminCallable(FirebaseFunctions.instance);

  final AdminCallable _demand;
  final AdminCallable _main;

  /// Посилкани «йўқолди» деб эълон қилиш (idempotent: қайта чақирув — аввалги натижа).
  Future<Map<String, dynamic>> markShipmentLost({
    required String shipmentId,
    required String reason,
    String note = '',
    required String opId,
  }) =>
      _demand.call('adminMarkShipmentLost', {
        'shipmentId': shipmentId,
        'reason': reason,
        if (note.trim().isNotEmpty) 'note': note.trim(),
        'opId': opId,
      });

  /// Курьер қарзи бўйича тўлов ёзиш (бутун сўм).
  Future<Map<String, dynamic>> recordLostParcelPayment({
    required String shipmentId,
    required int amount,
    String note = '',
    required String opId,
  }) =>
      _main.call('adminRecordLostParcelPayment', {
        'shipmentId': shipmentId,
        'amount': amount,
        'opId': opId,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      });

  Future<List<LossIncident>> listLossIncidents({int? limit}) async {
    final res = await _main.call('adminListLossIncidents', {if (limit != null) 'limit': limit});
    return LossIncident.parseList(res['items']);
  }

  /// Босқич ва/ёки синовчилар. Фақат берилган майдонлар юборилади.
  Future<StageChangeResult> setStage({
    String? stage,
    List<String>? addTesterIds,
    List<String>? removeTesterIds,
    String reason = '',
  }) async {
    final res = await _demand.call('adminSetLogisticsStage', {
      if (stage != null) 'stage': stage,
      if (addTesterIds != null && addTesterIds.isNotEmpty) 'addTesterIds': addTesterIds,
      if (removeTesterIds != null && removeTesterIds.isNotEmpty) 'removeTesterIds': removeTesterIds,
      if (reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    return StageChangeResult.fromMap(res);
  }
}

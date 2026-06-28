import 'package:cloud_functions/cloud_functions.dart';

/// Settlement Ledger — trip settlement (open/confirm/cancel) Cloud Functions orqali.
///
/// Server tomoni caller'ni Firebase Auth (telefon token) orqali aniqlaydi,
/// shuning uchun `driverUid`/passenger uchun caller'ni yubormaymiz.
/// To'liq dizayn: docs/settlement_ledger_v1_uz.md
class SettlementService {
  SettlementService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  /// Haydovchi Pending settlement ochadi. `settlementAmount = totalChange - cashGiven`.
  /// Qaytaradi: { ok, idempotent, settlementId, state, settlementAmount, floatBalance, floatZone }
  static Future<Map<String, dynamic>> openSettlement({
    required String passengerPhone,
    required String tripId,
    required String opId,
    required int totalChange,
    int cashGiven = 0,
  }) async {
    final callable = _fn.httpsCallable('openSettlement');
    final result = await callable.call(<String, dynamic>{
      'passengerPhone': passengerPhone,
      'tripId': tripId,
      'opId': opId,
      'totalChange': totalChange,
      'cashGiven': cashGiven,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Yo'lovchi settlement'ni tasdiqlaydi → ledger post (kredit hisoblanadi).
  static Future<Map<String, dynamic>> confirmSettlement({
    required String settlementId,
  }) async {
    final callable = _fn.httpsCallable('confirmSettlement');
    final result = await callable.call(<String, dynamic>{
      'settlementId': settlementId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Settlement'ni bekor qiladi (yo'lovchi/haydovchi/admin) — pul ko'chmaydi.
  static Future<Map<String, dynamic>> cancelSettlement({
    required String settlementId,
    String reason = '',
  }) async {
    final callable = _fn.httpsCallable('cancelSettlement');
    final result = await callable.call(<String, dynamic>{
      'settlementId': settlementId,
      if (reason.isNotEmpty) 'reason': reason,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }
}

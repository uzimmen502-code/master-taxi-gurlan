import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'deferred_settlement_queue.dart';
import 'settlement_service.dart';

/// Trip qaytimi — Settlement Ledger orqali (creditChange fallbacksiz).
enum TripChangeSettlementStatus {
  /// Qaytim yo'q (cash <= fare).
  skipped,

  /// Pending settlement ochildi — yo'lovchi tasdiqlaydi.
  opened,

  /// Offline/tarmoq xatosi — deferred navbatga qo'yildi.
  deferred,

  /// Float kritik, identifikatsiya, float yetarli emas va h.k.
  failedPermanent,
}

class TripChangeSettlementOutcome {
  const TripChangeSettlementOutcome({
    required this.status,
    this.userMessage,
    this.reasonCode,
    this.settlementId,
  });

  final TripChangeSettlementStatus status;
  final String? userMessage;
  final String? reasonCode;
  final String? settlementId;

  bool get ok =>
      status == TripChangeSettlementStatus.skipped ||
      status == TripChangeSettlementStatus.opened ||
      status == TripChangeSettlementStatus.deferred;
}

/// Haydovchi qaytimini settlement oqimiga ulash (retry + aniq sabab).
class TripChangeSettlement {
  TripChangeSettlement._();

  static const int _maxRetries = 2;
  static const Duration _retryBaseDelay = Duration(milliseconds: 600);

  /// `change = cashPaid - fare`. `change <= 0` bo'lsa hech narsa qilinmaydi.
  static Future<TripChangeSettlementOutcome> settle({
    required String passengerPhone,
    required String tripId,
    required String opId,
    required int change,
    int cashGiven = 0,
  }) async {
    if (change <= 0) {
      return const TripChangeSettlementOutcome(
        status: TripChangeSettlementStatus.skipped,
      );
    }

    FirebaseFunctionsException? lastError;
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final res = await SettlementService.openSettlement(
          passengerPhone: passengerPhone,
          tripId: tripId,
          opId: opId,
          totalChange: change,
          cashGiven: cashGiven,
        );
        final settlementId = (res['settlementId'] ?? opId).toString();
        return TripChangeSettlementOutcome(
          status: TripChangeSettlementStatus.opened,
          settlementId: settlementId,
          userMessage: 'Qaytim $change so\'m yo\'lovchi tasdiqlashini kutmoqda',
        );
      } on FirebaseFunctionsException catch (e, st) {
        lastError = e;
        debugPrint('openSettlement[$attempt]: ${e.code} ${e.message}\n$st');
        final parsed = _parseError(e);
        if (parsed.permanent) {
          return TripChangeSettlementOutcome(
            status: TripChangeSettlementStatus.failedPermanent,
            reasonCode: parsed.code,
            userMessage: parsed.userMessage,
          );
        }
        if (parsed.retryable && attempt < _maxRetries) {
          await Future<void>.delayed(_retryBaseDelay * (attempt + 1));
          continue;
        }
        break;
      } catch (e, st) {
        debugPrint('openSettlement[$attempt]: $e\n$st');
        if (attempt < _maxRetries) {
          await Future<void>.delayed(_retryBaseDelay * (attempt + 1));
          continue;
        }
        break;
      }
    }

    await DeferredSettlementQueue.enqueue(
      passengerPhone: passengerPhone,
      tripId: tripId,
      opId: opId,
      settlementAmount: change,
    );

    final deferredMsg = lastError != null
        ? '${_parseError(lastError).userMessage} — navbatga saqlandi, internet qaytgach yuboriladi'
        : 'Tarmoq xatosi — qaytim navbatga saqlandi';

    return TripChangeSettlementOutcome(
      status: TripChangeSettlementStatus.deferred,
      reasonCode: lastError?.code ?? 'network',
      userMessage: deferredMsg,
      settlementId: opId,
    );
  }

  static _ParsedSettlementError _parseError(FirebaseFunctionsException e) {
    final code = e.code;
    final msg = (e.message ?? '').trim();

    if (code == 'failed-precondition') {
      if (msg.contains('Float kritik') || msg.contains('faqat naqd')) {
        return _ParsedSettlementError(
          code: 'float_critical',
          userMessage: 'Float kritik — qaytim faqat naqd. Admin float to\'ldirsin.',
          permanent: true,
        );
      }
      if (msg.contains('Float yetarli emas')) {
        return _ParsedSettlementError(
          code: 'float_insufficient',
          userMessage: 'Float yetarli emas — qolgan qaytimni naqd bering.',
          permanent: true,
        );
      }
      if (msg.contains('identifikatsiyadan')) {
        return _ParsedSettlementError(
          code: 'not_identified',
          userMessage: 'Yo\'lovchi yoki haydovchi identifikatsiyadan o\'tmagan.',
          permanent: true,
        );
      }
      return _ParsedSettlementError(
        code: code,
        userMessage: msg.isNotEmpty ? msg : 'Settlement ochib bo\'lmadi',
        permanent: true,
      );
    }

    if (code == 'invalid-argument' ||
        code == 'permission-denied' ||
        code == 'unauthenticated') {
      return _ParsedSettlementError(
        code: code,
        userMessage: msg.isNotEmpty ? msg : code,
        permanent: true,
      );
    }

    const retryable = {'unavailable', 'deadline-exceeded', 'internal', 'unknown'};
    return _ParsedSettlementError(
      code: code,
      userMessage: msg.isNotEmpty ? msg : 'Tarmoq xatosi — qayta uriniladi',
      retryable: retryable.contains(code),
    );
  }
}

class _ParsedSettlementError {
  const _ParsedSettlementError({
    required this.code,
    required this.userMessage,
    this.permanent = false,
    this.retryable = false,
  });

  final String code;
  final String userMessage;
  final bool permanent;
  final bool retryable;
}

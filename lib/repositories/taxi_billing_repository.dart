// TAXI BILLING — ҳайдовчи томонидаги репозиторий (D-TAXI-13, 22, 24).
//
// Ҳамма ҳисоб СЕРВЕРДА: `AVA fee = farePerSeat × 4 × 2%` — илова бу
// формулани ҚАЙТА ҲИСОБЛАМАЙДИ, фақат сервер қайтарган `feeAmount`ни
// кўрсатади (44-қоида: UI бизнес мантиғининг манбаси эмас). AVA орқали
// нечта йўловчи топилгани комиссияга таъсир қилмайди — шунинг учун бу
// файлда йўловчи сони умуман йўқ.
//
// Оқим (D-TAXI-13): `quote` → ҳайдовчи «N сўм тўлаб эълон қилиш»ни
// кўради → `publish` (сервер wallet'дан ечади, `published`) → шундан
// кейингина илова рейсни рўйхатдан ўтказади.
//
// Callable'лар `functions` default codebase'ида (us-central1) — ledger
// ўша ерда. Келишув эса `functions_demand` (europe-west1) да.

import 'package:cloud_functions/cloud_functions.dart';

import '../features/demand_offer/data/demand_repository.dart'
    show kDemandCoreRegion;

class TaxiFeeQuote {
  const TaxiFeeQuote({
    required this.allowed,
    required this.reason,
    required this.feeAmount,
    required this.quotedFee,
    required this.billable,
    required this.sufficient,
    required this.agreementRequired,
    this.walletBalance,
    this.agreementVersion,
    this.taxiStatus = '',
  });

  /// Эълон қилиш мумкинми (ҳуқуқ + келишув).
  final bool allowed;

  /// `ok` · `agreement_required` · `taxi_verification_required` · `taxi_not_allowed`.
  final String reason;

  /// Ҳозир ечиладиган сумма (starter/grace'да 0).
  final int feeAmount;

  /// Формула бўйича ҳисоб — ечилмаса ҳам кўрсатиш учун.
  final int quotedFee;

  /// D-TAXI-6.1: сервер `isTaxiBillable` (verified + grace тугаган);
  /// глобал флаг йўқ.
  final bool billable;
  final bool sufficient;

  /// D-TAXI-24.1: келишув ҳали қабул қилинмаган (starter тугаган
  /// ҳолатларда) — UI варақни тақдим қилади. `reason` нима бўлишидан
  /// қатъи назар келади (масалан `taxi_verification_required` билан бирга).
  final bool agreementRequired;
  final int? walletBalance;
  final int? agreementVersion;
  final String taxiStatus;

  factory TaxiFeeQuote.fromMap(Map<dynamic, dynamic> m) => TaxiFeeQuote(
        allowed: m['allowed'] == true,
        reason: (m['reason'] ?? '').toString(),
        feeAmount: (m['feeAmount'] as num?)?.toInt() ?? 0,
        quotedFee: (m['quotedFee'] as num?)?.toInt() ??
            (m['feeAmount'] as num?)?.toInt() ??
            0,
        billable: m['billable'] == true,
        sufficient: m['sufficient'] != false,
        agreementRequired: m['agreementRequired'] == true,
        walletBalance: (m['walletBalance'] as num?)?.toInt(),
        agreementVersion: (m['agreementVersion'] as num?)?.toInt(),
        taxiStatus: (m['taxiStatus'] ?? '').toString(),
      );
}

class TaxiPublishResult {
  const TaxiPublishResult({
    required this.tripId,
    required this.status,
    required this.feeAmount,
    this.walletBalance,
  });

  final String tripId;

  /// `published` ёки `payment_required`.
  final String status;
  final int feeAmount;
  final int? walletBalance;

  bool get published => status == 'published';
}

class TaxiBillingException implements Exception {
  const TaxiBillingException(this.code, this.reason, this.message);
  final String code;

  /// Сервер `details.reason` — UI матн танлаш учун.
  final String reason;
  final String message;

  @override
  String toString() => 'TaxiBillingException($code/$reason): $message';
}

class TaxiBillingRepository {
  TaxiBillingRepository({
    FirebaseFunctions? billingFunctions,
    FirebaseFunctions? demandFunctions,
  })  : _billing = billingFunctions ?? FirebaseFunctions.instance,
        _demand = demandFunctions ??
            FirebaseFunctions.instanceFor(region: kDemandCoreRegion);

  /// Default codebase (ledger билан бирга).
  final FirebaseFunctions _billing;

  /// Demand codebase — келишув.
  final FirebaseFunctions _demand;

  Future<TaxiFeeQuote> quote({required int farePerSeat}) async {
    final data = await _call(_billing, 'quoteTaxiFee', {'farePerSeat': farePerSeat});
    return TaxiFeeQuote.fromMap(data);
  }

  Future<TaxiPublishResult> publish({
    required int farePerSeat,
    required String from,
    required String to,
    required String scheduleDate,
    required String startTime,
    required int seats,
    DateTime? departureAt,
    double? driverLat,
    double? driverLng,
    double? locationAccuracy,
  }) async {
    final data = await _call(_billing, 'publishTaxiTrip', {
      'farePerSeat': farePerSeat,
      'from': from,
      'to': to,
      'scheduleDate': scheduleDate,
      'startTime': startTime,
      'seats': seats,
      if (departureAt != null) 'departureAt': departureAt.toUtc().toIso8601String(),
      if (driverLat != null) 'driverLat': driverLat,
      if (driverLng != null) 'driverLng': driverLng,
      if (locationAccuracy != null) 'locationAccuracy': locationAccuracy,
    });
    return TaxiPublishResult(
      tripId: (data['tripId'] ?? '').toString(),
      status: (data['status'] ?? '').toString(),
      feeAmount: (data['feeAmount'] as num?)?.toInt() ?? 0,
      walletBalance: (data['walletBalance'] as num?)?.toInt(),
    );
  }

  /// Рейс бекор — комиссия wallet'га қайтади (D-TAXI-15).
  Future<Map<String, dynamic>> cancel({
    required String tripId,
    bool hadAvaBooking = false,
    double? driverLat,
    double? driverLng,
  }) =>
      _call(_billing, 'cancelTaxiTrip', {
        'tripId': tripId,
        'hadAvaBooking': hadAvaBooking,
        if (driverLat != null) 'driverLat': driverLat,
        if (driverLng != null) 'driverLng': driverLng,
      });

  Future<Map<String, dynamic>> complete({required String tripId}) =>
      _call(_billing, 'completeTaxiTrip', {'tripId': tripId});

  /// Кейинга суриш (D-TAXI-CANCEL-3): `tripId` ва комиссия сақланади,
  /// фақат сана/вақт ўзгаради. Нарх ҳам ўзгарса — фақат фарқ.
  Future<Map<String, dynamic>> reschedule({
    required String tripId,
    required DateTime departureAt,
    String? scheduleDate,
    String? startTime,
    int? farePerSeat,
  }) =>
      _call(_billing, 'rescheduleTaxiTrip', {
        'tripId': tripId,
        'departureAt': departureAt.toUtc().toIso8601String(),
        if (scheduleDate != null) 'scheduleDate': scheduleDate,
        if (startTime != null) 'startTime': startTime,
        if (farePerSeat != null) 'farePerSeat': farePerSeat,
      });

  /// Нарх ўзгарди — фарқ (D-TAXI-11/12).
  Future<Map<String, dynamic>> reprice({
    required String tripId,
    required int farePerSeat,
  }) =>
      _call(_billing, 'repriceTaxiTrip', {'tripId': tripId, 'farePerSeat': farePerSeat});

  /// Taxi Service Agreement (D-TAXI-24). Версия сервер айтганидек.
  Future<void> acceptAgreement({required int version, String service = 'taxi'}) =>
      _call(_demand, 'acceptServiceAgreement', {'service': service, 'version': version});

  Future<Map<String, dynamic>> _call(
    FirebaseFunctions fn,
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await fn.httpsCallable(name).call<Object?>(payload);
      final d = res.data;
      if (d is Map) return d.map((k, v) => MapEntry(k.toString(), v));
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final reason = details is Map ? (details['reason'] ?? '').toString() : '';
      throw TaxiBillingException(e.code, reason, e.message ?? 'Xatolik');
    }
  }
}

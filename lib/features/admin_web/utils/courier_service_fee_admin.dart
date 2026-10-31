// Админ «Курьер хизмат ҳақи» (AVA Logistics) — СОФ мантиқ (тестланади).
//
// Сервер (default, us-central1, `functions/courier_payout.js`):
//   `adminGetCourierServiceFee`  — жорий %, авто-тўлов калити, охирги тўловлар,
//                                  очиқ аномалиялар (фақат ўқиш);
//   `adminSetCourierServiceFee`  — {feeBps 0..5000, autoPayoutEnabled?, reason}.
// Курьер LEG ҳақи (EARNED) АВТОМАТИК ҳамёнга тушади; тўлов пайтида шу фоиз
// ушланади: fee = ceil(gross × bps / 10000). Ҳисоб СЕРВЕРДА (44-банд); экран
// фақат намуна учун АЙНИ формулани кўрсатади.

import '../../logistics/domain/tariff_adjust.dart' show bpsToPercentText, percentTextToBps;

const kCourierFeeBpsMin = 0;
const kCourierFeeBpsMax = 5000;

/// Намуна ҳисоби учун сумма (эга мисоли: 40 000 сўм).
const kCourierFeeExampleGross = 40000;

int? _int(Object? v) => v is num ? v.toInt() : null;

class CourierFeePayoutRow {
  const CourierFeePayoutRow({
    required this.key,
    this.shipmentId = '',
    this.legId = '',
    this.providerId = '',
    this.gross = 0,
    this.fee = 0,
    this.net = 0,
    this.feeVersion,
    this.createdAtMs,
  });

  final String key;
  final String shipmentId;
  final String legId;
  final String providerId;
  final int gross;
  final int fee;
  final int net;
  final int? feeVersion;
  final int? createdAtMs;
}

class CourierFeeAnomalyRow {
  const CourierFeeAnomalyRow({
    required this.key,
    this.shipmentId = '',
    this.legId = '',
    this.providerId = '',
    this.amount,
    this.reason = '',
    this.attempts = 0,
    this.lastSeenAtMs,
  });

  final String key;
  final String shipmentId;
  final String legId;
  final String providerId;
  final int? amount;
  final String reason;
  final int attempts;
  final int? lastSeenAtMs;
}

class CourierServiceFeeState {
  const CourierServiceFeeState({
    this.configured = false,
    this.valid = true,
    this.feeBps,
    this.feeVersion = 0,
    this.autoPayoutEnabled = true,
    this.reason = '',
    this.updatedAtMs,
    this.updatedBy = '',
    this.feeAccountBalance = 0,
    this.recentPayouts = const [],
    this.openAnomalies = const [],
  });

  final bool configured;

  /// Сервердаги қиймат бузуқ (масалан қўлда 9999 ёзилган) — тўлов тўхтаган.
  final bool valid;

  /// `null` — бузуқ қиймат.
  final int? feeBps;
  final int feeVersion;
  final bool autoPayoutEnabled;
  final String reason;
  final int? updatedAtMs;
  final String updatedBy;
  final int feeAccountBalance;
  final List<CourierFeePayoutRow> recentPayouts;
  final List<CourierFeeAnomalyRow> openAnomalies;

  String get percentText => feeBps == null ? '' : bpsToPercentText(feeBps!);

  static CourierServiceFeeState fromMap(Map<String, dynamic> m) {
    final payouts = <CourierFeePayoutRow>[];
    final rawP = m['recentPayouts'];
    if (rawP is List) {
      for (final e in rawP) {
        if (e is! Map) continue;
        payouts.add(CourierFeePayoutRow(
          key: (e['key'] ?? '').toString(),
          shipmentId: (e['shipmentId'] ?? '').toString(),
          legId: (e['legId'] ?? '').toString(),
          providerId: (e['providerId'] ?? '').toString(),
          gross: _int(e['gross']) ?? 0,
          fee: _int(e['fee']) ?? 0,
          net: _int(e['net']) ?? 0,
          feeVersion: _int(e['feeVersion']),
          createdAtMs: _int(e['createdAtMs']),
        ));
      }
    }
    final anomalies = <CourierFeeAnomalyRow>[];
    final rawA = m['openAnomalies'];
    if (rawA is List) {
      for (final e in rawA) {
        if (e is! Map) continue;
        anomalies.add(CourierFeeAnomalyRow(
          key: (e['key'] ?? '').toString(),
          shipmentId: (e['shipmentId'] ?? '').toString(),
          legId: (e['legId'] ?? '').toString(),
          providerId: (e['providerId'] ?? '').toString(),
          amount: _int(e['amount']),
          reason: (e['reason'] ?? '').toString(),
          attempts: _int(e['attempts']) ?? 0,
          lastSeenAtMs: _int(e['lastSeenAtMs']),
        ));
      }
    }
    return CourierServiceFeeState(
      configured: m['configured'] == true,
      valid: m['valid'] != false,
      feeBps: _int(m['feeBps']),
      feeVersion: _int(m['feeVersion']) ?? 0,
      autoPayoutEnabled: m['autoPayoutEnabled'] != false,
      reason: (m['reason'] ?? '').toString(),
      updatedAtMs: _int(m['updatedAtMs']),
      updatedBy: (m['updatedBy'] ?? '').toString(),
      feeAccountBalance: _int(m['feeAccountBalance']) ?? 0,
      recentPayouts: payouts,
      openAnomalies: anomalies,
    );
  }
}

/// Сервер формуласи билан бир хил: ceil(gross × bps / 10000), бутун сўм.
int courierServiceFee(int gross, int bps) {
  if (gross <= 0 || bps <= 0) return 0;
  final p = gross * bps;
  return p ~/ 10000 + (p % 10000 > 0 ? 1 : 0);
}

class CourierFeeExample {
  const CourierFeeExample({required this.gross, required this.fee, required this.net});

  final int gross;
  final int fee;
  final int net;
}

CourierFeeExample courierFeeExample(int bps, {int gross = kCourierFeeExampleGross}) {
  final fee = courierServiceFee(gross, bps);
  return CourierFeeExample(gross: gross, fee: fee, net: gross - fee);
}

class CourierFeePlan {
  const CourierFeePlan({this.bps, this.changed = false, this.error});

  final int? bps;
  final bool changed;
  final String? error;
}

/// Фоиз матни → bps режаси. Бўш — хато (стандарт йўқ: 0 % ни очиқ ёзинг).
/// Чегара 0..50 % (0..5000 bps), қадам 0,01 %.
CourierFeePlan planCourierFeeChange({required int? currentBps, required String text}) {
  final t = text.trim();
  if (t.isEmpty) return const CourierFeePlan(error: 'Фоизни ёзинг (0..50, масалан 5 ёки 2,5)');
  if (!RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(t)) {
    return const CourierFeePlan(error: 'Фоиз 0..50 оралиғида, кўпи билан 2 хона каср (масалан 2,75)');
  }
  final bps = percentTextToBps(t);
  if (bps == null || bps < kCourierFeeBpsMin || bps > kCourierFeeBpsMax) {
    return const CourierFeePlan(error: 'Фоиз 0..50 оралиғида бўлиши керак');
  }
  return CourierFeePlan(bps: bps, changed: bps != currentBps);
}

/// Аномалия сабаби → админ матни.
String courierFeeAnomalyLabel(String reason) {
  switch (reason) {
    case 'auto_payout_disabled':
      return 'Авто-тўлов ўчиқ — кутилмоқда';
    case 'payable_insufficient':
      return 'Қарз қолдиғи етмайди (қўлда тўланганми?)';
    case 'user_missing':
      return 'Курьер фойдаланувчиси топилмади';
    case 'fee_config_invalid':
      return 'Хизмат ҳақи созламаси бузуқ';
    case 'earned_malformed':
      return 'EARNED ёзуви бузуқ';
    default:
      return reason.isEmpty ? 'номаълум' : reason;
  }
}

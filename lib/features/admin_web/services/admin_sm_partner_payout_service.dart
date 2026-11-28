// «AVA Супермаркет» ҳамкорга тўлов (эга 2026-11-28) — админ маълумот манбаи. Ҳаммаси сервер callable'лари
// (sm_partner_payout.js): қарз мавжуд ledger'да ҳисобланади, админ фақат қўлда тўлаганини белгилайди. Пул тизимдан
// ташқарига ЎТКАЗИЛМАЙДИ. Пул — бутун сўм; комиссия — базис пункт (бутун), float йўқ.
import 'package:cloud_functions/cloud_functions.dart';

import 'admin_supermarket_service.dart' show AdminSupermarketException, smAdminErrorText;

int _i(Object? v) => v is num ? v.toInt() : 0;
int? _iN(Object? v) => v is num ? v.toInt() : null;
String _s(Object? v) => v == null ? '' : '$v';

class SmPpSettings {
  const SmPpSettings({this.stage = 'off', this.commissionBp, this.version = 0, this.reason = '', this.valid = true});
  final String stage;
  final int? commissionBp;
  final int version;
  final String reason;
  final bool valid;

  factory SmPpSettings.fromMap(Map m) => SmPpSettings(
        stage: _s(m['stage']).isEmpty ? 'off' : _s(m['stage']),
        commissionBp: _iN(m['commissionBp']),
        version: _i(m['version']),
        reason: _s(m['reason']),
        valid: m['valid'] != false,
      );
}

class SmPpPartner {
  const SmPpPartner({
    required this.partnerKey,
    this.companyName = '',
    this.sellerId,
    this.balance = 0,
    this.accruedTotal = 0,
    this.paidTotal = 0,
    this.offsetTotal = 0,
    this.reversedTotal = 0,
    this.clawbackTotal = 0,
    this.openCount = 0,
    this.blockedCount = 0,
  });
  final String partnerKey;
  final String companyName;
  final String? sellerId;
  final int balance;
  final int accruedTotal;
  final int paidTotal;
  final int offsetTotal;
  final int reversedTotal;
  final int clawbackTotal;
  final int openCount;
  final int blockedCount;

  factory SmPpPartner.fromMap(Map m) => SmPpPartner(
        partnerKey: _s(m['partnerKey']),
        companyName: _s(m['companyName']),
        sellerId: m['sellerId'] == null ? null : _s(m['sellerId']),
        balance: _i(m['balance']),
        accruedTotal: _i(m['accruedTotal']),
        paidTotal: _i(m['paidTotal']),
        offsetTotal: _i(m['offsetTotal']),
        reversedTotal: _i(m['reversedTotal']),
        clawbackTotal: _i(m['clawbackTotal']),
        openCount: _i(m['openCount']),
        blockedCount: _i(m['blockedCount']),
      );
}

class SmPpPayable {
  const SmPpPayable({
    required this.payableId,
    required this.orderId,
    required this.partnerKey,
    required this.status,
    this.companyName = '',
    this.slotDate = '',
    this.blockReason,
    this.goodsBasis = 0,
    this.commissionBp,
    this.commission,
    this.amount,
    this.method,
    this.clawback = false,
    this.reverseReason,
  });
  final String payableId;
  final String orderId;
  final String partnerKey;
  final String status;
  final String companyName;
  final String slotDate;
  final String? blockReason;
  final int goodsBasis;
  final int? commissionBp;
  final int? commission;
  final int? amount;
  final String? method;
  final bool clawback;
  final String? reverseReason;

  bool get payable => status == 'accrued' && (amount ?? 0) > 0;
  bool get reversible => (status == 'accrued' || status == 'paid') && (amount ?? 0) > 0;

  factory SmPpPayable.fromMap(Map m) => SmPpPayable(
        payableId: _s(m['payableId']),
        orderId: _s(m['orderId']),
        partnerKey: _s(m['partnerKey']),
        status: _s(m['status']),
        companyName: _s(m['companyName']),
        slotDate: _s(m['slotDate']),
        blockReason: m['blockReason'] == null ? null : _s(m['blockReason']),
        goodsBasis: _i(m['goodsBasis']),
        commissionBp: _iN(m['commissionBp']),
        commission: _iN(m['commission']),
        amount: _iN(m['amount']),
        method: m['method'] == null ? null : _s(m['method']),
        clawback: m['clawback'] == true,
        reverseReason: m['reverseReason'] == null ? null : _s(m['reverseReason']),
      );
}

class SmPpPayment {
  const SmPpPayment({required this.paymentId, required this.amount, required this.method, this.reference = '', this.count = 0, this.createdAtMs});
  final String paymentId;
  final int amount;
  final String method;
  final String reference;
  final int count;
  final int? createdAtMs;

  factory SmPpPayment.fromMap(Map m) => SmPpPayment(
        paymentId: _s(m['paymentId']),
        amount: _i(m['amount']),
        method: _s(m['method']),
        reference: _s(m['reference']),
        count: _i(m['count']),
        createdAtMs: _iN(m['createdAtMs']),
      );
}

class SmPpList {
  const SmPpList({required this.settings, this.partners = const [], this.blocked = const [], this.payables = const [], this.payments = const []});
  final SmPpSettings settings;
  final List<SmPpPartner> partners;
  final List<SmPpPayable> blocked;
  final List<SmPpPayable> payables;
  final List<SmPpPayment> payments;

  static List<T> _list<T>(Object? v, T Function(Map) f) => [for (final x in (v is List ? v : const [])) if (x is Map) f(x)];

  factory SmPpList.fromMap(Map m) => SmPpList(
        settings: SmPpSettings.fromMap(m['settings'] is Map ? m['settings'] as Map : const {}),
        partners: _list(m['partners'], SmPpPartner.fromMap),
        blocked: _list(m['blocked'], SmPpPayable.fromMap),
        payables: _list(m['payables'], SmPpPayable.fromMap),
        payments: _list(m['payments'], SmPpPayment.fromMap),
      );
}

/// «12.5» → 1250 базис пункт (соф, float йўқ). 0..100 %, кўпи билан 2 каср; бўш/нотўғри → null.
int? smPercentTextToBp(String text) {
  final t = text.trim().replaceAll(',', '.');
  final m = RegExp(r'^(\d{1,3})(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final bp = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
  return bp <= 10000 ? bp : null;
}

/// 1250 → «12.5» (соф).
String smBpToPercent(int bp) {
  final f = (bp % 100).toString().padLeft(2, '0');
  return bp % 100 == 0 ? '${bp ~/ 100}' : '${bp ~/ 100}.${f.endsWith('0') ? f.substring(0, 1) : f}';
}

/// Блок сабаби → админ Кирилл матни.
String smPpBlockReasonText(String? r) => switch (r) {
      'RULE_NOT_SET' => 'Комиссия қоидаси белгиланмаган',
      'WEIGH_PENDING' => 'Тортилмаган маҳсулот бор (етказилган)',
      'SELLER_UNKNOWN' => 'Ҳамкор (сотувчи) аниқланмади',
      _ => r ?? '',
    };

String smPpStatusText(String s) => switch (s) {
      'accrued' => 'Тўланиши керак',
      'paid' => 'Тўланди',
      'reversed' => 'Қайтарилди',
      'blocked' => 'Кутилмоқда',
      'nothing_due' => 'Тўлов йўқ',
      'void' => 'Бекор',
      _ => s,
    };

String smPpMethodText(String? m) => switch (m) {
      'cash' => 'Нақд',
      'bank_transfer' => 'Банк ўтказмаси',
      'offset' => 'Қайтарилган қарзга ҳисоб (offset)',
      _ => m ?? '',
    };

class AdminSmPartnerPayoutService {
  AdminSmPartnerPayoutService({FirebaseFunctions? functions}) : _fnsOverride = functions;
  final FirebaseFunctions? _fnsOverride;
  FirebaseFunctions get _fns => _fnsOverride ?? FirebaseFunctions.instance;

  Future<SmPpSettings> loadSettings() async => SmPpSettings.fromMap(await _call('adminGetSmPartnerPayoutSettings', const {}));

  /// [commissionBp] null — «белгиланмаган» (сервер қарзни ҳисобламайди). [setBp] false — комиссияга тегилмайди.
  Future<Map<String, dynamic>> saveSettings({required String stage, int? commissionBp, bool setBp = true, required String reason}) =>
      _call('adminSetSmPartnerPayoutSettings', {'stage': stage, if (setBp) 'commissionBp': commissionBp, 'reason': reason});

  Future<SmPpList> list({String? partnerKey}) async =>
      SmPpList.fromMap(await _call('adminListSmPartnerPayables', {if (partnerKey != null) 'partnerKey': partnerKey}));

  Future<Map<String, dynamic>> markPaid({
    required String partnerKey,
    required List<String> payableIds,
    required String method,
    required String clientRequestId,
    String reference = '',
  }) =>
      _call('adminMarkSmPartnerPaid', {
        'partnerKey': partnerKey,
        'payableIds': payableIds,
        'method': method,
        'clientRequestId': clientRequestId,
        if (reference.trim().isNotEmpty) 'reference': reference.trim(),
      });

  Future<Map<String, dynamic>> reverse(String payableId, String reason) =>
      _call('adminReverseSmPartnerPayable', {'payableId': payableId, 'reason': reason});

  Future<Map<String, dynamic>> recompute({required String from, required String to}) =>
      _call('adminRecomputeSmPartnerPayables', {'from': from, 'to': to}, timeout: const Duration(seconds: 540));

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data, {Duration? timeout}) async {
    try {
      final r = await _fns
          .httpsCallable(name, options: timeout == null ? null : HttpsCallableOptions(timeout: timeout))
          .call<Object?>(data);
      return r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw AdminSupermarketException(smAdminErrorText(name, e.code, e.details));
    }
  }
}

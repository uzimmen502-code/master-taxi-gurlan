// Улгуржи буюртма занжири, 5-босқич (админ) — СОФ мантиқ (Firestore'сиз, тестланади).
//
//   • буюртма ҳужжати (`wholesale_orders/{id}`) → админ кўриниши, «муаммоли» белгилари;
//   • AVA улуши: фоиз матни ↔ bps (0..30 % — сервер `AVA_FEE_BPS_MAX = 3000` билан бир хил);
//   • дарвоза ҳолати (`adminGetWholesaleOrdersStage` жавоби).
//
// Ҳамма ҳисоб ва рухсат СЕРВЕРДА (18, 44-банд); бу ерда фақат кўрсатиш ва ақлли текширув.

import '../../logistics/domain/tariff_adjust.dart' show bpsToPercentText;

// ─── Буюртма ҳолатлари ─────────────────────────────────────────────────

/// Сервер ҳолатлари (`functions_demand/core/wholesale_orders.js` `STATUS`; карта
/// занжири ҳолатлари — 3b, параллел агент, 2026-10-31). Номаълум ҳолат ҳам кўрсатилади.
const kWholesaleOrderStatusLabels = <String, String>{
  'placed': 'Берилди',
  'in_delivery': 'Етказилмоқда',
  'delivered': 'Етказилди',
  'cancelled': 'Бекор қилинди',
  'refused': 'Харидор рад этди',
  'payment_dispute': 'Тўлов низоси',
  'returning': 'Сотувчига қайтмоқда',
  'returned': 'Сотувчига қайтди',
};

/// Филтр калитлари: '' — ҳаммаси, `problem` — муаммоли, қолгани — ҳолат.
const kWholesaleOrderFilters = <String, String>{
  '': 'Ҳаммаси',
  'problem': '⚠ Муаммоли',
  'payment_dispute': 'Тўлов низоси',
  'placed': 'Берилди',
  'in_delivery': 'Етказилмоқда',
  'delivered': 'Етказилди',
  'cancelled': 'Бекор қилинди',
  'refused': 'Рад этилди',
  'returning': 'Қайтмоқда',
  'returned': 'Қайтди',
};

/// To'lov usuli (`order.paymentMethod`; yo'q = hamyon — server `methodOf` bilan bir xil).
const kWholesaleCardMethod = 'card_on_delivery';

int? _int(Object? v) => v is num ? v.toInt() : null;

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : null;

String _str(Object? v) => v == null ? '' : v.toString();

/// Firestore `Timestamp` / `DateTime` / millis → `DateTime` (Firestore импортисиз).
DateTime? wholesaleTimeOf(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  try {
    final d = (v as dynamic).toDate();
    if (d is DateTime) return d;
  } catch (_) {}
  return null;
}

/// Админ кўриши учун «муаммо» (код — сервер ёзгани, матн — қисқа изоҳ).
class WholesaleOrderProblem {
  const WholesaleOrderProblem(this.kind, this.text);

  /// `ship_fund` | `release` | `shipment` | `dispute` | `return_debt`.
  final String kind;
  final String text;
}

class WholesaleOrderAdminView {
  const WholesaleOrderAdminView({
    required this.id,
    required this.status,
    required this.paymentMethod,
    required this.buyerId,
    required this.sellerId,
    required this.productTitle,
    required this.packLabel,
    required this.qty,
    required this.unitPrice,
    required this.goodsTotal,
    required this.deliveryFee,
    required this.total,
    required this.paymentStatus,
    required this.refundStatus,
    required this.trackingNumber,
    required this.shipmentId,
    required this.tariffVersion,
    required this.zone,
    required this.createdAt,
    required this.updatedAt,
    required this.cardPayment,
    required this.returnDebt,
    required this.shipFundAnomaly,
    required this.releaseAnomaly,
    required this.shipmentError,
    required this.historySeq,
  });

  final String id;
  final String status;

  /// `wallet` | `card_on_delivery` (йўқ — `wallet`).
  final String paymentMethod;
  final String buyerId;
  final String sellerId;
  final String productTitle;
  final String packLabel;
  final int? qty;
  final int? unitPrice;
  final int? goodsTotal;
  final int? deliveryFee;
  final int? total;
  final String paymentStatus;
  final String refundStatus;
  final String trackingNumber;
  final String shipmentId;
  final int? tariffVersion;
  final String zone;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// `{status, receiptPath, submittedAt, confirmedAt}` (карта занжири) ёки `null`.
  final Map<String, dynamic>? cardPayment;

  /// `{amount, at}` ёки `null`.
  final Map<String, dynamic>? returnDebt;
  final Map<String, dynamic>? shipFundAnomaly;
  final Map<String, dynamic>? releaseAnomaly;

  /// `{code, at, attempts, final}` ёки `null`.
  final Map<String, dynamic>? shipmentError;
  final int? historySeq;

  bool get isCard => paymentMethod == kWholesaleCardMethod;
  String get statusLabel => kWholesaleOrderStatusLabels[status] ?? status;
  String get cardStatus => _str(cardPayment?['status']);
  String get receiptPath => _str(cardPayment?['receiptPath']);
  int? get returnDebtAmount => _int(returnDebt?['amount']);
  bool get shipmentErrorFinal => shipmentError?['final'] == true;

  /// Тўлов низоси — админ қарори керак (`adminResolveWholesaleCardDispute`).
  bool get needsDisputeDecision => status == 'payment_dispute';

  static WholesaleOrderAdminView fromMap(String id, Map<String, dynamic> d) {
    final payment = _map(d['payment']);
    final shipment = _map(d['shipment']);
    final delivery = _map(d['delivery']);
    final method = _str(d['paymentMethod']);
    return WholesaleOrderAdminView(
      id: id,
      status: _str(d['status']),
      paymentMethod: method == kWholesaleCardMethod ? kWholesaleCardMethod : 'wallet',
      buyerId: _str(d['buyerId']),
      sellerId: _str(d['sellerId']),
      productTitle: _str(d['productTitle']),
      packLabel: _str(d['packLabel']),
      qty: _int(d['qty']),
      unitPrice: _int(d['unitPrice']),
      goodsTotal: _int(d['goodsTotal']),
      deliveryFee: _int(d['deliveryFee']),
      total: _int(d['total']),
      paymentStatus: _str(payment?['status']),
      refundStatus: _str(d['refundStatus']),
      trackingNumber: _str(shipment?['trackingNumber']),
      shipmentId: _str(shipment?['shipmentId']),
      tariffVersion: _int(delivery?['tariffVersion']),
      zone: _str(delivery?['zone']),
      createdAt: wholesaleTimeOf(d['createdAt']),
      updatedAt: wholesaleTimeOf(d['updatedAt']),
      cardPayment: _map(d['cardPayment']),
      returnDebt: _map(d['returnDebt']),
      shipFundAnomaly: _map(d['shipFundAnomaly']),
      releaseAnomaly: _map(d['releaseAnomaly']),
      shipmentError: _map(d['shipmentError']),
      historySeq: _int(d['historySeq']),
    );
  }

  /// «Муаммоли» белгилари. `shipmentError` — фақат `final: true` (5 уринишдан кейин
  /// reconcile тўхтайди, админ керак); ҳали қайта уринилаётгани муаммо эмас, лекин
  /// карточкада алоҳида кўрсатилади.
  List<WholesaleOrderProblem> get problems {
    final out = <WholesaleOrderProblem>[];
    if (shipFundAnomaly != null) {
      out.add(WholesaleOrderProblem('ship_fund', 'Етказиш ҳақи escrow\'га ўтмади: ${_str(shipFundAnomaly!['code'])}'));
    }
    if (releaseAnomaly != null) {
      out.add(WholesaleOrderProblem('release', 'Товар пули сотувчига ўтмади: ${_str(releaseAnomaly!['code'])}'));
    }
    if (shipmentErrorFinal) {
      out.add(WholesaleOrderProblem(
        'shipment',
        'Жўнатма очилмади (${_int(shipmentError!['attempts']) ?? '?'} уриниш): ${_str(shipmentError!['code'])}',
      ));
    }
    if (needsDisputeDecision) out.add(const WholesaleOrderProblem('dispute', 'Тўлов низоси — қарор керак'));
    final debt = returnDebtAmount;
    if (returnDebt != null && (debt == null || debt > 0)) {
      out.add(WholesaleOrderProblem('return_debt', 'Қайтариш қарзи (сотувчи): ${debt == null ? '?' : wholesaleMoney(debt)} сўм'));
    }
    return out;
  }

  bool get hasProblem => problems.isNotEmpty;

  /// Филтр: '' — ҳаммаси, `problem` — муаммоли, акс ҳолда ҳолат тенглиги.
  bool matchesFilter(String filter) {
    if (filter.isEmpty) return true;
    if (filter == 'problem') return hasProblem;
    return status == filter;
  }
}

/// `125000` → «125 000» (бутун сўм).
String wholesaleMoney(int v) {
  final neg = v < 0;
  final s = (neg ? -v : v).toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i += 1) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${neg ? '−' : ''}$buf';
}

// ─── AVA улуши (bps ↔ %) ───────────────────────────────────────────────

/// Сервер чегараси: `functions_demand/api/wholesale_orders.js` `AVA_FEE_BPS_MAX` (30 %).
const int kWholesaleFeeBpsMax = 3000;

class WholesaleFeeCurrent {
  const WholesaleFeeCurrent({this.avaFeeBps, this.feeVersion = 0, this.exists = false});

  /// `null` — ҳужжат йўқ (сервер 0 деб ҳисоблайди: `readFeeSettings`).
  final int? avaFeeBps;
  final int feeVersion;
  final bool exists;

  /// Сервер `readFeeSettings` каби: ҳужжат йўқ ёки майдон йўқ — 0 bps.
  int get effectiveBps => avaFeeBps ?? 0;

  static WholesaleFeeCurrent fromDoc(Map<String, dynamic>? d) {
    if (d == null) return const WholesaleFeeCurrent();
    return WholesaleFeeCurrent(
      avaFeeBps: _int(d['avaFeeBps']),
      feeVersion: _int(d['feeVersion']) ?? 0,
      exists: true,
    );
  }
}

/// Фоиз матни → bps. Фақат 0..30 ва нуқтадан кейин кўпи билан 2 хона («2», «2,5»,
/// «12.75»); бошқа ҳолда `null` (яхлитлаб юборилмайди — админ кўрганини юборамиз).
int? wholesaleFeePercentToBps(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,2}(\.\d{1,2})?$').hasMatch(t)) return null;
  final parts = t.split('.');
  final whole = int.parse(parts[0]);
  final frac = parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0;
  final bps = whole * 100 + frac;
  if (bps < 0 || bps > kWholesaleFeeBpsMax) return null;
  return bps;
}

String wholesaleFeeBpsToPercent(int bps) => bpsToPercentText(bps);

class WholesaleFeePlan {
  const WholesaleFeePlan({this.bps, this.error, this.unchanged = false});

  final int? bps;
  final String? error;
  final bool unchanged;
}

WholesaleFeePlan planWholesaleFee(String text, WholesaleFeeCurrent current) {
  final bps = wholesaleFeePercentToBps(text);
  if (bps == null) {
    return const WholesaleFeePlan(error: 'AVA улуши: 0..30 % (масалан 2 ёки 2,5; кўпи билан 2 ўнли хона)');
  }
  if (current.exists && current.avaFeeBps == bps) return WholesaleFeePlan(bps: bps, unchanged: true);
  return WholesaleFeePlan(bps: bps);
}

// ─── Дарвоза ───────────────────────────────────────────────────────────

const kWholesaleStages = <String>['off', 'internal', 'pilot', 'public'];

const kWholesaleStageLabels = <String, String>{
  'off': 'OFF — ҳеч ким (тестчилар ҳам)',
  'internal': 'INTERNAL — фақат тестчилар',
  'pilot': 'PILOT — фақат тестчилар (сервер ҳозир INTERNAL каби)',
  'public': 'PUBLIC — ҳамма',
};

class WholesaleGateState {
  const WholesaleGateState({
    required this.exists,
    required this.enabled,
    required this.stage,
    required this.testerIds,
    required this.globalEnabled,
    required this.effectiveOpen,
    this.updatedAt,
    this.updatedBy,
  });

  final bool exists;
  final bool enabled;
  final String stage;
  final List<String> testerIds;
  final bool globalEnabled;
  final bool effectiveOpen;
  final DateTime? updatedAt;
  final String? updatedBy;

  static WholesaleGateState fromMap(Map<String, dynamic> m) {
    final s = m['stage'];
    final raw = m['testerIds'];
    final ms = _int(m['updatedAtMs']);
    return WholesaleGateState(
      exists: m['exists'] == true,
      enabled: m['enabled'] == true,
      stage: s is String && kWholesaleStages.contains(s) ? s : 'internal',
      testerIds: raw is List ? [for (final e in raw) e.toString()] : const [],
      globalEnabled: m['globalEnabled'] != false,
      effectiveOpen: m['effectiveOpen'] == true,
      updatedAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      updatedBy: m['updatedBy'] is String ? m['updatedBy'] as String : null,
    );
  }
}

class WholesaleGateChange {
  const WholesaleGateChange({
    required this.unchanged,
    required this.created,
    required this.enabled,
    required this.stage,
    required this.testerCount,
    required this.added,
    required this.removed,
  });

  final bool unchanged;
  final bool created;
  final bool enabled;
  final String stage;
  final int testerCount;
  final int added;
  final int removed;

  static WholesaleGateChange fromMap(Map<String, dynamic> m) => WholesaleGateChange(
        unchanged: m['unchanged'] == true,
        created: m['created'] == true,
        enabled: m['enabled'] == true,
        stage: _str(m['stage']),
        testerCount: _int(m['testerCount']) ?? 0,
        added: _int(m['added']) ?? 0,
        removed: _int(m['removed']) ?? 0,
      );
}

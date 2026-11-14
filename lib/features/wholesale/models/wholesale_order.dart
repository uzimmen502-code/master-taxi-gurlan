import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart' show canonicalPhoneId;
import 'wholesale_quote.dart' show WholesaleDeliveryMethod, WholesaleDeliveryPaymentMethod;

// S57: нақд етказиш константаси квота моделида; эски импортлар (`wholesale_order.dart`) учун қайта экспорт.
export 'wholesale_quote.dart' show WholesaleDeliveryPaymentMethod;

/// Улгуржи буюртма ҳолатлари — сервер state machine'и билан бир хил
/// (`functions_demand/core/wholesale_orders.js` `STATUS` + 3b қўшимчалари).
///
/// Илова ҳолатни ЎЗГАРТИРМАЙДИ — фақат кўрсатади (CLAUDE.md 17/44). Ўтишни
/// сервер текширади; бу ердаги қоидалар фақат қайси тугма КЎРИНИШИНИ
/// белгилайди (сервер барибир рад этиши мумкин).
abstract final class WholesaleOrderStatus {
  static const placed = 'placed';
  static const inDelivery = 'in_delivery';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';

  /// 3b (эга, 2026-10-31): харидор эшик олдида рад этди → товар қайтади.
  static const refused = 'refused';
  static const returning = 'returning';
  static const returned = 'returned';

  /// 3b: карта тўлови бўйича низо — админ кўриб чиқади (5-босқич).
  static const paymentDispute = 'payment_dispute';

  /// Якуний: чиқиш посилкаси йўқолди (курьер сотувчига тўлайди; ҳамён буюртмасида
  /// товар пули харидорга автоматик қайтади).
  static const lost = 'lost';

  static const known = {
    placed,
    inDelivery,
    delivered,
    cancelled,
    refused,
    returning,
    returned,
    paymentDispute,
    lost,
  };

  /// Ҳолат матни калити (3 тилда). Номаълум ҳолат — умумий «янгиланмоқда».
  static String l10nKey(String status) => known.contains(status)
      ? 'wholesale_order_status_$status'
      : 'wholesale_order_status_unknown';
}

abstract final class WholesalePaymentMethod {
  static const wallet = 'wallet';

  /// 3b: етказилганда сотувчи картасига.
  static const cardOnDelivery = 'card_on_delivery';

  /// Банк ўтказмаси (эга, 2026-11-13/14): товар пули ИЛОВАДАН ТАШҚАРИДА (ҳисоб-фактура),
  /// иловада фақат етказиш ҳақи — харидор ҳамёнидан ушланади.
  static const bankTransfer = 'bank_transfer';
}

/// `bankPayment.status` (сервер `BANK_PAYMENT`). Майдон йўқ — банк буюртмаси
/// эмас ёки сотувчи ҳали қабул қилмаган.
abstract final class WholesaleBankPaymentStatus {
  static const awaiting = 'awaiting';
  static const confirmed = 'confirmed';
  static const timeout = 'timeout';
  static const cancelled = 'cancelled';
}

/// S4: `order.selfDelivery.status` (сервер `SELF_STATUS`).
abstract final class WholesaleSelfStatus {
  static const pending = 'pending';
  static const inDelivery = 'in_delivery';
  static const completed = 'completed';
  static const refused = 'refused';
  static const returned = 'returned';
}

/// 3b: `cardPayment.status`.
abstract final class WholesaleCardPaymentStatus {
  static const awaiting = 'awaiting';
  static const receiptSubmitted = 'receipt_submitted';
  static const confirmed = 'confirmed';

  /// Чек 30 дақиқада тасдиқланмади — буюртма payment_dispute да (админ ҳал қилади).
  static const disputed = 'disputed';
}

/// 3b: рад этилган буюртманинг қайтиш жараёни (order.returnStatus).
abstract final class WholesaleReturnStatus {
  static const pendingShipment = 'pending_shipment';
  static const awaitingPayment = 'awaiting_payment';
  static const inTransit = 'in_transit';
  static const returned = 'returned';

  static const known = {pendingShipment, awaitingPayment, inTransit, returned};

  /// Матн калити; номаълум/бўш — `null` (кўрсатилмайди).
  static String? l10nKey(String s) => known.contains(s) ? 'wholesale_return_status_$s' : null;
}

/// «Етказилмади» харидор тасдиғи билан (эга қарори 2026-11-01; сервер
/// `functions_demand/api/wholesale_failed.js`). Курьер белгилайди — ҳолат ва пул
/// ЎЗГАРМАЙДИ; харидор тасдиқлайди ёки «Олмоқчиман» дейди; муддат ўтса сотувчи
/// (захира — админ) ҳал қилади. Ҳаммаси серверда — бу ерда фақат кўрсатиш.
class WholesaleDeliveryFailed {
  const WholesaleDeliveryFailed({
    this.pending = false,
    this.seq = 0,
    this.reasonCode = '',
    this.escalateAt,
    this.escalated = false,
    this.resolutionBy = '',
    this.resolutionDecision = '',
    this.cashPaid,
    this.cashTotal = 0,
  });

  static const none = WholesaleDeliveryFailed();

  /// S57 нақд: курьер белгиси — харидор эшик олдида етказиш + қайтариш ҳақини тўладими
  /// (`deliveryFailed.cash.paid`); нақд бўлмаса `null`. [cashTotal] — сервер ҳисоблаган жами (сўм).
  final bool? cashPaid;
  final int cashTotal;

  /// Сўров очиқ (`deliveryFailed.open == true` ва буюртма етказилмоқда).
  final bool pending;
  final int seq;

  /// customer_absent | customer_refused | courier_problem | other.
  final String reasonCode;

  /// Шу вақтгача харидор жавоб беради, кейин қарор сотувчи/админда.
  final DateTime? escalateAt;

  /// Муддат ўтди — сервер қарорни сотувчи/админга ўтказди.
  final bool escalated;
  final String resolutionBy;

  /// failed | continue | superseded (бўш — ҳали қарор йўқ).
  final String resolutionDecision;

  /// Сотувчи/админ қарор қила оладими (сервер ҳам текширади: `decision_not_yet`).
  bool canDecide(DateTime now) => pending && (escalated || (escalateAt != null && !now.isBefore(escalateAt!)));

  factory WholesaleDeliveryFailed.fromOrder(Map<String, dynamic> d) {
    final raw = d['deliveryFailed'];
    if (raw is! Map) return none;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final res = m['resolution'] is Map ? (m['resolution'] as Map) : const {};
    final esc = m['escalateAt'];
    final cash = m['cash'] is Map ? (m['cash'] as Map) : const {};
    return WholesaleDeliveryFailed(
      cashPaid: cash['paid'] is bool ? cash['paid'] as bool : null,
      cashTotal: cash['total'] is num ? (cash['total'] as num).toInt() : 0,
      pending: m['open'] == true && d['status'] == WholesaleOrderStatus.inDelivery,
      seq: m['seq'] is num ? (m['seq'] as num).toInt() : 0,
      reasonCode: m['reasonCode'] is String ? m['reasonCode'] as String : '',
      escalateAt: esc is Timestamp ? esc.toDate() : (esc is DateTime ? esc : null),
      escalated: m['escalatedAt'] != null,
      resolutionBy: res['by'] is String ? res['by'] as String : '',
      resolutionDecision: res['decision'] is String ? res['decision'] as String : '',
    );
  }
}

/// Курьер «етказилмади» жавоби / ҳолати (`markWholesaleBuyerRefused`,
/// `getWholesaleDeliveryFailedState`). Майдон йўқ (эски сервер) — кутиш йўқ.
class WholesaleDeliveryFailedReport {
  const WholesaleDeliveryFailedReport({
    this.status = '',
    this.pending = false,
    this.stage = '',
    this.escalateAt,
    this.resolutionDecision = '',
    this.paymentMethod = '',
    this.allowedReasons = const [],
    this.deliveryPaymentMethod = '',
    this.cashToCollect,
    this.cashDueDeliveryFee = 0,
    this.cashDueReturnFee = 0,
    this.cashDueTotal = 0,
    this.cashPaid,
  });

  /// S57 нақд (`getWholesaleDeliveryFailedState`): `deliveryPaymentMethod == 'cash'` ва курьер
  /// эшик олдида оладиган суммалар — ҲАММАСИ СЕРВЕРДАН (илова ҳисобламайди):
  ///   [cashToCollect] — етказилса харидордан олинадиган етказиш ҳақи;
  ///   [cashDueTotal]  — рад этилса: етказиш ([cashDueDeliveryFee]) + қайтариш ([cashDueReturnFee]).
  /// `markWholesaleBuyerRefused` жавоби ҳам `cashDue` ва `cashPaid` беради.
  final String deliveryPaymentMethod;
  final int? cashToCollect;
  final int cashDueDeliveryFee;
  final int cashDueReturnFee;
  final int cashDueTotal;
  final bool? cashPaid;

  /// Нақд буюртма: жавобда `deliveryPaymentMethod: cash` ёки `cashDue` бор.
  bool get isCashOrder => deliveryPaymentMethod == WholesaleDeliveryPaymentMethod.cash || cashDueTotal > 0;

  /// Буюртма ҳолати (`in_delivery`; эски сервер дарҳол `refused` қайтарарди).
  final String status;
  final bool pending;

  /// awaiting_buyer | awaiting_decision.
  final String stage;
  final DateTime? escalateAt;
  final String resolutionDecision;

  /// 2026-11-01: `getWholesaleDeliveryFailedState` — тўлов усули ва курьер танлай оладиган сабаблар
  /// (ҳамён буюртмасида «бошқа» йўқ). Эски серверда бўш — барча сабаблар кўрсатилади.
  final String paymentMethod;
  final List<String> allowedReasons;

  bool get awaitingDecision => pending && stage == 'awaiting_decision';
  bool get continued => !pending && resolutionDecision == 'continue';
  /// Етказиш ҳақини харидор ҳамёндан тўлаганми — ҳамён ВА банк ўтказмаси (сервер
  /// `deliveryPaidByBuyer`: банк буюртмаси «етказилмади»да ҳамён қоидалари билан).
  /// S6 янги карта (`deliveryPaidBy: buyer`) ҳам шу қоидада — сервер унга ҳамён сабаблари
  /// рўйхатини беради («бошқа» йўқ), тўлов усули эса `card_on_delivery` қолади.
  /// S57 нақд буюртма бу қоидадан ТАШҚАРИДА (ҳақ ҳамёнда эмас — алоҳида огоҳлантириш).
  bool get isWalletOrder =>
      !isCashOrder &&
      (paymentMethod == WholesalePaymentMethod.wallet ||
          paymentMethod == WholesalePaymentMethod.bankTransfer ||
          (allowedReasons.isNotEmpty && !allowedReasons.contains('other')));

  /// Курьер ойнасидаги сабаблар: сервер рўйхати (маълум кодлар тартибида), бўлмаса — ҳаммаси.
  /// Нақд буюртмада фақат харидор сабаблари (эга, 2026-11-14: «курьер муаммоси» йўқ; сервер
  /// `reason_not_allowed_cash` билан ҳам рад этади) — сервер рўйхати бўлмаса ҳам.
  List<String> get reasons {
    final known = wholesaleDeliveryFailedReasons.where(allowedReasons.contains).toList();
    final list = known.isEmpty ? wholesaleDeliveryFailedReasons : known;
    if (!isCashOrder) return list;
    return list.where(wholesaleCashDeliveryFailedReasons.contains).toList();
  }

  factory WholesaleDeliveryFailedReport.fromMap(Map<String, dynamic> d) {
    final ms = d['escalateAtMs'];
    final res = d['resolution'] is Map ? d['resolution'] as Map : const {};
    final pending = d['pending'] == true || d['awaitingBuyer'] == true || d['stage'] == 'awaiting_decision';
    final allowed = d['allowedReasons'];
    final due = d['cashDue'] is Map ? d['cashDue'] as Map : const {};
    int n(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
    return WholesaleDeliveryFailedReport(
      deliveryPaymentMethod: d['deliveryPaymentMethod'] is String ? d['deliveryPaymentMethod'] as String : '',
      cashToCollect: d['cashToCollect'] is num ? (d['cashToCollect'] as num).toInt() : null,
      cashDueDeliveryFee: n(due['deliveryFee']),
      cashDueReturnFee: n(due['returnFee']),
      cashDueTotal: n(due['total']),
      cashPaid: d['cashPaid'] is bool ? d['cashPaid'] as bool : null,
      status: d['status'] is String ? d['status'] as String : '',
      pending: pending,
      stage: d['stage'] is String ? d['stage'] as String : '',
      escalateAt: ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null,
      resolutionDecision: res['decision'] is String ? res['decision'] as String : '',
      paymentMethod: d['paymentMethod'] is String ? d['paymentMethod'] as String : '',
      allowedReasons: allowed is List ? allowed.whereType<String>().toList() : const [],
    );
  }
}

/// Админ рўйхати элементи (`listWholesaleDeliveryFailedPending`) — телефон йўқ, фақат охирги 4 рақам.
class WholesaleDeliveryFailedItem {
  const WholesaleDeliveryFailedItem({
    required this.orderId,
    this.productTitle = '',
    this.qty,
    this.total,
    this.stage = '',
    this.reasonCode = 'other',
    this.escalateAt,
    this.canDecide = false,
    this.buyerTail = '',
    this.sellerTail = '',
    this.courierTail = '',
  });

  final String orderId;
  final String productTitle;
  final int? qty;
  final int? total;
  final String stage;
  final String reasonCode;
  final DateTime? escalateAt;
  final bool canDecide;
  final String buyerTail;
  final String sellerTail;
  final String courierTail;

  static WholesaleDeliveryFailedItem? fromMap(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k] is String ? (raw[k] as String).trim() : '';
    int? n(String k) => raw[k] is num ? (raw[k] as num).toInt() : null;
    final id = s('orderId');
    if (id.isEmpty) return null;
    final ms = n('escalateAtMs');
    return WholesaleDeliveryFailedItem(
      orderId: id,
      productTitle: s('productTitle'),
      qty: n('qty'),
      total: n('total'),
      stage: s('stage'),
      reasonCode: s('reasonCode').isEmpty ? 'other' : s('reasonCode'),
      escalateAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      canDecide: raw['canDecide'] == true,
      buyerTail: s('buyerTail'),
      sellerTail: s('sellerTail'),
      courierTail: s('courierTail'),
    );
  }

  static List<WholesaleDeliveryFailedItem> listFrom(Object? raw) {
    if (raw is! List) return const [];
    final seen = <String>{};
    final out = <WholesaleDeliveryFailedItem>[];
    for (final e in raw) {
      final it = fromMap(e);
      if (it != null && seen.add(it.orderId)) out.add(it);
    }
    return out;
  }
}

/// Курьер сабаби → матн калити (курьер панелидаги мавжуд калитлар; номаълум — «бошқа»).
String wholesaleDeliveryFailedReasonKey(String code) => switch (code) {
      'customer_absent' || 'customer_refused' || 'courier_problem' => 'restaurants_courier_fail_$code',
      _ => 'restaurants_courier_fail_other',
    };

/// Сервер сабаб кодлари (`functions_demand/api/wholesale_failed.js` REASONS).
const wholesaleDeliveryFailedReasons = ['customer_absent', 'customer_refused', 'courier_problem', 'other'];

/// S57 нақд етказиш сабаблари (сервер `CASH_REASONS`): фақат харидор сабаби.
const wholesaleCashDeliveryFailedReasons = ['customer_absent', 'customer_refused'];

/// `wholesale_orders/{id}` — фақат ўқиш (Rules: харидор/сотувчи/админ;
/// клиент ёзолмайди). Эски/тўлиқсиз ҳужжатда майдон бўлмаса — хавфсиз
/// стандарт қиймат (26-банд).
class WholesaleOrder {
  const WholesaleOrder({
    required this.id,
    required this.buyerId,
    required this.sellerId,
    required this.productId,
    required this.productTitle,
    required this.packId,
    required this.packLabel,
    required this.qty,
    required this.unitPrice,
    required this.goodsTotal,
    required this.deliveryFee,
    required this.total,
    required this.status,
    this.paymentMethod = WholesalePaymentMethod.wallet,
    this.cardPaymentStatus = '',
    this.receiptPath = '',
    this.receiptUrl = '',
    this.trackingNumber = '',
    this.shipmentId = '',
    this.destinationText = '',
    this.returnDebt = 0,
    this.returnStatus = '',
    this.returnTrackingNumber = '',
    this.paymentStatus = '',
    this.lostRefunded = 0,
    this.lostRefundTo = '',
    this.lostReview = false,
    this.deliveryFailed = WholesaleDeliveryFailed.none,
    this.returnDebtPayer = '',
    this.walletRefusalFault = '',
    this.walletRefundGoods = 0,
    this.walletReturnFeeCharged = 0,
    this.createdAt,
    this.sellerDecision = '',
    this.acceptDeadlineAt,
    this.cancelReason = '',
    this.bankPaymentStatus = '',
    this.bankPayDeadlineAt,
    this.deliveryMethod = WholesaleDeliveryMethod.avaCourier,
    this.deliveryPaidBy = '',
    this.selfStatus = '',
    this.selfDropoff = '',
    this.refundStatus = '',
    this.deliveryPaymentMethod = WholesaleDeliveryPaymentMethod.wallet,
    this.cashDeliveryAmount = 0,
    this.cashRefusalPaid,
    this.cashRefusalTotal = 0,
    this.returnDebtKind = '',
    this.returnDebtStatus = '',
  });

  /// S57 (эга, 2026-11-14): етказиш ҳақини тўлаш усули — `wallet` (майдон йўқ — эски) | `cash`.
  final String deliveryPaymentMethod;

  /// `cashDelivery.amount` — курьер жўнатмаси очилгач сервер ёзган нақд сумма (0 — ҳали йўқ).
  final int cashDeliveryAmount;

  /// `cashRefusal{paid, total}` — рад этилган нақд буюртма: харидор курьерга тўладими ва жами.
  final bool? cashRefusalPaid;
  final int cashRefusalTotal;

  /// `returnDebt.kind` (`cash_refusal` — нақд рад, тўланмаган етказиш + қайтариш) ва `status` (`open`).
  final String returnDebtKind;
  final String returnDebtStatus;

  /// Етказиш ҳақи курьерга нақд (ўз етказишида ҳеч қачон).
  bool get isCashDelivery => !isSelf && deliveryPaymentMethod == WholesaleDeliveryPaymentMethod.cash;

  /// Эшик олдида курьерга нақд: сервер `cashDelivery.amount`, бўлмаса буюртманинг етказиш ҳақи.
  int get cashToCourierAmount => !isCashDelivery ? 0 : (cashDeliveryAmount > 0 ? cashDeliveryAmount : deliveryFee);

  /// Харидорнинг нақд рад қарзи (тўланмаган етказиш + қайтариш ҳақи).
  bool get hasBuyerCashDebt => returnDebt > 0 && returnDebtPayer == 'buyer' && returnDebtKind == 'cash_refusal';

  /// S4: `deliveryMethod` — `self` ёки `ava_courier` (майдон йўқ — эски буюртма, курьер).
  final String deliveryMethod;

  /// S6: `deliveryPaidBy` — `buyer` (янги карта буюртмаси: етказиш ҳақи ҳамёндан); бўш — эски.
  final String deliveryPaidBy;

  /// S4: `selfDelivery.status` ([WholesaleSelfStatus]) ва `selfDelivery.dropoff`.
  final String selfStatus;
  final String selfDropoff;

  /// `refundStatus` (`pending` | `done` | бўш) — рад/бекордан кейинги ҳисоб-китоб.
  final String refundStatus;

  /// S4: сотувчи ўзи етказади (курьер/кузатув йўқ).
  bool get isSelf => deliveryMethod == WholesaleDeliveryMethod.self;

  /// S6: янги карта — етказиш ҳақини харидор ҳамёндан тўлаган, эшик олдида ФАҚАТ товар.
  bool get isNewCard => isCardOrder && deliveryPaidBy == 'buyer';

  /// Эски карта (S6 дан олдин): харидор эшик олдида товар + етказишни тўлайди.
  bool get isLegacyCard => isCardOrder && !isNewCard && !isSelf;

  /// Харидор эшик олдида сотувчи картасига тўлайдиган сумма: янги карта — фақат товар,
  /// эски — товар + етказиш (ўз етказишида етказиш ҳақи 0, жами = товар).
  int get cardAtDoorAmount => isNewCard ? goodsTotal : total;

  /// Харидор ҳамёнидан фақат етказиш ҳақи ушланган (банк ёки янги карта, курьер билан).
  /// S57: нақд етказишда етказиш ҳақи ҳамёндан ушланмаган.
  bool get walletHeldDeliveryOnly => (isBankOrder || isNewCard) && !isSelf && !isCashDelivery && deliveryFee > 0;

  /// «Етказилмади»/рад: товар пули иловадан ташқарида, етказиш/қайтариш ҳақи — ҳамён айб
  /// қоидаси бўйича (банк ва янги карта; матнлар бир хил).
  bool get goodsOutsideWalletFeeRules => isBankOrder || isNewCard;

  /// Банк ўтказмаси: `bankPayment.status` ([WholesaleBankPaymentStatus]); бўш — қабулдан олдин
  /// ёки банк буюртмаси эмас.
  final String bankPaymentStatus;

  /// Сотувчи шу вақтгача «Пул тушди»ни босиши керак (қабул + 5 иш куни, сервер ҳисоблайди).
  final DateTime? bankPayDeadlineAt;

  bool get isBankOrder => paymentMethod == WholesalePaymentMethod.bankTransfer;
  bool get bankConfirmed => isBankOrder && bankPaymentStatus == WholesaleBankPaymentStatus.confirmed;

  /// Банк тўлови кутилмоқда: қабул қилинган, ҳали `placed`, сотувчи «Пул тушди» босмаган.
  bool get bankPaymentAwaiting =>
      isBankOrder &&
      status == WholesaleOrderStatus.placed &&
      sellerDecision == 'accepted' &&
      bankPaymentStatus == WholesaleBankPaymentStatus.awaiting;

  /// Сотувчи қарори (эга, 2026-11-13): `pending` | `accepted` | `rejected` | `timeout`;
  /// бўш — эски буюртма (қабул қадами бўлмаган, аввалгидек автоматик).
  final String sellerDecision;

  /// Сотувчи шу вақтгача жавоб бериши керак (2 иш куни, сервер ҳисоблайди).
  final DateTime? acceptDeadlineAt;

  /// Бекор сабаби: `seller_rejected` | `seller_timeout` | `bank_payment_timeout` | бўш (харидор/админ).
  final String cancelReason;

  /// Сотувчи жавобини кутяпти: ҳали `placed` ва қарор `pending`.
  bool get awaitingSellerDecision =>
      status == WholesaleOrderStatus.placed && sellerDecision == 'pending';

  final String id;
  final String buyerId;
  final String sellerId;
  final String productId;
  final String productTitle;
  final String packId;
  final String packLabel;
  final int qty;

  /// Пул — бутун сўм (8-банд). Ҳаммаси серверда ҳисобланган.
  final int unitPrice;
  final int goodsTotal;
  final int deliveryFee;
  final int total;
  final String status;
  final String paymentMethod;

  /// 3b: `cardPayment.status` (бўш — карта буюртмаси эмас ёки эски ҳужжат).
  final String cardPaymentStatus;

  /// 3b: харидор юклаган чек — Storage йўли ва/ёки URL (қайсиниси келса).
  final String receiptPath;
  final String receiptUrl;
  final String trackingNumber;
  final String shipmentId;
  final String destinationText;

  /// 3b: сотувчининг қайтариш қарзи (сўм) — `returnDebt: {amount, at, attempts}`;
  /// тўлангач сервер `null` қилади (0).
  final int returnDebt;

  /// 3b: `returnStatus` ([WholesaleReturnStatus]) ва қайтиш жўнатмаси рақами.
  final String returnStatus;
  final String returnTrackingNumber;

  /// `payment.status` (held | released | refunded_lost | lost_review ...).
  final String paymentStatus;

  /// Йўқолган посилка (`lost{refundTo, refunded, review}`): қайтарилган сумма,
  /// кимга (buyer | seller | бўш) ва админ кўриб чиқадими (`payment.status: lost_review`).
  final int lostRefunded;
  final String lostRefundTo;
  final bool lostReview;

  /// «Етказилмади» сўрови (2026-11-01).
  final WholesaleDeliveryFailed deliveryFailed;

  /// Қайтариш қарзи кимда (`returnDebt.payer`): бўш/`seller` — карта буюртмаси сотувчиси (аввалгидек);
  /// ҳамён буюртмасида — `buyer` ёки `courier` (эга, 2026-11-01).
  final String returnDebtPayer;

  /// Ҳамён буюртмаси рад этилгач (`walletRefusal`, сервер ҳисоблайди): айб (`buyer` | `courier`),
  /// ҳамёнга қайтган товар суммаси ва ушланган қайтариш ҳақи (сўм).
  final String walletRefusalFault;
  final int walletRefundGoods;
  final int walletReturnFeeCharged;
  final DateTime? createdAt;

  /// Харидорга ҳамён қайтими изоҳи калити (соф): товар суммаси қайтди (+ ушланган ҳақ ёки «курьер тўлайди»).
  String? walletRefundNoticeKey(String viewerId) {
    // Банк ўтказмаси (эга, 2026-11-14): товар пули иловадан ташқарида — қайтиш изоҳи йўқ.
    if (isCardOrder || isBankOrder || walletRefusalFault.isEmpty || walletRefundGoods <= 0 || !isBuyer(viewerId)) return null;
    return walletRefusalFault == 'courier' ? 'wholesale_order_wallet_refund_courier' : 'wholesale_order_wallet_refund';
  }

  /// Қайтиш жараёни матни калити: ҳамён буюртмасида қайтариш ҳақи кимдан кутилаётгани ҳам.
  String? returnStatusKey() {
    // S4: ўз етказиши — қайтиш жўнатмаси йўқ, товар сотувчининг ўзида.
    if (isSelf) {
      if (status == WholesaleOrderStatus.returned) return 'wholesale_return_status_returned';
      if (status == WholesaleOrderStatus.refused) return 'wholesale_self_return_pending';
    }
    // S6 янги карта ҳам ҳамён айб қоидаси билан (қарз харидор ёки курьерда).
    if (returnStatus == WholesaleReturnStatus.awaitingPayment && !isLegacyCard) {
      final payer = returnDebtPayer.isNotEmpty ? returnDebtPayer : walletRefusalFault;
      if (payer == 'buyer' || payer == 'courier') return 'wholesale_return_status_awaiting_payment_$payer';
    }
    return WholesaleReturnStatus.l10nKey(returnStatus);
  }

  /// S4: харидорга — сотувчи «харидор воз кечди» деб белгилагани (ҳамён: товар суммаси қайтади).
  String? selfRefusedNoticeKey(String viewerId) {
    if (!isSelf || !isBuyer(viewerId)) return null;
    if (status != WholesaleOrderStatus.refused && status != WholesaleOrderStatus.returned) return null;
    return paymentMethod == WholesalePaymentMethod.wallet
        ? 'wholesale_self_refused_buyer_wallet'
        : 'wholesale_self_refused_buyer';
  }

  /// S6 янги карта, харидор айби: қайтариш ҳақи ҳамёндан ушланди (сумма сервердан).
  String? cardReturnFeeNoticeKey(String viewerId) =>
      isNewCard && isBuyer(viewerId) && walletRefusalFault == 'buyer' && walletReturnFeeCharged > 0
          ? 'wholesale_order_card_return_fee_charged'
          : null;

  bool get isCardOrder => paymentMethod == WholesalePaymentMethod.cardOnDelivery;
  bool get cardConfirmed => cardPaymentStatus == WholesaleCardPaymentStatus.confirmed;

  /// Карта тўлови ҳали очиқ: сотувчи «Пул тушди» босмаган, низо йўқ ва буюртма
  /// ЕТКАЗИЛМОҚДА (сервер карта callable'ларини фақат `in_delivery` да қабул қилади).
  bool get cardPaymentOpen =>
      isCardOrder &&
      status == WholesaleOrderStatus.inDelivery &&
      (cardPaymentStatus == WholesaleCardPaymentStatus.awaiting ||
          cardPaymentStatus == WholesaleCardPaymentStatus.receiptSubmitted ||
          cardPaymentStatus.isEmpty);

  /// Йўқолган посилка изоҳи калити (соф): сотувчига — «курьердан тўланади»;
  /// харидорга — қайтарилди (сумма [lostRefunded]) / картада пул олинмайди /
  /// админ кўриб чиқмоқда. Йўқолмаган ёки бегона — `null`.
  String? lostNoticeKey(String viewerId) {
    if (status != WholesaleOrderStatus.lost) return null;
    if (isBuyer(viewerId)) {
      if (lostReview) return 'wholesale_order_lost_review';
      // Банк ўтказмаси: товар пули ҳақида ҳеч нарса айтилмайди (эга, 2026-11-14).
      if (isBankOrder) return 'wholesale_order_status_lost';
      if (lostRefundTo == 'buyer' && lostRefunded > 0) return 'wholesale_order_lost_refunded';
      if (isCardOrder) return 'wholesale_order_lost_card_unpaid';
      return 'wholesale_order_status_lost';
    }
    if (isSeller(viewerId)) return 'wholesale_order_lost_seller';
    return null;
  }

  bool isBuyer(String viewerId) => _same(buyerId, viewerId);
  bool isSeller(String viewerId) => _same(sellerId, viewerId);

  static bool _same(String a, String b) {
    final x = canonicalPhoneId(a);
    return x.isNotEmpty && x == canonicalPhoneId(b);
  }

  static int _int(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
  static String _str(Object? v) => v is String ? v.trim() : '';
  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : const {};

  static DateTime? _date(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }

  factory WholesaleOrder.fromMap(String id, Map<String, dynamic> d) {
    final shipment = _map(d['shipment']);
    final card = _map(d['cardPayment']);
    final dest = _map(d['destination']);
    final debt = d['returnDebt'];
    final ret = _map(d['returnShipment']);
    final pay = _map(d['payment']);
    final lost = _map(d['lost']);
    final wr = _map(d['walletRefusal']);
    final bank = _map(d['bankPayment']);
    final self = _map(d['selfDelivery']);
    final method = _str(d['paymentMethod']);
    return WholesaleOrder(
      id: id,
      buyerId: _str(d['buyerId']),
      sellerId: _str(d['sellerId']),
      productId: _str(d['productId']),
      productTitle: _str(d['productTitle']),
      packId: _str(d['packId']),
      packLabel: _str(d['packLabel']),
      qty: _int(d['qty']),
      unitPrice: _int(d['unitPrice']),
      goodsTotal: _int(d['goodsTotal']),
      deliveryFee: _int(d['deliveryFee']),
      total: _int(d['total']),
      status: _str(d['status']),
      // Эски (2-босқич) ҳужжатда майдон йўқ — улар фақат ҳамён орқали.
      paymentMethod: method.isEmpty ? WholesalePaymentMethod.wallet : method,
      cardPaymentStatus: _str(card['status']),
      receiptPath: _str(card['receiptPath']),
      receiptUrl: _str(card['receiptUrl']),
      trackingNumber: _str(shipment['trackingNumber']),
      shipmentId: _str(shipment['shipmentId']),
      destinationText: _str(dest['addressText']),
      returnDebt: debt is Map ? _int(debt['amount']) : _int(debt),
      returnStatus: _str(d['returnStatus']),
      returnTrackingNumber: _str(ret['trackingNumber']),
      paymentStatus: _str(pay['status']),
      lostRefunded: _int(lost['refunded']),
      lostRefundTo: _str(lost['refundTo']),
      lostReview: lost['review'] == true || _str(pay['status']) == 'lost_review',
      deliveryFailed: WholesaleDeliveryFailed.fromOrder(d),
      returnDebtPayer: debt is Map ? _str(debt['payer']) : '',
      walletRefusalFault: _str(wr['fault']),
      walletRefundGoods: _int(wr['goodsRefunded']),
      walletReturnFeeCharged: _int(wr['returnFeeCharged']),
      createdAt: _date(d['createdAt']),
      sellerDecision: _str(d['sellerDecision']),
      acceptDeadlineAt: _date(d['acceptDeadlineAt']),
      cancelReason: _str(d['cancelReason']),
      bankPaymentStatus: _str(bank['status']),
      bankPayDeadlineAt: _date(d['bankPayDeadlineAt']),
      deliveryMethod: _str(d['deliveryMethod']) == WholesaleDeliveryMethod.self
          ? WholesaleDeliveryMethod.self
          : WholesaleDeliveryMethod.avaCourier,
      deliveryPaidBy: _str(d['deliveryPaidBy']),
      selfStatus: _str(self['status']),
      selfDropoff: _str(self['dropoff']),
      refundStatus: _str(d['refundStatus']),
      deliveryPaymentMethod: _str(d['deliveryPaymentMethod']) == WholesaleDeliveryPaymentMethod.cash
          ? WholesaleDeliveryPaymentMethod.cash
          : WholesaleDeliveryPaymentMethod.wallet,
      cashDeliveryAmount: _int(_map(d['cashDelivery'])['amount']),
      cashRefusalPaid: _map(d['cashRefusal'])['paid'] is bool ? _map(d['cashRefusal'])['paid'] as bool : null,
      cashRefusalTotal: _int(_map(d['cashRefusal'])['total']),
      returnDebtKind: debt is Map ? _str(debt['kind']) : '',
      returnDebtStatus: debt is Map ? _str(debt['status']) : '',
    );
  }
}

/// Буюртма тафсилотида КИМГА қайси амал кўринади (соф, тестланади).
///
/// Эга қарори (2026-11-13; 31.10 даги «сотувчи қабул/рад қилмайди» ўрнига):
/// янги буюртмани сотувчи 2 иш кунида ҚАБУЛ ёки РАД қилади; курьер фақат
/// қабулдан кейин. Карта буюртмасида «Пул тушди» ҳам қолади.
class WholesaleOrderActions {
  const WholesaleOrderActions._({
    required this.isBuyer,
    required this.isSeller,
    required this.canDecide,
    required this.awaitingDecision,
    required this.canCancel,
    required this.showDeliveryCode,
    required this.showCardInfo,
    required this.canUploadReceipt,
    required this.waitingSeller,
    required this.codeAfterCardConfirm,
    required this.canConfirmCardPayment,
    required this.showReceipt,
    required this.showReturnDebt,
    required this.showBuyerReturnDebt,
    required this.answerDeliveryFailed,
    required this.decideDeliveryFailed,
    required this.canConfirmBankPayment,
    required this.awaitingBankPayment,
    required this.bankPaymentLate,
    required this.canStartSelf,
    required this.canCompleteSelf,
    required this.selfCompleteAfterCard,
    required this.canRefuseSelf,
    required this.canCompleteSelfReturn,
    required this.selfReturnWaitRefund,
    required this.selfAwaitingStart,
    required this.selfCompletedWaiting,
    required this.showBuyerCashDebt,
    required this.showCashToCourier,
  });

  // ── S57: нақд етказиш (эга, 2026-11-14) ──

  /// Харидор: нақд рад қарзи (`returnDebt {payer: buyer, kind: cash_refusal}`) — сумма ва «нақд ёпиқ».
  final bool showBuyerCashDebt;

  /// Харидор: буюртма ҳали етказилмаган — «етказиш ҳақини курьерга нақд тўлайсиз» + рад огоҳлантириши.
  final bool showCashToCourier;

  // ── S4: ўз етказиши (сервер `functions_demand/api/wholesale_self.js`) ──

  /// Сотувчи: «Йўлга чиқдим» — қабул қилинган `placed`; банк — «Пул тушди»дан кейин.
  final bool canStartSelf;

  /// Сотувчи: «Етказилди — харидор кодини киритинг»; карта — фақат «Пул тушди»дан кейин.
  final bool canCompleteSelf;

  /// Сотувчи: карта буюртмаси йўлда, «Пул тушди» босилмаган — кодни киритишдан олдин.
  final bool selfCompleteAfterCard;

  /// Сотувчи: «Харидор воз кечди» — йўлда; карта тўлови тасдиқланган бўлса йўқ.
  final bool canRefuseSelf;

  /// Сотувчи: «Товар қайтиб келди» — рад этилган ва ҳисоб-китоб тугаган.
  final bool canCompleteSelfReturn;

  /// Сотувчи: рад этилган, ҳисоб-китоб ҳали тугамаган — «бироздан кейин».
  final bool selfReturnWaitRefund;

  /// Харидор: қабул қилинган, сотувчи ҳали йўлга чиқмаган.
  final bool selfAwaitingStart;

  /// Иккала томон: код тасдиқланди, ҳисоб-китоб якунланмоқда (`delivered` ҳали ёзилмаган).
  final bool selfCompletedWaiting;

  /// Сотувчи (банк ўтказмаси): «Пул тушди» — қабул қилинган, тўлов кутилмоқда ва муддат ўтмаган.
  final bool canConfirmBankPayment;

  /// Харидор (банк ўтказмаси): «товар пулини банк орқали ўтказинг, сотувчи {муддат} гача тасдиқлайди».
  final bool awaitingBankPayment;

  /// Иккала томон: банк тўлови муддати ўтди, буюртма бекор қилинади (сервер текширувчиси).
  final bool bankPaymentLate;

  final bool isBuyer;
  final bool isSeller;

  /// Сотувчи: «Қабул қилиш / Рад этиш» — қарор кутилмоқда ва муддат ўтмаган.
  final bool canDecide;

  /// Харидор (ва муддати ўтган сотувчи): «сотувчи жавобини кутяпмиз ({муддат} гача)».
  final bool awaitingDecision;

  /// Харидор: фақат `placed` да (сервер ҳам шуни текширади).
  final bool canCancel;

  /// Харидор: етказилмоқда; карта буюртмасида — сотувчи тасдиқлагач.
  final bool showDeliveryCode;

  /// Харидор: карта буюртмаси, тўлов очиқ — сотувчи картаси маълумоти.
  final bool showCardInfo;

  /// Харидор: чек ҳали юборилмаган.
  final bool canUploadReceipt;

  /// Харидор: чек юборилган — «Сотувчи тасдиқлашини кутяпмиз».
  final bool waitingSeller;

  /// Харидор: карта буюртмаси етказилмоқда, лекин тўлов тасдиқланмаган —
  /// код ўрнига изоҳ.
  final bool codeAfterCardConfirm;

  /// Сотувчи: «Пул тушди» (awaiting ёки receipt_submitted).
  final bool canConfirmCardPayment;

  /// Сотувчи: харидор юклаган чек расми.
  final bool showReceipt;

  /// Сотувчи: қайтариш қарзи огоҳлантириши (фақат қарз сотувчида — карта буюртмаси).
  final bool showReturnDebt;

  /// Харидор: ҳамён буюртмаси рад этилди, қайтариш ҳақига маблағ етмади (`returnDebt.payer == buyer`).
  final bool showBuyerReturnDebt;

  /// Харидор: курьер «етказилмади» деди — «Тасдиқлайман» / «Олмоқчиман» (мажбурий).
  final bool answerDeliveryFailed;

  /// Сотувчи: «етказилмади» сўрови кўринади (тугмалар муддат ўтгач — [WholesaleDeliveryFailed.canDecide]).
  final bool decideDeliveryFailed;

  factory WholesaleOrderActions.of(WholesaleOrder o, String viewerId, {DateTime? now}) {
    final buyer = o.isBuyer(viewerId);
    final seller = !buyer && o.isSeller(viewerId);
    final cardOpen = o.cardPaymentOpen;
    final submitted = o.cardPaymentStatus == WholesaleCardPaymentStatus.receiptSubmitted;
    final inDelivery = o.status == WholesaleOrderStatus.inDelivery;
    final at = now ?? DateTime.now();
    final deadline = o.acceptDeadlineAt;
    final inTime = deadline == null || at.isBefore(deadline);
    // Банк тўлови муддати: йўқ — тасдиқ ҳам йўқ (сервер `bank_pay_deadline_missing`);
    // муддат вақтида ва ундан кейин — текширувчи бекор қилади, тугма кўрсатилмайди.
    final bankDeadline = o.bankPayDeadlineAt;
    final bankAwaiting = o.bankPaymentAwaiting;
    final bankInTime = bankDeadline != null && at.isBefore(bankDeadline);
    final self = o.isSelf;
    final selfOnWay = self && inDelivery && o.selfStatus == WholesaleSelfStatus.inDelivery;
    final selfStartReady = self &&
        o.status == WholesaleOrderStatus.placed &&
        o.sellerDecision == 'accepted' &&
        (!o.isBankOrder || o.bankConfirmed);
    final refusedSelf = self && o.status == WholesaleOrderStatus.refused;
    return WholesaleOrderActions._(
      canStartSelf: seller && selfStartReady,
      canCompleteSelf: seller && selfOnWay && (!o.isCardOrder || o.cardConfirmed),
      selfCompleteAfterCard: seller && selfOnWay && o.isCardOrder && !o.cardConfirmed,
      canRefuseSelf: seller && selfOnWay && !(o.isCardOrder && o.cardConfirmed),
      canCompleteSelfReturn: seller && refusedSelf && o.refundStatus == 'done',
      selfReturnWaitRefund: seller && refusedSelf && o.refundStatus != 'done',
      selfAwaitingStart: buyer && selfStartReady,
      selfCompletedWaiting:
          (buyer || seller) && self && inDelivery && o.selfStatus == WholesaleSelfStatus.completed,
      canConfirmBankPayment: seller && bankAwaiting && bankInTime,
      awaitingBankPayment: buyer && bankAwaiting && bankInTime,
      bankPaymentLate: (buyer || seller) && bankAwaiting && bankDeadline != null && !bankInTime,
      isBuyer: buyer,
      isSeller: seller,
      canDecide: seller && o.awaitingSellerDecision && inTime,
      awaitingDecision: (buyer || seller) && o.awaitingSellerDecision && !(seller && inTime),
      // Банк ўтказмаси: сотувчи «Пул тушди» босгач бекор йўқ (сервер `bank_payment_confirmed`).
      canCancel: buyer && o.status == WholesaleOrderStatus.placed && !o.bankConfirmed,
      // S4: ўз етказишида код — сотувчи йўлга чиққач (сервер `self_delivery_not_started`).
      showDeliveryCode: buyer && inDelivery && (!self || selfOnWay) && (!o.isCardOrder || o.cardConfirmed),
      showCardInfo: buyer && cardOpen,
      canUploadReceipt: buyer && cardOpen && !submitted,
      waitingSeller: buyer && cardOpen && submitted,
      codeAfterCardConfirm: buyer && inDelivery && o.isCardOrder && !o.cardConfirmed,
      canConfirmCardPayment: seller && cardOpen,
      // Сотувчида Storage ўқиш ҳуқуқи ЙЎҚ — фақат сервер ёзган `receiptUrl`.
      showReceipt: seller && o.isCardOrder && o.receiptUrl.isNotEmpty,
      showReturnDebt: seller && o.returnDebt > 0 && (o.returnDebtPayer.isEmpty || o.returnDebtPayer == 'seller'),
      // Нақд рад қарзи — алоҳида банер ([showBuyerCashDebt]): ҳамённи тўлдириш уни ёпиши тасдиқланмаган.
      showBuyerReturnDebt: buyer && o.returnDebt > 0 && o.returnDebtPayer == 'buyer' && !o.hasBuyerCashDebt,
      showBuyerCashDebt: buyer && o.hasBuyerCashDebt,
      showCashToCourier: buyer &&
          o.isCashDelivery &&
          (o.status == WholesaleOrderStatus.placed || inDelivery) &&
          !o.deliveryFailed.pending,
      answerDeliveryFailed: buyer && o.deliveryFailed.pending,
      decideDeliveryFailed: seller && o.deliveryFailed.pending,
    );
  }
}

/// `module_config/wholesale_orders_all` — фақат КИРИШ НУҚТАСИНИ кўрсатиш
/// учун (42-банд). Ҳал қилувчи — сервер (`requireOrdersGate`); бу ерда
/// унинг қоидаси такрорланади: ҳужжат йўқ / `enabled != true` — ёпиқ;
/// `public` — ҳамма; `off` — ҳеч ким; бошқа (internal/pilot/номаълум) —
/// фақат синовчилар (`core/logistics.js` `isStageAllowed`).
class WholesaleOrdersGate {
  const WholesaleOrdersGate({
    this.enabled = false,
    this.stage = 'off',
    this.testerIds = const [],
  });

  static const closed = WholesaleOrdersGate();

  final bool enabled;
  final String stage;
  final List<String> testerIds;

  factory WholesaleOrdersGate.fromMap(Map<String, dynamic>? d) {
    if (d == null) return closed;
    final raw = d['testerIds'];
    return WholesaleOrdersGate(
      enabled: d['enabled'] == true,
      stage: d['stage'] is String ? d['stage'] as String : 'internal',
      testerIds: raw is List ? raw.map((e) => canonicalPhoneId('$e')).toList() : const [],
    );
  }

  /// [uid] учун «Буюртма бериш» кўринсинми.
  bool allows(String uid) {
    if (!enabled) return false;
    if (stage == 'public') return true;
    if (stage == 'off') return false;
    final id = canonicalPhoneId(uid);
    return id.isNotEmpty && testerIds.contains(id);
  }
}

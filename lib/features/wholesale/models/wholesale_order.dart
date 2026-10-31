import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart' show canonicalPhoneId;

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
  });

  static const none = WholesaleDeliveryFailed();

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
    return WholesaleDeliveryFailed(
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
  });

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
  bool get isWalletOrder => paymentMethod == WholesalePaymentMethod.wallet;

  /// Курьер ойнасидаги сабаблар: сервер рўйхати (маълум кодлар тартибида), бўлмаса — ҳаммаси.
  List<String> get reasons {
    final known = wholesaleDeliveryFailedReasons.where(allowedReasons.contains).toList();
    return known.isEmpty ? wholesaleDeliveryFailedReasons : known;
  }

  factory WholesaleDeliveryFailedReport.fromMap(Map<String, dynamic> d) {
    final ms = d['escalateAtMs'];
    final res = d['resolution'] is Map ? d['resolution'] as Map : const {};
    final pending = d['pending'] == true || d['awaitingBuyer'] == true || d['stage'] == 'awaiting_decision';
    final allowed = d['allowedReasons'];
    return WholesaleDeliveryFailedReport(
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
  });

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
    if (isCardOrder || walletRefusalFault.isEmpty || walletRefundGoods <= 0 || !isBuyer(viewerId)) return null;
    return walletRefusalFault == 'courier' ? 'wholesale_order_wallet_refund_courier' : 'wholesale_order_wallet_refund';
  }

  /// Қайтиш жараёни матни калити: ҳамён буюртмасида қайтариш ҳақи кимдан кутилаётгани ҳам.
  String? returnStatusKey() {
    if (returnStatus == WholesaleReturnStatus.awaitingPayment && !isCardOrder) {
      final payer = returnDebtPayer.isNotEmpty ? returnDebtPayer : walletRefusalFault;
      if (payer == 'buyer' || payer == 'courier') return 'wholesale_return_status_awaiting_payment_$payer';
    }
    return WholesaleReturnStatus.l10nKey(returnStatus);
  }

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
    );
  }
}

/// Буюртма тафсилотида КИМГА қайси амал кўринади (соф, тестланади).
///
/// Эга қарори (2026-10-31): СОТУВЧИ буюртмани ҚАБУЛ/РАД ҚИЛМАЙДИ — бу ерда
/// бундай амал умуман йўқ. Сотувчининг ягона амали — карта буюртмасида
/// «Пул тушди».
class WholesaleOrderActions {
  const WholesaleOrderActions._({
    required this.isBuyer,
    required this.isSeller,
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
  });

  final bool isBuyer;
  final bool isSeller;

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

  factory WholesaleOrderActions.of(WholesaleOrder o, String viewerId) {
    final buyer = o.isBuyer(viewerId);
    final seller = !buyer && o.isSeller(viewerId);
    final cardOpen = o.cardPaymentOpen;
    final submitted = o.cardPaymentStatus == WholesaleCardPaymentStatus.receiptSubmitted;
    final inDelivery = o.status == WholesaleOrderStatus.inDelivery;
    return WholesaleOrderActions._(
      isBuyer: buyer,
      isSeller: seller,
      canCancel: buyer && o.status == WholesaleOrderStatus.placed,
      showDeliveryCode: buyer && inDelivery && (!o.isCardOrder || o.cardConfirmed),
      showCardInfo: buyer && cardOpen,
      canUploadReceipt: buyer && cardOpen && !submitted,
      waitingSeller: buyer && cardOpen && submitted,
      codeAfterCardConfirm: buyer && inDelivery && o.isCardOrder && !o.cardConfirmed,
      canConfirmCardPayment: seller && cardOpen,
      // Сотувчида Storage ўқиш ҳуқуқи ЙЎҚ — фақат сервер ёзган `receiptUrl`.
      showReceipt: seller && o.isCardOrder && o.receiptUrl.isNotEmpty,
      showReturnDebt: seller && o.returnDebt > 0 && (o.returnDebtPayer.isEmpty || o.returnDebtPayer == 'seller'),
      showBuyerReturnDebt: buyer && o.returnDebt > 0 && o.returnDebtPayer == 'buyer',
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

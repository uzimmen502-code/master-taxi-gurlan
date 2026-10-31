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
  final DateTime? createdAt;

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

  /// Сотувчи: қайтариш қарзи огоҳлантириши.
  final bool showReturnDebt;

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
      showReturnDebt: seller && o.returnDebt > 0,
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

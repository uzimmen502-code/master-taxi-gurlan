/// Улгуржи буюртма — callable жавоблари (фақат кўрсатиш учун).
///
/// НАРХ ФАҚАТ СЕРВЕРДАН (CLAUDE.md 18/44): илова ҳеч нарсани ҳисобламайди,
/// `quoteWholesaleOrder` қайтарганини кўрсатади ва `quoteId` ни
/// `placeWholesaleOrder` га беради.
library;

int _int(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
String _str(Object? v) => v is String ? v.trim() : '';

/// Етказиш манзили (`quoteWholesaleOrder.destination`).
class WholesaleDestination {
  const WholesaleDestination({
    required this.regionId,
    required this.districtId,
    required this.addressText,
    this.lat,
    this.lng,
  });

  final String regionId;
  final String districtId;
  final String addressText;
  final double? lat;
  final double? lng;

  Map<String, dynamic> toInput() => {
        'regionId': regionId,
        'districtId': districtId,
        'addressText': addressText.trim(),
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      };
}

/// S4: етказиш усули (сервер `DELIVERY_METHOD`; йўқ — `ava_courier`).
abstract final class WholesaleDeliveryMethod {
  static const avaCourier = 'ava_courier';
  static const self = 'self';
}

/// S6 (эга, 2026-11-13): ким қачон қанча тўлайди — сервер `payPlan` (илова ҳисобламайди).
///   wallet — ҳозир ҳамёндан: товар + етказиш;
///   card   — ҳозир ҳамёндан: етказиш ҳақи; эшик олдида сотувчи картасига: ФАҚАТ товар;
///   bank   — ҳозир ҳамёндан: етказиш ҳақи; банк орқали: товар.
/// S57 (эга, 2026-11-14): нақд етказишда `cashToCourier` — етказиш ҳақи эшик олдида курьерга
/// (ҳамёндан ушланмайди); ҳамён/эски серверда 0.
class WholesalePayPlan {
  const WholesalePayPlan({
    required this.walletNow,
    required this.atDoorToSellerCard,
    required this.bankTransfer,
    this.cashToCourier = 0,
  });

  final int walletNow;
  final int atDoorToSellerCard;
  final int bankTransfer;
  final int cashToCourier;

  static WholesalePayPlan? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return WholesalePayPlan(
      walletNow: _int(raw['walletNow']),
      atDoorToSellerCard: _int(raw['atDoorToSellerCard']),
      bankTransfer: _int(raw['bankTransfer']),
      cashToCourier: _int(raw['cashToCourier']),
    );
  }
}

/// S57: курьер етказишида етказиш ҳақини тўлаш усули (сервер `DELIVERY_PAYMENT_METHODS`).
/// Майдон йўқ (эски буюртма/сервер) = `wallet`.
abstract final class WholesaleDeliveryPaymentMethod {
  static const wallet = 'wallet';

  /// Эшик олдида курьерга нақд (фақат квота `deliveryPaymentMethods.cash == true` деса).
  static const cash = 'cash';
}

class WholesaleQuote {
  const WholesaleQuote({
    required this.quoteId,
    required this.unitPrice,
    required this.goodsTotal,
    required this.deliveryFee,
    required this.total,
    required this.qty,
    this.currency = 'UZS',
    this.packLabel = '',
    this.productTitle = '',
    this.expiresAt,
    this.paymentMethodsKnown = false,
    this.cardOnDeliveryAvailable = false,
    this.cardUnavailableReason = '',
    this.bankTransferAvailable = false,
    this.bankUnavailableReason = '',
    this.walletHold,
    this.payPlan,
    this.deliveryMethod = WholesaleDeliveryMethod.avaCourier,
    this.courierAvailable = true,
    this.selfAvailable = false,
    this.selfUnavailableReason = '',
    this.selfCoverage = '',
    this.selfDropoff = '',
    this.deliveryPaymentMethod = WholesaleDeliveryPaymentMethod.wallet,
    this.cashDeliveryAvailable = false,
    this.cashUnavailableReason = '',
    this.cashToCourier = 0,
  });

  /// S57: шу квота етказиш ҳақини қандай тўлаш учун (`wallet` | `cash`).
  final String deliveryPaymentMethod;

  /// S57: `deliveryPaymentMethods.cash` — нақд мумкинми (сервер ҳал қилади, флаг ўчиқ бўлса `false`).
  final bool cashDeliveryAvailable;

  /// `cash_disabled` | `buyer_debt` | `self_delivery` | бўш.
  final String cashUnavailableReason;

  /// Нақд квотада эшик олдида курьерга тўланадиган сумма (= етказиш ҳақи, сервердан); бошқа — 0.
  final int cashToCourier;

  bool get isCashDelivery => deliveryPaymentMethod == WholesaleDeliveryPaymentMethod.cash;

  /// S6: тўлов режаси (эски серверда `null`).
  final WholesalePayPlan? payPlan;

  /// S4: шу квота қайси усул учун (`ava_courier` | `self`).
  final String deliveryMethod;

  /// S4: `deliveryMethods` — бу буюртмада мавжуд усуллар (сервер ҳал қилади).
  final bool courierAvailable;
  final bool selfAvailable;

  /// `self_disabled` | `self_settings_invalid` | `out_of_coverage` | бўш.
  final String selfUnavailableReason;

  /// Ўз етказиши мумкин бўлса: `district|region|nation` ва `district_center|buyer_address`.
  final String selfCoverage;
  final String selfDropoff;

  bool get isSelf => deliveryMethod == WholesaleDeliveryMethod.self;

  /// Ҳозир ҳамёндан ушланадиган сумма (S6: карта ва банкда — етказиш ҳақи; ўз етказишида 0).
  /// Сервер `payPlan.walletNow`, бўлмаса `walletHold`; иккаласи ҳам йўқ — `null`.
  int? get walletNowAmount => payPlan?.walletNow ?? walletHold;

  /// Банк ўтказмаси (эга, 2026-11-13/14) — ФАҚАТ сервер `paymentMethods.bank_transfer == true` деса.
  final bool bankTransferAvailable;
  final String bankUnavailableReason;

  /// Банк ва (S6) карта квотасида ҳамёндан ҳозир ушланадиган сумма (= етказиш ҳақи,
  /// сервер ҳисоблайди); ҳамён усулида `null`.
  final int? walletHold;

  final String quoteId;
  final int unitPrice;
  final int goodsTotal;
  final int deliveryFee;
  final int total;
  final int qty;
  final String currency;
  final String packLabel;
  final String productTitle;
  final DateTime? expiresAt;

  /// Сервер `paymentMethods` қайтардими (3b). Йўқ бўлса — фақат ҳамён,
  /// карта варианти умуман кўрсатилмайди.
  final bool paymentMethodsKnown;
  final bool cardOnDeliveryAvailable;
  final String cardUnavailableReason;

  bool isExpired(DateTime now) => expiresAt != null && !now.isBefore(expiresAt!);

  factory WholesaleQuote.fromMap(Map<String, dynamic> d) {
    // Жонли сервер `expiresAtMs` (сон) қайтаради; `expiresAt` ҳам қабул.
    final ms = d['expiresAtMs'] ?? d['expiresAt'];
    final methods = d['paymentMethods'];
    final dms = d['deliveryMethods'];
    final self = d['selfDelivery'] is Map ? d['selfDelivery'] as Map : const {};
    final dpms = d['deliveryPaymentMethods'];
    final plan = WholesalePayPlan.fromMap(d['payPlan']);
    final isCash = _str(d['deliveryPaymentMethod']) == WholesaleDeliveryPaymentMethod.cash;
    return WholesaleQuote(
      payPlan: plan,
      deliveryPaymentMethod: isCash ? WholesaleDeliveryPaymentMethod.cash : WholesaleDeliveryPaymentMethod.wallet,
      cashDeliveryAvailable: dpms is Map && dpms['cash'] == true,
      cashUnavailableReason: _str(d['cashUnavailableReason']),
      // Сервер иккала жойда беради: юқори `cashToCourier` ва `payPlan.cashToCourier`.
      cashToCourier: isCash ? (d['cashToCourier'] is num ? _int(d['cashToCourier']) : (plan?.cashToCourier ?? 0)) : 0,
      deliveryMethod: _str(d['deliveryMethod']) == WholesaleDeliveryMethod.self
          ? WholesaleDeliveryMethod.self
          : WholesaleDeliveryMethod.avaCourier,
      // Эски сервер (`deliveryMethods` йўқ) — фақат курьер.
      courierAvailable: dms is Map ? dms['ava_courier'] == true : true,
      selfAvailable: dms is Map && dms['self'] == true,
      selfUnavailableReason: _str(d['selfUnavailableReason']),
      selfCoverage: _str(self['coverage']),
      selfDropoff: _str(self['dropoff']),
      quoteId: _str(d['quoteId']),
      unitPrice: _int(d['unitPrice']),
      goodsTotal: _int(d['goodsTotal']),
      deliveryFee: _int(d['deliveryFee']),
      total: _int(d['total']),
      qty: _int(d['qty']),
      currency: _str(d['currency']).isEmpty ? 'UZS' : _str(d['currency']),
      packLabel: _str(d['packLabel']),
      productTitle: _str(d['productTitle']),
      expiresAt: ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null,
      paymentMethodsKnown: methods is Map,
      cardOnDeliveryAvailable: methods is Map && methods['card_on_delivery'] == true,
      cardUnavailableReason: _str(d['cardUnavailableReason']),
      bankTransferAvailable: methods is Map && methods['bank_transfer'] == true,
      bankUnavailableReason: _str(d['bankUnavailableReason']),
      walletHold: d['walletHold'] is num && (d['walletHold'] as num).isFinite ? (d['walletHold'] as num).toInt() : null,
    );
  }
}

class WholesalePlaceResult {
  const WholesalePlaceResult({
    required this.orderId,
    required this.status,
    required this.total,
    required this.idempotent,
  });

  final String orderId;
  final String status;
  final int total;
  final bool idempotent;

  factory WholesalePlaceResult.fromMap(Map<String, dynamic> d) => WholesalePlaceResult(
        orderId: _str(d['orderId']),
        status: _str(d['status']),
        total: _int(d['total']),
        idempotent: d['idempotent'] == true,
      );
}

class WholesaleDeliveryCode {
  const WholesaleDeliveryCode({
    required this.deliveryCode,
    required this.trackingNumber,
    required this.shipmentId,
  });

  final String deliveryCode;
  final String trackingNumber;
  final String shipmentId;

  factory WholesaleDeliveryCode.fromMap(Map<String, dynamic> d) => WholesaleDeliveryCode(
        deliveryCode: '${d['deliveryCode'] ?? ''}'.trim(),
        trackingNumber: _str(d['trackingNumber']),
        shipmentId: _str(d['shipmentId']),
      );
}

/// 3b `getWholesaleCardPaymentInfo` — харидор эшик олдида шу картага тўлайди.
class WholesaleCardInfo {
  const WholesaleCardInfo({
    required this.amount,
    required this.cardNumber,
    required this.holderName,
    required this.sellerName,
  });

  final int amount;
  final String cardNumber;
  final String holderName;
  final String sellerName;

  /// «8600 1234 5678 9012» — ўқиш осон бўлсин (фақат кўрсатиш).
  String get cardNumberGrouped {
    final d = cardNumber.replaceAll(RegExp(r'\D'), '');
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(d[i]);
    }
    return b.toString();
  }

  factory WholesaleCardInfo.fromMap(Map<String, dynamic> d) => WholesaleCardInfo(
        amount: _int(d['amount']),
        cardNumber: '${d['cardNumber'] ?? ''}'.trim(),
        holderName: _str(d['holderName']),
        sellerName: _str(d['sellerName']),
      );
}

/// 3b `getWholesaleReturnHandoverCode` — қайтиш LEG-1 ни олиш коди.
class WholesaleReturnHandoverCode {
  const WholesaleReturnHandoverCode({
    required this.handoverCode,
    required this.trackingNumber,
    required this.shipmentId,
  });

  final String handoverCode;
  final String trackingNumber;
  final String shipmentId;

  factory WholesaleReturnHandoverCode.fromMap(Map<String, dynamic> d) => WholesaleReturnHandoverCode(
        handoverCode: '${d['handoverCode'] ?? ''}'.trim(),
        trackingNumber: _str(d['trackingNumber']),
        shipmentId: _str(d['shipmentId']),
      );
}
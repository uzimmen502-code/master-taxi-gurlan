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
  });

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
    return WholesaleQuote(
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

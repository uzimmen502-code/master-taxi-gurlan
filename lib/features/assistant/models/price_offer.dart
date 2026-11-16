/// «Нарх қидириш» (AVA AI Plus, эга 2026-11-17) — `assistantPriceSearch` жавоби.
///
/// Нарх ва етказиш ФАҚАТ серверда ҳисобланади (`functions/price_search.js`); бу класс фақат кўрсатади.
/// Якуний нарх буюртма пайтида серверда (мавжуд буюртма занжирлари).
library;

/// Сабаб кодлари — сервер `price_search.REASONS` билан бир хил.
abstract final class PriceDeliveryReason {
  static const tariffNotActive = 'tariff_not_active';
  static const deliveryQuoteRequired = 'delivery_quote_required';
  static const deliveryTooFar = 'delivery_too_far';
  static const buyerLocationMissing = 'buyer_location_missing';
}

class PriceOfferDelivery {
  const PriceOfferDelivery({
    required this.fee,
    required this.fromPrice,
    required this.reason,
    this.tariffVersion,
  });

  /// `null` — нарх ҳали йўқ (тариф йўқ / фаол эмас / маршрут йўқ …) — ўйлаб топилмайди.
  final int? fee;

  /// Вазн номаълум — энг кичик поғона: «≈ X сўмдан», «вазнга қараб ўзгаради».
  final bool fromPrice;
  final String? reason;
  final int? tariffVersion;

  factory PriceOfferDelivery.fromMap(Map<String, dynamic> m) => PriceOfferDelivery(
        fee: (m['fee'] as num?)?.toInt(),
        fromPrice: m['fromPrice'] == true,
        reason: m['reason'] as String?,
        tariffVersion: (m['tariffVersion'] as num?)?.toInt(),
      );
}

class PriceOffer {
  const PriceOffer({
    required this.id,
    required this.source,
    required this.wholesale,
    required this.title,
    required this.photoUrl,
    required this.sellerName,
    required this.ownerPhone,
    required this.sellerDistrictId,
    required this.sellerRegionId,
    required this.price,
    required this.priceUnit,
    required this.priceFrom,
    required this.unit,
    required this.qty,
    required this.moq,
    required this.packLabel,
    required this.goodsTotal,
    required this.delivery,
    required this.total,
    required this.totalFrom,
    required this.listedAt,
    required this.sponsored,
  });

  static const sourceShopItems = 'tv_shop_items';
  static const sourceWholesale = 'wholesale_products';

  final String id;
  final String source;

  /// «улгуржи» (wholesale_products) / «чакана» (tv_shop_items).
  final bool wholesale;
  final String title;
  final String photoUrl;
  final String sellerName;
  final String ownerPhone;
  final String sellerDistrictId;
  final String sellerRegionId;
  final int price;
  final String priceUnit;
  final bool priceFrom;
  final String unit;
  final int qty;
  final int? moq;
  final String packLabel;
  final int goodsTotal;
  final PriceOfferDelivery delivery;
  final int? total;
  final bool totalFrom;
  final DateTime? listedAt;
  final bool sponsored;

  factory PriceOffer.fromMap(Map<String, dynamic> m) {
    final listed = (m['listedAt'] as num?)?.toInt();
    return PriceOffer(
      id: (m['id'] ?? '') as String,
      source: (m['source'] ?? '') as String,
      wholesale: m['kind'] == 'wholesale',
      title: (m['title'] ?? '') as String,
      photoUrl: (m['photoUrl'] ?? '') as String,
      sellerName: (m['sellerName'] ?? '') as String,
      ownerPhone: (m['ownerPhone'] ?? '') as String,
      sellerDistrictId: (m['sellerDistrictId'] ?? '') as String,
      sellerRegionId: (m['sellerRegionId'] ?? '') as String,
      price: (m['price'] as num?)?.toInt() ?? 0,
      priceUnit: (m['priceUnit'] ?? '') as String,
      priceFrom: m['priceFrom'] == true,
      unit: (m['unit'] ?? '') as String,
      qty: (m['qty'] as num?)?.toInt() ?? 1,
      moq: (m['moq'] as num?)?.toInt(),
      packLabel: (m['packLabel'] ?? '') as String,
      goodsTotal: (m['goodsTotal'] as num?)?.toInt() ?? 0,
      delivery: PriceOfferDelivery.fromMap(
          m['delivery'] is Map ? Map<String, dynamic>.from(m['delivery'] as Map) : const {}),
      total: (m['total'] as num?)?.toInt(),
      totalFrom: m['totalFrom'] == true,
      listedAt: listed == null || listed <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(listed),
      sponsored: m['sponsored'] == true,
    );
  }
}

class PriceSearchResult {
  const PriceSearchResult({required this.offers, required this.partial});

  final List<PriceOffer> offers;

  /// Ҳамма сўз мос келган таклиф йўқ — яқинлари кўрсатилди.
  final bool partial;

  factory PriceSearchResult.fromMap(Map<String, dynamic> m) {
    final raw = m['offers'];
    return PriceSearchResult(
      offers: raw is List
          ? raw.whereType<Map>().map((o) => PriceOffer.fromMap(Map<String, dynamic>.from(o))).toList()
          : const [],
      partial: m['partial'] == true,
    );
  }
}

// AVA LOGISTICS (Relay) — иловадаги моделлар (D-3…D-10).
//
// ТАШҚИ боғламлар йўқ: `Map<String, dynamic>`дан ўқийди, Firestore
// типларини билмайди (`parseDemandDate` динамик `toDate()`). Шунинг учун
// `flutter test`да плагинсиз ишлайди ва сервер фикстураси билан паритет
// тести ёзилади (`functions_demand/test/fixtures/logistics_parity.json`).
//
// МИЖОЗ КЎРМАЙДИГАН НАРСАЛАР (45-банд): LEG, ички ҳақ тақсимоти, зона
// маъноси. Мижоз битта буюртма, битта нарх, битта кузатув тасмасини кўради.

import '../../demand_offer/domain/demand.dart'
    show asDemandMap, demandStringList, parseDemandDate, toDemandDouble, toDemandInt;

/// Жўнатма ҳолати — сервер `core/logistics.js` → `SHIPMENT_STATUS`.
enum ShipmentStatus {
  awaitingPayment,
  ready,
  inTransit,
  delivered,
  closed,
  cancelled,
  disputed,
  lost;

  String get wire {
    switch (this) {
      case ShipmentStatus.awaitingPayment:
        return 'awaiting_payment';
      case ShipmentStatus.inTransit:
        return 'in_transit';
      default:
        return name;
    }
  }

  static ShipmentStatus? tryParse(String? v) {
    if (v == null) return null;
    for (final s in ShipmentStatus.values) {
      if (s.wire == v) return s;
    }
    return null;
  }

  String get l10nKey => 'logistics_status_$wire';

  /// Жўнатувчи ҳали бекор қила оладими (custody бошланмаган).
  bool get isCancellable =>
      this == ShipmentStatus.awaitingPayment || this == ShipmentStatus.ready;

  bool get isFinal =>
      this == ShipmentStatus.closed || this == ShipmentStatus.cancelled;
}

/// Тўлов ҳолати — сервер `PAYMENT_STATUS` (relay ҳужжати 7.6).
enum PaymentStatus {
  pending,
  escrowFunded,
  releaseApproved,
  settled,
  escrowFrozen,
  refundPending,
  refunded,

  /// Посилка йўқолган деб эълон қилинган (D1) — товар қиймати қайтарилади.
  lossPending,
  lossSettled;

  String get wire {
    switch (this) {
      case PaymentStatus.lossPending:
        return 'loss_pending';
      case PaymentStatus.lossSettled:
        return 'loss_settled';
      case PaymentStatus.escrowFunded:
        return 'escrow_funded';
      case PaymentStatus.releaseApproved:
        return 'release_approved';
      case PaymentStatus.escrowFrozen:
        return 'escrow_frozen';
      case PaymentStatus.refundPending:
        return 'refund_pending';
      default:
        return name;
    }
  }

  static PaymentStatus? tryParse(String? v) {
    if (v == null) return null;
    for (final s in PaymentStatus.values) {
      if (s.wire == v) return s;
    }
    return null;
  }

  String get l10nKey => 'logistics_payment_$wire';
}

/// Custody эгаси тури.
enum CustodianKind {
  sender,
  provider,
  recipient;

  static CustodianKind? tryParse(String? v) {
    for (final k in CustodianKind.values) {
      if (k.name == v) return k;
    }
    return null;
  }
}

/// Handover ҳолат белгилари (7.4, 3-қадам) — сервер `CONDITION_FLAGS`.
class ConditionFlags {
  ConditionFlags._();
  static const intact = 'intact';
  static const packageDamaged = 'package_damaged';
  static const opened = 'opened';
  static const wet = 'wet';
  static const other = 'other';
  static const all = [intact, packageDamaged, opened, wet, other];
  static String l10nKey(String flag) => 'logistics_condition_$flag';
}

/// Нуқта — виловят/туман ID (сервер `geo_*` бўйича текширади) + манзил матни.
class LogisticsPoint {
  const LogisticsPoint({
    required this.regionId,
    this.districtId = '',
    this.lat,
    this.lng,
    this.addressText = '',
  });

  final String regionId;
  final String districtId;
  final double? lat;
  final double? lng;
  final String addressText;

  bool get isSet => regionId.isNotEmpty;

  Map<String, dynamic> toInput() => <String, dynamic>{
        'regionId': regionId,
        if (districtId.isNotEmpty) 'districtId': districtId,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
        if (addressText.isNotEmpty) 'addressText': addressText,
      };

  static LogisticsPoint? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    return LogisticsPoint(
      regionId: (m['regionId'] ?? '').toString(),
      districtId: (m['districtId'] ?? '').toString(),
      lat: toDemandDouble(m['lat']),
      lng: toDemandDouble(m['lng']),
      addressText: (m['addressText'] ?? '').toString(),
    );
  }

  LogisticsPoint copyWith({
    String? regionId,
    String? districtId,
    double? lat,
    double? lng,
    String? addressText,
  }) =>
      LogisticsPoint(
        regionId: regionId ?? this.regionId,
        districtId: districtId ?? this.districtId,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        addressText: addressText ?? this.addressText,
      );
}

/// Посилка — ГРАММ ва СМ, бутун сон (сервер шундай талаб қилади, 12-банд).
class ParcelSpec {
  const ParcelSpec({
    required this.actualWeightG,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    this.declaredValue = 0,
    this.description = '',
    this.fragile = false,
  });

  final int actualWeightG;
  final int lengthCm;
  final int widthCm;
  final int heightCm;
  final int declaredValue;
  final String description;
  final bool fragile;

  /// Вазн ва ўлчамлар мусбат бутун сон.
  bool get hasValidMeasures =>
      actualWeightG > 0 && lengthCm > 0 && widthCm > 0 && heightCm > 0;

  /// Эълон қилинган қиймат (сўм) МАЖБУРИЙ: > 0 (сервер `declared_value_required`
  /// билан рад этади, D1 — йўқолган посилка товар қиймати шунга асосланади).
  bool get hasDeclaredValue => declaredValue > 0;

  bool get isValid => hasValidMeasures && hasDeclaredValue;

  /// Маҳаллий текширув натижаси: `parcel_invalid` | `declared_value_required`
  /// | null. Калит: `logistics_err_<reason>`.
  String? get localErrorReason {
    if (!hasValidMeasures) return 'parcel_invalid';
    if (!hasDeclaredValue) return 'declared_value_required';
    return null;
  }

  Map<String, dynamic> toInput() => <String, dynamic>{
        'actualWeightG': actualWeightG,
        'lengthCm': lengthCm,
        'widthCm': widthCm,
        'heightCm': heightCm,
        'declaredValue': declaredValue,
        if (description.isNotEmpty) 'description': description,
        'fragile': fragile,
      };

  static ParcelSpec fromMap(Map<String, dynamic>? m) {
    final d = m ?? const <String, dynamic>{};
    return ParcelSpec(
      actualWeightG: toDemandInt(d['actualWeightG']) ?? 0,
      lengthCm: toDemandInt(d['lengthCm']) ?? 0,
      widthCm: toDemandInt(d['widthCm']) ?? 0,
      heightCm: toDemandInt(d['heightCm']) ?? 0,
      declaredValue: toDemandInt(d['declaredValue']) ?? 0,
      description: (d['description'] ?? '').toString(),
      fragile: d['fragile'] == true,
    );
  }
}

/// Нарх муҳри (D-8) — сервер ҳисоблайди, илова ФАҚАТ кўрсатади (44-банд).
class PriceSnapshot {
  const PriceSnapshot({
    required this.zone,
    required this.tariffVersion,
    required this.chargeableWeightG,
    required this.volumetricWeightG,
    required this.basePrice,
    required this.declaredValueFee,
    required this.customerPrice,
  });

  final String zone;
  final int tariffVersion;
  final int chargeableWeightG;
  final int volumetricWeightG;
  final int basePrice;
  final int declaredValueFee;

  /// Мижоз тўлайдиган нарх — бутун сўм.
  final int customerPrice;

  static PriceSnapshot fromMap(Map<String, dynamic>? m) {
    final d = m ?? const <String, dynamic>{};
    return PriceSnapshot(
      zone: (d['zone'] ?? '').toString(),
      tariffVersion: toDemandInt(d['tariffVersion']) ?? 0,
      chargeableWeightG: toDemandInt(d['chargeableWeightG']) ?? 0,
      volumetricWeightG: toDemandInt(d['volumetricWeightG']) ?? 0,
      basePrice: toDemandInt(d['basePrice']) ?? 0,
      declaredValueFee: toDemandInt(d['declaredValueFee']) ?? 0,
      customerPrice: toDemandInt(d['customerPrice']) ?? 0,
    );
  }
}

/// `quoteLogisticsOrder` натижаси.
class LogisticsQuote {
  const LogisticsQuote({
    required this.tariffVersion,
    required this.total,
    required this.parcels,
  });

  final int tariffVersion;
  final int total;
  final List<PriceSnapshot> parcels;

  static LogisticsQuote fromMap(Map<String, dynamic> m) {
    final raw = m['parcels'];
    return LogisticsQuote(
      tariffVersion: toDemandInt(m['tariffVersion']) ?? 0,
      total: toDemandInt(m['total']) ?? 0,
      parcels: raw is List
          ? raw.map((e) => PriceSnapshot.fromMap(asDemandMap(e))).toList()
          : const [],
    );
  }
}

/// `createLogisticsOrder` натижаси.
class CreateOrderResult {
  const CreateOrderResult({
    required this.orderId,
    required this.shipmentIds,
    required this.trackingNumbers,
    required this.total,
    required this.duplicate,
  });

  final String orderId;
  final List<String> shipmentIds;
  final List<String> trackingNumbers;
  final int total;
  final bool duplicate;

  static CreateOrderResult fromMap(Map<String, dynamic> m) => CreateOrderResult(
        orderId: (m['orderId'] ?? '').toString(),
        shipmentIds: demandStringList(m['shipmentIds']),
        trackingNumbers: demandStringList(m['trackingNumbers']),
        total: toDemandInt(m['total']) ?? 0,
        duplicate: m['duplicate'] == true,
      );
}

/// QR payload ва кодлар (D-5, D-6). `deliveryCode` фақат эгасига келади.
class ShipmentSecrets {
  const ShipmentSecrets({
    required this.shipmentId,
    required this.trackingNumber,
    required this.qrPayload,
    required this.handoverCode,
    this.deliveryCode,
  });

  final String shipmentId;
  final String trackingNumber;
  final String qrPayload;
  final String handoverCode;
  final String? deliveryCode;

  static ShipmentSecrets fromMap(Map<String, dynamic> m) => ShipmentSecrets(
        shipmentId: (m['shipmentId'] ?? '').toString(),
        trackingNumber: (m['trackingNumber'] ?? '').toString(),
        qrPayload: (m['qrPayload'] ?? '').toString(),
        handoverCode: (m['handoverCode'] ?? '').toString(),
        deliveryCode: m['deliveryCode']?.toString(),
      );
}

/// `logistics_orders/{id}` — мижознинг буюртмаси. Статус ҲИСОБЛАНАДИ (сервер).
class LogisticsOrder {
  const LogisticsOrder({
    required this.id,
    required this.ownerId,
    required this.status,
    required this.shipmentIds,
    required this.trackingNumbers,
    required this.customerPriceTotal,
    this.origin,
    this.destination,
    this.recipientName = '',
    this.recipientPhone = '',
    this.note = '',
    this.createdAt,
  });

  final String id;
  final String ownerId;

  /// `awaiting_payment` · `ready` · `in_transit` · `delivered` · `closed` ·
  /// `cancelled` · `disputed` · `problem` (сервер `deriveOrderStatus`).
  final String status;
  final List<String> shipmentIds;
  final List<String> trackingNumbers;
  final int customerPriceTotal;
  final LogisticsPoint? origin;
  final LogisticsPoint? destination;
  final String recipientName;
  final String recipientPhone;
  final String note;
  final DateTime? createdAt;

  String get l10nStatusKey => 'logistics_order_$status';

  factory LogisticsOrder.fromMap(String id, Map<String, dynamic> m) {
    final recipient = asDemandMap(m['recipient']) ?? const {};
    return LogisticsOrder(
      id: id,
      ownerId: (m['ownerId'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      shipmentIds: demandStringList(m['shipmentIds']),
      trackingNumbers: demandStringList(m['trackingNumbers']),
      customerPriceTotal: toDemandInt(m['customerPriceTotal']) ?? 0,
      origin: LogisticsPoint.fromMap(asDemandMap(m['origin'])),
      destination: LogisticsPoint.fromMap(asDemandMap(m['destination'])),
      recipientName: (recipient['name'] ?? '').toString(),
      recipientPhone: (recipient['phone'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
      createdAt: parseDemandDate(m['createdAt']),
    );
  }
}

/// `shipments/{id}` — битта жисмоний қути (D-4).
class Shipment {
  const Shipment({
    required this.id,
    required this.orderId,
    required this.ownerId,
    required this.trackingNumber,
    required this.status,
    required this.paymentStatus,
    required this.parcel,
    required this.priceSnapshot,
    this.origin,
    this.destination,
    this.recipientName = '',
    this.custodianKind,
    this.custodianId,
    this.legIds = const [],
    this.legCount = 1,
    this.assignedProviderIds = const [],
    this.createdAt,
    this.deliveredAt,
  });

  final String id;
  final String orderId;
  final String ownerId;
  final String trackingNumber;
  final ShipmentStatus status;
  final PaymentStatus paymentStatus;
  final ParcelSpec parcel;
  final PriceSnapshot priceSnapshot;
  final LogisticsPoint? origin;
  final LogisticsPoint? destination;
  final String recipientName;
  final CustodianKind? custodianKind;
  final String? custodianId;
  final List<String> legIds;
  final int legCount;
  final List<String> assignedProviderIds;
  final DateTime? createdAt;
  final DateTime? deliveredAt;

  bool get needsPayment =>
      status == ShipmentStatus.awaitingPayment && paymentStatus == PaymentStatus.pending;

  /// QR/код варағи кўрсатиладими (яакунланмаган жўнатма).
  bool get secretsAvailable => !status.isFinal && status != ShipmentStatus.delivered;

  factory Shipment.fromMap(String id, Map<String, dynamic> m) {
    final cust = asDemandMap(m['currentCustodian']) ?? const {};
    return Shipment(
      id: id,
      orderId: (m['orderId'] ?? '').toString(),
      ownerId: (m['ownerId'] ?? '').toString(),
      trackingNumber: (m['trackingNumber'] ?? '').toString(),
      status: ShipmentStatus.tryParse(m['status']?.toString()) ?? ShipmentStatus.awaitingPayment,
      paymentStatus: PaymentStatus.tryParse(m['paymentStatus']?.toString()) ?? PaymentStatus.pending,
      parcel: ParcelSpec.fromMap(asDemandMap(m['parcel'])),
      priceSnapshot: PriceSnapshot.fromMap(asDemandMap(m['priceSnapshot'])),
      origin: LogisticsPoint.fromMap(asDemandMap(m['origin'])),
      destination: LogisticsPoint.fromMap(asDemandMap(m['destination'])),
      recipientName: (m['recipientName'] ?? '').toString(),
      custodianKind: CustodianKind.tryParse(cust['kind']?.toString()),
      custodianId: cust['id']?.toString(),
      legIds: demandStringList(m['legIds']),
      legCount: toDemandInt(m['legCount']) ?? 1,
      assignedProviderIds: demandStringList(m['assignedProviderIds']),
      createdAt: parseDemandDate(m['createdAt']),
      deliveredAt: parseDemandDate(m['deliveredAt']),
    );
  }
}

/// `custody_events/{id}` — ўзгармас тарих (15, 16-банд). Мижозга
/// «кузатув тасмаси» сифатида кўрсатилади.
class CustodyEvent {
  const CustodyEvent({
    required this.id,
    required this.shipmentId,
    required this.legId,
    required this.kind,
    required this.fromKind,
    required this.toKind,
    this.fromId,
    this.toId,
    this.timestamp,
    this.conditionFlags = const [],
    this.photoUrls = const [],
    this.legIndex = 0,
    this.legCount = 1,
  });

  final String id;
  final String shipmentId;
  final String legId;

  /// `pickup` | `delivery`.
  final String kind;
  final CustodianKind? fromKind;
  final CustodianKind? toKind;
  final String? fromId;
  final String? toId;
  final DateTime? timestamp;
  final List<String> conditionFlags;
  final List<String> photoUrls;
  final int legIndex;
  final int legCount;

  bool get isDelivery => kind == 'delivery';

  /// Кузатув тасмаси матни калити (мижоз учун содда, LEG сўзи йўқ).
  String get l10nKey {
    if (isDelivery) return 'logistics_event_delivered';
    if (fromKind == CustodianKind.sender) return 'logistics_event_picked_up';
    return 'logistics_event_handed_over';
  }

  factory CustodyEvent.fromMap(String id, Map<String, dynamic> m) {
    final from = asDemandMap(m['from']) ?? const {};
    final to = asDemandMap(m['to']) ?? const {};
    final proof = asDemandMap(m['proof']) ?? const {};
    return CustodyEvent(
      id: id,
      shipmentId: (m['shipmentId'] ?? '').toString(),
      legId: (m['legId'] ?? '').toString(),
      kind: (m['kind'] ?? '').toString(),
      fromKind: CustodianKind.tryParse(from['kind']?.toString()),
      toKind: CustodianKind.tryParse(to['kind']?.toString()),
      fromId: from['id']?.toString(),
      toId: to['id']?.toString(),
      timestamp: parseDemandDate(m['timestamp']),
      conditionFlags: demandStringList(proof['conditionFlags']),
      photoUrls: demandStringList(proof['photoUrls']),
      legIndex: toDemandInt(m['legIndex']) ?? 0,
      legCount: toDemandInt(m['legCount']) ?? 1,
    );
  }
}

/// Ижрочи кўрадиган LEG проекцияси (`demand_matches.projection.attributes`,
/// сервер `adapters/logistics.js` → `buildProjection`).
class LegProjection {
  const LegProjection({
    required this.shipmentId,
    required this.trackingNumber,
    required this.legKind,
    required this.legIndex,
    required this.legCount,
    required this.payout,
    required this.chargeableWeightG,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.fragile,
    required this.fromDistrictId,
    required this.toDistrictId,
    required this.toRegionId,
  });

  /// Custodian бўлгач кодларни олиш учун (`getShipmentSecrets`).
  final String shipmentId;
  final String trackingNumber;
  final String legKind;
  final int legIndex;
  final int legCount;

  /// Ижрочи ҳақи — бутун сўм (ички қатлам, ижрочига очиқ).
  final int payout;
  final int chargeableWeightG;
  final int lengthCm;
  final int widthCm;
  final int heightCm;
  final bool fragile;
  final String fromDistrictId;
  final String toDistrictId;
  final String toRegionId;

  bool get isLastLeg => legIndex == legCount - 1;
  bool get isFirstLeg => legIndex == 0;

  static LegProjection fromAttributes(Map<String, dynamic>? a) {
    final d = a ?? const <String, dynamic>{};
    return LegProjection(
      shipmentId: (d['shipmentId'] ?? '').toString(),
      trackingNumber: (d['trackingNumber'] ?? '').toString(),
      legKind: (d['legKind'] ?? 'direct').toString(),
      legIndex: toDemandInt(d['legIndex']) ?? 0,
      legCount: toDemandInt(d['legCount']) ?? 1,
      payout: toDemandInt(d['payout']) ?? 0,
      chargeableWeightG: toDemandInt(d['chargeableWeightG']) ?? 0,
      lengthCm: toDemandInt(d['lengthCm']) ?? 0,
      widthCm: toDemandInt(d['widthCm']) ?? 0,
      heightCm: toDemandInt(d['heightCm']) ?? 0,
      fragile: d['fragile'] == true,
      fromDistrictId: (d['fromDistrictId'] ?? '').toString(),
      toDistrictId: (d['toDistrictId'] ?? '').toString(),
      toRegionId: (d['toRegionId'] ?? '').toString(),
    );
  }
}

/// «1 234 567» — бутун сўм форматлаш (ядро `ServiceUiAdapter._money` билан бир хил).
String logisticsMoney(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i += 1) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Грамм → «1,2 кг» кўриниши.
String logisticsWeightLabel(int grams) {
  if (grams < 1000) return '$grams г';
  final kg = grams / 1000;
  final text = kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} кг';
}

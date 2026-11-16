// «Бозорлар» STAGE 11 — йирик маиший техника учун «Етказиш нархини сўраш» (эга 2026-11-16).
//
// Сервер (feat/bozor-orders-srv): `requestDeliveryQuote` · `respondDeliveryQuote` · `acceptDeliveryQuote` ·
// `listOpenDeliveryQuotes`; ҳолат ҳужжати `delivery_quotes/{quoteId}` (фақат сервер ёзади; харидор ўзиникини
// ўқийди). Нарх, ҳолат ўтиши, рухсат ва муддат — фақат серверда (18/44-қоида); бу ерда фақат КЎРСАТИШ.
// Пул — бутун сўм (8-қоида).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../tv_market/models/tv_shop.dart';

/// Йирик (етказиш нархи олдиндан келишиладиган) бўлимлар: бозор → бўлимлар. Сервер константасининг КЎЗГУСИ —
/// клиентда фақат қайси тугма кўрсатилишини танлаш учун (ягона клиент жойи; сервер барибир текширади:
/// `DELIVERY_QUOTE_REQUIRED` / `DELIVERY_QUOTE_NOT_NEEDED`).
const Map<String, Set<String>> kLargeDeliveryCategories = {
  'appliances': {'fridges', 'washers', 'stoves', 'air_conditioners'},
};

/// Таклиф йирик етказишми ([kLargeDeliveryCategories]).
bool isLargeDeliveryItem(TvShopItem item) =>
    kLargeDeliveryCategories[item.market]?.contains(item.category) ?? false;

/// Сервер чекловлари кўзгуси (`requestDeliveryQuote`): миқдор 1..100, қават 0..60, матнлар ≤ 300.
abstract final class DeliveryQuoteLimits {
  static const maxQty = 100;
  static const maxFloor = 60;
  static const maxText = 300;
}

/// `delivery_quotes/{id}.status`.
abstract final class DeliveryQuoteStatus {
  static const open = 'open';
  static const answered = 'answered';
  static const used = 'used';
  static const expired = 'expired';
}

int _int(Object? v) => v is num ? v.toInt() : 0;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
String _str(Object? v) => v is String ? v : '';
double? _dbl(Object? v) => v is num ? v.toDouble() : null;
DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
DateTime? _ms(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

/// Харидор кўрадиган сўров ҳолати (`delivery_quotes/{id}`).
class DeliveryQuote {
  const DeliveryQuote({
    required this.id,
    required this.status,
    this.itemId = '',
    this.qty = 1,
    this.itemTitle = '',
    this.sellerName = '',
    this.priceUzs,
    this.orderId = '',
    this.expiresAt,
    this.respondedAt,
    this.createdAt,
  });

  final String id;

  /// Хом ҳолат ([DeliveryQuoteStatus]); кўрсатиш учун [effectiveStatus].
  final String status;
  final String itemId;
  final int qty;
  final String itemTitle;
  final String sellerName;

  /// Етказиш нархи (бутун сўм) — фақат `answered`/`used` да.
  final int? priceUzs;
  final String orderId;
  final DateTime? expiresAt;
  final DateTime? respondedAt;
  final DateTime? createdAt;

  /// `open`/`answered` бўлса-ю муддати ўтган бўлса — `expired` (сервер триггери кечикса ҳам UI тўғри).
  String effectiveStatus(DateTime now) {
    final exp = expiresAt;
    if ((status == DeliveryQuoteStatus.open || status == DeliveryQuoteStatus.answered) &&
        exp != null &&
        exp.isBefore(now)) {
      return DeliveryQuoteStatus.expired;
    }
    return status;
  }

  static DeliveryQuote fromMap(String id, Map<String, dynamic> d) => DeliveryQuote(
        id: id,
        status: _str(d['status']).isEmpty ? DeliveryQuoteStatus.open : _str(d['status']),
        itemId: _str(d['itemId']),
        qty: _int(d['qty']) < 1 ? 1 : _int(d['qty']),
        itemTitle: _str(d['itemTitle']),
        sellerName: _str(d['sellerName']),
        priceUzs: _intOrNull(d['priceUzs']),
        orderId: _str(d['orderId']),
        expiresAt: _date(d['expiresAt']),
        respondedAt: _date(d['respondedAt']),
        createdAt: _date(d['createdAt']),
      );
}

/// `requestDeliveryQuote` натижаси.
class DeliveryQuoteRequestResult {
  const DeliveryQuoteRequestResult({required this.quoteId, this.status = '', this.expiresAt, this.duplicate = false});

  final String quoteId;
  final String status;
  final DateTime? expiresAt;

  /// Шу харидор + шу маҳсулот учун очиқ сўров аллақачон бор эди — ўшаниси қайтди.
  final bool duplicate;

  static DeliveryQuoteRequestResult fromMap(Map<String, dynamic> m) => DeliveryQuoteRequestResult(
        quoteId: _str(m['quoteId']),
        status: _str(m['status']),
        expiresAt: _ms(m['expiresAtMs']),
        duplicate: m['duplicate'] == true,
      );
}

/// `respondDeliveryQuote` натижаси.
class DeliveryQuoteRespondResult {
  const DeliveryQuoteRespondResult({required this.quoteId, required this.priceUzs, this.responderRole = ''});

  final String quoteId;
  final int priceUzs;

  /// `admin` | `courier`.
  final String responderRole;

  static DeliveryQuoteRespondResult fromMap(Map<String, dynamic> m) => DeliveryQuoteRespondResult(
        quoteId: _str(m['quoteId']),
        priceUzs: _int(m['priceUzs']),
        responderRole: _str(m['responderRole']),
      );
}

/// `listOpenDeliveryQuotes` қатори. Мижоз манзили ва телефон охири — ФАҚАТ админга (40-қоида; курьерда йўқ).
class OpenDeliveryQuote {
  const OpenDeliveryQuote({
    required this.id,
    this.itemId = '',
    this.itemTitle = '',
    this.qty = 1,
    this.market = '',
    this.category = '',
    this.sellerName = '',
    this.pickupAddress = '',
    this.pickupLat,
    this.pickupLng,
    this.floor,
    this.note = '',
    this.distanceMeters,
    this.courierToPickupM,
    this.districtId = '',
    this.createdAt,
    this.expiresAt,
    this.address = '',
    this.buyerPhoneTail = '',
  });

  final String id;
  final String itemId;
  final String itemTitle;
  final int qty;
  final String market;
  final String category;
  final String sellerName;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final int? floor;
  final String note;

  /// Олиб кетиш нуқтаси → харидор (тўғри чизиқ).
  final int? distanceMeters;
  final int? courierToPickupM;
  final String districtId;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// Фақат админ.
  final String address;
  final String buyerPhoneTail;

  static OpenDeliveryQuote fromMap(Map<String, dynamic> m) => OpenDeliveryQuote(
        id: _str(m['id']),
        itemId: _str(m['itemId']),
        itemTitle: _str(m['itemTitle']),
        qty: _int(m['qty']) < 1 ? 1 : _int(m['qty']),
        market: _str(m['market']),
        category: _str(m['category']),
        sellerName: _str(m['sellerName']),
        pickupAddress: _str(m['pickupAddress']),
        pickupLat: _dbl(m['pickupLat']),
        pickupLng: _dbl(m['pickupLng']),
        floor: _intOrNull(m['floor']),
        note: _str(m['note']),
        distanceMeters: _intOrNull(m['distanceMeters']),
        courierToPickupM: _intOrNull(m['courierToPickupM']),
        districtId: _str(m['districtId']),
        createdAt: _ms(m['createdAtMs']),
        expiresAt: _ms(m['expiresAtMs']),
        address: _str(m['address']),
        buyerPhoneTail: _str(m['buyerPhoneTail']),
      );
}

/// `listOpenDeliveryQuotes` жавоби.
class OpenDeliveryQuotes {
  const OpenDeliveryQuotes(this.quotes, {this.viewer = ''});

  final List<OpenDeliveryQuote> quotes;

  /// `admin` | `courier`.
  final String viewer;

  bool get isAdmin => viewer == 'admin';
}

/// Нарх киритиш (курьер/админ): фақат рақамлар, бутун сўм > 0, юқори чегара ЙЎҚ (эга 2026-11-16). 15 рақамгача —
/// web'да ҳам аниқ бутун сон (< 2^53). Нотўғри — `null` (сервер барибир текширади).
const int kQuotePriceMaxDigits = 15;

int? parseQuotePrice(String raw) {
  final digits = raw.replaceAll(RegExp(r'[\s,.]'), '');
  if (digits.isEmpty || digits.length > kQuotePriceMaxDigits || !RegExp(r'^\d+$').hasMatch(digits)) return null;
  final v = int.parse(digits);
  return v > 0 ? v : null;
}

/// Қават майдони: бўш — `null` (кўрсатилмаган); 0..60 бутун сон; бошқаси — хато (`-1`).
int? parseQuoteFloor(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final v = int.tryParse(s);
  if (v == null || v < 0 || v > DeliveryQuoteLimits.maxFloor) return -1;
  return v;
}

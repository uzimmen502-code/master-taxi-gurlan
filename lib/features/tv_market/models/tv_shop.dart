import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/price_unit.dart';
import '../../product_badges/product_badge.dart';

/// Сотувчи мини-дўкони — `tv_shops/{ownerPhone}`.
class TvShop {
  const TvShop({
    required this.ownerPhone,
    required this.name,
    this.createdAt,
    this.status = 'active',
    this.pickupLat,
    this.pickupLng,
    this.pickupAddress = '',
    this.areaLat,
    this.areaLng,
    this.showExactLocation = false,
  });

  final String ownerPhone;
  final String name;
  final DateTime? createdAt;

  /// `active` | `blocked` — фақат админ ўрнатади (`adminSetShopStatus`); эски ҳужжатларда йўқ (= `active`).
  final String status;

  /// ЭСКИ оммавий «Маҳсулотни топшириш жойи» (STAGE 11 биринчи шакли). Эга 2026-11-16: аниқ нуқта энди
  /// `tv_shops/{phone}/private/pickup` да ([ShopPickup]); бу майдонлар фақат ўқилади (сервер fallback'и) ва
  /// сотувчи қайта сақлаганда ўчирилади. Янги код уларни ЁЗМАЙДИ.
  final double? pickupLat;
  final double? pickupLng;
  final String pickupAddress;

  /// Оммавий ТАХМИНИЙ нуқта (~500 м, [approxShopCoord]); [showExactLocation] да — аниқ. Эски ҳужжатда йўқ.
  final double? areaLat;
  final double? areaLng;

  /// Сотувчи «Аниқ жойимни кўрсат»ни ёққан (сукут — йўқ).
  final bool showExactLocation;

  bool get isBlocked => status == 'blocked';

  /// Топшириш жойи белгиланган — оммавий белги: тахминий нуқта ёки эски аниқ майдонлар (сервер `validLatLng`
  /// кўзгуси: 0,0 — йўқ). Аниқ нуқтани сервер private ҳужжатдан ўзи текширади.
  bool get hasPickup => validLatLng(areaLat, areaLng) || validLatLng(pickupLat, pickupLng);

  static bool validLatLng(double? lat, double? lng) =>
      lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180 && !(lat == 0 && lng == 0);

  factory TvShop.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) =>
      TvShop.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});

  factory TvShop.fromMap(String id, Map<String, dynamic> d) {
    final lat = d['pickupLat'];
    final lng = d['pickupLng'];
    final addr = d['pickupAddress'];
    return TvShop(
      ownerPhone: id,
      name: d['name'] is String ? d['name'] as String : '',
      createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null,
      status: d['status'] == 'blocked' ? 'blocked' : 'active',
      pickupLat: lat is num ? lat.toDouble() : null,
      pickupLng: lng is num ? lng.toDouble() : null,
      pickupAddress: addr is String ? addr : '',
      areaLat: d['areaLat'] is num ? (d['areaLat'] as num).toDouble() : null,
      areaLng: d['areaLng'] is num ? (d['areaLng'] as num).toDouble() : null,
      showExactLocation: d['showExactLocation'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'ownerPhone': ownerPhone,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };
}

/// Тахминий оммавий нуқта қадами — 0.005° (~550 м кенглик бўйича; 3 хона ≈ 110 м жуда аниқ, эга 2026-11-16).
const double kShopAreaStepDeg = 0.005;

/// Координатани [kShopAreaStepDeg] тўрига яхлитлайди (float шовқинисиз, 3 хона).
double approxShopCoord(double v) => double.parse(((v / kShopAreaStepDeg).round() * kShopAreaStepDeg).toStringAsFixed(3));

/// Ўз дўконининг АНИҚ олиб кетиш нуқтаси — `tv_shops/{phone}/private/pickup` (фақат эгаси ўқийди/ёзади;
/// сервер Admin SDK билан ўқиб буюртмага кўчиради). [legacy] — эски оммавий майдонлардан олинган.
class ShopPickup {
  const ShopPickup({required this.lat, required this.lng, this.address = '', this.legacy = false});

  final double lat;
  final double lng;
  final String address;
  final bool legacy;

  static ShopPickup? fromMap(Map<String, dynamic>? d) {
    if (d == null) return null;
    final lat = d['lat'];
    final lng = d['lng'];
    if (lat is! num || lng is! num || !TvShop.validLatLng(lat.toDouble(), lng.toDouble())) return null;
    return ShopPickup(lat: lat.toDouble(), lng: lng.toDouble(), address: d['address'] is String ? d['address'] as String : '');
  }
}

/// Витрина товар/хизмати — `tv_shop_items/{id}`.
/// Расмлар: `photoUrls` (1–7). `photoUrl` — қоплама (биринчи расм, back-compat).
/// `businessId` — Бизнес харитасидаги объектнинг маҳсулоти/хизмати (ихтиёрий; эски ҳужжатларда йўқ).
class TvShopItem {
  const TvShopItem({
    required this.id,
    required this.ownerPhone,
    required this.ownerName,
    required this.title,
    required this.price,
    required this.photoUrl,
    required this.kind,
    required this.districtId,
    required this.districtLabel,
    this.photoUrls = const [],
    this.description = '',
    this.clipIds = const [],
    this.viewCount = 0,
    this.boostUntil,
    this.socialConsent = false,
    this.socialPostedAt,
    this.status = 'active',
    this.createdAt,
    this.businessId = '',
    this.badge = ProductBadgeData.empty,
    this.priceUnit = PriceUnit.fixed,
    this.expiresAt,
    this.submittedAt,
    this.rejectReason = '',
    this.market = '',
    this.category = '',
    this.attrs = const {},
    this.imported,
    this.regionId = '',
    this.taxonomyVersion = 0,
    this.unitWeightG,
  });

  /// AVA AI нарх қидируви (эга 2026-11-17, А вариант): ихтиёрий «тахминий вазн» — бир бирлик, грамм
  /// (1..10 000 000, rules `tvShopItemShapeOk`). Йўқ — `null` (етказиш «≈ … дан»). Эски ҳужжатда йўқ.
  final int? unitWeightG;
  static const maxUnitWeightG = 10000000;

  /// «Бозорлар» 2a/2b (эга 2026-11-15): модерация ва 30 кунлик муддат майдонлари — ФАҚАТ сервер ёзади
  /// (`functions/market_moderation.js`; rules `tvShopModerationKeys`). Клиент уларни ўқийди, [toMap]да ЁЗМАЙДИ.
  /// Эски ҳужжатларда йўқ — `null`/бўш (аввалги кўриниш ўзгармайди).
  final DateTime? expiresAt;
  final DateTime? submittedAt;

  /// Рад этиш сабаби (`status == 'rejected'`); бўлмаса бўш.
  final String rejectReason;

  /// Бозор идентификатори (`taxonomy/markets`; 1-босқич). Эски ҳужжатда йўқ — бўш.
  final String market;

  /// «Бозорлар» 5+6 (эга 2026-11-15): бозор бўлими (`taxonomy/markets.markets.{market}.categories[].id`);
  /// динамик майдонлар (`attrs`, турли қийматлар; сана — `yyyy-mm-dd`); «Импорт» (Гўшт; `null` — ёзилмайди);
  /// эълон туманининг вилояти; ёзилган пайтдаги таксономия версияси (0 — ёзилмайди). Эски ҳужжатда йўқ.
  final String category;
  final Map<String, Object?> attrs;
  final bool? imported;
  final String regionId;
  final int taxonomyVersion;

  /// Эга қарори (2026-10-24): 7 тагача расм (Аҳоли бозори эълони билан бир хил).
  static const maxPhotos = 7;

  /// Нарх бирлиги (S2, 2026-11-03). Эски ҳужжатда йўқ — [PriceUnit.fixed]; `fixed` бўлса майдон ёзилмайди.
  final PriceUnit priceUnit;

  /// Бизнес харитаси объекти (`businesses/{id}`); бўш — оддий витрина товари.
  final String businessId;

  final String id;
  final String ownerPhone;
  final String ownerName;
  final String title;
  final int price;

  /// Қоплама (биринчи расм).
  final String photoUrl;
  final List<String> photoUrls;

  /// `product` | `service`
  final String kind;
  final String districtId;
  final String districtLabel;
  final String description;
  final List<String> clipIds;
  final int viewCount;
  final DateTime? boostUntil;
  final bool socialConsent;
  final DateTime? socialPostedAt;

  /// Карточка белгиси (сервер майдонлари: promo, firstActiveAt, stockLeft; эга 2026-11-19).
  final ProductBadgeData badge;

  /// `active` | `pending` | `rejected` | `expired` | `deleted` | `blocked` (2a: `rejected`/`expired` — сервер).
  final String status;
  final DateTime? createdAt;

  static List<String> normalizePhotos({
    List<dynamic>? rawUrls,
    String photoUrl = '',
  }) {
    final out = <String>[];
    if (rawUrls != null) {
      for (final e in rawUrls) {
        final s = '$e'.trim();
        if (s.isEmpty || out.contains(s)) continue;
        out.add(s);
        if (out.length >= maxPhotos) return out;
      }
    }
    if (out.isEmpty) {
      final one = photoUrl.trim();
      if (one.isNotEmpty) out.add(one);
    }
    return out;
  }

  List<String> get displayPhotos {
    if (photoUrls.isNotEmpty) {
      return photoUrls
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(maxPhotos)
          .toList(growable: false);
    }
    final one = photoUrl.trim();
    return one.isEmpty ? const <String>[] : <String>[one];
  }

  String get coverPhotoUrl {
    final list = displayPhotos;
    return list.isEmpty ? '' : list.first;
  }

  bool get isActive => status == 'active';
  bool get isBlocked => status == 'blocked';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
  bool get isExpired => status == 'expired';
  bool get hasVideo => clipIds.isNotEmpty;
  bool get hasPrice => price > 0;

  /// Карточка/варақдаги нарх матни — ягона [formatOfferPrice] орқали; кўрсатиладиган нарх йўқ бўлса `''`.
  /// `fixed` учун аввалги `formatMoney(price)` билан айнан бир хил.
  String priceLabel(String Function(String key) tr) => formatOfferPrice(price, priceUnit, tr);
  bool get isBoosted =>
      boostUntil != null && boostUntil!.isAfter(DateTime.now());
  bool get socialPosted => socialPostedAt != null;
  bool get isVitrineReady =>
      isActive && coverPhotoUrl.isNotEmpty && hasVideo;

  factory TvShopItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      TvShopItem.fromMap(doc.id, doc.data()!);

  /// Хом маълумотдан (❤ Танланганлар экрани манба ҳужжатини шундай очади).
  factory TvShopItem.fromMap(String docId, Map<String, dynamic> d) {
    final rawClips = d['clipIds'];
    final photos = normalizePhotos(
      rawUrls: d['photoUrls'] as List?,
      photoUrl: (d['photoUrl'] ?? '') as String,
    );
    return TvShopItem(
      id: docId,
      ownerPhone: (d['ownerPhone'] ?? '') as String,
      ownerName: (d['ownerName'] ?? '') as String,
      title: (d['title'] ?? '') as String,
      price: (d['price'] ?? 0) as int,
      photoUrl: photos.isNotEmpty ? photos.first : '',
      photoUrls: photos,
      kind: (d['kind'] ?? 'product') as String,
      districtId: (d['districtId'] ?? '') as String,
      districtLabel: (d['districtLabel'] ?? '') as String,
      description: (d['description'] ?? '') as String,
      clipIds: rawClips is List
          ? rawClips.map((e) => '$e').where((e) => e.isNotEmpty).toList()
          : const [],
      viewCount: (d['viewCount'] ?? 0) as int,
      boostUntil: (d['boostUntil'] as Timestamp?)?.toDate(),
      socialConsent: d['socialConsent'] == true,
      socialPostedAt: (d['socialPostedAt'] as Timestamp?)?.toDate(),
      status: (d['status'] ?? 'active') as String,
      badge: ProductBadgeData.fromMap(d),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      businessId: (d['businessId'] ?? '') is String ? (d['businessId'] ?? '') as String : '',
      priceUnit: PriceUnit.fromWire(d['priceUnit']),
      expiresAt: _tsOrNull(d['expiresAt']),
      submittedAt: _tsOrNull(d['submittedAt']),
      rejectReason: d['rejectReason'] is String ? (d['rejectReason'] as String).trim() : '',
      market: d['market'] is String ? (d['market'] as String).trim() : '',
      category: d['category'] is String ? (d['category'] as String).trim() : '',
      attrs: d['attrs'] is Map
          ? {for (final e in (d['attrs'] as Map).entries) '${e.key}': e.value as Object?}
          : const {},
      imported: d['imported'] is bool ? d['imported'] as bool : null,
      regionId: d['regionId'] is String ? (d['regionId'] as String).trim() : '',
      taxonomyVersion: d['taxonomyVersion'] is int ? d['taxonomyVersion'] as int : 0,
      unitWeightG: d['unitWeightG'] is int && (d['unitWeightG'] as int) >= 1 && (d['unitWeightG'] as int) <= maxUnitWeightG
          ? d['unitWeightG'] as int
          : null,
    );
  }

  /// `Timestamp` → `DateTime`; бошқа тур (эски/бузилган ҳужжат) — `null` (crash эмас).
  static DateTime? _tsOrNull(Object? v) => v is Timestamp ? v.toDate() : null;

  Map<String, dynamic> toMap() {
    final photos = normalizePhotos(rawUrls: photoUrls, photoUrl: photoUrl);
    return {
      if (businessId.isNotEmpty) 'businessId': businessId,
      'ownerPhone': ownerPhone,
      'ownerName': ownerName,
      'title': title,
      'price': price,
      // Белгиланган нархда майдон йўқ — эски ҳужжат/APK билан бир хил шакл (26-банд).
      if (priceUnit != PriceUnit.fixed) 'priceUnit': priceUnit.wire,
      'photoUrl': photos.isNotEmpty ? photos.first : photoUrl,
      'photoUrls': photos,
      'kind': kind,
      // «Бозорлар» майдонлари — фақат бор бўлса (Аралаш/эски шакл ўзгармайди, 26-банд).
      if (market.isNotEmpty) 'market': market,
      if (market.isNotEmpty && category.isNotEmpty) 'category': category,
      if (attrs.isNotEmpty) 'attrs': attrs,
      if (imported != null) 'imported': imported,
      if (regionId.isNotEmpty) 'regionId': regionId,
      if (taxonomyVersion >= 1) 'taxonomyVersion': taxonomyVersion,
      if (unitWeightG != null) 'unitWeightG': unitWeightG,
      'districtId': districtId,
      'districtLabel': districtLabel,
      'description': description,
      'clipIds': clipIds,
      'viewCount': viewCount,
      if (boostUntil != null) 'boostUntil': Timestamp.fromDate(boostUntil!),
      'socialConsent': socialConsent,
      if (socialPostedAt != null)
        'socialPostedAt': Timestamp.fromDate(socialPostedAt!),
      'status': status,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }
}

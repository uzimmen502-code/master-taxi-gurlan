import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/price_unit.dart';

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
  });

  final String ownerPhone;
  final String name;
  final DateTime? createdAt;

  /// `active` | `blocked` — фақат админ ўрнатади (`adminSetShopStatus`); эски ҳужжатларда йўқ (= `active`).
  final String status;

  /// «Маҳсулотни топшириш жойи» («Бозорлар» STAGE 11): курьер шу ердан олади (сервер `tv_shops/{phone}`
  /// `pickupLat`/`pickupLng` — сон, `pickupAddress`). Эски ҳужжатларда йўқ → буюртма қилиб бўлмайди.
  final double? pickupLat;
  final double? pickupLng;
  final String pickupAddress;

  bool get isBlocked => status == 'blocked';

  /// Топшириш жойи белгиланган (сервер `validLatLng` кўзгуси: 0,0 — йўқ).
  bool get hasPickup =>
      pickupLat != null &&
      pickupLng != null &&
      pickupLat!.abs() <= 90 &&
      pickupLng!.abs() <= 180 &&
      !(pickupLat == 0 && pickupLng == 0);

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
  });

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

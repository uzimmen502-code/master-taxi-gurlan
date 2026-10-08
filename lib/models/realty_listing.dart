import 'package:cloud_firestore/cloud_firestore.dart';

/// Битим тури — Сотиш ёки Ижара.
enum RealtyDeal { sale, rent }

extension RealtyDealX on RealtyDeal {
  String get key => this == RealtyDeal.sale ? 'sale' : 'rent';

  static RealtyDeal parse(Object? raw) =>
      '${raw ?? ''}' == 'rent' ? RealtyDeal.rent : RealtyDeal.sale;
}

/// Эълон даражаси — концепциядаги учта TAB.
///
/// [plain] бепул (эгасига 2 тагача объект), [promo] ва [urgent] пуллик.
/// Янги эълон ДОИМ [plain] бўлиб туғилади; пуллик даража мавжуд
/// объектга «Менинг объектларим»дан сотиб олинади
/// (`purchaseRealtyTier`) — бир уй учта эмас, битта ёзув.
enum RealtyTier { plain, promo, urgent }

extension RealtyTierX on RealtyTier {
  String get key {
    switch (this) {
      case RealtyTier.plain:
        return 'plain';
      case RealtyTier.promo:
        return 'promo';
      case RealtyTier.urgent:
        return 'urgent';
    }
  }

  bool get isPaid => this != RealtyTier.plain;

  /// Пуллик даража муддат вариантлари — сервердаги `PAID_DURATIONS`
  /// билан бир хил бўлиши шарт.
  List<int> get durationOptions {
    switch (this) {
      case RealtyTier.promo:
        return const [7, 15, 30];
      case RealtyTier.urgent:
        return const [3, 7, 15];
      case RealtyTier.plain:
        return const [];
    }
  }

  // Муддат (30 кун) ва бепул объект лимити (2 та) АТАЙЛАБ бу ерда
  // ЁЗИЛМАГАН: уларни сервер ҳисоблайди (`functions/realty.js` даги
  // `PLAIN_EXPIRY_DAYS` ва `FREE_PLAIN_LIMIT`), илова эса ҳақиқий
  // ҳолатни `getRealtyQuota` ва `expiresAt` дан олади. Иккита нусха
  // бўлса, биттаси ўзгарганда илова ёлғон сон кўрсатар эди.

  static RealtyTier parse(Object? raw) {
    switch ('${raw ?? ''}') {
      case 'promo':
        return RealtyTier.promo;
      case 'urgent':
        return RealtyTier.urgent;
      default:
        return RealtyTier.plain;
    }
  }
}

/// Мурожаат усули — мулк эгасининг ўзига ёки AVA риэлторлик хизматига.
/// AVA ҳеч кимни риэлторга мажбуран боғламайди (концепция, 3-бўлим).
enum RealtyContactMode { owner, avaAgent }

extension RealtyContactModeX on RealtyContactMode {
  String get key => this == RealtyContactMode.owner ? 'owner' : 'ava_agent';

  static RealtyContactMode parse(Object? raw) =>
      '${raw ?? ''}' == 'ava_agent'
          ? RealtyContactMode.avaAgent
          : RealtyContactMode.owner;
}

/// `realty_listings` ҳужжати — «Кўчмас мулк Кластери»нинг битта объекти.
///
/// Концепциянинг 6-бўлими: бир уй ОДДИЙ, РЕКЛАМА ва СРОЧНО учун уч марта
/// яратилмайди — барча статус ва боғламалар айнан шу битта ёзувга уланади.
/// Шунинг учун [tier] ҳужжатнинг майдони, алоҳида ҳужжат эмас.
///
/// Нега `ads` эмас: бу ёзувда мажбурий координата, иккита пуллик статус
/// муддати, видео боғламалари ва муддат тугаганда автоўчириш бор — булар
/// `ads` схемасига сиғмайди. Эълон матни майдонлари ва қоидалари эса
/// `ads`даги билан бир хил қолади (концепция, 3-бўлим).
class RealtyListing {
  const RealtyListing({
    required this.id,
    required this.ownerKey,
    required this.ownerName,
    required this.deal,
    required this.tier,
    required this.title,
    required this.text,
    required this.areaLat,
    required this.areaLng,
    required this.status,
    this.priceText = '',
    this.priceAmount,
    this.rooms,
    this.floor,
    this.totalFloors,
    this.areaM2,
    this.imageUrls = const [],
    this.geohash4 = '',
    this.addressText = '',
    this.contactMode = RealtyContactMode.owner,
    this.hasAgent = false,
    this.avagramClipId = '',
    this.adClipId = '',
    this.districtId = '',
    this.regionId = '',
    this.tierUntil,
    this.createdAt,
    this.updatedAt,
    this.expiresAt,
  });

  final String id;

  /// Эганинг ОПАҚ калити (`users/{uid}.realtyOwnerKey`) — телефон эмас.
  ///
  /// Телефон очиқ ҳужжатда сақланмайди: у ахборот пакети сотадиган
  /// нарсанинг бир қисми, шунинг учун [RealtyDetail] ичида.
  final String ownerKey;
  final String ownerName;

  final RealtyDeal deal;
  final RealtyTier tier;

  final String title;
  final String text;
  final String priceText;

  /// Ихтиёрий РАҚАМЛИ нарх (бутун сўм; ижарада — ойига). Хабарноманинг
  /// нарх фильтри шу бўйича ишлайди; кўрсатиш учун [priceText].
  final int? priceAmount;

  final int? rooms;
  final int? floor;
  final int? totalFloors;
  final num? areaM2;

  final List<String> imageUrls;

  /// ТАХМИНИЙ нуқта — аниқ координата ≈1.2 км радиусда БИР МАРТА
  /// силкитилган (сервердаги `jitteredPoint`).
  ///
  /// Бу объектнинг аниқ жойи ЭМАС. Аниқ нуқта [RealtyDetail] да ва
  /// фақат эга, админ ёки пакетидан шу объектни очган харидорга
  /// кўринади (концепция, 9-бўлим: «Пакетсиз — тахминий ҳудуд»).
  final double areaLat;
  final double areaLng;

  /// Харита катакчаси — `GeoHash.encode(lat, lng, precision: 4)`.
  final String geohash4;

  /// ЭСКИ ёзувлардаги ОЧИҚ манзил. 2026-10-08 дан манзил ёпиқ ҳужжатда
  /// ([RealtyDetail.addressText]) — бу майдон фақат миграциягача
  /// қолган ёзувларда бўлади ва пакетсиз КЎРСАТИЛМАЙДИ.
  final String addressText;

  final RealtyContactMode contactMode;

  /// AVA риэлторлик хизмати рақами ёзилганми (рақамнинг ўзи ёпиқ).
  final bool hasAgent;

  /// AVAGram видеоси (бепул) ва видео-реклама (пуллик) — иккови ҳам
  /// ихтиёрий. Бўш бўлса эълонда «Видеони кўриш» тугмаси кўринмайди.
  final String avagramClipId;
  final String adClipId;

  /// `pending` | `active` | `blocked`.
  final String status;

  final String districtId;
  final String regionId;

  /// РЕКЛАМА/СРОЧНО муддати тугайдиган вақт. [RealtyTier.plain] да null.
  final DateTime? tierUntil;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Объектнинг ўзи ўчириладиган вақт (концепция, 9-бўлим: муддат тугаса
  /// эълон лентадан ҳам, харитадан ҳам йўқолади).
  final DateTime? expiresAt;

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';

  bool get hasVideo => avagramClipId.isNotEmpty || adClipId.isNotEmpty;

  /// Эълонга боғланган видео — аввал пуллик реклама, кейин AVAGram.
  String get videoClipId => adClipId.isNotEmpty ? adClipId : avagramClipId;

  bool get isExpired {
    final exp = expiresAt;
    return exp != null && exp.isBefore(DateTime.now());
  }

  String get titleOrText => title.trim().isEmpty ? text : title.trim();

  /// «3 хона · 4/9 қават · 68 м²» — бўш майдонлар тушиб қолади.
  String get specsLabel {
    final parts = <String>[
      if (rooms != null) '$rooms хона',
      if (floor != null)
        totalFloors != null ? '$floor/$totalFloors қават' : '$floor-қават',
      if (areaM2 != null) '${_trimNum(areaM2!)} м²',
    ];
    return parts.join(' · ');
  }

  static String _trimNum(num v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  factory RealtyListing.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      RealtyListing.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});

  factory RealtyListing.fromMap(String id, Map<String, dynamic> d) {
    return RealtyListing(
      id: id,
      ownerKey: (d['ownerKey'] ?? '') as String,
      ownerName: (d['ownerName'] ?? '') as String,
      deal: RealtyDealX.parse(d['deal']),
      tier: RealtyTierX.parse(d['tier']),
      title: (d['title'] ?? '') as String,
      text: (d['text'] ?? '') as String,
      priceText: (d['priceText'] ?? '') as String,
      priceAmount: (d['priceAmount'] as num?)?.toInt(),
      rooms: (d['rooms'] as num?)?.toInt(),
      floor: (d['floor'] as num?)?.toInt(),
      totalFloors: (d['totalFloors'] as num?)?.toInt(),
      areaM2: d['areaM2'] as num?,
      imageUrls: List<String>.from(d['imageUrls'] ?? const <String>[]),
      areaLat: (d['areaLat'] as num?)?.toDouble() ?? 0,
      areaLng: (d['areaLng'] as num?)?.toDouble() ?? 0,
      geohash4: (d['geohash4'] ?? '') as String,
      addressText: (d['addressText'] ?? '') as String,
      contactMode: RealtyContactModeX.parse(d['contactMode']),
      hasAgent: d['hasAgent'] == true,
      avagramClipId: (d['avagramClipId'] ?? '') as String,
      adClipId: (d['adClipId'] ?? '') as String,
      status: (d['status'] ?? 'active') as String,
      districtId: ((d['districtId'] ?? '') as String).trim(),
      regionId: ((d['regionId'] ?? '') as String).trim(),
      tierUntil: _parseDate(d['tierUntil']),
      createdAt: _parseDate(d['createdAt']),
      updatedAt: _parseDate(d['updatedAt']),
      expiresAt: _parseDate(d['expiresAt']),
    );
  }

  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}

/// `realty_listings/{id}/private/detail` — ПУЛЛИК ахборот.
///
/// Аниқ координата ва алоқа рақами. Firestore қоидаси уни фақат учта
/// ҳолатда беради: сўровчи — эга, админ, ёки шу объектни ахборот
/// пакетидан очган харидор. Рухсат бўлмаса ўқиш `permission-denied`
/// билан тугайди ва репозиторий `null` қайтаради — бу хато эмас,
/// нормал «ҳали очилмаган» ҳолат.
class RealtyDetail {
  const RealtyDetail({
    required this.lat,
    required this.lng,
    required this.ownerPhone,
    this.addressText = '',
  });

  final double lat;
  final double lng;
  final String ownerPhone;

  /// Кўча ва уй рақами — ПУЛЛИК (эга қарори 2026-10-08). Эски ёзувда
  /// бўш бўлиши мумкин: унда манзил ҳали очиқ ҳужжатда.
  final String addressText;

  /// Очилган эълоннинг манзили: аввал ёпиқ ҳужжатдан, эски ёзувда —
  /// очиқдагидан ([legacyPublic]).
  String addressOr(String legacyPublic) =>
      addressText.trim().isNotEmpty ? addressText.trim() : legacyPublic.trim();

  /// Харидор босадиган рақам — эга танлаган мурожаат усулига мос.
  ///
  /// [agentPhone] — AVA риэлторлик хизматининг ЖОРИЙ рақами
  /// (`settings/app.realtyAgentPhone`). У эълон ёзувида сақланмайди
  /// (эга қарори, 2026-10-02): аввал ҳар бир эълонга нусхаланар эди ва
  /// созламадаги рақам ўзгарганда эски эълонлар ишламайдиган рақам
  /// билан қолиб кетарди. Бўш бўлса — эганинг ўз рақами.
  String contactPhone(RealtyContactMode mode, {String agentPhone = ''}) =>
      mode == RealtyContactMode.avaAgent && agentPhone.isNotEmpty
          ? agentPhone
          : ownerPhone;

  factory RealtyDetail.fromMap(Map<String, dynamic> d) => RealtyDetail(
        lat: (d['lat'] as num?)?.toDouble() ?? 0,
        lng: (d['lng'] as num?)?.toDouble() ?? 0,
        ownerPhone: (d['ownerPhone'] ?? '') as String,
        addressText: (d['addressText'] ?? '') as String,
      );
}

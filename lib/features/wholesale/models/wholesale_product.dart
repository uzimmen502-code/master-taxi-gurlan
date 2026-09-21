import 'package:cloud_firestore/cloud_firestore.dart';

import '../../ads/utils/ad_search_text.dart';

/// Улгуржи нарх поғонаси: `minQty`дан бошлаб шу нархда сотилади
/// (масалан 1-9 дона — 10000 сўм, 10+ дона — 9000 сўм).
class WholesalePriceTier {
  const WholesalePriceTier({required this.minQty, required this.price});

  final int minQty;
  final int price;

  factory WholesalePriceTier.fromMap(Map<String, dynamic> m) =>
      WholesalePriceTier(
        minQty: (m['minQty'] as num?)?.toInt() ?? 1,
        price: (m['price'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {'minQty': minQty, 'price': price};

  /// «10+: 9 000 сўм» — қисқа кўриниш (admin/тафсилот учун).
  String label(String unit) => '$minQty+ $unit: $price сўм';
}

/// Поғоналарни `minQty` бўйича ўсиш тартибида саралайди (дублика ва
/// нотўғри қийматлар четлаб ўтилади).
List<WholesalePriceTier> sortWholesalePriceTiers(
  List<WholesalePriceTier> tiers,
) {
  final clean = tiers.where((t) => t.minQty >= 1 && t.price > 0).toList()
    ..sort((a, b) => a.minQty.compareTo(b.minQty));
  return clean;
}

/// Улгуржи/кичик улгуржи маҳсулот эълони — `wholesale_products/{id}`.
///
/// `ads`даги `AdModel` андозасига мос: эга ҳеч қачон ўзини `active`
/// қилолмайди (Firestore Rules), фақат admin тасдиғи орқали.
class WholesaleProduct implements AdSearchable {
  const WholesaleProduct({
    required this.id,
    required this.sellerId,
    required this.sellerCompanyName,
    required this.title,
    required this.titleLower,
    required this.description,
    required this.priceTiers,
    this.unit = 'дона',
    this.imageUrls = const [],
    this.status = statusPending,
    this.views = 0,
    this.videoClipIds = const [],
    this.searchTokens = const [],
    this.createdAt,
    this.updatedAt,
    this.publishedAt,
    this.adminNote = '',
    this.moderatedAt,
    this.moderatedBy = '',
  });

  static const maxImages = 5;
  static const maxVideoClips = 5;
  static const maxPriceTiers = 5;
  static const statusPending = 'pending';
  static const statusActive = 'active';
  static const statusInactive = 'inactive';

  final String id;

  /// Сотувчининг каноник телефони (`wholesale_sellers` ҳужжат ID'си).
  final String sellerId;
  final String sellerCompanyName;
  final String title;
  @override
  final String titleLower;
  @override
  final String description;

  /// Нарх поғоналари — `minQty` бўйича ўсиш тартибида (энг камида 1 та).
  final List<WholesalePriceTier> priceTiers;
  final String unit;
  final List<String> imageUrls;

  /// `pending` | `active` | `inactive`.
  final String status;
  final int views;

  /// `tv_clips` ID'лари — видеообзор/пуллик реклама сифатида боғланган
  /// AVAGram видеолари (TvShopItem'даги `clipIds` андозаси).
  final List<String> videoClipIds;
  @override
  final List<String> searchTokens;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? publishedAt;
  final String adminNote;
  final DateTime? moderatedAt;
  final String moderatedBy;

  bool get isPending => status == statusPending;
  bool get isActive => status == statusActive;
  bool get isInactive => status == statusInactive;

  /// Минимал буюртма сони — энг паст поғона.
  int get moq => priceTiers.isEmpty ? 1 : priceTiers.first.minQty;

  /// Бошланғич нарх ("дан ... сўм") — энг паст поғона нархи.
  int get basePrice => priceTiers.isEmpty ? 0 : priceTiers.first.price;

  static DateTime? _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static List<WholesalePriceTier> _parseTiers(dynamic raw) {
    if (raw is! List) return const [];
    final tiers = raw
        .whereType<Map>()
        .map((m) => WholesalePriceTier.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    return sortWholesalePriceTiers(tiers);
  }

  factory WholesaleProduct.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final title = (d['title'] as String?)?.trim() ?? '';
    final description = (d['description'] as String?)?.trim() ?? '';
    final rawTokens = d['searchTokens'];
    final tokens = rawTokens is List
        ? rawTokens.map((e) => e.toString()).where((t) => t.isNotEmpty).toList()
        : AdSearchText.buildTokens(title, description);
    return WholesaleProduct(
      id: doc.id,
      sellerId: (d['sellerId'] as String?) ?? '',
      sellerCompanyName: (d['sellerCompanyName'] as String?)?.trim() ?? '',
      title: title,
      titleLower: title.toLowerCase(),
      description: description,
      priceTiers: _parseTiers(d['priceTiers']),
      unit: (d['unit'] as String?)?.trim().isNotEmpty == true
          ? (d['unit'] as String).trim()
          : 'дона',
      imageUrls: List<String>.from(d['imageUrls'] ?? const <String>[]),
      status: (d['status'] as String?)?.trim() ?? statusPending,
      views: (d['views'] as num?)?.toInt() ?? 0,
      videoClipIds: List<String>.from(d['videoClipIds'] ?? const <String>[]),
      searchTokens: tokens,
      createdAt: _parseDate(d['createdAt']),
      updatedAt: _parseDate(d['updatedAt']),
      publishedAt: _parseDate(d['publishedAt']),
      adminNote: (d['adminNote'] as String?) ?? '',
      moderatedAt: _parseDate(d['moderatedAt']),
      moderatedBy: (d['moderatedBy'] as String?) ?? '',
    );
  }

  /// Яратиш учун — Firestore Rules текширади: `status` фақат `pending`,
  /// ёки [autoApproved] (`settings/app.wholesaleProductAutoApprove` ёқиқ
  /// бўлса) `active` бўлиши мумкин.
  Map<String, dynamic> toFirestoreCreate({bool autoApproved = false}) {
    final tiers = sortWholesalePriceTiers(priceTiers);
    return {
      'sellerId': sellerId,
      'sellerCompanyName': sellerCompanyName,
      'title': title,
      'titleLower': title.toLowerCase(),
      'description': description,
      'priceTiers': tiers.take(maxPriceTiers).map((t) => t.toMap()).toList(),
      'unit': unit,
      'imageUrls': imageUrls.take(maxImages).toList(growable: false),
      'status': autoApproved ? statusActive : statusPending,
      'views': 0,
      'videoClipIds': <String>[],
      'searchTokens': AdSearchText.buildTokens(title, description),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (autoApproved) 'publishedAt': FieldValue.serverTimestamp(),
      if (autoApproved) 'moderatedAt': FieldValue.serverTimestamp(),
      if (autoApproved) 'moderatedBy': 'auto',
    };
  }

  /// Эга томонидан таҳрирлаш — контент майдонлари + `pending`га қайтариш.
  /// Rules эгага ҳеч қачон `active`га ўтишга рухсат бермайди.
  Map<String, dynamic> toFirestoreOwnerUpdate() {
    final tiers = sortWholesalePriceTiers(priceTiers);
    return {
      'title': title,
      'titleLower': title.toLowerCase(),
      'description': description,
      'priceTiers': tiers.take(maxPriceTiers).map((t) => t.toMap()).toList(),
      'unit': unit,
      'imageUrls': imageUrls.take(maxImages).toList(growable: false),
      'searchTokens': AdSearchText.buildTokens(title, description),
      'status': statusPending,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

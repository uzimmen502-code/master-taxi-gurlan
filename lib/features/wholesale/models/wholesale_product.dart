import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/price_tier.dart';
import '../../ads/utils/ad_search_text.dart';
import 'shipping_dims.dart';

export '../../../models/price_tier.dart' show PriceTier;
export 'shipping_dims.dart';

/// Нарх поғонаси таърифи `lib/models/price_tier.dart` га кўчирилди
/// (2026-09-29): энди AVA дўкони товари ҳам айнан шу поғоналар билан
/// сотилади ва Улгуржи лентасида кўринади, шунинг учун таъриф битта
/// бўлиши керак. Бу ерда эски ном сақлаб қолинган — улгуржи модули,
/// формаси, карточкаси ва админ панели уни шу ном билан ишлатади.
typedef WholesalePriceTier = PriceTier;

/// Эски ном — [sortPriceTiers] нинг тақалмаси.
List<WholesalePriceTier> sortWholesalePriceTiers(
  List<WholesalePriceTier> tiers,
) =>
    sortPriceTiers(tiers);

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
    this.market = marketWholesale,
    this.currency = '',
    this.deliveryDays,
    this.unitWeightG,
    this.unitDims,
  });

  /// Улгуржи бозор (ички сотувчилар) — нархи сўмда.
  static const marketWholesale = 'wholesale';

  /// Хитой бозори — валютали нарх ва етказиш муддати бор.
  /// Архитектураси улгуржи билан БИР ХИЛ (эга қарори): ўша коллекция,
  /// ўша қоидалар, фақат `market` майдони билан ажралади.
  static const marketChina = 'china';

  /// 1..7 (эга қарори, 2026-10-17; аввал 5) — `firestore.rules`даги
  /// `wholesaleProductCreateOk` / `wholesaleProductOwnerUpdateOk` билан бир хил.
  static const maxImages = 7;
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

  /// `wholesale` | `china`. Эски ёзувларда бўш — улар улгуржи бозор.
  final String market;

  /// Хитой бозори учун валюта белгиси («$», «¥»); бўш бўлса сўм.
  final String currency;

  /// Хитой бозори учун етказиш муддати (кун); маълум бўлмаса `null`.
  final int? deliveryDays;

  /// Етказиш ҳақи учун — БИР ДОНА (бир [unit]) товарнинг вазни, грамм.
  /// Эски товарларда йўқ (У1, 2026-10-09): киритилмагунча буюртма
  /// қилиб бўлмайди, фақат қўнғироқ (ўтиш даври).
  final int? unitWeightG;

  /// Бир дона товарнинг ўлчами, см — ҳажмий вазн учун.
  final ShippingDims? unitDims;

  /// Етказиш ҳақини ҳисоблаш учун маълумот тўлиқми.
  bool get hasShippingData => (unitWeightG ?? 0) > 0;

  /// Бир дона учун пулли вазн (грамм); маълумот йўқ бўлса 0.
  int get unitChargeableWeightG =>
      hasShippingData ? chargeableWeightG(unitWeightG!, unitDims) : 0;

  bool get isChina => market == marketChina;

  /// Маҳсулот [m] бозорига тегишлими. Ягона қоида (иловадаги лента,
  /// сотувчининг ўз рўйхати ва админ панел — ҳаммаси шуни ишлатади):
  /// Хитой — фақат `market == 'china'`; Улгуржи — қолган ҳамма, жумладан
  /// `market` майдони йўқ эски ёзувлар.
  bool belongsToMarket(String m) => m == marketChina ? isChina : !isChina;

  /// Бозорнинг модул калити (`config/module_defaults` дарвозаси ва
  /// хизмат белгиси). Хитой бозорининг дарвозаси алоҳида (эга қарори,
  /// 2026-09-28), шунинг учун Хитой оқими `wholesale_market` ни эмас,
  /// `china_market` ни текшириши керак.
  static String moduleIdFor(String market) =>
      market == marketChina ? 'china_market' : 'wholesale_market';

  /// Нарх ёнидаги валюта белгиси — Хитой бозорида ўзиники, қолганда сўм.
  String get currencyLabel =>
      currency.trim().isNotEmpty ? currency.trim() : kCurrencySum;

  /// «дан 9 000 $ / дона» — карточка ва тафсилотдаги ягона нарх сатри.
  String get priceLine =>
      '${priceTiers.length > 1 ? 'дан ' : ''}'
      '${formatPrice(basePrice)} $currencyLabel / $unit';

  bool get isPending => status == statusPending;
  bool get isActive => status == statusActive;
  bool get isInactive => status == statusInactive;

  /// Минимал буюртма сони — энг паст поғона.
  int get moq => priceTiers.isEmpty ? 1 : priceTiers.first.minQty;

  /// Бошланғич нарх ("дан ... сўм") — энг паст поғона нархи.
  int get basePrice => priceTiers.isEmpty ? 0 : priceTiers.first.price;

  /// [qty] даги бир дона нархи (поғона қоидаси — `price_tier.dart`).
  /// Фақат кўрсатиш учун: ҳақиқий нархни буюртмада сервер ҳисоблайди.
  int priceForQty(int qty) => tierPriceForQty(priceTiers, qty) ?? 0;

  static DateTime? _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static List<WholesalePriceTier> _parseTiers(dynamic raw) =>
      parsePriceTiers(raw);

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
      market: (d['market'] as String?)?.trim().isNotEmpty == true
          ? (d['market'] as String).trim()
          : marketWholesale,
      currency: (d['currency'] as String?)?.trim() ?? '',
      deliveryDays: (d['deliveryDays'] as num?)?.toInt(),
      unitWeightG: _positiveInt(d['unitWeightG']),
      unitDims: ShippingDims.fromMap(d['unitDims']),
    );
  }

  static int? _positiveInt(dynamic v) {
    final n = v is num ? v.toInt() : null;
    return n != null && n > 0 ? n : null;
  }

  /// Етказиш майдонлари — яратиш ва таҳрирда бир хил; йўқ бўлса ёзилмайди
  /// (таҳрирда ўчириш = `FieldValue.delete()`, Rules калитга рухсат беради).
  Map<String, dynamic> _shippingFields({required bool forUpdate}) => {
        if (unitWeightG != null)
          'unitWeightG': unitWeightG
        else if (forUpdate)
          'unitWeightG': FieldValue.delete(),
        if (unitDims != null)
          'unitDims': unitDims!.toMap()
        else if (forUpdate)
          'unitDims': FieldValue.delete(),
      };

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
      'market': market,
      if (currency.trim().isNotEmpty) 'currency': currency.trim(),
      if (deliveryDays != null) 'deliveryDays': deliveryDays,
      ..._shippingFields(forUpdate: false),
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
      // `market` бу ерда ЙЎҚ — Rules эгага маҳсулотни бир бозордан
      // бошқасига кўчиришга рухсат бермайди. Валюта ва етказиш муддати
      // эса таҳрирланади, лекин фақат Хитой бозорида — улгуржида бу
      // майдонлар ишлатилмайди, шунинг учун уларга тегилмайди.
      if (isChina) 'currency': currency.trim(),
      if (isChina) 'deliveryDays': deliveryDays ?? FieldValue.delete(),
      ..._shippingFields(forUpdate: true),
    };
  }
}

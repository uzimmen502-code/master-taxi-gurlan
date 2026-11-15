// «Эълонлар модерацияси» (Бозорлар 2b, эга 2026-11-15) — соф мантиқ (тестланади).
//
// Сервер: `adminModerateListing({collection, id, decision, reason?})` — `functions/market_moderation.js`.
// Коллекциялар: tv_shop_items · wholesale_products (Улгуржи/Хитой — `market` бўйича) · realty_listings ·
// ads (фақат `type == 'cheap_product'`). Рад этиш сабаби 1..300 белги (сервер `normalizeReason`).
// Админ панели матнлари — кирилл (панель конвенцияси; панелда l10n йўқ).

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import '../../../core/utils/formatters.dart';
import '../../tv_market/domain/price_unit.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../services/admin_callable.dart';

/// Рад этиш сабабининг юқори чегараси (сервер `REASON_MAX`).
const kListingRejectReasonMax = 300;

/// Сўров чегараси (композит индекссиз: фақат `status` бўйича, тартиб — клиентда).
const kListingModPageLimit = 100;

enum ListingModSource {
  shop('tv_shop_items', 'Аралаш / дўкон'),

  /// «Админ тузатиб тасдиқлайди» (эга 2026-11-15): рад этилган tv_shop_items сотувчи томонидан қайта
  /// юборилмайди — админ шу ерда тузатиб тасдиқлайди (сервер `APPROVE_FROM.tv_shop_items`: pending|rejected).
  shopRejected('tv_shop_items', 'Рад этилганлар', status: 'rejected'),
  wholesale('wholesale_products', 'Улгуржи'),
  china('wholesale_products', 'Хитой'),
  realty('realty_listings', 'Уй-жой'),
  ads('ads', 'Эски эълонлар');

  const ListingModSource(this.collection, this.label, {this.status = 'pending'});

  /// `adminModerateListing` `collection` қиймати.
  final String collection;
  final String label;

  /// Навбат сўрови: `status == [status]`.
  final String status;

  /// Тузатиб тасдиқлаш мумкинми (сервер `EDIT_COLLECTIONS` — фақат tv_shop_items).
  bool get editable => collection == 'tv_shop_items';

  /// Рад этиш тугмаси (рад этилганни қайта рад этиб бўлмайди — сервер `LISTING_NOT_PENDING`).
  bool get canReject => status == 'pending';
}

/// Модерация навбатидаги битта эълон (кўриниш учун; манба ҳужжат — Firestore).
class ListingModItem {
  const ListingModItem({
    required this.source,
    required this.id,
    required this.title,
    required this.priceText,
    required this.photoUrl,
    required this.seller,
    required this.market,
    required this.category,
    required this.submittedAt,
    this.description = '',
    this.price = 0,
    this.priceUnit = '',
    this.photoUrls = const [],
    this.rejectReason = '',
    this.categoryValue = '',
  });

  /// Тузатиш диалоги учун хом қийматлар (фақат tv_shop_items тўлдирилади).
  final String description;
  final int price;

  /// `priceUnit` wire қиймати ('' — белгиланган нарх).
  final String priceUnit;

  /// Жорий `photoUrls` (бўш сатрлар олиб ташланган; сервер фақат қисм-тўпламни қабул қилади).
  final List<String> photoUrls;
  final String rejectReason;

  /// Ҳужжатдаги category айнан (кўриниш учун [category] kindга қайтиши мумкин — тузатишда шу ишлатилади).
  final String categoryValue;

  final ListingModSource source;
  final String id;
  final String title;
  final String priceText;
  final String photoUrl;
  final String seller;

  /// Бозор (`tv_shop_items.market` / `wholesale_products.market`); йўқ — бўш.
  final String market;
  final String category;

  /// `submittedAt`, бўлмаса `createdAt` (эски ҳужжат); иккаласи ҳам йўқ — `null`.
  final DateTime? submittedAt;
}

DateTime? _date(Object? v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

String _str(Object? v) => v is String ? v.trim() : '';

int _int(Object? v) => v is num ? v.toInt() : 0;

String _firstUrl(Map<String, dynamic> d, List<String> listKeys, [String? singleKey]) {
  for (final k in listKeys) {
    final raw = d[k];
    if (raw is List) {
      for (final e in raw) {
        final s = e is String ? e.trim() : '';
        if (s.isNotEmpty) return s;
      }
    }
  }
  return singleKey == null ? '' : _str(d[singleKey]);
}

/// Хом ҳужжат → [ListingModItem]. Майдон номлари — мавжуд моделлардан (`TvShopItem`, `WholesaleProduct`,
/// `RealtyListing`, `AdModel`). Нотўғри турдаги майдон — бўш қиймат (crash эмас).
ListingModItem listingModItemFromRaw(ListingModSource source, String id, Map<String, dynamic> d) {
  final submitted = _date(d['submittedAt']) ?? _date(d['createdAt']);
  switch (source) {
    case ListingModSource.shop:
    case ListingModSource.shopRejected:
      final price = _int(d['price']);
      final unit = _str(d['priceUnit']);
      final rawPhotos = d['photoUrls'];
      return ListingModItem(
        description: d['description'] is String ? d['description'] as String : '',
        price: price,
        priceUnit: unit,
        // Сервер солиштиради — URL'лар айнан ҳужжатдагидек (trim қилинмайди), фақат бўш/сатр эмаслари ташланади.
        photoUrls: rawPhotos is List ? [for (final e in rawPhotos) if (e is String && e.trim().isNotEmpty) e] : const [],
        rejectReason: _str(d['rejectReason']),
        categoryValue: _str(d['category']),
        source: source,
        id: id,
        title: _str(d['title']),
        priceText: price > 0 ? '${formatMoney(price)}${unit.isEmpty ? '' : ' / $unit'}' : (unit == 'negotiable' ? 'Келишилади' : ''),
        photoUrl: _firstUrl(d, const ['photoUrls'], 'photoUrl'),
        seller: _str(d['ownerName']),
        market: _str(d['market']),
        category: _str(d['category']).isNotEmpty ? _str(d['category']) : _str(d['kind']),
        submittedAt: submitted,
      );
    case ListingModSource.wholesale:
    case ListingModSource.china:
      final p = WholesaleProduct.fromMap(id, d);
      return ListingModItem(
        source: source,
        id: id,
        title: p.title,
        priceText: p.priceTiers.isEmpty ? '' : p.priceLine,
        photoUrl: p.imageUrls.isEmpty ? '' : p.imageUrls.first,
        seller: p.sellerCompanyName,
        market: p.market,
        category: _str(d['category']),
        submittedAt: submitted,
      );
    case ListingModSource.realty:
      final amount = _int(d['priceAmount']);
      final text = _str(d['priceText']);
      return ListingModItem(
        source: source,
        id: id,
        title: _str(d['title']),
        priceText: text.isNotEmpty ? text : (amount > 0 ? formatMoney(amount) : ''),
        photoUrl: _firstUrl(d, const ['imageUrls']),
        seller: _str(d['ownerName']),
        market: '',
        category: _str(d['deal']),
        submittedAt: submitted,
      );
    case ListingModSource.ads:
      final price = _int(d['price']);
      return ListingModItem(
        source: source,
        id: id,
        title: _str(d['title']),
        priceText: price > 0 ? formatMoney(price) : '',
        photoUrl: _firstUrl(d, const ['imageUrls']),
        seller: _str(d['sellerName']),
        market: '',
        category: _str(d['category']),
        submittedAt: submitted,
      );
  }
}

/// Улгуржи/Хитой ажратиш: `market` йўқ эски ҳужжат — Улгуржи (`WholesaleProduct.fromMap` билан бир хил).
bool listingModMatchesSource(ListingModSource source, Map<String, dynamic> d) {
  if (source == ListingModSource.ads) return d['type'] == 'cheap_product';
  if (source != ListingModSource.wholesale && source != ListingModSource.china) return true;
  final m = _str(d['market']);
  final market = m.isEmpty ? WholesaleProduct.marketWholesale : m;
  return source == ListingModSource.china
      ? market == WholesaleProduct.marketChina
      : market != WholesaleProduct.marketChina;
}

/// Навбат тартиби: аввал юборилгани биринчи (FIFO); вақти йўқ — охирида; тенгда — `id`.
List<ListingModItem> sortListingModItems(Iterable<ListingModItem> items) {
  final list = items.toList();
  list.sort((a, b) {
    final x = a.submittedAt;
    final y = b.submittedAt;
    if (x == null && y == null) return a.id.compareTo(b.id);
    if (x == null) return 1;
    if (y == null) return -1;
    final c = x.compareTo(y);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return list;
}

/// Рад этиш сабаби тўғрими (сервер `normalizeReason`: trim, 1..300).
bool listingRejectReasonValid(String? reason) {
  final s = (reason ?? '').trim();
  return s.isNotEmpty && s.length <= kListingRejectReasonMax;
}

// ───────────── «Админ тузатиб тасдиқлайди» (эга 2026-11-15) ─────────────
// Сервер: `adminModerateListing({..., decision: 'approve', edits})` — `validateListingEdits`
// (functions/market_moderation.js). Чегаралар шу ерда сервер/rules билан бир хил; сервер барибир текширади.

const kListingTitleMax = 200;
const kListingDescriptionMax = 2000;
const kListingPriceMax = 999999999;
const kListingCategoryMax = 40;

/// Нарх бирликлари — админ панели (кирилл) номлари. Тартиб ва wire — [PriceUnit] (rules/PRICE_UNITS).
const kListingPriceUnitLabels = <PriceUnit, String>{
  PriceUnit.fixed: 'Белгиланган нарх',
  PriceUnit.from: 'дан (бошланғич)',
  PriceUnit.hour: 'соат',
  PriceUnit.day: 'кун',
  PriceUnit.month: 'ой',
  PriceUnit.session: 'сеанс',
  PriceUnit.person: 'киши',
  PriceUnit.kg: 'кг',
  PriceUnit.ton: 'тонна',
  PriceUnit.m2: 'м²',
  PriceUnit.piece: 'дона',
  PriceUnit.negotiable: 'Келишилади',
};

/// Бозор бўлими (`taxonomy/markets.markets.{market}.categories[]`): `id` ҳужжатга ёзилади.
class ListingModCategory {
  const ListingModCategory(this.id, this.name);
  final String id;
  final String name;
}

/// `taxonomy/markets` хом ҳужжати → бозор бўйича бўлимлар. `all` — фильтр, бўлим эмас (ташланади).
/// Бузилган шакл — бўш (crash эмас; диалогда матн майдони қолади).
Map<String, List<ListingModCategory>> listingModCategoriesFromTaxonomy(Map<String, dynamic>? doc) {
  final out = <String, List<ListingModCategory>>{};
  final markets = doc?['markets'];
  if (markets is! Map) return out;
  markets.forEach((key, value) {
    if (key is! String || value is! Map) return;
    final cats = value['categories'];
    if (cats is! List) return;
    final list = <ListingModCategory>[];
    for (final c in cats) {
      if (c is! Map) continue;
      final id = _str(c['id']);
      if (id.isEmpty || id == 'all') continue;
      final names = c['names'];
      final name = names is Map ? _str(names['uz_Cyrl']) : '';
      list.add(ListingModCategory(id, name.isEmpty ? id : name));
    }
    if (list.isNotEmpty) out[key] = list;
  });
  return out;
}

/// Тузатиш натижаси: [edits] — фақат ўзгарган майдонлар; [error] — биринчи хато майдони (`null` — тўғри).
class ListingEditResult {
  const ListingEditResult(this.edits, this.error);
  final Map<String, Object?> edits;
  final String? error;
  bool get ok => error == null;
}

/// «1 500 000» → 1500000; рақамдан бошқа белги (бўшлиқдан ташқари) ёки бўш — `null`.
int? parseListingPrice(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s ]'), '');
  if (s.isEmpty || !RegExp(r'^\d+$').hasMatch(s) || s.length > 9) return null;
  return int.parse(s);
}

/// Диалог қийматлари → `edits` (сервер `validateListingEdits` билан бир хил қоидалар). Хато матни — кирилл.
ListingEditResult buildListingEdits(
  ListingModItem orig, {
  required String title,
  required String description,
  required String priceText,
  required String priceUnit,
  required String category,
  required List<String> keptPhotos,
}) {
  final edits = <String, Object?>{};
  final t = title.trim();
  if (t.isEmpty || t.length > kListingTitleMax) {
    return const ListingEditResult({}, 'Сарлавҳа 1–$kListingTitleMax белги бўлсин');
  }
  if (t != orig.title) edits['title'] = t;

  final d = description.trim();
  if (d.length > kListingDescriptionMax) {
    return const ListingEditResult({}, 'Тавсиф $kListingDescriptionMax белгидан ошмасин');
  }
  if (d != orig.description.trim()) edits['description'] = d;

  final price = parseListingPrice(priceText);
  if (price == null || price > kListingPriceMax) {
    return const ListingEditResult({}, 'Нарх — бутун сон (0–$kListingPriceMax сўм)');
  }
  if (price != orig.price) edits['price'] = price;

  if (!PriceUnit.wires.contains(priceUnit)) return const ListingEditResult({}, 'Нарх бирлиги нотўғри');
  if (priceUnit != orig.priceUnit) edits['priceUnit'] = priceUnit;

  final c = category.trim();
  if (c != orig.categoryValue && !(c.isEmpty && orig.categoryValue.isEmpty)) {
    // rules/сервер: category фақат market билан; ўчириш (бўш) — тузатиш орқали мумкин эмас.
    if (orig.market.isEmpty) return const ListingEditResult({}, 'Бўлимни фақат бозор эълонида ўзгартириш мумкин');
    if (c.isEmpty || c.length > kListingCategoryMax) {
      return const ListingEditResult({}, 'Бўлим 1–$kListingCategoryMax белги бўлсин');
    }
    edits['category'] = c;
  }

  if (keptPhotos.any((u) => !orig.photoUrls.contains(u)) || keptPhotos.toSet().length != keptPhotos.length) {
    return const ListingEditResult({}, 'Расмлар фақат олиб ташланади');
  }
  if (keptPhotos.length != orig.photoUrls.length) {
    // Тартиб жорий рўйхатдагидек.
    edits['photoUrls'] = [for (final u in orig.photoUrls) if (keptPhotos.contains(u)) u];
  }
  return ListingEditResult(edits, null);
}

/// Хато → админ матни + диагностик код (панелда код кўринади — админ учун, 25-банд: stack trace эмас).
String listingModErrorText(Object e) {
  final code = e is AdminCallableException ? (e.reason.isNotEmpty ? e.reason : e.code) : 'CLIENT_ERROR';
  const byCode = <String, String>{
    'LISTING_NOT_PENDING': 'Эълон аллақачон кўриб чиқилган ёки ўзгарган',
    'LISTING_NOT_FOUND': 'Эълон топилмади (ўчирилган бўлиши мумкин)',
    'REASON_REQUIRED': 'Рад этиш сабабини ёзинг (1–300 белги)',
    'COLLECTION_INVALID': 'Бу турдаги эълонни бу ерда модерация қилиб бўлмайди',
    'INVALID_EDITS': 'Тузатишлар нотўғри (майдонларни текширинг)',
    'EDITS_NOT_SUPPORTED': 'Бу турдаги эълонни тузатиб бўлмайди',
    'EDITS_REQUIRE_APPROVE': 'Тузатиш фақат тасдиқлаш билан юборилади',
    'permission-denied': 'Рухсат йўқ (фақат admin/superadmin)',
    'unauthenticated': 'Қайта киринг',
    'unavailable': 'Тармоқ хатоси — қайта уриниб кўринг',
  };
  final text = byCode[code] ?? 'Амал бажарилмади. Қайта уриниб кўринг.';
  return '$text ($code)';
}

/// «дд.ММ.йййй сс:дд» (маҳаллий вақт); `null` — «—».
String listingModTimeLabel(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

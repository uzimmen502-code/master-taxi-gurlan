// «Эълонлар модерацияси» (Бозорлар 2b, эга 2026-11-15) — соф мантиқ (тестланади).
//
// Сервер: `adminModerateListing({collection, id, decision, reason?})` — `functions/market_moderation.js`.
// Коллекциялар: tv_shop_items · wholesale_products (Улгуржи/Хитой — `market` бўйича) · realty_listings ·
// ads (фақат `type == 'cheap_product'`). Рад этиш сабаби 1..300 белги (сервер `normalizeReason`).
// Админ панели матнлари — кирилл (панель конвенцияси; панелда l10n йўқ).

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import '../../../core/utils/formatters.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../services/admin_callable.dart';

/// Рад этиш сабабининг юқори чегараси (сервер `REASON_MAX`).
const kListingRejectReasonMax = 300;

/// Сўров чегараси (композит индекссиз: фақат `status` бўйича, тартиб — клиентда).
const kListingModPageLimit = 100;

enum ListingModSource {
  shop('tv_shop_items', 'Аралаш / дўкон'),
  wholesale('wholesale_products', 'Улгуржи'),
  china('wholesale_products', 'Хитой'),
  realty('realty_listings', 'Уй-жой'),
  ads('ads', 'Эски эълонлар');

  const ListingModSource(this.collection, this.label);

  /// `adminModerateListing` `collection` қиймати.
  final String collection;
  final String label;
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
  });

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
      final price = _int(d['price']);
      final unit = _str(d['priceUnit']);
      return ListingModItem(
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

/// Хато → админ матни + диагностик код (панелда код кўринади — админ учун, 25-банд: stack trace эмас).
String listingModErrorText(Object e) {
  final code = e is AdminCallableException ? (e.reason.isNotEmpty ? e.reason : e.code) : 'CLIENT_ERROR';
  const byCode = <String, String>{
    'LISTING_NOT_PENDING': 'Эълон аллақачон кўриб чиқилган ёки ўзгарган',
    'LISTING_NOT_FOUND': 'Эълон топилмади (ўчирилган бўлиши мумкин)',
    'REASON_REQUIRED': 'Рад этиш сабабини ёзинг (1–300 белги)',
    'COLLECTION_INVALID': 'Бу турдаги эълонни бу ерда модерация қилиб бўлмайди',
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

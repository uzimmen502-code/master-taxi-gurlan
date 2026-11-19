import '../../../models/realty_listing.dart';
import '../../ads/models/ad_model.dart';
import '../../tv_market/domain/price_unit.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../wholesale/models/wholesale_product.dart';

/// ❤ Танланганлар манбалари — `firestore.rules` `users/{id}/favorites` даги рўйхат билан БИР ХИЛ
/// (сервер 2026-11-15, functions/test/user_favorites_rules.test.js).
abstract final class FavoriteCollections {
  static const tvShopItems = 'tv_shop_items';
  static const wholesaleProducts = 'wholesale_products';
  static const realtyListings = 'realty_listings';
  static const ads = 'ads';

  static const all = <String>[tvShopItems, wholesaleProducts, realtyListings, ads];
}

/// Rules чегаралари (қатъий шакл) — клиент ёзишдан олдин шу чегарага солади, акс ҳолда сервер рад этади.
abstract final class FavoriteLimits {
  static const itemIdMax = 128;
  static const titleMax = 200;
  static const photoUrlMax = 1000;
  static const priceMax = 999999999;
  static const shortMax = 20;
}

/// Ҳужжат ID = `{collection}_{itemId}` (rules: favId == collection + '_' + itemId) — такрор босиш битта ҳужжат.
String favoriteKey(String collection, String itemId) => '${collection}_$itemId';

/// Танланган элемент снимоги (`users/{uid}/favorites/{key}`). Нарх — ФАҚАТ кўрсатиш учун снимок
/// (пул ҳисобида ишлатилмайди); ҳақиқий нарх экран очилганда манба ҳужжатдан олинади.
class FavoriteRef {
  const FavoriteRef({
    required this.collection,
    required this.itemId,
    this.title = '',
    this.photoUrl = '',
    this.price,
    this.priceUnit = '',
    this.market = '',
    this.addedAt,
  });

  final String collection;
  final String itemId;
  final String title;
  final String photoUrl;
  final int? price;
  final String priceUnit;
  final String market;
  final DateTime? addedAt;

  String get key => favoriteKey(collection, itemId);

  /// Rules талабига мос: маълум манба, ID 1..128, `/` йўқ.
  bool get isValid =>
      FavoriteCollections.all.contains(collection) &&
      itemId.isNotEmpty &&
      itemId.length <= FavoriteLimits.itemIdMax &&
      !itemId.contains('/');

  /// Create payload (addedAt'ни чақирувчи `serverTimestamp` қилиб қўшади). Ихтиёрий майдонлар бўш бўлса ёзилмайди.
  Map<String, dynamic> toCreateMap() => {
        'collection': collection,
        'itemId': itemId,
        'title': _cut(title, FavoriteLimits.titleMax),
        if (photoUrl.isNotEmpty && photoUrl.length <= FavoriteLimits.photoUrlMax) 'photoUrl': photoUrl,
        if (price != null && price! >= 0 && price! <= FavoriteLimits.priceMax) 'price': price,
        if (priceUnit.isNotEmpty) 'priceUnit': _cut(priceUnit, FavoriteLimits.shortMax),
        if (market.isNotEmpty) 'market': _cut(market, FavoriteLimits.shortMax),
      };

  factory FavoriteRef.fromMap(String id, Map<String, dynamic> d) {
    final rawPrice = d['price'];
    final rawAdded = d['addedAt'];
    DateTime? added;
    try {
      added = rawAdded == null ? null : (rawAdded as dynamic).toDate() as DateTime;
    } catch (_) {
      added = rawAdded is DateTime ? rawAdded : null;
    }
    final collection = (d['collection'] ?? '').toString();
    var itemId = (d['itemId'] ?? '').toString();
    if (itemId.isEmpty && id.startsWith('${collection}_')) itemId = id.substring(collection.length + 1);
    return FavoriteRef(
      collection: collection,
      itemId: itemId,
      title: (d['title'] ?? '').toString(),
      photoUrl: (d['photoUrl'] ?? '').toString(),
      price: rawPrice is int ? rawPrice : null,
      priceUnit: (d['priceUnit'] ?? '').toString(),
      market: (d['market'] ?? '').toString(),
      addedAt: added,
    );
  }

  factory FavoriteRef.fromShopItem(TvShopItem item) => FavoriteRef(
        collection: FavoriteCollections.tvShopItems,
        itemId: item.id,
        title: item.title,
        photoUrl: item.coverPhotoUrl,
        price: item.price > 0 ? item.price : null,
        priceUnit: item.priceUnit == PriceUnit.fixed ? '' : item.priceUnit.wire,
        market: item.market,
      );

  factory FavoriteRef.fromAd(AdModel ad) => FavoriteRef(
        collection: FavoriteCollections.ads,
        itemId: ad.id,
        title: ad.title,
        photoUrl: ad.imageUrls.isEmpty ? '' : ad.imageUrls.first,
        price: ad.price > 0 ? ad.price : null,
        market: 'aralash',
      );

  /// Улгуржи/Хитой: нарх снимоги фақат сўмда (бошқа валюта — снимоксиз; кўрсатиш манба ҳужжатдан).
  factory FavoriteRef.fromWholesale(WholesaleProduct p) {
    final cur = p.currency.trim().toUpperCase();
    final isSum = cur.isEmpty || cur == 'UZS';
    return FavoriteRef(
      collection: FavoriteCollections.wholesaleProducts,
      itemId: p.id,
      title: p.title,
      photoUrl: p.imageUrls.isEmpty ? '' : p.imageUrls.first,
      price: isSum && p.basePrice > 0 ? p.basePrice : null,
      market: p.market,
    );
  }

  factory FavoriteRef.fromRealty(RealtyListing r) => FavoriteRef(
        collection: FavoriteCollections.realtyListings,
        itemId: r.id,
        title: r.titleOrText,
        photoUrl: r.imageUrls.isEmpty ? '' : r.imageUrls.first,
        // Сараланганларда нарх сўмда кўрсатилади — USD эълонда нарх берилмайди.
        price: (r.priceAmount ?? 0) > 0 && !r.extras.isUsd ? r.priceAmount : null,
        market: 'realty',
      );

  static String _cut(String s, int max) => s.length <= max ? s : s.substring(0, max);
}

/// Манба ҳужжати бўйича «мавжудми»: ҳужжат йўқ/ўқиб бўлмади ёки `status != 'active'`
/// (ўчирилган, муддати ўтган, рад этилган, блокланган, нофаол) — «Мавжуд эмас».
/// Уй-жой ва бозор эълонида `expiresAt` ўтган бўлса ҳам (сервер супуриши кечикса) — мавжуд эмас.
bool favoriteSourceAvailable(Map<String, dynamic>? data, {DateTime? now}) {
  if (data == null) return false;
  if ((data['status'] ?? '').toString() != 'active') return false;
  final exp = data['expiresAt'];
  DateTime? at;
  try {
    at = exp == null ? null : (exp is DateTime ? exp : (exp as dynamic).toDate() as DateTime);
  } catch (_) {
    at = null;
  }
  if (at != null && at.isBefore(now ?? DateTime.now())) return false;
  return true;
}

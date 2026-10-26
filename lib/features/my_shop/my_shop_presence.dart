import 'package:flutter/foundation.dart';

import '../ads/repositories/ads_repository.dart';
import '../business_map/data/business_repository.dart';
import '../business_map/domain/business.dart';
import '../business_map/domain/product_kind.dart' as product_kind;
import '../tv_market/repositories/tv_shop_repository.dart';
import '../wholesale/repositories/wholesale_sellers_repository.dart';

/// Эганинг дўконлари ҳолати: «＋» менюсидаги «Онлайн Дўкон очиш» қатори шунга
/// қараб «Менинг дўконим»га айланади.
///
/// Асосий дўкон = Аҳоли бозори эълонлари ([retail]) ва/ёки Улгуржи сотувчи
/// ҳужжати ([wholesale]) ва/ёки номи сақланган `tv_shops` ҳужжати ([mainShop]).
/// Қўшимча дўконлар = Бизнес харитасидаги чакана/улгуржи объектлар ([otherShops]).
///
/// Ўқилмаса (тармоқ, ruxsat) «йўқ» деб ҳисобланади — қатор аввалги «очиш»
/// оқимига қайтади, ҳеч нарса бузилмайди.
@immutable
class MyShopPresence {
  const MyShopPresence({
    this.retail = false,
    this.wholesale = false,
    this.mainShop = false,
    this.otherShops = 0,
  });

  static const none = MyShopPresence();

  /// Аҳоли бозорида камида битта эълон бор (ҳар қандай ҳолатда).
  final bool retail;

  /// Улгуржи сотувчи ҳужжати бор.
  final bool wholesale;

  /// `tv_shops/{телефон}` ҳужжати бор (дўкон номи шу ерда).
  final bool mainShop;

  /// Бизнес харитасидаги чакана/улгуржи объектлар сони.
  final int otherShops;

  bool get any => retail || wholesale || mainShop || otherShops > 0;

  /// Асосий дўконда маҳсулот ёки сотувчи ҳолати бор.
  bool get hasMainContent => retail || wholesale || mainShop;

  /// Асосий дўкон қайси сегментдан очилади: 0 — Аҳоли, 1 — Улгуржи.
  /// Иккаласида бўлса — Аҳоли; фақат улгуржида бўлса — Улгуржи.
  int get initialSegment => (!retail && wholesale) ? 1 : 0;

  /// 2 та ҳужжат ўқиш + 2 та сўров (барчаси параллел, ҳар бири `limit(1)` ёки
  /// эганинг ўз объектлари). Текширувлар тестда алмаштирилади; берилмаса ҳақиқий
  /// репозиторийлар (фақат керак бўлганда яратилади).
  static Future<MyShopPresence> load(
    String phone, {
    Future<bool> Function(String phone)? hasAds,
    Future<bool> Function(String phone)? hasSeller,
    Future<bool> Function(String phone)? hasMainShop,
    Future<int> Function(String phone)? countOtherShops,
  }) async {
    final adsCheck = hasAds ?? (p) => AdsRepository().hasAnyAd(p);
    final sellerCheck = hasSeller ??
        (p) async => (await WholesaleSellersRepository().fetchByPhone(p)) != null;
    final mainCheck = hasMainShop ?? (p) => TvShopRepository().hasShop(p);
    final otherCheck = countOtherShops ?? _countBusinessShops;

    Future<T> safe<T>(String label, Future<T> Function(String) check, T fallback) async {
      try {
        return await check(phone);
      } catch (e) {
        debugPrint('[MyShopPresence] $label failed: $e');
        return fallback;
      }
    }

    final r = await Future.wait<Object>([
      safe<bool>('retail', adsCheck, false),
      safe<bool>('wholesale', sellerCheck, false),
      safe<bool>('mainShop', mainCheck, false),
      safe<int>('otherShops', otherCheck, 0),
    ]);
    return MyShopPresence(
      retail: r[0] as bool,
      wholesale: r[1] as bool,
      mainShop: r[2] as bool,
      otherShops: r[3] as int,
    );
  }

  static Future<int> _countBusinessShops(String phone) async {
    final mine = await BusinessRepository().watchMine(phone).first;
    return mine.where(isShopCategory).length;
  }

  /// «Дўкон» деб ҳисобланадиган объект турлари: чакана ва улгуржи.
  static bool isShopCategory(Business b) => product_kind.isShopCategory(b.category);

  @override
  bool operator ==(Object other) =>
      other is MyShopPresence &&
      other.retail == retail &&
      other.wholesale == wholesale &&
      other.mainShop == mainShop &&
      other.otherShops == otherShops;

  @override
  int get hashCode => Object.hash(retail, wholesale, mainShop, otherShops);
}

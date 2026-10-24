import 'tv_shop.dart';

/// Маҳсулотдан пуллик АВАГрам рекламасини бошлаш (эга қарори, 2026-10-24: каталог доимий, реклама — уни оммалаштириш
/// учун АЛОҲИДА механизм). Янги реклама тизими йўқ: мавжуд `TvPublishScreen` «Эълон» (пуллик) режимида очилади,
/// фақат ном/нарх/тавсиф маҳсулотдан олдиндан тўлдирилади. Видео, тариф, муддат ва ҳудудни эга ўзи танлайди,
/// тўлов — ҳамёндан, серверда (`publishTvAd`).
class TvAdPrefill {
  const TvAdPrefill({required this.title, this.price = 0, this.description = '', this.shopItemId = ''});

  /// `TvPublishScreen` чегаралари (`_titleMaxLen` / `_descMaxLen`) — узунроқ матн қирқилади.
  static const titleMax = 80;
  static const descriptionMax = 500;

  final String title;
  final int price;
  final String description;

  /// Реклама боғланадиган каталог маҳсулоти (`tv_shop_items/{id}`): клипга `shopItemId` бўлиб ёзилади, томошабин
  /// «Дўкон» тугмасидан шу маҳсулотга ўтади. Мавжудлиги ва эгалигини сервер текширади.
  final String shopItemId;

  factory TvAdPrefill.fromItem(TvShopItem item) => TvAdPrefill(
        title: _cut(item.title.trim(), titleMax),
        price: item.price > 0 ? item.price : 0,
        description: _cut(item.description.trim(), descriptionMax),
        shopItemId: item.id,
      );

  /// Кодпоинт бўйича қирқади — эмодзи (суррогат жуфт) ўртасидан узилмайди.
  static String _cut(String s, int max) => s.runes.length <= max ? s : String.fromCharCodes(s.runes.take(max));
}

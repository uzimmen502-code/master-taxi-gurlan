import '../../tv_market/models/tv_clip.dart' show tvOwnerDisplayName;

/// Сервер `sellerName`ни шу узунликда қисқартиради (`submitMarketAd`).
const kSellerNameMaxLength = 80;

/// Эълонда кўринадиган сотувчи номи. Тартиб:
///  1. дўкон номи (`tv_shops.name`, «Менинг дўконим») — яроқли бўлса;
///  2. Firebase профил исми;
///  3. email;
///  4. [fallback] (умумий «Сотувчи»).
///
/// «Яроқли» — [tvOwnerDisplayName] қоидаси: бўш, `@nick`, телефон рақами ва
/// «Фойдаланувчи» каби ёлғон исмлар ҳисобга олинмайди. Ном эълон яратилган пайтда
/// ёзилади (нусха): дўкон номи кейин ўзгарса, эски эълонлар ўзгармайди.
String resolveSellerName({
  String shopName = '',
  String? authName,
  String? email,
  required String fallback,
}) {
  final shop = tvOwnerDisplayName(shopName);
  if (shop.isNotEmpty) return _clamp(shop);
  final auth = (authName ?? '').trim();
  if (auth.isNotEmpty) return _clamp(auth);
  final mail = (email ?? '').trim();
  if (mail.isNotEmpty) return _clamp(mail);
  return fallback;
}

String _clamp(String s) =>
    s.length <= kSellerNameMaxLength ? s : s.substring(0, kSellerNameMaxLength);

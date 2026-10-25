import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';

/// Видео → маҳсулот (`clip.shopItemId`) боғланиши ишончлими (2026-10-25, 3-босқич): маҳсулот мавжуд, фаол, айнан
/// шу ID ва КЛИП ЭГАСИНИКИ бўлиши шарт. Акс ҳолда `null` — видео бошқа сотувчининг маҳсулотини очмайди
/// (клип ҳужжатидаги `shopItemId` мижоз ёзадиган майдон; сервер фақат реклама клипида текширади).
TvShopItem? productForClip(TvClip clip, TvShopItem? item) {
  if (item == null || !item.isActive) return null;
  if (clip.shopItemId.isEmpty || item.id != clip.shopItemId) return null;
  final owner = canonicalPhoneId(clip.ownerPhone);
  if (owner.isEmpty || canonicalPhoneId(item.ownerPhone) != owner) return null;
  return item;
}

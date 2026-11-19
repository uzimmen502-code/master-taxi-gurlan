import '../models/wholesale_product.dart';

/// Эга 2026-11-20: нарх ўзгариши қайта модерация ЭМАС. Таҳрирда фақат нарх (поғоналар — маҳсулотда ва қадоқларда)
/// ўзгарган бўлса — `true`: фаол товар фаол қолади. Rules (`wholesaleProductOwnerUpdateOk`) нархдан бошқа майдонни
/// active ҳолатда ўзгартиришга йўл қўймайди; қадоқнинг бошқа майдони ўзгарса сервер (`onWholesaleProductPromoWrite`)
/// `pending` қилади — бу функция фақат тўғри ҳолатни олдиндан танлайди.
bool wholesaleOnlyPriceChanged(WholesaleProduct before, WholesaleProduct after) {
  bool sameList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String packKey(WholesalePack p) =>
      '${p.id}|${p.label}|${p.unitWeightG}|${p.unitDims?.toMap()}|${p.minOrderQty}|${p.photoUrl}';

  return before.title.trim() == after.title.trim() &&
      before.description.trim() == after.description.trim() &&
      before.unit.trim() == after.unit.trim() &&
      sameList(before.imageUrls, after.imageUrls) &&
      before.currency.trim() == after.currency.trim() &&
      before.deliveryDays == after.deliveryDays &&
      before.unitWeightG == after.unitWeightG &&
      before.unitDims?.toMap().toString() == after.unitDims?.toMap().toString() &&
      before.minOrderQty == after.minOrderQty &&
      sameList(before.packs.map(packKey).toList(), after.packs.map(packKey).toList());
}

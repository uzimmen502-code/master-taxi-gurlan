/// Супермаркет таклифи — мавжуд `platform_products` ҳужжати + ихтиёрий `sm*` майдонлар
/// (сервер шартномаси, эга 2026-11-20). Янги коллекция ЭМАС (4-банд).
///
/// Ихтиёрий майдонлар: smGroupId, smCategoryId, smVariety{id,names}, smQuality{3 тил}, packLabel,
/// unit (kg|l|piece|pack|bunch), qtyStep, weighed, stock, smStatus active|out_of_stock|hidden,
/// priceUpdatedAt; price — бутун сўм / бирлик.
/// Бирлик нархи учун: `packQty` (сон) + `packUnit` (kg|l|piece) — эга қарори 2026-11-20, сервер қўшмоқда.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'sm_qty.dart';
import 'sm_taxonomy.dart';

/// Қадоқ ичидаги миқдор бирлиги (эга 2026-11-20, сервер `packUnit`): «1 л — N сўм» учун.
const kSmPackUnits = <String>{'kg', 'l', 'piece'};

enum SmStatus { active, outOfStock, hidden }

SmStatus smParseStatus(Object? raw, {required bool legacyActive}) {
  switch (raw) {
    case 'active':
      return SmStatus.active;
    case 'out_of_stock':
      return SmStatus.outOfStock;
    case 'hidden':
      return SmStatus.hidden;
  }
  // smStatus йўқ (эски ҳужжат) — мавжуд `active` белгиси бўйича (26-банд).
  return legacyActive ? SmStatus.active : SmStatus.hidden;
}

String smStatusWire(SmStatus s) => switch (s) {
      SmStatus.active => 'active',
      SmStatus.outOfStock => 'out_of_stock',
      SmStatus.hidden => 'hidden',
    };

class SmOffer {
  const SmOffer({
    required this.id,
    required this.name,
    required this.groupId,
    required this.price,
    this.categoryId = '',
    this.varietyId = '',
    this.varietyNames = const {},
    this.qualityNames = const {},
    this.packLabel = '',
    this.unit = '',
    this.stepMilli = 1000,
    this.weighed = false,
    this.stockMilli,
    this.status = SmStatus.active,
    this.imageUrl = '',
    this.priceUpdatedAt,
    this.priceUpdatedBy = '',
    this.packQtyMilli,
    this.packUnit = '',
  });

  final String id;
  final String name;
  final String groupId;
  final String categoryId;
  final String varietyId;
  final Map<String, String> varietyNames;
  final Map<String, String> qualityNames;
  final String packLabel;
  final String unit;
  final int stepMilli;
  final bool weighed;

  /// `null` — қолдиқ кўрсатилмаган (чекланмаган).
  final int? stockMilli;
  final SmStatus status;

  /// Бутун сўм / бирлик (кг, л, дона, пакет, боғ).
  final int price;
  final String imageUrl;
  final DateTime? priceUpdatedAt;

  /// Ким ўзгартирди (сервер ёзса — `priceUpdatedBy`; шартномада йўқ, ихтиёрий).
  final String priceUpdatedBy;
  final int? packQtyMilli;
  final String packUnit;

  bool get isSupermarket => groupId.isNotEmpty;
  bool get visible => isSupermarket && status != SmStatus.hidden && price > 0;
  /// Сотувда: ҳолат active ВА қолдиқ бор. Сервер (supermarket.js) stock йўқ/0 ни «0 мавжуд» деб
  /// ҳисоблайди — клиент ҳам шундай (буюртмада OUT_OF_STOCK бўлмасин).
  bool get available => visible && status == SmStatus.active && (stockMilli ?? 0) >= stepMilli;

  String varietyName(String lang) => localizedName(varietyNames, lang, fallback: name);
  String qualityName(String lang) => localizedName(qualityNames, lang);

  /// Пакет учун бирлик нархи (масалан 1 л учун), бутун сўм; ҳисоблаб бўлмаса `null`.
  int? get unitPriceOfPack {
    final q = packQtyMilli;
    if (unit != 'pack' || q == null || q <= 0 || price <= 0) return null;
    if (!kSmPackUnits.contains(packUnit)) return null;
    return (price * 1000 + q ~/ 2) ~/ q;
  }

  /// Энг кўп миқдор (қолдиқ бўйича); чекланмаган — `null`.
  int? get maxQtyMilli => stockMilli != null && stockMilli! > 0 ? stockMilli : null;

  static SmOffer fromMap(String id, Map<String, dynamic> d, {SmGroup? group}) {
    final variety = d['smVariety'];
    final unit = (d['unit'] is String && kSmUnits.contains(d['unit'])) ? d['unit'] as String : (group?.unit ?? '');
    final step = d['qtyStep'] is num ? smToMilli(d['qtyStep'] as num) : (group?.stepMilli ?? 1000);
    final urls = d['imageUrls'];
    var img = '';
    if (urls is List && urls.isNotEmpty && urls.first is String) img = (urls.first as String).trim();
    if (img.isEmpty && d['imageUrl'] is String) img = (d['imageUrl'] as String).trim();
    final ts = d['priceUpdatedAt'];
    return SmOffer(
      id: id,
      name: (d['name'] as String?)?.trim() ?? '',
      groupId: (d['smGroupId'] as String?)?.trim() ?? '',
      categoryId: (d['smCategoryId'] as String?)?.trim() ?? (group?.categoryId ?? ''),
      varietyId: variety is Map ? ((variety['id'] as String?)?.trim() ?? '') : '',
      varietyNames: variety is Map ? smNames(variety['names']) : const {},
      qualityNames: smNames(d['smQuality']),
      packLabel: (d['packLabel'] as String?)?.trim() ?? '',
      unit: unit,
      stepMilli: step > 0 ? step : 1000,
      weighed: d['weighed'] is bool ? d['weighed'] as bool : (group?.weighed ?? false),
      stockMilli: d['stock'] is num ? smToMilli(d['stock'] as num) : null,
      status: smParseStatus(d['smStatus'], legacyActive: d['active'] as bool? ?? true),
      price: (d['price'] as num?)?.toInt() ?? 0,
      imageUrl: img,
      priceUpdatedAt: ts is Timestamp ? ts.toDate() : null,
      priceUpdatedBy: (d['priceUpdatedBy'] as String?)?.trim() ?? '',
      packQtyMilli: d['packQty'] is num ? smToMilli(d['packQty'] as num) : null,
      packUnit: (d['packUnit'] as String?)?.trim() ?? '',
    );
  }
}

/// Нав ичидаги таклифлар: аввал мавжудлари нарх ўсиши бўйича, кейин «Ҳозир мавжуд эмас»
/// (улар ҳам нарх бўйича). Яширинлар — йўқ.
List<SmOffer> smSortOffersAsc(Iterable<SmOffer> offers) {
  final list = offers.where((o) => o.visible).toList();
  list.sort((a, b) {
    if (a.available != b.available) return a.available ? -1 : 1;
    final byPrice = a.price.compareTo(b.price);
    return byPrice != 0 ? byPrice : a.id.compareTo(b.id);
  });
  return list;
}

/// Гуруҳ учун «… сўм/кг дан» — ФАҚАТ мавжуд (active) энг арзон таклифдан; йўқ бўлса `null`.
int? smCheapestActivePrice(Iterable<SmOffer> offers) {
  int? best;
  for (final o in offers) {
    if (!o.available) continue;
    if (best == null || o.price < best) best = o.price;
  }
  return best;
}

/// Гуруҳ навлари (таклиф тартибида, такрорсиз): `id → номлар`. Нави йўқ таклиф — `''`.
List<({String id, Map<String, String> names})> smVarieties(Iterable<SmOffer> offers) {
  final seen = <String>{};
  final out = <({String id, Map<String, String> names})>[];
  for (final o in smSortOffersAsc(offers)) {
    if (seen.add(o.varietyId)) out.add((id: o.varietyId, names: o.varietyNames));
  }
  return out;
}

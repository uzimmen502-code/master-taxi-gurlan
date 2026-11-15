/// Эълон карточкасидаги нисбий жой ёрлиғи (эга, 2026-11-15; GeoMode.rings):
///   - фойдаланувчи билан бир туман → туман номи («Гурлан»);
///   - бир вилоят → туман тўлиқ номи («Ҳазорасп тумани» / «Hazorasp tumani» /
///     рус `nameRu`);
///   - бошқа вилоят → вилоят номи.
/// Номлар — [GeoNames] (3 тил, ID бўйича); ҳужжатдаги сақланган ёрлиқ — fallback.
library;

import 'geo_names.dart';

enum RelativeLocationKind { sameDistrict, sameRegion, otherRegion, unknown }

/// Тоза таснифлаш. Эълоннинг [itemRegionId]и бўш бўлса (эски ҳужжат) ва туман
/// фарқ қилса — вилоят аниқланмайди: [RelativeLocationKind.unknown].
RelativeLocationKind relativeLocationKind({
  required String itemDistrictId,
  required String itemRegionId,
  required String userDistrictId,
  required String userRegionId,
}) {
  final id = itemDistrictId.trim();
  final ir = itemRegionId.trim();
  final ud = userDistrictId.trim();
  final ur = userRegionId.trim();
  if (id.isNotEmpty && id == ud) return RelativeLocationKind.sameDistrict;
  if (ir.isEmpty || ur.isEmpty) return RelativeLocationKind.unknown;
  return ir == ur ? RelativeLocationKind.sameRegion : RelativeLocationKind.otherRegion;
}

/// Карточка ёрлиғи [lang] тилида (`uz_Cyrl` / `uz_Latn` / `ru`). Ҳеч нарса
/// маълум бўлмаса — бўш сатр (карточка ёрлиқсиз чизилади).
String relativeLocationLabel({
  required String itemDistrictId,
  required String itemRegionId,
  required String userDistrictId,
  required String userRegionId,
  required String lang,
  String districtFallback = '',
  String regionFallback = '',
}) {
  final kind = relativeLocationKind(
    itemDistrictId: itemDistrictId,
    itemRegionId: itemRegionId,
    userDistrictId: userDistrictId,
    userRegionId: userRegionId,
  );
  switch (kind) {
    case RelativeLocationKind.sameDistrict:
      return GeoNames.district(itemDistrictId, lang, fallback: districtFallback);
    case RelativeLocationKind.sameRegion:
      if (itemDistrictId.trim().isEmpty) {
        return GeoNames.region(itemRegionId, lang, fallback: regionFallback);
      }
      return GeoNames.districtFull(itemDistrictId, lang, fallback: districtFallback);
    case RelativeLocationKind.otherRegion:
      return GeoNames.region(itemRegionId, lang, fallback: regionFallback);
    case RelativeLocationKind.unknown:
      if (itemDistrictId.trim().isNotEmpty) {
        return GeoNames.district(itemDistrictId, lang, fallback: districtFallback);
      }
      return GeoNames.region(itemRegionId, lang, fallback: regionFallback);
  }
}

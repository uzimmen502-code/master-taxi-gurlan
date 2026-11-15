/// Вилоят марказлари — «ҳалқалар» тартиби учун (GeoMode.rings).
///
/// Манба: OpenStreetMap, эга тасдиқлаган 2026-11-15 (CONFIRMED). ID'лар —
/// `geo_regions/{id}` (functions/tools/data/uzbekistan_geo_data.js + xorazm).
/// Фақат ТАРТИБ учун (вилоятлар орасидаги масофа), нарх ёки ҳудуд чегараси
/// учун эмас.
library;

import 'dart:math' as math;

/// regionId → (lat, lng).
const Map<String, (double, double)> kRegionCenters = {
  'toshkent_shahri': (41.3123, 69.2787),
  'toshkent_viloyati': (41.0429, 69.3578),
  'andijon': (40.7833, 72.3507),
  'fargona': (40.3765, 71.7913),
  'namangan': (40.9996, 71.6726),
  'samarqand': (39.6550, 66.9757),
  'buxoro': (39.7760, 64.4152),
  'navoiy': (40.1035, 65.3734),
  'qashqadaryo': (38.8398, 65.7928),
  'surxondaryo': (37.2442, 67.2832),
  'jizzax': (40.1332, 67.8234),
  'sirdaryo': (40.5221, 68.7802),
  'qoraqalpogiston': (42.4600, 59.6177),
  'xorazm': (41.5518, 60.6313),
};

/// Икки нуқта орасидаги масофа (км, haversine).
double haversineKm((double, double) a, (double, double) b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.$1 - a.$1);
  final dLng = rad(b.$2 - a.$2);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(a.$1)) * math.cos(rad(b.$1)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Барча вилоятлар яқиндан узоққа: фойдаланувчи вилояти биринчи, қолганлари
/// марказлар орасидаги масофа бўйича (тенг масофада — ID алифбоси).
/// Номаълум вилоят → барқарор алифбо тартиби (фойдаланувчи вилояти бўш бўлмаса
/// ва рўйхатда бўлмаса ҳам — у биринчи туради).
List<String> regionRingOrder(String userRegionId) {
  final user = userRegionId.trim();
  final ids = kRegionCenters.keys.toList()..sort();
  final center = kRegionCenters[user];
  if (center == null) {
    return [if (user.isNotEmpty) user, ...ids];
  }
  final others = ids.where((id) => id != user).toList()
    ..sort((a, b) {
      final c = haversineKm(center, kRegionCenters[a]!)
          .compareTo(haversineKm(center, kRegionCenters[b]!));
      return c != 0 ? c : a.compareTo(b);
    });
  return [user, ...others];
}

// ҲУДУД ТАНЛОВИ (республика миқёси, ега 2026-10-20).
//
// Таклифчи экранида ҳудуд чиплари аввал қаттиқ `['xorazm']` эди — яъни
// Хоразмдан бошқа вилоятдаги уста ўзини рўйхатга ола олмасди. Энди рўйхат
// `geo_regions` (14 вилоят)дан, номлар фойдаланувчи тилида.
//
// Тоза функциялар: Firestore ва виджетсиз тестланади.

import '../../../core/geo/geo_names.dart';
import '../../../models/geo_area.dart';

/// Чип: `geo_regions` ID (`toshkent_shahri` каби `_` билан бўлиши мумкин) ва ном.
class RegionOption {
  const RegionOption(this.id, this.label);

  final String id;
  final String label;
}

/// Фаол вилоятлар — `order` бўйича, кейин ном бўйича. Ном бўш бўлса ID.
List<RegionOption> buildRegionOptions(List<GeoRegion> regions, String lang) {
  final active = regions.where((r) => r.active).toList()
    ..sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) return byOrder;
      return a.id.compareTo(b.id);
    });
  return [
    for (final r in active)
      RegionOption(
        r.id,
        GeoNames.shortRegion(r, lang).trim().isEmpty
            ? r.id
            : GeoNames.shortRegion(r, lang).trim(),
      ),
  ];
}

/// Бошланғич танлов.
///
/// 1) берилган ID'лардан рўйхатда борлари; 2) йўқ бўлса — фойдаланувчининг
/// ўз вилояти (профилдан), рўйхатда бўлса; 3) акс ҳолда БЎШ: ҳеч қайси
/// вилоят ўзбошимчалик билан (масалан «xorazm») танланмайди.
Set<String> resolveInitialRegions({
  required Iterable<String> initial,
  required String? userRegion,
  required Iterable<String> options,
}) {
  final valid = options.toSet();
  final picked = initial.where(valid.contains).toSet();
  if (picked.isNotEmpty) return picked;
  final own = (userRegion ?? '').trim();
  if (own.isNotEmpty && valid.contains(own)) return {own};
  return <String>{};
}

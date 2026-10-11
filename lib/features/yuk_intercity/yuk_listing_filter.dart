import 'models/yuk_listing.dart';
import '../yuk_shared/yuk_vehicle_types.dart';

/// Шаҳарлараро эълонлар рўйхатини фильтрлаш — Firestore'сиз, pure.
///
/// [tab]: `all` | `cargo` | `truck`. [from]/[to] — маршрут шаҳарлари
/// (`from`, `stops`, `to`) ичида substring (lowercase). Иккаласи берилса
/// ЙЎНАЛИШ ТАРТИБИ ҳам текширилади (3в): [from] маршрутда [to] дан олдин
/// келиши шарт — «Тошкент → Урганч» эълони «Урганч → Тошкент» қидирувида
/// чиқмайди. [vehicleType] — normalize қилинган код бўйича тенглик.
/// moto/traktor — фақат туман ичи, шаҳарлараро рўйхатда кўринмайди.
/// Жўнаш куни ўтган эълон кўринмайди. [departDay] берилса — шу куни
/// жўнайдиганлар ва куни кўрсатилмаган (эски) эълонлар.
/// Натижа `createdAt` бўйича янги тепада.
List<YukListing> filterYukListings(
  Iterable<YukListing> source, {
  required String tab,
  String from = '',
  String to = '',
  String vehicleType = '',
  DateTime? departDay,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final day = departDay == null ? null : YukListing.dayOf(departDay);
  final f = from.trim().toLowerCase();
  final t = to.trim().toLowerCase();
  final vt = vehicleType.trim().toLowerCase();

  var list = source.where((item) {
    if (!item.isActive || item.isExpired(at) || item.departed(at)) return false;
    if (day != null && item.departDate != null && item.departDate != day) {
      return false;
    }
    final code = normalizeYukVehicleType(item.vehicleType);
    if (kYukLocalOnlyVehicleValues.contains(code)) return false;
    final cities = item.routeCities.map((c) => c.toLowerCase()).toList();
    final fromIdx = f.isEmpty ? -1 : cities.indexWhere((c) => c.contains(f));
    final toIdx = t.isEmpty ? -1 : cities.lastIndexWhere((c) => c.contains(t));
    if (f.isNotEmpty && fromIdx < 0) return false;
    if (t.isNotEmpty && toIdx < 0) return false;
    if (f.isNotEmpty && t.isNotEmpty && fromIdx >= toIdx) return false;
    if (vt.isNotEmpty && code != normalizeYukVehicleType(vt)) return false;
    return true;
  }).toList();

  if (tab == 'cargo') {
    list = list.where((e) => e.isCargo).toList();
  } else if (tab == 'truck') {
    list = list.where((e) => !e.isCargo).toList();
  }

  list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return list;
}

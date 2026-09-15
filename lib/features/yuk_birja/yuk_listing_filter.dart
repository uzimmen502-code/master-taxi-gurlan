import 'models/yuk_listing.dart';
import 'yuk_vehicle_types.dart';

/// Шаҳарлараро эълонлар рўйхатини фильтрлаш — Firestore'сиз, pure.
///
/// [tab]: `all` | `cargo` | `truck`. [from]/[to] — маршрут шаҳарлари
/// (`from`, `stops`, `to`) ичида substring (lowercase). [vehicleType] —
/// normalize қилинган код бўйича тенглик. moto/traktor — фақат туман ичи,
/// шаҳарлараро рўйхатда кўринмайди. Натижа `createdAt` бўйича янги тепада.
List<YukListing> filterYukListings(
  Iterable<YukListing> source, {
  required String tab,
  String from = '',
  String to = '',
  String vehicleType = '',
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final f = from.trim().toLowerCase();
  final t = to.trim().toLowerCase();
  final vt = vehicleType.trim().toLowerCase();

  var list = source.where((item) {
    if (!item.isActive || item.isExpired(at)) return false;
    final code = normalizeYukVehicleType(item.vehicleType);
    if (kYukLocalOnlyVehicleValues.contains(code)) return false;
    final cities = item.routeCities.map((c) => c.toLowerCase()).toList();
    if (f.isNotEmpty && !cities.any((c) => c.contains(f))) return false;
    if (t.isNotEmpty && !cities.any((c) => c.contains(t))) return false;
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

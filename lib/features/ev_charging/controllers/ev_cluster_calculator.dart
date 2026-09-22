import '../../../models/ev_charging_station.dart';
import '../../../utils/geo_hash.dart';
import '../models/ev_cluster.dart';

/// Marker clustering — texnik topshiriq 5-band: viewport'da ko'rinadigan
/// nuqtalar soni [threshold]dan oshsa, geohash katakchalari bo'yicha
/// birlashtiriladi; oshmasa har bir stansiya alohida ⚡ marker (5-band).
///
/// Sof mantiq — GoogleMap/Firebase'siz test qilinadi (`GeoHash` allaqachon
/// `rides_repository.dart`da ishlatiladigan mavjud utility, yangi kutubxona
/// qo'shilmadi).
abstract final class EvClusterCalculator {
  static List<EvCluster> build(
    List<EvChargingStation> stations, {
    required int threshold,
    required double zoom,
  }) {
    if (stations.length <= threshold) {
      return stations
          .map((s) => EvCluster(lat: s.latitude, lng: s.longitude, stations: [s]))
          .toList();
    }

    final precision = _precisionForZoom(zoom);
    final byCell = <String, List<EvChargingStation>>{};
    for (final s in stations) {
      final cell = GeoHash.encode(s.latitude, s.longitude, precision: precision);
      byCell.putIfAbsent(cell, () => []).add(s);
    }
    return byCell.values.map((group) {
      final lat = group.map((s) => s.latitude).reduce((a, b) => a + b) / group.length;
      final lng = group.map((s) => s.longitude).reduce((a, b) => a + b) / group.length;
      return EvCluster(lat: lat, lng: lng, stations: group);
    }).toList();
  }

  /// Kichik zoom (uzoqdan) — kichik precision (katta katak, ko'proq birlashish);
  /// katta zoom (yaqindan) — katta precision (kichik katak, kamroq birlashish).
  ///
  /// 2026-09-22: эски чегаралар (zoom>=9→precision4) шаҳар даражасидаги
  /// зумда (масалан бутун Тошкентни экранга сиғдирганда, ~zoom 11) ҳали
  /// precision4'да қолиб кетар эди — production маълумотида precision4
  /// катаги ~29×19 км, яъни бутун Тошкент (204 та станция) БОР-ЙЎҒИ 4 та
  /// катакка сиғиб кетади (production'да ўлчанди). Чегаралар шаҳар
  /// зумида precision5/6'га эртароқ ўтадиган қилиб сурилди (Тошкент учун
  /// precision5 → 30 та, precision6 → 135 та алоҳида катак).
  static int _precisionForZoom(double zoom) {
    if (zoom >= 15) return 7;
    if (zoom >= 13) return 6;
    if (zoom >= 10) return 5;
    if (zoom >= 7) return 4;
    if (zoom >= 4) return 3;
    return 2;
  }
}
